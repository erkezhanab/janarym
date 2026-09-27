#include "esp_camera.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include "esp_http_server.h"
#include <SPIFFS.h>
#define DEFAULT_FLASH_FS SPIFFS
#include <FirebaseESP32.h>
#include <FS.h>
#include "addons/TokenHelper.h"

#include "secrets.h"

// ── AI-Thinker ESP32-CAM pin map ─────────────────────────────
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

#define BUTTON_PIN        15
#define FLASH_LED_PIN      4

#define FRAME_DELAY_MS    40
#define MAX_STREAM_CLIENTS 2

static const char* STREAM_BOUNDARY = "\r\n--frame\r\n";
static const char* STREAM_PART     = "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";
static const char* BLE_DEVICE_NAME = "JANARYM-CAM";
static const char* BLE_SERVICE_UUID = "7A0247E7-7E88-4B71-9A5D-E3A8A4D31F01";
static const char* BLE_CHAR_UUID = "7A0247E7-7E88-4B71-9A5D-E3A8A4D31F02";

httpd_handle_t stream_httpd = NULL;
BLECharacteristic* cameraInfoCharacteristic = nullptr;
static volatile int activeStreamClients = 0;
FirebaseAuth auth;
FirebaseConfig firebaseConfig;

// 👉 сохраняем последний снимок
static camera_fb_t* lastFrame = NULL;
static String lastPhotoPath = "/last_photo.jpg";

// ── BLE ──────────────────────────────────────────────────────
static void startBLEBeacon(const String& ipAddress) {
    BLEDevice::init(BLE_DEVICE_NAME);
    BLEServer* server = BLEDevice::createServer();
    BLEService* service = server->createService(BLE_SERVICE_UUID);

    cameraInfoCharacteristic = service->createCharacteristic(
        BLE_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ
    );

    cameraInfoCharacteristic->setValue(ipAddress.c_str());
    service->start();

    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(BLE_SERVICE_UUID);
    advertising->setScanResponse(true);
    advertising->start();
}

static void setupFirebase() {
    firebaseConfig.api_key = API_KEY;
    firebaseConfig.database_url = DATABASE_URL;
    firebaseConfig.token_status_callback = tokenStatusCallback;
    firebaseConfig.timeout.serverResponse = 10000;
    firebaseConfig.timeout.socketConnection = 10000;
    auth.user.email = USER_EMAIL;
    auth.user.password = USER_PASSWORD;

    Firebase.begin(&firebaseConfig, &auth);
    Firebase.reconnectWiFi(true);

    Serial.print("Firebase connecting");
    while (!Firebase.ready()) {
        delay(500);
        Serial.print(".");
    }
    Serial.println();
    Serial.println("Firebase ready");
}

static bool uploadPhotoToFirebaseStorage(camera_fb_t* fb, String& downloadUrl, String& storagePath) {
    if (!Firebase.ready()) {
        Serial.println("Firebase not ready");
        return false;
    }

    if (!fb) {
        Serial.println("Firebase upload skipped: empty frame");
        return false;
    }

    const char* idToken = Firebase.getToken();
    if (!idToken || strlen(idToken) == 0) {
        Serial.println("Firebase upload skipped: missing ID token");
        return false;
    }

    WiFiClientSecure client;
    client.setInsecure();

    HTTPClient http;
    if (!http.begin(client, FIREBASE_UPLOAD_URL)) {
        Serial.println("Firebase upload failed: HTTP begin error");
        return false;
    }

    String fileName = String("photo_") + String((uint32_t)millis()) + ".jpg";

    http.setTimeout(20000);
    http.addHeader("Authorization", String("Bearer ") + String(idToken));
    http.addHeader("Content-Type", "image/jpeg");
    http.addHeader("X-File-Name", fileName);
    http.addHeader("X-Device-IP", WiFi.localIP().toString());

    int httpCode = http.sendRequest("POST", fb->buf, fb->len);
    String response = http.getString();
    http.end();

    if (httpCode != HTTP_CODE_OK) {
        Serial.print("Firebase upload failed: HTTP ");
        Serial.println(httpCode);
        if (response.length() > 0) {
            Serial.println(response);
        }
        return false;
    }

    FirebaseJson json;
    FirebaseJsonData jsonData;
    if (!json.setJsonData(response)) {
        Serial.println("Firebase upload failed: invalid JSON response");
        Serial.println(response);
        return false;
    }

    if (json.get(jsonData, "download_url") && jsonData.success) {
        downloadUrl = jsonData.stringValue;
    }

    if (json.get(jsonData, "storage_path") && jsonData.success) {
        storagePath = jsonData.stringValue;
    }

    Serial.println("Firebase Storage upload ok");
    if (storagePath.length() > 0) {
        Serial.print("Storage path: ");
        Serial.println(storagePath);
    }
    if (downloadUrl.length() > 0) {
        Serial.print("Download URL: ");
        Serial.println(downloadUrl);
    }
    return true;
}

