const JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

// Only these models may be requested by the client.
const ALLOWED_CHAT_MODELS = new Set(["gpt-4.1-mini", "gpt-4o-mini"]);
const ALLOWED_STT_MODELS = new Set(["gpt-4o-transcribe", "whisper-1"]);
const ALLOWED_TTS_MODELS = new Set(["gpt-4o-mini-tts"]);
const DEFAULTS = { chat: "gpt-4.1-mini", stt: "gpt-4o-transcribe", tts: "gpt-4o-mini-tts" };

// Used when a request carries only a camera frame and no speech.
const DEFAULT_SCENE_INSTRUCTION = "Describe what is in front of me.";

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

let jwksCache = { keys: null, expiresAt: 0 };

async function getSigningKeys() {
  if (jwksCache.keys && Date.now() < jwksCache.expiresAt) return jwksCache.keys;
  const res = await fetch(JWKS_URL);
  if (!res.ok) throw new HttpError(503, "Cannot fetch Google signing keys");
  const body = await res.json();
  const maxAge = /max-age=(\d+)/.exec(res.headers.get("cache-control") || "");
  jwksCache = {
    keys: body.keys,
    expiresAt: Date.now() + (maxAge ? Number(maxAge[1]) * 1000 : 3600_000),
  };
  return jwksCache.keys;
}

function base64UrlToBytes(input) {
  const padded = input + "=".repeat((4 - (input.length % 4)) % 4);
  const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

/** Verifies a Firebase ID token (RS256) and returns its payload. */
async function verifyFirebaseIdToken(token, projectId) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new HttpError(401, "Malformed token");

  const [rawHeader, rawPayload, rawSignature] = parts;
  const decoder = new TextDecoder();
  const header = JSON.parse(decoder.decode(base64UrlToBytes(rawHeader)));
  const payload = JSON.parse(decoder.decode(base64UrlToBytes(rawPayload)));

  if (header.alg !== "RS256") throw new HttpError(401, "Unexpected token algorithm");

  const jwk = (await getSigningKeys()).find((k) => k.kid === header.kid);
  if (!jwk) throw new HttpError(401, "Unknown signing key");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const signatureValid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64UrlToBytes(rawSignature),
    new TextEncoder().encode(`${rawHeader}.${rawPayload}`),
  );
  if (!signatureValid) throw new HttpError(401, "Invalid token signature");

  const now = Math.floor(Date.now() / 1000);
  const skew = 60;
  if (payload.aud !== projectId) throw new HttpError(401, "Token audience mismatch");
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new HttpError(401, "Token issuer mismatch");
  }
  if (!payload.sub) throw new HttpError(401, "Token has no subject");
  if (payload.exp <= now - skew) throw new HttpError(401, "Token expired");
  if (payload.iat > now + skew) throw new HttpError(401, "Token issued in the future");

  return payload;
}

function pickModel(requested, allowed, fallback) {
  return requested && allowed.has(requested) ? requested : fallback;
}

function isTruthy(value) {
  return value === true || value === "1" || value === "true";
}

