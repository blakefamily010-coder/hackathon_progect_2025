#include "BluetoothSerial.h"

const int buzzer = 2;
const int trig_pin = 0;
const int echo_pin = 4;

BluetoothSerial SerialBT;

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

void setup() {
    // pinMode(echo_pin, INPUT);
    // pinMode(trig_pin, OUTPUT);
    // pinMode(buzzer, OUTPUT);
    //
    // digitalWrite(trig_pin, LOW);
    // digitalWrite(buzzer, LOW);
        
    Serial.begin(115200);
    SerialBT.begin("ESP32test1");
    Serial.println("The device started, now you can pair it with bluetooth!");
}

void loop() {
    
    float dist = read_dist();
    char buff[26];
    sprintf(buff, "{\"distace0\":\"%f\",}", dist);
    SerialBT.write( (uint8_t*) buff, 26);
    Serial.write( (uint8_t*) buff, 26);
    if (dist <= 5.0) {
        digitalWrite(buzzer, HIGH);
    } else {
        digitalWrite(buzzer, LOW);
    }
    if (SerialBT.available()) {
      Serial.write(SerialBT.read());
    }
    
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
    delay(20);
}


