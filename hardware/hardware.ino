#include "BluetoothSerial.h"

const int buzzer = 8;
const int trig_pin0 = 9;
const int echo_pin0 = 10;
const int trig_pin1 = 5;
const int echo_pin1 = 6;
const int trig_pin2 = 7;
const int echo_pin2 = 8;

BluetoothSerial SerialBT;

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
    
    float dist0 = read_dist(trig_pin0, echo_pin0);
    float dist1 = read_dist(trig_pin1, echo_pin1);
    float dist2 = read_dist(trig_pin2, echo_pin2);
    char buff[72];
    sprintf(buff, "{\"distace0\":\"%f\",\"distance1\":\"%f\",\"distance2\":\"%f\"}", dist0, dist1, dist2);
    SerialBT.write( (uint8_t*) buff, 72);
    Serial.write( (uint8_t*) buff, 72);
    if (((dist0 <= 5.0) || (dist1 <= 5.0)) || (dist1 <= 5.0)) {
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


