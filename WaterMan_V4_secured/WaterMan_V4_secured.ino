#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <BLESecurity.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>

// ---------------- Security ----------------
// CHANGE THIS before flashing. This is the PIN your phone will be asked to enter
// the first time it pairs. Keep it out of any public repo/commit.
#define WATERMAN_PASSKEY 921010

class MySecurity : public BLESecurityCallbacks {
  uint32_t onPassKeyRequest() { return 0; } // unused in static-passkey mode
  void onPassKeyNotify(uint32_t pass_key) {}
  bool onSecurityRequest() { return true; }
  bool onConfirmPIN(uint32_t pass_key) { return true; }
  // Note: onAuthenticationComplete is intentionally not overridden here — its
  // parameter type differs between the Bluedroid and NimBLE backends
  // (esp_ble_auth_cmpl_t vs ble_gap_conn_desc*), and this class works with
  // either backend without needing to know which one is active. Pairing
  // success/failure is still visible via nRF Connect and your OS's own
  // pairing prompt even without this log line.
};

// ---------------- Pins ----------------
const int cPin = 8;          // MOSFET gate control pin (pump)
#define RGB_PIN 48            // Onboard RGB LED Pin
#define NUM_PIXELS 1

Adafruit_NeoPixel statusLED(NUM_PIXELS, RGB_PIN, NEO_GRB + NEO_KHZ800);
Preferences prefs;

// ---------------- BLE UUIDs ----------------
#define SERVICE_UUID          "4fafc201-1fb5-459e-8fcc-c5c9c331914c"
#define CONTROL_CHAR_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a9"   // write commands
#define STATUS_CHAR_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26aa"   // read + notify status

BLEServer *pServer;
BLECharacteristic *pControlChar;
BLECharacteristic *pStatusChar;
bool deviceConnected = false;
volatile bool needsAdvertisingRestart = false;

// ---------------- Safety ----------------
const unsigned long MAX_RUN_MS = 180000UL; // 3 minute hard cap (user-selected)

// ---------------- Pump state ----------------
bool isPumpOn = false;
bool timedRunActive = false;
unsigned long pumpStartMillis = 0;
unsigned long pumpRunDurationMs = 0;

// ---------------- Time sync (phone-supplied, drifts after power loss) ----------------
long timeSyncEpoch = 0;
unsigned long timeSyncMillis = 0;
bool timeSynced = false;

// ---------------- Schedule (persisted in flash) ----------------
int schedHour = -1;
int schedMin = -1;
int schedDurationSec = 0;
bool scheduleSet = false;
long lastRunDayIndex = -1; // prevents re-firing within the same day

// ---------------- Helpers ----------------
long currentEpoch() {
  if (!timeSynced) return -1;
  return timeSyncEpoch + (long)((millis() - timeSyncMillis) / 1000UL);
}

void loadSchedule() {
  prefs.begin("waterman", true);
  scheduleSet = prefs.getBool("schedOn", false);
  schedHour = prefs.getInt("schedH", -1);
  schedMin = prefs.getInt("schedM", -1);
  schedDurationSec = prefs.getInt("schedSec", 0);
  prefs.end();
}

void saveSchedule() {
  prefs.begin("waterman", false);
  prefs.putBool("schedOn", scheduleSet);
  prefs.putInt("schedH", schedHour);
  prefs.putInt("schedM", schedMin);
  prefs.putInt("schedSec", schedDurationSec);
  prefs.end();
}

void updateStatus() {
  long remainMs = 0;
  if (timedRunActive) {
    long elapsed = (long)(millis() - pumpStartMillis);
    remainMs = (long)pumpRunDurationMs - elapsed;
    if (remainMs < 0) remainMs = 0;
  }

  char buf[128];
  char schedStr[8];
  if (scheduleSet) {
    snprintf(schedStr, sizeof(schedStr), "%02d:%02d", schedHour, schedMin);
  } else {
    strcpy(schedStr, "NONE");
  }

  snprintf(buf, sizeof(buf),
           "STATE:%s;REMAIN:%ld;SCHED:%s;SCHEDSEC:%d;SYNCED:%d",
           isPumpOn ? "RUNNING" : "IDLE",
           remainMs / 1000,
           schedStr,
           schedDurationSec,
           timeSynced ? 1 : 0);

  pStatusChar->setValue((uint8_t*)buf, strlen(buf));
  if (deviceConnected) {
    pStatusChar->notify();
  }
}

