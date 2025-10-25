#include "BluetoothSerial.h"

// Bluetooth Serial object
BluetoothSerial SerialBT;

// --- Removed: Pin Definitions for Buzzer and Sensor ---
// Configuration variables
// We'll hardcode the test distance for now, no need for caution/danger vars

// --------------------------------------------------------------------------
// 1. Setup
// --------------------------------------------------------------------------
void setup() {
    // Start standard Serial for debugging
    Serial.begin(115200);
    
    // Start Bluetooth Serial with the name the Flutter app expects
    SerialBT.begin("ESP32test1"); 
    Serial.println("The device started, now you can pair it with bluetooth!");
    Serial.println("Sending test distance of 100 cm...");
}

// --------------------------------------------------------------------------
// 2. Main Loop
// --------------------------------------------------------------------------
void loop() {
    
    // 1. --- Simplified Data Sending (Test Value) ---
    float test_dist = 100.0; // The fixed test distance in cm
    
    // Sending VALID JSON and terminating with a newline (\n)
    char buff[32]; // Buffer size to be safe
    // The value is 100, which will be received by the Flutter app as 'centerCm'
    int len = sprintf(buff, "{\"centerCm\":%.0f}\n", test_dist); 
    
    // Send data to Bluetooth Serial
    SerialBT.write( (uint8_t*) buff, len);
    
    // Also send to standard Serial for debug monitoring
    Serial.write( (uint8_t*) buff, len);
    
    // --- Removed: read_settings() and buzzer logic ---
    
    // Delay to send data every 250ms
    delay(250); 
}
