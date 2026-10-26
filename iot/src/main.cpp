#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <Firebase.h>
#include <Wire.h>
#include <BH1750.h>
#include <DHT.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ==========================================
// 1. KONFIGURASI WIFI & FIREBASE
// ==========================================
#define WIFI_SSID "Auditorium"
#define WIFI_PASSWORD "gloryglorymanunited"

// URL Realtime Database (tanpa "https://" dan tanpa "/")
#define FIREBASE_HOST "smart-greenhouse-ad587-default-rtdb.asia-southeast1.firebasedatabase.app"

// ==========================================
// 2. KONFIGURASI HARDWARE
// ==========================================
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

#define DHTPIN 2       // Pin D4 NodeMCU (GPIO 2)
#define DHTTYPE DHT22

DHT dht(DHTPIN, DHTTYPE);
BH1750 lightMeter;
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

void setup() {
  Serial.begin(115200);
  Wire.begin(D2, D1); // SDA = D2, SCL = D1

  // Inisialisasi OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("[ERROR] OLED tidak terdeteksi!"));
  } else {
    display.clearDisplay();
    display.setTextColor(WHITE);
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("Connecting WiFi...");
    display.display();
  }

  // Inisialisasi Sensor
  dht.begin();
  lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);

  // Hubungkan ke WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Menghubungkan ke WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Terhubung!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // Inisialisasi Firebase (Mode Publik / Test Mode)
  config.database_url = FIREBASE_HOST;
  config.signer.test_mode = true;

  Firebase.reconnectWiFi(true);
  fbdo.setBSSLBufferSize(4096, 1024);
  Firebase.begin(&config, &auth);
}

void loop() {
  delay(2000); // Jeda pembacaan DHT22

  float temp = dht.readTemperature();
  float hum = dht.readHumidity();
  float lux = lightMeter.readLightLevel();

  // Validasi pembacaan sensor DHT22
  if (isnan(temp) || isnan(hum)) {
    Serial.println("[ERROR] Gagal membaca dari sensor DHT22!");
    return;
  }

  // 1. Kirim Data ke Firebase Realtime Database
  if (Firebase.setFloat(fbdo, "/greenhouse/suhu", temp)) {
    Serial.print("Suhu terkirim: "); Serial.println(temp);
  } else {
    Serial.print("Gagal kirim Suhu: "); Serial.println(fbdo.errorReason());
  }

  if (Firebase.setFloat(fbdo, "/greenhouse/kelembapan", hum)) {
    Serial.print("Kelembapan terkirim: "); Serial.println(hum);
  } else {
    Serial.print("Gagal kirim Kelembapan: "); Serial.println(fbdo.errorReason());
  }

  if (Firebase.setFloat(fbdo, "/greenhouse/cahaya", lux)) {
    Serial.print("Cahaya terkirim: "); Serial.println(lux);
  } else {
    Serial.print("Gagal kirim Cahaya: "); Serial.println(fbdo.errorReason());
  }

  // 2. Tampilkan Data di Layar OLED
  display.clearDisplay();
  
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("GREENHOUSE (ONLINE)");
  display.println("---------------------");

  display.setCursor(0, 18);
  display.print("Suhu   : "); display.print(temp, 1); display.println(" C");

  display.setCursor(0, 32);
  display.print("Lembap : "); display.print(hum, 1); display.println(" %");

  display.setCursor(0, 46);
  display.print("Cahaya : "); display.print(lux, 0); display.println(" lx");

  display.display();
}