void startPump(unsigned long durationMs) {
  if (durationMs > MAX_RUN_MS) durationMs = MAX_RUN_MS; // hard safety cap, always enforced
  digitalWrite(cPin, HIGH);
  isPumpOn = true;
  timedRunActive = true;
  pumpStartMillis = millis();
  pumpRunDurationMs = durationMs;
  Serial.print("Pump started for (ms): ");
  Serial.println(durationMs);
  updateStatus();
}

void stopPump() {
  digitalWrite(cPin, LOW);
  isPumpOn = false;
  timedRunActive = false;
  statusLED.setPixelColor(0, statusLED.Color(0, 0, 0));
  statusLED.show();
  Serial.println("Pump stopped");
  updateStatus();
}

void handleCommand(String value) {
  value.trim();
  if (value.length() == 0) return;

  Serial.print("Command: ");
  Serial.println(value);

  if (value.equalsIgnoreCase("ON")) {
    startPump(MAX_RUN_MS); // manual hold is capped too; OFF stops it early
  }
  else if (value.equalsIgnoreCase("OFF")) {
    stopPump();
  }
  else if (value.startsWith("RUN:")) {
    long secs = value.substring(4).toInt();
    if (secs > 0) startPump((unsigned long)secs * 1000UL);
  }
  else if (value.startsWith("SCHED:SET:")) {
    // format: SCHED:SET:HH:MM:seconds
    String rest = value.substring(10); // "HH:MM:seconds"
    int c1 = rest.indexOf(':');
    int c2 = rest.indexOf(':', c1 + 1);
    if (c1 > 0 && c2 > c1) {
      int hh = rest.substring(0, c1).toInt();
      int mm = rest.substring(c1 + 1, c2).toInt();
      long sec = rest.substring(c2 + 1).toInt();
      if (sec > (long)(MAX_RUN_MS / 1000UL)) sec = MAX_RUN_MS / 1000UL;
      if (hh >= 0 && hh < 24 && mm >= 0 && mm < 60 && sec > 0) {
        schedHour = hh;
        schedMin = mm;
        schedDurationSec = (int)sec;
        scheduleSet = true;
        lastRunDayIndex = -1; // allow it to fire today if time hasn't passed yet
        saveSchedule();
        Serial.println("Schedule saved");
      }
    }
  }
  else if (value.equalsIgnoreCase("SCHED:CLEAR")) {
    scheduleSet = false;
    saveSchedule();
    Serial.println("Schedule cleared");
  }
  else if (value.startsWith("TIME:")) {
    long epoch = value.substring(5).toInt();
    if (epoch > 0) {
      timeSyncEpoch = epoch;
      timeSyncMillis = millis();
      timeSynced = true;
      Serial.println("Time synced from phone");
    }
  }
  else if (value.equalsIgnoreCase("STATUS?")) {
    // fall through, updateStatus() below covers it
  }
  else {
    Serial.println("Unrecognized command");
  }

  updateStatus();
}

// ---------------- BLE callbacks ----------------
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    Serial.println("Phone connected via Bluetooth!");
  }
  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
    Serial.println("Phone disconnected.");
    // Calling startAdvertising() directly here is unreliable after a secure/
    // bonded disconnect — the BLE stack isn't always done tearing down the
    // old link yet, so the call can silently no-op. Defer it to loop().
    needsAdvertisingRestart = true;
  }
};

class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String value = String(pCharacteristic->getValue().c_str());
    handleCommand(value);
  }
};