// ── AUTH ─────────────────────────────────────────────────────
// Both endpoints require "Authorization: Bearer <STREAM_AUTH_TOKEN>".
// Debug builds additionally accept "?token=<...>" so the stream can be opened
// from a browser or curl while developing; release builds do not.
static bool tokenMatches(const char* candidate) {
    const size_t expectedLen = strlen(STREAM_AUTH_TOKEN);
    if (strlen(candidate) != expectedLen) return false;
    uint8_t diff = 0;
    for (size_t i = 0; i < expectedLen; i++) {
        diff |= (uint8_t)(candidate[i] ^ STREAM_AUTH_TOKEN[i]);
    }
    return diff == 0;
}

static bool isAuthorized(httpd_req_t* req) {
    char header[160];
    if (httpd_req_get_hdr_value_str(req, "Authorization", header, sizeof(header)) == ESP_OK) {
        const char* prefix = "Bearer ";
        const size_t prefixLen = strlen(prefix);
        if (strncmp(header, prefix, prefixLen) == 0 && tokenMatches(header + prefixLen)) {
            return true;
        }
    }

#ifdef JANARYM_DEBUG_STREAM_TOKEN_QUERY
    size_t queryLen = httpd_req_get_url_query_len(req) + 1;
    if (queryLen > 1 && queryLen < 192) {
        char query[192];
        char value[160];
        if (httpd_req_get_url_query_str(req, query, queryLen) == ESP_OK &&
            httpd_query_key_value(query, "token", value, sizeof(value)) == ESP_OK &&
            tokenMatches(value)) {
            return true;
        }
    }
#endif

    return false;
}

static esp_err_t rejectUnauthorized(httpd_req_t* req) {
    httpd_resp_set_status(req, "401 Unauthorized");
    httpd_resp_set_hdr(req, "WWW-Authenticate", "Bearer");
    httpd_resp_send(req, "Unauthorized", HTTPD_RESP_USE_STRLEN);
    return ESP_OK;
}

// ── STREAM ───────────────────────────────────────────────────
static esp_err_t stream_handler(httpd_req_t* req) {
    if (!isAuthorized(req)) return rejectUnauthorized(req);

    if (activeStreamClients >= MAX_STREAM_CLIENTS) {
        httpd_resp_set_status(req, "503 Service Unavailable");
        httpd_resp_send(req, "Too many stream clients", HTTPD_RESP_USE_STRLEN);
        return ESP_OK;
    }

    activeStreamClients++;

    camera_fb_t* fb = NULL;
    char part_buf[64];

    httpd_resp_set_type(req, "multipart/x-mixed-replace;boundary=frame");

    esp_err_t res = ESP_OK;

    while (res == ESP_OK) {
        fb = esp_camera_fb_get();
        if (!fb) { res = ESP_FAIL; break; }

        res = httpd_resp_send_chunk(req, STREAM_BOUNDARY, strlen(STREAM_BOUNDARY));

        if (res == ESP_OK) {
            size_t hlen = snprintf(part_buf, sizeof(part_buf), STREAM_PART, fb->len);
            res = httpd_resp_send_chunk(req, part_buf, hlen);
        }

        if (res == ESP_OK) {
            res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
        }

        esp_camera_fb_return(fb);
        vTaskDelay(pdMS_TO_TICKS(FRAME_DELAY_MS));
    }

    activeStreamClients--;
    return res;
}

