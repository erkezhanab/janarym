const admin = require("firebase-admin");
const { randomUUID } = require("crypto");
const { onRequest } = require("firebase-functions/v2/https");

admin.initializeApp();

function getStorageBucketName() {
  return process.env.FIREBASE_STORAGE_BUCKET ||
    process.env.STORAGE_BUCKET ||
    (process.env.GCLOUD_PROJECT ? `${process.env.GCLOUD_PROJECT}.firebasestorage.app` : "");
}

function buildDownloadUrl(bucketName, storagePath, downloadToken) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(storagePath)}?alt=media&token=${downloadToken}`;
}

async function verifyFirebaseBearerToken(req, res) {
  const authHeader = req.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: { message: "Missing Firebase bearer token" } });
    return null;
  }

  const firebaseToken = authHeader.slice("Bearer ".length).trim();
  try {
    return await admin.auth().verifyIdToken(firebaseToken);
  } catch (error) {
    res.status(401).json({ error: { message: "Invalid Firebase token" } });
    return null;
  }
}

exports.createOpenAIRealtimeSession = onRequest(
  {
    cors: false,
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: { message: "Method not allowed" } });
      return;
    }

    const decodedToken = await verifyFirebaseBearerToken(req, res);
    if (!decodedToken) {
      return;
    }

    const openAIKey = process.env.OPENAI_API_KEY;
    if (!openAIKey) {
      res.status(500).json({ error: { message: "OPENAI_API_KEY is not configured" } });
      return;
    }

    const body = req.body && typeof req.body === "object" ? req.body : {};
    const model = typeof body.model === "string" && body.model ? body.model : "gpt-realtime";
    const voice = typeof body.voice === "string" && body.voice ? body.voice : "cedar";
    const language = typeof body.language === "string" && body.language ? body.language : "ru";

    const sessionPayload = {
      session: {
        type: "realtime",
        model,
        voice,
        modalities: ["audio"],
        input_audio_format: "pcm16",
        output_audio_format: "pcm16",
        input_audio_noise_reduction: { type: "near_field" },
        input_audio_transcription: {
          model: "gpt-4o-transcribe",
          language,
        },
      },
    };

    const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(sessionPayload),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message =
        data?.error?.message ||
        data?.message ||
        `OpenAI session creation failed with HTTP ${response.status}`;
      res.status(response.status).json({ error: { message } });
      return;
    }

    const clientSecret = data?.client_secret?.value;
    const expiresAt = data?.client_secret?.expires_at;
    if (!clientSecret || !expiresAt) {
      res.status(502).json({ error: { message: "OpenAI response did not include a client secret" } });
      return;
    }

    res.status(200).json({
      client_secret: clientSecret,
      expires_at: expiresAt,
      model,
    });
  }
);

exports.uploadEspSnapshot = onRequest(
  {
    cors: false,
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: { message: "Method not allowed" } });
      return;
    }

    const decodedToken = await verifyFirebaseBearerToken(req, res);
    if (!decodedToken) {
      return;
    }

    if (!req.rawBody || req.rawBody.length === 0) {
      res.status(400).json({ error: { message: "Missing JPEG body" } });
      return;
    }

    const bucketName = getStorageBucketName();
    if (!bucketName) {
      res.status(500).json({ error: { message: "Storage bucket is not configured" } });
      return;
    }

    const contentType = req.get("Content-Type") || "image/jpeg";
    const extension = contentType.includes("png") ? "png" : "jpg";
    const deviceIp = (req.get("X-Device-IP") || "").trim();
    const requestedFileName = (req.get("X-File-Name") || "").trim();
    const safeFileName = requestedFileName.replace(/[^a-zA-Z0-9._-]/g, "_");
    const objectName = safeFileName || `snapshot_${Date.now()}.${extension}`;
    const storagePath = `esp32-captures/${decodedToken.uid}/${objectName}`;
    const downloadToken = randomUUID();

    try {
      const bucket = admin.storage().bucket(bucketName);
      const file = bucket.file(storagePath);

      const metadata = {
        contentType,
        cacheControl: "private, max-age=0, no-transform",
        metadata: {
          firebaseStorageDownloadTokens: downloadToken,
          uploadedBy: decodedToken.uid,
        },
      };

      if (deviceIp) {
        metadata.metadata.deviceIp = deviceIp;
      }

      await file.save(req.rawBody, {
        metadata,
        resumable: false,
      });

      res.status(200).json({
        bucket: bucket.name,
        content_type: contentType,
        download_url: buildDownloadUrl(bucket.name, storagePath, downloadToken),
        size: req.rawBody.length,
        storage_path: storagePath,
      });
    } catch (error) {
      console.error("ESP snapshot upload failed", error);
      res.status(500).json({
        error: {
          message: error instanceof Error ? error.message : "Storage upload failed",
        },
      });
    }
  }
);