// ---------------- Setup ----------------
void setup() {
  Serial.begin(115200);
  pinMode(cPin, OUTPUT);
  digitalWrite(cPin, LOW);

  statusLED.begin();
  statusLED.setBrightness(80);
  statusLED.clear();
  statusLED.show();

  loadSchedule();

  Serial.println("Starting BLE Configuration...");
  BLEDevice::init("WaterMan-V2");

  // ---- Security: require bonding + a fixed passkey before any read/write works ----
  // Uses the current unified BLESecurity static API, which works whether the
  // underlying stack is Bluedroid or NimBLE (arduino-esp32 3.x supports both).
  BLEDevice::setSecurityCallbacks(new MySecurity());
  BLESecurity::setAuthenticationMode(true, true, true); // bonding, MITM protection, secure connections
  BLESecurity::setCapability(ESP_IO_CAP_OUT); // "has a display" so peer is asked to enter our fixed passkey
  BLESecurity::setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  BLESecurity::setRespEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  BLESecurity::setKeySize(16);
  BLESecurity::setPassKey(true, WATERMAN_PASSKEY); // static passkey, same PIN every pairing

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pControlChar = pService->createCharacteristic(
      CONTROL_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
  pControlChar->setValue("OFF");
  pControlChar->setCallbacks(new ControlCallbacks());
  pControlChar->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM | ESP_GATT_PERM_WRITE_ENC_MITM);

  pStatusChar = pService->createCharacteristic(
      STATUS_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902()); // required for notify
  pStatusChar->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  pServer->startAdvertising();

  updateStatus();
  Serial.println("Bluetooth Active! Advertising as 'WaterMan-V2'");
}

// ---------------- Main loop ----------------
void loop() {
  // 0. Resume advertising after a disconnect (deferred from onDisconnect() —
  // calling startAdvertising() directly in that callback is unreliable right
  // after a secure/bonded disconnect since the stack is still tearing down
  // the old link; a short delay here lets it settle first).
  if (needsAdvertisingRestart) {
    needsAdvertisingRestart = false;
    delay(500);
    pServer->startAdvertising();
    Serial.println("Resumed advertising after disconnect");
  }

  // 1. Non-blocking timed-run expiry (covers RUN:, manual ON cap, and schedule-triggered runs)
  if (timedRunActive && (millis() - pumpStartMillis >= pumpRunDurationMs)) {
    stopPump();
  }

  // 2. LED feedback
  static unsigned long lastLEDChange = 0;
  if (isPumpOn) {
    if (millis() - lastLEDChange >= 50) {
      lastLEDChange = millis();
      int r = random(0, 256), g = random(0, 256), b = random(0, 256);
      statusLED.setPixelColor(0, statusLED.Color(r, g, b));
      statusLED.show();
    }
  } else {
    // Idle indicator: dim blue if time is synced, slow amber blink if not
    if (timeSynced) {
      statusLED.setPixelColor(0, statusLED.Color(0, 0, 15));
      statusLED.show();
    } else if (millis() - lastLEDChange >= 800) {
      lastLEDChange = millis();
      static bool blinkOn = false;
      blinkOn = !blinkOn;
      statusLED.setPixelColor(0, blinkOn ? statusLED.Color(20, 10, 0) : statusLED.Color(0, 0, 0));
      statusLED.show();
    }
  }

  // 3. Schedule check (once per second is plenty)
  static unsigned long lastSchedCheck = 0;
  if (scheduleSet && timeSynced && millis() - lastSchedCheck >= 1000) {
    lastSchedCheck = millis();
    long epoch = currentEpoch();
    long dayIndex = epoch / 86400L;
    long secOfDay = epoch % 86400L;
    int hh = secOfDay / 3600;
    int mm = (secOfDay % 3600) / 60;

    if (hh == schedHour && mm == schedMin && dayIndex != lastRunDayIndex && !isPumpOn) {
      lastRunDayIndex = dayIndex;
      startPump((unsigned long)schedDurationSec * 1000UL);
      Serial.println("Scheduled watering triggered");
    }
  }

  // 4. Periodic status notify while running, so app countdown stays live
  static unsigned long lastStatusPush = 0;
  if (timedRunActive && millis() - lastStatusPush >= 1000) {
    lastStatusPush = millis();
    updateStatus();
  }

  // 5. Serial fallback (unchanged interface, routed through same command handler)
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    handleCommand(command);
  }
}