// ── Save photo to SPIFFS ─────────────────────────────────────
static bool savePhotoToSPIFFS(camera_fb_t* fb) {
    File file = SPIFFS.open(lastPhotoPath, "w");
    if (!file) {
        Serial.println("Failed to open file for writing");
        return false;
    }
    
    size_t written = file.write(fb->buf, fb->len);
    file.close();
    
    Serial.printf("Saved photo to SPIFFS: %d bytes\n", written);
    return written > 0;
}
static esp_err_t snapshot_handler(httpd_req_t* req) {
    if (!isAuthorized(req)) return rejectUnauthorized(req);

    // Try to serve from SPIFFS first
    File file = SPIFFS.open(lastPhotoPath, "r");
    if (file) {
        size_t size = file.size();
        httpd_resp_set_type(req, "image/jpeg");
        httpd_resp_set_hdr(req, "Content-Length", String(size).c_str());
        
        // Stream file in chunks
        uint8_t buffer[2048];
        while (file.available()) {
            size_t read = file.read(buffer, sizeof(buffer));
            httpd_resp_send_chunk(req, (const char*)buffer, read);
        }
        file.close();
        return ESP_OK;
    }

    // Fallback to RAM (if any)
    if (!lastFrame) {
        httpd_resp_send(req, "No snapshot yet", HTTPD_RESP_USE_STRLEN);
        return ESP_OK;
    }

    httpd_resp_set_type(req, "image/jpeg");
    httpd_resp_send(req, (const char*)lastFrame->buf, lastFrame->len);
    return ESP_OK;
}

// ── SERVER ───────────────────────────────────────────────────
void startServer() {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = 80;

    if (httpd_start(&stream_httpd, &config) == ESP_OK) {
        httpd_uri_t stream_uri = { "/stream", HTTP_GET, stream_handler, NULL };
        httpd_uri_t snap_uri   = { "/snapshot", HTTP_GET, snapshot_handler, NULL };

        httpd_register_uri_handler(stream_httpd, &stream_uri);
        httpd_register_uri_handler(stream_httpd, &snap_uri);
    }
}

// ── SETUP ────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);

    // Initialize SPIFFS for photo storage
    if (!SPIFFS.begin(true)) {
        Serial.println("SPIFFS mount failed");
    } else {
        Serial.println("SPIFFS mounted");
    }

    pinMode(FLASH_LED_PIN, OUTPUT);
    digitalWrite(FLASH_LED_PIN, LOW);

    pinMode(BUTTON_PIN, INPUT_PULLUP);

    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer   = LEDC_TIMER_0;
    config.pin_d0 = Y2_GPIO_NUM;
    config.pin_d1 = Y3_GPIO_NUM;
    config.pin_d2 = Y4_GPIO_NUM;
    config.pin_d3 = Y5_GPIO_NUM;
    config.pin_d4 = Y6_GPIO_NUM;
    config.pin_d5 = Y7_GPIO_NUM;
    config.pin_d6 = Y8_GPIO_NUM;
    config.pin_d7 = Y9_GPIO_NUM;
    config.pin_xclk = XCLK_GPIO_NUM;
    config.pin_pclk = PCLK_GPIO_NUM;
    config.pin_vsync = VSYNC_GPIO_NUM;
    config.pin_href = HREF_GPIO_NUM;
    config.pin_sccb_sda = SIOD_GPIO_NUM;
    config.pin_sccb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;
    config.pixel_format = PIXFORMAT_JPEG;
    config.frame_size = FRAMESIZE_QQVGA;  // 160x120 - smallest option
    config.jpeg_quality = 20;  // Max compression
    config.fb_count = psramFound() ? 2 : 1;

    if (esp_camera_init(&config) != ESP_OK) {
        Serial.println("Camera init failed!");
        return;
    }

    WiFi.begin(WIFI_SSID, WIFI_PASS);

    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }

    Serial.println();
    Serial.println(WiFi.localIP());

    setupFirebase();
    startServer();
    startBLEBeacon(WiFi.localIP().toString());

    Serial.println("READY");
}

// ── LOOP ─────────────────────────────────────────────────────
void loop() {
    static bool lastState = HIGH;
    bool currentState = digitalRead(BUTTON_PIN);

    if (currentState == LOW && lastState == HIGH) {
        Serial.println("📸 Capture");

        digitalWrite(FLASH_LED_PIN, HIGH);
        delay(100);

        camera_fb_t* fb = esp_camera_fb_get();

        digitalWrite(FLASH_LED_PIN, LOW);

        if (fb) {
            // Save to SPIFFS instead of Telegram (no network needed)
            if (savePhotoToSPIFFS(fb)) {
                Serial.println("✅ Photo saved to SPIFFS");
                Serial.print("View at: http://");
                Serial.print(WiFi.localIP());
                Serial.println("/snapshot");

                String downloadUrl;
                String storagePath;
                if (!uploadPhotoToFirebaseStorage(fb, downloadUrl, storagePath)) {
                    Serial.println("❌ Firebase Storage upload failed");
                }
            } else {
                Serial.println("❌ Save failed");
            }
            esp_camera_fb_return(fb);
        } else {
            Serial.println("❌ Capture failed");
        }
    }

    lastState = currentState;
    delay(10);
}
