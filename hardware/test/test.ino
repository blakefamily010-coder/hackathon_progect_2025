#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <string>

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

// Simulated Data Variables
int simulatedLeftCm = 0;
int simulatedCenterCm = 0; // This value will cycle for testing
int simulatedRightCm = 0;
int loopCounter = 0;

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
      std::string rxValue = pCharacteristic->getValue();

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

// 5. Arduino Setup Function
void setup() {
  Serial.begin(115200); // For debugging over USB
  initBLE();            // Initialize and start the BLE server
}

// 6. Arduino Loop Function (Sends a single, cycling test number)
void loop() {
  if (deviceConnected) {
    
    loopCounter++;
    
    // Update data every 50 loops (approx 500ms at 10ms delay)
    if (loopCounter % 50 == 0) { 
        // Cycles the Center distance from 10 to 100 for clear testing.
        simulatedCenterCm = (loopCounter / 50) % 90 + 10; 
        
        // Keep other distances static for clear testing
        simulatedLeftCm = 0; 
        simulatedRightCm = 0;
        
        // Prepare and Send the Data Packet (6 bytes total)
        // Format: [Left, Placeholder, Center, Placeholder, Right, Placeholder]
        // This format matches the expected parsing in your Flutter app: data[0], data[2], data[4]
        
        uint8_t sensorData[6];
        sensorData[0] = (uint8_t)simulatedLeftCm;   
        sensorData[1] = 0;                          
        sensorData[2] = (uint8_t)simulatedCenterCm; 
        sensorData[3] = 0;                          
        sensorData[4] = (uint8_t)simulatedRightCm;  
        sensorData[5] = 0;                          

        // Set the new value and notify the connected client
        pDistanceCharacteristic->setValue(sensorData, 6);
        pDistanceCharacteristic->notify(); 
        
        Serial.printf("TESTING: Sending Center Distance = %d\n", simulatedCenterCm);
    }
  }
  
  delay(10); // Small delay to prevent watchdog timeout
}
