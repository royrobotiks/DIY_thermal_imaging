// servo positioning code for DIY thermal imaging camera

#include <Servo.h>

Servo Xservo;
Servo Yservo;
int Xpos = 90;
int Ypos = 90;
int pXpos = 90;
int pYpos = 90;
long XposT = 0;
long YposT = 0;
boolean Xatt = true;
boolean Yatt = true;



void setup() {
  Xservo.attach(9);  // moves thermometer left and right (pan)
  Yservo.attach(10); // moves thermometer up and down (tilt)
  Serial.begin(9600);
  pinMode(LED_BUILTIN, OUTPUT);
  Xservo.write(Xpos);
  delay(1000);
  Yservo.write(Ypos);
  delay(1000);
}

void loop() {
  while (Serial.available() == 0) {   // wait until a byte is available at the serial port
    digitalWrite(LED_BUILTIN, HIGH);
    delay(20);
    digitalWrite(LED_BUILTIN, LOW);
    delay(20);
  }
  while (Serial.available() > 0) {
    int inByte = Serial.read();
    if (inByte < 128) {               // incoming byte to servo position
      Xpos = inByte + 30;             // 0....127  = X
    } else {
      Ypos = inByte - 127 + 30;       // 128...255 = Y
    }
  }

  if (Xpos != pXpos) { // new X-position: attach servo if it isn't and position servo
    XposT = millis()+1000;
    if (Xatt == false) {
      Xservo.attach(9);
      Xatt = true;
    }
    Xservo.write(Xpos);
  }
  pXpos = Xpos;

  if (Ypos != pYpos) { // new Y-position: attach servo if it isn't and position servo
    YposT = millis()+1000;
    if (Yatt == false) {
      Yservo.attach(10);
      Yatt = true;
    }
    Yservo.write(Ypos);
  }
  pYpos = Ypos;

  if (XposT< millis()) { // detach servos if there didn't come a new position value for 1 second
    Xservo.detach();  
    Xatt = false;
  }
  if (YposT< millis()) {
  //  Yservo.detach();
   // Yatt = false;
  }
  delay(15);
}