async function openAI(env, path, init) {
  const res = await fetch(`https://api.openai.com/v1/${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, ...(init.headers || {}) },
  });
  if (!res.ok) {
    // Never forward OpenAI's raw error body — it can echo request details.
    throw new HttpError(502, `Upstream ${path} failed (${res.status})`);
  }
  return res;
}

async function transcribe(env, audioFile, model, language) {
  const form = new FormData();
  form.append("file", audioFile, audioFile.name || "speech.m4a");
  form.append("model", model);
  if (language) form.append("language", language);
  const res = await openAI(env, "audio/transcriptions", { method: "POST", body: form });
  return (await res.json()).text ?? "";
}

async function chat(env, { model, systemPrompt, transcript, imageBase64, outputLanguage }) {
  const content = [{ type: "text", text: transcript }];
  if (imageBase64) {
    content.push({
      type: "image_url",
      image_url: { url: `data:image/jpeg;base64,${imageBase64}`, detail: "low" },
    });
  }
  const system = outputLanguage ? `${systemPrompt}\n\nAnswer in ${outputLanguage}.` : systemPrompt;

  const res = await openAI(env, "chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      max_tokens: 300,
      messages: [
        { role: "system", content: system },
        { role: "user", content },
      ],
    }),
  });
  const data = await res.json();
  return data.choices?.[0]?.message?.content?.trim() ?? "";
}

async function synthesise(env, { model, text, voice, speed }) {
  const res = await openAI(env, "audio/speech", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      input: text,
      voice: voice || "alloy",
      speed: Number.isFinite(speed) && speed > 0 ? Math.min(Math.max(speed, 0.5), 2.0) : 1.0,
      response_format: "mp3",
    }),
  });
  return bytesToBase64(new Uint8Array(await res.arrayBuffer()));
}

async function readRequest(request) {
  const contentType = request.headers.get("content-type") || "";

  if (contentType.includes("multipart/form-data")) {
    const form = await request.formData();
    const image = form.get("image");
    return {
      audio: form.get("audio"),
      imageBase64: null,
      imageFile: image instanceof File ? image : null,
      text: null,
      prompt: form.get("prompt") || "",
      language: form.get("language") || "",
      outputLanguage: form.get("output_language") || "",
      chatModel: form.get("response_model"),
      sttModel: form.get("transcription_model"),
      ttsModel: form.get("tts_model"),
      voice: form.get("voice"),
      speed: Number(form.get("speech_rate")),
      includeAudio: isTruthy(form.get("include_audio")),
      task: form.get("task") || "assist",
    };
  }

  const body = await request.json();
  return {
    audio: null,
    imageBase64: body.image_base64 || null,
    imageFile: null,
    text: body.text || "",
    prompt: body.prompt || "",
    language: body.language || "",
    outputLanguage: body.output_language || "",
    chatModel: body.response_model,
    sttModel: body.transcription_model,
    ttsModel: body.tts_model,
    voice: body.voice,
    speed: Number(body.speed),
    includeAudio: isTruthy(body.include_audio),
    task: body.task || "assist",
  };
}

async function handle(request, env) {
  if (request.method !== "POST") throw new HttpError(405, "Method not allowed");
  if (!env.OPENAI_API_KEY) throw new HttpError(500, "Worker is not configured");
  if (!env.FIREBASE_PROJECT_ID) throw new HttpError(500, "Worker is not configured");

  const authorization = request.headers.get("authorization") || "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new HttpError(401, "Missing Firebase ID token");
  }
  await verifyFirebaseIdToken(authorization.slice(7).trim(), env.FIREBASE_PROJECT_ID);

  const input = await readRequest(request);

  // task="tts" means: speak this exact text back, do not run it through a model.
  if (input.task === "tts") {
    const text = (input.text || "").trim();
    if (!text) throw new HttpError(400, "Nothing to speak");
    return Response.json({
      transcript: "",
      response_text: text,
      audio_base64: await synthesise(env, {
        model: pickModel(input.ttsModel, ALLOWED_TTS_MODELS, DEFAULTS.tts),
        text,
        voice: input.voice,
        speed: input.speed,
      }),
    });
  }

  let transcript = (input.text || "").trim();
  if (!transcript && input.audio instanceof File) {
    transcript = await transcribe(
      env,
      input.audio,
      pickModel(input.sttModel, ALLOWED_STT_MODELS, DEFAULTS.stt),
      input.language,
    );
  }

  let imageBase64 = input.imageBase64;
  if (!imageBase64 && input.imageFile) {
    imageBase64 = bytesToBase64(new Uint8Array(await input.imageFile.arrayBuffer()));
  }

  // An image with no speech is a valid request: describe what the camera sees.
  if (!transcript && imageBase64) transcript = DEFAULT_SCENE_INSTRUCTION;
  if (!transcript) throw new HttpError(400, "Nothing to process");

  const responseText = await chat(env, {
    model: pickModel(input.chatModel, ALLOWED_CHAT_MODELS, DEFAULTS.chat),
    systemPrompt: input.prompt,
    transcript,
    imageBase64,
    outputLanguage: input.outputLanguage,
  });
  if (!responseText) throw new HttpError(502, "Empty model response");

  let audioBase64 = null;
  if (input.includeAudio) {
    audioBase64 = await synthesise(env, {
      model: pickModel(input.ttsModel, ALLOWED_TTS_MODELS, DEFAULTS.tts),
      text: responseText,
      voice: input.voice,
      speed: input.speed,
    });
  }

  return Response.json({
    transcript,
    response_text: responseText,
    audio_base64: audioBase64,
  });
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      const message = error instanceof HttpError ? error.message : "Internal error";
      if (status >= 500) console.error(error);
      return Response.json({ error: message }, { status });
    }
  },
};
