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
    // Ensure all pins are initialized correctly before use
    digitalWrite(trig_pin, LOW);
    delayMicroseconds(2);

    digitalWrite(trig_pin, HIGH);
    delayMicroseconds(10);
    digitalWrite(trig_pin, LOW);

    // Measure the echo pulse width
    float timing = pulseIn(echo_pin, HIGH, 15000); // 15ms timeout for reliable operation
    
    // Calculate distance (speed of sound ~0.034 cm/µs)
    float distance = (timing * 0.034) / 2;
    return distance;
}
void beep0() {
    // This function is currently unused but kept for reference
    digitalWrite(buzzer, HIGH);
}
void beep1() {
    // This function is currently unused but kept for reference
    digitalWrite(buzzer, HIGH);
    delay(200);
}

// 1. UUID Definitions (Must match Flutter app's ble_service.dart)
#define SERVICE_UUID           "96f30d22-26f5-4673-a4f6-7b4431e7c5b6" 
#define DISTANCE_CHAR_UUID     "96f30d22-26f5-4673-a4f6-7b4431e7c5b7" // Notify characteristic
#define SETTINGS_CHAR_UUID     "96f30d22-26f5-4673-a4f6-7b4431e7c5b8" // Write characteristic

// Global BLE Objects
BLEServer* pServer = NULL;
BLECharacteristic* pDistanceCharacteristic = NULL;
BLECharacteristic* pSettingsCharacteristic = NULL;
bool deviceConnected = false;

// Current Settings received from app
int currentCautionCm = 120; // Default values
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
      // Get the raw data as a string/byte array
      std::string rxValue = pCharacteristic->getValue();

      if (rxValue.length() >= 2) {
        // Assuming the app sends two 1-byte integers: [CautionCm, DangerCm]
        // Note: Using rxValue.at(index) is safer than array access [] for std::string
        currentCautionCm = (uint8_t)rxValue.at(0);
        currentDangerCm = (uint8_t)rxValue.at(1);
        
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
    // Initializing all pins
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
// uint8_t error is not strictly needed if we use currentDangerCm/currentCautionCm
// but keeping the original logic flow using error for local buzz logic
uint8_t error = 50; 
bool button_last = false;

void loop() {
    // --- 1. Button Logic (Always runs for responsiveness) ---
    // Read the active low button state
    bool button_pressed = !digitalRead(button);
    
    // Simple state machine for button press detection (rising edge)
    if (button_pressed && !button_last) {
        toggle = !toggle;
        Serial.printf("Toggle state changed to: %s\n", toggle ? "ON" : "OFF");
    }
    button_last = button_pressed;

    // --- 2. Sensor and BLE Logic (Only runs if toggle is ON) ---
    if (toggle) {
        float dist0 = read_dist(trig_pin0, echo_pin0);
        float dist1 = read_dist(trig_pin1, echo_pin1);
        float dist2 = read_dist(trig_pin2, echo_pin2);
        
        // Convert to uint8_t, capping at 255 (maximum distance for a single byte)
        const float maximum = 255.0;
        uint8_t dist0_i = min((int)dist0, (int)maximum);
        uint8_t dist1_i = min((int)dist1, (int)maximum);
        uint8_t dist2_i = min((int)dist2, (int)maximum);
        uint8_t sensorData[3] = { dist0_i, dist1_i, dist2_i };
        
        // --- BLE Notification ---
        if (deviceConnected && pDistanceCharacteristic) {
            // Set the new value and notify the connected client
            pDistanceCharacteristic->setValue(sensorData, 3);
            pDistanceCharacteristic->notify(); 
        }

        // --- Buzzer Logic (Using the remote settings or local default) ---
        // Note: I'm cleaning up the original complex bitwise logic here to use the global settings
        // If the settings characteristic was written to, we'd use currentDangerCm.
        // Assuming the app provides currentDangerCm as the primary alert threshold.
        
        uint8_t alertThreshold = (currentDangerCm > 0) ? currentDangerCm : error;
        
        bool danger = (dist0 <= alertThreshold) || (dist1 <= alertThreshold) || (dist2 <= alertThreshold);

        // Your original buzzer logic was complex due to attempting to read 
        // the written characteristic value in every loop, which is not ideal.
        // The proper way is to let the onWrite callback handle the update (as implemented in SettingsCallbacks).
        
        if (danger) {
            // Short pulse for immediate danger
            digitalWrite(buzzer, HIGH);
        } else {
            // If the toggle is ON, the buzzer is either on or off based on danger.
            digitalWrite(buzzer, LOW);
        }

    } else {
        // --- 2b. If toggle is OFF, ensure the buzzer is OFF ---
        digitalWrite(buzzer, LOW);
    }
    
    // --- 3. Yield CPU Time (ALWAYS runs) ---
    // This is the CRITICAL fix: it allows the FreeRTOS scheduler to run the 
    // BLE stack and prevents CPU starvation.
    delay(20);
}
