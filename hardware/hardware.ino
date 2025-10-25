#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <string>

// Pin constants
const int buzzer = 16;
const int trig_pin = 17;
const int echo_pin = 5;

float read_dist() {
  digitalWrite(trig_pin, LOW);
  delay(2);

  digitalWrite(trig_pin, HIGH);
  delay(10);
  digitalWrite(trig_pin, LOW);

  float timing = pulseIn(echo_pin, HIGH);
  float distance = (timing * 0.034) / 2;
  return distance;
}

// 1. UUID Definitions (Must match Flutter app's ble_service.dart)
// REPLACE THESE WITH YOUR ACTUAL 128-bit UUIDs
#define SERVICE_UUID           "96f30d22-26f5-4673-a4f6-7b4431e7c5b6" 
#define DISTANCE_CHAR_UUID     "96f30d22-26f5-4673-a4f6-7b4431e7c5b7" // Notify characteristic
#define SETTINGS_CHAR_UUID     "96f30d22-26f5-4673-a4f6-7b4431e7c5b8" // Write characteristic

// Global BLE Objects
BLEServer* pServer = NULL;
BLECharacteristic* pDistanceCharacteristic = NULL;
BLECharacteristic* pSettingsCharacteristic = NULL;
bool deviceConnected = false;

// Current Settings received from app
int currentCautionCm = 120;
int currentDangerCm = 50;

// 2. Callback Class for Connection/Disconnection Events
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Device connected.");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Device disconnected. Restarting advertising...");
      // Allows the device to be discoverable again immediately
      BLEDevice::startAdvertising(); 
    }
};

// 3. Callback Class for Handling Data Written to Settings Characteristic
class SettingsCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();

      if (rxValue.length() == 2) {
        // Assuming the app sends two 1-byte integers: [CautionCm, DangerCm]
        currentCautionCm = (uint8_t)rxValue[0];
        currentDangerCm = (uint8_t)rxValue[1];
        
        Serial.printf("Settings Received: Caution=%d cm, Danger=%d cm\n", currentCautionCm, currentDangerCm);
      }
    }
};

// 4. Initialization of the BLE Server
void initBLE() {
  // Initialize BLE Device, giving it the name your app is looking for
  BLEDevice::init("SmartCane");

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create Distance Characteristic (READ/NOTIFY)
  pDistanceCharacteristic = pService->createCharacteristic(
                      DISTANCE_CHAR_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY 
                    );
  // Add a Descriptor to enable notifications (required for Flutter)
  pDistanceCharacteristic->addDescriptor(new BLE2902());

  // Create Settings Characteristic (WRITE)
  pSettingsCharacteristic = pService->createCharacteristic(
                      SETTINGS_CHAR_UUID,
                      BLECharacteristic::PROPERTY_WRITE
                    );
  pSettingsCharacteristic->setCallbacks(new SettingsCallbacks());

  // Start the service
  pService->start();

  // Start Advertising (makes the device visible)
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID); // Critical for filter-based scanning
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  
  Serial.println("BLE Advertising started. Waiting for connection...");
}


void setup() {
    pinMode(echo_pin, INPUT);
    pinMode(trig_pin, OUTPUT);
    pinMode(buzzer, OUTPUT);
    //
    // digitalWrite(trig_pin, LOW);
    // digitalWrite(buzzer, LOW);
        
    Serial.begin(115200);
    // SerialBT.begin("ESP32test1");
    Serial.println("The device started, now you can pair it with bluetooth!");
    initBLE();
}

void loop() {
    
    float dist = read_dist();
    // char buff[26];
    // sprintf(buff, "{\"distace0\":\"%f\",}\n", dist);
    // SerialBT.write( (uint8_t*) buff, 26);
    // Serial.write( (uint8_t*) buff, 26);
    // Serial.write("\n\r");
    const float maximum = 255.0;
    uint8_t dist0_i = min(dist, maximum);
    uint8_t sensorData[3] = { dist0_i, 5, 10 };

    // Set the new value and notify the connected client
    pDistanceCharacteristic->setValue(sensorData, 3);
    pDistanceCharacteristic->notify(); 
    if (dist <= 5.0) {
        Serial.println("\rbuzz up");
        digitalWrite(buzzer, HIGH);
    } else {
        digitalWrite(buzzer, LOW);
    }
    // if (SerialBT.available()) {
    //   Serial.write(SerialBT.read());
    // }
    
    // Serial.print("Distance: ");
    // Serial.print(distance);
    // Serial.print("cm | ");
    // Serial.print(distance / 2.54);
    // Serial.println("in");

    // if (distance <= 50) {
    //     digitalWrite(buzzer, HIGH);
    // } else {
    //     digitalWrite(buzzer, LOW);
    // }
    //
    delay(2);
}


