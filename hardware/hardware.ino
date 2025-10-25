#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <string>

const int buzzer = 21;
const int button = 35;
const int trig_pin0 = 13;
const int echo_pin0 = 0;
const int trig_pin1 = 16;
const int echo_pin1 = 17;
const int trig_pin2 = 5;
const int echo_pin2 = 18;

float read_dist(const int trig_pin, const int echo_pin) {
    digitalWrite(trig_pin, LOW);
    delay(2);

    digitalWrite(trig_pin, HIGH);
    delay(10);
    digitalWrite(trig_pin, LOW);

    float timing = pulseIn(echo_pin, HIGH);
    float distance = (timing * 0.034) / 2;
    return distance;
}

void beep0() {
    digitalWrite(buzzer, HIGH);
}

void beep1() {
    digitalWrite(buzzer, HIGH);
    delay(200);
}

#define SERVICE_UUID           "96f30d22-26f5-4673-a4f6-7b4431e7c5b6"
#define DISTANCE_CHAR_UUID     "96f30d22-26f5-4673-a4f6-7b4431e7c5b7"
#define SETTINGS_CHAR_UUID     "96f30d22-26f5-4673-a4f6-7b4431e7c5b8"

BLEServer* pServer = NULL;
BLECharacteristic* pDistanceCharacteristic = NULL;
BLECharacteristic* pSettingsCharacteristic = NULL;
bool deviceConnected = false;

int currentCautionCm = 120;
int currentDangerCm = 50;

class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Device connected.");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Device disconnected. Restarting advertising...");
      BLEDevice::startAdvertising();
    }
};

class SettingsCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();

      if (rxValue.length() == 2) {
        currentCautionCm = (uint8_t)rxValue[0];
        currentDangerCm = (uint8_t)rxValue[1];

        Serial.printf("Settings Received: Caution=%d cm, Danger=%d cm\n",
                      currentCautionCm, currentDangerCm);
      }
    }
};

void initBLE() {
  BLEDevice::init("SmartCane");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pDistanceCharacteristic = pService->createCharacteristic(
                      DISTANCE_CHAR_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pDistanceCharacteristic->addDescriptor(new BLE2902());

  pSettingsCharacteristic = pService->createCharacteristic(
                      SETTINGS_CHAR_UUID,
                      BLECharacteristic::PROPERTY_WRITE
                    );
  pSettingsCharacteristic->setCallbacks(new SettingsCallbacks());

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  
  Serial.println("BLE Advertising started. Waiting for connection...");
}

void setup() {
    pinMode(echo_pin0, INPUT);
    pinMode(echo_pin1, INPUT);
    pinMode(echo_pin2, INPUT);
    pinMode(button, INPUT_PULLUP);
    pinMode(trig_pin0, OUTPUT);
    pinMode(trig_pin1, OUTPUT);
    pinMode(trig_pin2, OUTPUT);
    pinMode(buzzer, OUTPUT);

    digitalWrite(trig_pin0, LOW);
    digitalWrite(trig_pin1, LOW);
    digitalWrite(trig_pin2, LOW);
    digitalWrite(buzzer, LOW);
        
    Serial.begin(115200);
    initBLE();
    Serial.println("The device started, now you can pair it with bluetooth!");
}

bool toggle = false;
uint8_t error = 20.0;
bool button_toggle = true;

// ✅ Debounce variables
static unsigned long lastDebounceTime = 0;
static const unsigned long debounceDelay = 50;
static bool lastSteadyState = HIGH;
static bool lastReading = HIGH;

void loop() {

    // ✅ Debounced Button Logic
    bool currentReading = digitalRead(button);
    if (currentReading != lastReading) {
        lastDebounceTime = millis();
    }
    lastReading = currentReading;

    if ((millis() - lastDebounceTime) > debounceDelay) {
        if (currentReading != lastSteadyState) {
            lastSteadyState = currentReading;

            if (lastSteadyState == LOW) {
                button_toggle = !button_toggle;
                digitalWrite(buzzer, LOW);
            }
        }
    }

    if (!button_toggle) {
        uint8_t v = pSettingsCharacteristic->getValue()[0];
        if ((v & 0x80) == 0x80) {
            digitalWrite(buzzer, HIGH);
        } else {
            digitalWrite(buzzer, LOW);
        }
        delay(2);
        return;
    }
    
    float dist0 = read_dist(trig_pin0, echo_pin0);
    float dist1 = read_dist(trig_pin1, echo_pin1);
    float dist2 = read_dist(trig_pin2, echo_pin2);

    const float maximum = 255.0;
    uint8_t dist0_i = min(dist0, maximum);
    uint8_t dist1_i = min(dist1, maximum);
    uint8_t dist2_i = min(dist2, maximum);
    uint8_t sensorData[3] = { dist0_i, dist1_i, dist2_i };

    pDistanceCharacteristic->setValue(sensorData, 3);
    pDistanceCharacteristic->notify();

    uint8_t v = pSettingsCharacteristic->getValue()[0];
    if (v != 0) {
        error = v & 0x7f;
    }
    if ((dist0 <= error) || (dist1 <= error) || (dist2 <= error)) {
        digitalWrite(buzzer, HIGH);
        Serial.println("high dist");
    } else if ((v & 0x80) == 0x80) {
        digitalWrite(buzzer, HIGH);
        Serial.println("high");
    } else {
        digitalWrite(buzzer, LOW);
        Serial.println("low");
    }

    delay(2);
}
