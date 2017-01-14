/* 
  *********************************************************
  DIY thermal imaging camera code by Niklas Roy
  Written in Processing 3.2.3
  Published under the beer-ware license
  
  This code reads a 3-digit temperature value via a webcam 
  from an IR thermometer and positions 2 servos (X&Y) 
  in order to scan and draw a thermal image.
  
  *********************************************************
  Setup:

  - Mount webcam at IR thermometer
  - Gimbal IR thermometer with 2 Servos (X & Y)
  - Connect Servos to Arduino 
  - Connect Arduino to PC
  - Flash Arduino with "ircam_XY" servo script
  - set # of COM port and number of webcam in setup()
  - run this program
  - adjust LCD digit readout overlay so that the program 
    can read the digits
  
  Congratulations! 
  You have a low cost slow speed thermal imaging camera!
  *********************************************************
 */

import processing.video.*;
import processing.serial.*;
Serial myPort;
Capture cam;
PFont font;
PrintWriter output;

boolean pMousePressed=false;            // mouse Button State in previous program cycle
int[][] segToDec = {                    // used to convert segments to decimal number
  {1, 1, 1, 0, 1, 1, 1}, /*0*/
  {0, 0, 1, 0, 0, 1, 0}, /*1*/
  {1, 0, 1, 1, 1, 0, 1}, /*2*/
  {1, 0, 1, 1, 0, 1, 1}, /*3*/
  {0, 1, 1, 1, 0, 1, 0}, /*4*/
  {1, 1, 0, 1, 0, 1, 1}, /*5*/
  {1, 1, 0, 1, 1, 1, 1}, /*6*/
  {1, 0, 1, 0, 0, 1, 0}, /*7*/
  {1, 1, 1, 1, 1, 1, 1}, /*8*/
  {1, 1, 1, 1, 0, 1, 1} /*9*/
}; 

float[] segX = {.5, 0, 1, .5, 0, 1, .5};      //position of each segment
float[] segY = {0, .5, .5, 1, 1.5, 1.5, 2}; 
int[] segments= new int[7];             //stores on / off value for each segment?
int refX=100;                           // reference pixel position
int refY=100;
int segI2X[]= {158, 308, 482};            // segment overlay positioning interface : coordinates of the 3 buttons per digit
int segI2Y[]= {158, 158, 300};
int segI3X[]= {127, 275, 458};
int segI3Y[]= {442, 440, 450};
int segI4X[]= {218, 375, 510};
int segI4Y[]= {442, 440, 450};
int Gdrag=0;                            // global button drag index
float Greference=0;                     // brightness reference value
int[] digit = new int [3];              // value of each digit
float pNumber =0;                       // previous number
float vNumber =0;                       // verified number

float thermImg[][]=new float[71][45];   // thermal image buffer  70*45 
int pixX=0;
int pixY=0;

int Xtarget=25;   // target coordinates for servos x-range: 25...95  y-range: 35...80
int Ytarget=35;
int Xservo=25;    // servo coordinates
int Yservo=35;
boolean pause=true; // pauses scan if true

int lastMove=0;   // millis() of last servo movement
float scale=15.5; //scaling of thermal image on screen

float minTemp; // lowest temperature in thermal image
float maxTemp; // highest temperature in thermal image

int minScaleButton=350; // x-position of dragable min and max scale buttons
int maxScaleButton=470;

float minDispTemp;      // min and max temperatures of temperature scale
float maxDispTemp;
  

void setup() {
  printArray(Serial.list());

  // Open the port you are using at the rate you want:
  myPort = new Serial(this, Serial.list()[5], 9600); // <------------------------------------ set serial port (Arduino) here

  colorMode(HSB, 100);
  font = loadFont("OpenSans-16.vlw");

  size(1880, 1000);

  String[] cameras = Capture.list();

  if (cameras.length == 0) {
    println("There are no cameras available for capture.");
    exit();
  } else {
    println("Available cameras:");
    for (int i = 0; i < cameras.length; i++) {
      println(cameras[i]);
    }
    cam = new Capture(this, cameras[0]);    // <------------------------------------ set webcam here
    cam.start();
  }

  //reset thermal image
  for (int x=0; x<70; x++) {
    for (int y=0; y<45; y++) {
      thermImg[x][y]=-100;
    }
  }
  textFont(font, 16);
}



////////////////////////////////////////////////////////////////////////////////////////////////////// loop

void draw() {
  background(0);
  // -------------------------------------------------------------------------------------------- position thermometer with servos
  
  if (mouseOverThermImg() && mousePressed) {                                                   // if button is pressed and if mouse is over thermal image:
    moveToMouse();                                                                             // move servos to mouse position 
  } else {                                                                                     // if not:
    if (millis()>lastMove && Xtarget==Xservo && Ytarget == Yservo) {                           // scan positions automatically
      lastMove=millis()+500;                                                                   // speed of scan (delay between pixel movement)
      if(!pause){scanTargetPosition();}                                                        // update X- and Y-target automatically with scan movement
    }
  }
  updateServoBasedOnTarget();                                                                  // move X- and Y-servo step by step to X- and Y-target
  positionServos(Xservo, Yservo);                                                              // send servo positions via serial port to arduino
  
  // -------------------------------------------------------------------------------------------- read temperature from webcam and write it in thermal image array
  
  drawWebcamImg();                                                                             // draw the latest webcam image
  float number=readLCD();                                                                      // read 3-digit (XX.x) 7-segment value from webcam image 
                                                                                               // segments must be darker than reference point 
  if (pNumber == number && number !=-1 && number!=88.8 && number!=79.9) {vNumber=number;}                     // verifiyng number: number hast be tread twice in order to be accepted 
                                                                                               // 'vNumber' is verified number
  pNumber=number;                                                                              // remember current temperature for next program cycle
  fill(100, 0, 100);
  text("Temperature: "+vNumber, 60, 520);                                                      // write currently measured temperature on screen
  if (Xtarget==Xservo && Ytarget == Yservo && !pause) {thermImg [Xservo-25] [Yservo-35] = vNumber;}      // write verified temperature readout in thermal image array
  
  // -------------------------------------------------------------------------------------------- draw thermal image and scales
  
  findTemperatureExtremes();                                                                   // update minimal and maximum Temperature 
  fill(100, 0, 100);
  text("Min. Temperature: "+minTemp+"°C // Max. Temperature: "+maxTemp+"°C", 740, 80+45*15.5); // write extreme temperature values below thermal image
                                                                                               // draw interactive temperature scales 
  drawScaleInterface();                                                                        // draw temperature scale interface (updates minDispTemp and maxDispTemp)
  drawTemperatureScale(minDispTemp, maxDispTemp);                                              // draw temperature scale (legend)
  drawThermalImage(minDispTemp,maxDispTemp);                                                   // draw thermal image from thermal image array
  drawFrames();                                                                                // draw real position and target position 
  if (mouseOverThermImg()) {pickTemperature();}                                                // draw temperature readout if mouse is over thermal image
  
  // -------------------------------------------------------------------------------------------- save, load, pause - interface
   
  if(interfaceButton("Load thermal image",50,710)){loadThermalImg();}
  if(interfaceButton("Save thermal image",270,710)){saveThermalImg();}
  if(!pause){
    if(interfaceButton("Pause scan",490,710)){pause=true;}
  }else{
    if(interfaceButton("Resume scan",490,710)){pause=false;}
  }
  pMousePressed=mousePressed;
}

////////////////////////////////////////////////////////////////////////////////////////////////////// end of loop


//-------------------------------------------------- load image
void loadThermalImg(){
  pause=true;
  selectInput("Select a file to load thermal image:", "tlSelected");
}
void tlSelected(File selection) {

  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } else {
    println("load thermal image...");
    String line;
    BufferedReader reader;
    reader = createReader(selection.getAbsolutePath());
    try {
      line = reader.readLine();
    } 
    catch (IOException e) {
      e.printStackTrace();
      line = null;
    }
    int x=-1;
    int y=0;
    for (int i=0; i<3199; i++) {
      try {
        line = reader.readLine();
      } 
      catch (IOException e) {
        e.printStackTrace();
        line = null;
      }
      println(line);
      if(i==0){minScaleButton=int(line); }
      if(i==1){maxScaleButton=int(line); }
      if(i>1 && i<3197){
      x++;
      if(x==71){x=0;y++;}
      thermImg[x][y]= float(line);
      }
    }
  }
}

//-------------------------------------------------- save image
void saveThermalImg(){
  pause=true;
  //------ open filesystem; choose filename
  selectOutput("Select a file to write thermal image:", "tsSelected");
}
void tsSelected(File selection) {
  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } else {
    println("saving thermal image...");
    output = createWriter(selection.getAbsolutePath()); 
    output.println("Thermal image 71 * 45 pixel"); 
    output.println(minScaleButton); 
    output.println(maxScaleButton); 

    for (int y=0;y<45;y++){
      for (int x=0;x<71;x++){ 
        output.println(thermImg[x][y]); 
      }
    }
    output.println("--EOF--"); 
    output.flush(); // Writes the remaining data to the file
    output.close(); // Finishes the file
    println("saved!");
  }
}
    
    

//-------------------------------------------------- draw interface button
boolean interfaceButton(String Lbutton,int Xbutton,int Ybutton){
  int buttonWidth=200;
  boolean pushed=false;
  if (mouseX>=Xbutton && mouseX <=Xbutton+buttonWidth && mouseY>=Ybutton && mouseY<=Ybutton+35 && Gdrag==0){
    fill(0,0,50);
    if (mousePressed){fill(0,0,75);}
    if (mousePressed && !pMousePressed){pushed=true;}
  }else{
    noFill();
  }
  stroke(0,0,100);
  
  rect(Xbutton,Ybutton,buttonWidth,35);
  fill(0,0,100);
  text(Lbutton,Xbutton+buttonWidth/2-textWidth(Lbutton)/2,Ybutton+24);
  return pushed;
}

//-------------------------------------------------- draw temperature scale interface (updates minDispTemp and maxDispTemp)
void drawScaleInterface(){
  noStroke();       // draw color scale in 0°C ... 100°C range
  //draw area between min and max measured temperature dashed white colored
  for (int i=int(map(minTemp,0,100,50,width-50));i<=int(map(maxTemp,0,100,50,width-50));i++){   
    valToFill(map(i,minScaleButton,maxScaleButton,0,100));
    rect(i,855,2,10);
  }  
  stroke(0,0,100);
  for (int i=int(map(minTemp,0,100,50,width-50))-10;i<=int(map(maxTemp,0,100,50,width-50));i+=5){
    line(i+9,855,i,864);
  }
  noStroke();
  fill(0,0,0);
  rect(int(map(minTemp,0,100,50,width-50))-10,855,10,10);
  rect(int(map(maxTemp,0,100,50,width-50)),855,10,10);

  //draw area between min and max button rainbow colored
  for (int i=minScaleButton;i<maxScaleButton;i++){
    valToFill(map(i,minScaleButton,maxScaleButton,0,100));
    rect(i,855,2,10);
  }
  
  //draw total range white
  stroke(0,0,100);  // draw 0°C ... 100°C range
  fill(0,0,100);
  for (int i=0;i<=100;i+=5){
    float Xline=map(i,0,100,50,width-50);
    line(Xline,850,Xline,870);
    text(i+"°C",Xline-15,840);
  }
  
  if(buttonHit(minScaleButton, 930, 20)){ // drag min button
    minScaleButton=mouseX;
    if (minScaleButton<50){minScaleButton=50;}
    if (minScaleButton>width-70){minScaleButton=width-70;}
    if (minScaleButton>maxScaleButton-15){maxScaleButton=minScaleButton+15;}
  }
  
  if(buttonHit(maxScaleButton, 930, 21)){ // drag max button
    maxScaleButton=mouseX;
    if (maxScaleButton>width-50){maxScaleButton=width-50;}
    if (maxScaleButton<70){maxScaleButton=70;}
    if (maxScaleButton<minScaleButton+15){minScaleButton=maxScaleButton-15;}
  }
  
  minDispTemp=map(minScaleButton,50,width-50,0,100);  // label min and max buttons
  maxDispTemp=map(maxScaleButton,50,width-50,0,100);
  stroke(0,0,100);
  line(minScaleButton,850,minScaleButton,920);
  line(maxScaleButton,850,maxScaleButton,920);
  fill(0,0,100);
  text(nf(minDispTemp,2,1)+"°C",minScaleButton-40,960);
  text(nf(maxDispTemp,2,1)+"°C",maxScaleButton-7,960);
  
  // draw mintemp line and maxtemp line
  stroke(0,0,100);
  line(map(minTemp,0,100,50,width-50),850,map(minTemp,0,100,50,width-50),900);
  line(map(maxTemp,0,100,50,width-50),850,map(maxTemp,0,100,50,width-50),900);
  noStroke();
  fill(0,0,0);
  rect(map(minTemp,0,100,50,width-50)-90,885,86,20);
  rect(map(maxTemp,0,100,50,width-50)+5,885,86,20);
  fill(0,0,100);
  text("Min: "+nf(minTemp,2,1)+"°C",map(minTemp,0,100,50,width-50)-90,901);
  text("Max: "+nf(maxTemp,2,1)+"°C",map(maxTemp,0,100,50,width-50)+5,901);
}

//-------------------------------------------------- update X- and Y-target automatically with scan movement
void scanTargetPosition(){
  Xtarget++;
  if (Xtarget>95) {                                                                        // new line
    Xtarget=25;
    Ytarget++;
  }
  if (Ytarget>79) {                                                                        // new limage
    Ytarget=35;
  }
}

//-------------------------------------------------- move X- and Y-servo step by step to X- and Y-target
void updateServoBasedOnTarget(){
  if (Xservo<Xtarget) {Xservo++;}
  if (Xservo>Xtarget) {Xservo--;}
  if (Yservo<Ytarget) {Yservo++;}
  if (Yservo>Ytarget) {Yservo--;}
}

//-------------------------------------------------- set servo target positions to mouse position
  void moveToMouse(){
    Xtarget=int((mouseX-740)/scale)+25;
    Ytarget=int((mouseY-50)/scale)+35;
  }

//-------------------------------------------------- draw webcam image & read temperature value from LCD display
void drawWebcamImg(){
  if (cam.available() == true) {
    cam.read();
  }
  image(cam, 50, 50);
  filter(GRAY);
}

//-------------------------------------------------- draw mouse crosshair with temperature readout
void pickTemperature() {
  stroke(0, 0, 0);
  line(mouseX-15, mouseY, mouseX+15, mouseY);
  line(mouseX, mouseY-15, mouseX, mouseY+15);
  fill(0, 0, 0);
  String readTemp=nf(thermImg[int((mouseX-740)/scale)][int((mouseY-50)/scale)])+"°C";
  if (thermImg[int((mouseX-740)/scale)][int((mouseY-50)/scale)]==-100) {
    readTemp="";
  }
  int Xtext = mouseX+15;
  int Ytext = mouseY-15;
  if (mouseY<80) {
    Ytext=mouseY+30;
  } 
  if (mouseX>1200) {
    Xtext=mouseX-55;
  } 
  text(readTemp, Xtext, Ytext);
}

//-------------------------------------------------- draw real position and target position 
void drawFrames() {
  noFill();
  stroke(0, 0, 100);
  rect((Xservo-25)*scale+740, (Yservo-35)*scale+50, scale-.5, scale-.5); // draw lag frame white
  stroke(0, 0, 0);
  rect((Xtarget-25)*scale+740, (Ytarget-35)*scale+50, scale-.5, scale-.5); // draw servo position black
  rect((Xtarget-25)*scale+742, (Ytarget-35)*scale+52, scale-4.5, scale-4.5);
}


//-------------------------------------------------- returns true if mouse is over thermal image
boolean mouseOverThermImg() {
  boolean mo=false;
  if (mouseX>740 && mouseX<740 + scale*70 && mouseY>50 && mouseY<50+scale*45) {
    mo=true;
  }
  return mo;
}

//-------------------------------------------------- send servo positions via serial port to arduino
void positionServos(int xp, int yp) {
  myPort.write(95-constrain(xp, 25, 94));
  myPort.write(constrain(yp, 35, 79)+127);
}

//-------------------------------------------------- find min and max temperature in thermal image array
void findTemperatureExtremes() {
  minTemp=100;
  maxTemp=-50;
  for (int x=0; x<70; x++) {
    for (int y=0; y<45; y++) {
      if (thermImg[x][y]!=-100) {
        if (thermImg[x][y]>maxTemp) {
          maxTemp=thermImg[x][y];
        }
        if (thermImg[x][y]<minTemp) {
          minTemp=thermImg[x][y];
        }
      }
    }
  }
  if (maxTemp==minTemp) {
    maxTemp=minTemp+.01;
  }
}

//-------------------------------------------------- draw thermal image
void drawThermalImage(float minT, float maxT) {
  noStroke();
  for (int x=0; x<70; x++) {
    for (int y=0; y<45; y++) {
      float colorV=50;
      if (thermImg[x][y]!=-100) {
        colorV=map(thermImg[x][y], minT, maxT, 0, 100);
        valToFill(colorV); //fill with color if there is a temperature value for this pixel
      } else {
        fill(0, 0, 25); // fill with dark grey if there isn't a temperature value for this pixel yet
      }
      noStroke();
      rect(x*scale+740, y*scale+50, scale+.5, scale+.5); 
      if(colorV>100 || colorV<0){stroke(0,0,255);line(x*scale+737+scale+.5, y*scale+52,x*scale+743, y*scale+46+scale+.5);} // draw white line in out of range pixels
    }
  }
}

//-------------------------------------------------- brightness picker - draws a square and returns brightness value
int getPixel(float xSense, float ySense) {
  color c = get(int(xSense), int(ySense));
  int b=int(brightness(c));
  //text(b, xSense-3, ySense-7);
  stroke(100, 0, 100);
  noFill();
  rect(xSense-3, ySense-3, 6, 6);
  return (b);
}

//-------------------------------------------------- button with index to drag
boolean buttonHit(int buttonX, int buttonY, int buttonI) {
  /*x,y,index returns true if dragged*/
  boolean drag=false;
  if ((abs(mouseX-buttonX)<6 && abs(mouseY-buttonY)<6) || Gdrag==buttonI) {
    if (mousePressed && Gdrag == 0) {
      Gdrag=buttonI;
    }
  }
  if (Gdrag==buttonI && !mousePressed) {
    Gdrag=0;
  }
  noFill();
  if ((abs(mouseX-buttonX)<6 && abs(mouseY-buttonY)<6)) {
    fill (100, 100, 0);
  }
  if (Gdrag==buttonI) {
    fill(100, 0, 100);
    drag=true;
  }
  rect(buttonX-5, buttonY-5, 10, 10);
  line(buttonX-7, buttonY-7, buttonX-3, buttonY-7);
  line(buttonX+3, buttonY-7, buttonX+7, buttonY-7);
  line(buttonX+7, buttonY-7, buttonX+7, buttonY-3);
  line(buttonX+7, buttonY+3, buttonX+7, buttonY+7);
  line(buttonX+7, buttonY+7, buttonX+3, buttonY+7);
  line(buttonX-3, buttonY+7, buttonX-7, buttonY+7);
  line(buttonX-7, buttonY+7, buttonX-7, buttonY+3);
  line(buttonX-7, buttonY-3, buttonX-7, buttonY-7);
  return drag;
}

//-------------------------------------------------- print coordinates
void printCoo() {
  println("int segI2X[]= {"+segI2X[0]+","+segI2X[1]+","+segI2X[2]+"};");
  println("int segI2Y[]= {"+segI2Y[0]+","+segI2Y[1]+","+segI2Y[2]+"};");
  println("int segI3X[]= {"+segI3X[0]+","+segI3X[1]+","+segI3X[2]+"};");
  println("int segI3Y[]= {"+segI3Y[0]+","+segI3Y[1]+","+segI3Y[2]+"};");
  println("int segI4X[]= {"+segI4X[0]+","+segI4X[1]+","+segI4X[2]+"};");
  println("int segI4Y[]= {"+segI4Y[0]+","+segI4Y[1]+","+segI4Y[2]+"};");
  println("----------------------------------");
}

float readLCD() {
  // ----------------------------------------------------------------------------------------------- position and read brightness reference pixel
  Greference=getPixel(refX, refY);
  Greference=Greference*.75;
  if (buttonHit(refX, refY, 1)) { // button1: reference
    refX=mouseX;
    refY=mouseY;
  }
  fill(100, 0, 100);
  text("BRIGHT_REF: "+int(Greference), refX+10, refY+7);

  // =============================================================================================== read 3 digits

  for (int d=0; d<3; d++) { // d= digit index; iterating through 3 7-segment overlays

    // ----------------------------------------------------------------------------------------------- calculate origin, scale and skewion of 7 segment overlay
    int segIposX=segI2X[d];
    int segIposY=segI2Y[d];
    int segIscalX=(segI4X[d]-segI2X[d]);
    int segIscalY=(segI4Y[d]-segI2Y[d])/2;
    int skew=segI3X[d]-segI2X[d];

    // ----------------------------------------------------------------------------------------------- draw and pick brightness values of 7 segments
    for (int i=0; i<7; i++) {  
      if (getPixel((segIposX+segX[i]*(segIscalX-skew)) + (segY[i]/2)*skew, segIposY+segY[i]*segIscalY)<Greference) {
        segments[i]=1;
        fill(100, 0, 100);
        rect((segIposX+segX[i]*(segIscalX-skew)) + (segY[i]/2)*skew -7, segIposY+segY[i]*segIscalY -7, 14, 14);     
        noFill();
        stroke(0, 0, 0);
        rect((segIposX+segX[i]*(segIscalX-skew)) + (segY[i]/2)*skew -5, segIposY+segY[i]*segIscalY -5, 10, 10);
      } else {
        segments[i]=0;
      }
      stroke(100, 0, 100);
    }

    // ----------------------------------------------------------------------------------------------- convert segment readings to decimal digit value
    digit[d]=-1;
    for (int i=0; i<=9; i++) {
      boolean b=true;
      for (int j=0; j<7; j++) {
        if (segments[j]!=segToDec[i][j]) {
          b=false;
          break;
        }
      }
      if (b) {
        digit[d]=i;
      }
    }
    fill(100, 0, 100);
    text("DIGIT_"+d+": "+digit[d], segIposX +skew, segIposY+2*segIscalY+30);

    // ----------------------------------------------------------------------------------------------- 3-button interface to position 7 segment overlay

    if (buttonHit(segI2X[d], segI2Y[d], 2+d*3)) { // --------- button2: top left 7segmentA 
      segI2X[d]=mouseX;
      segI2Y[d]=mouseY;
      if (segI2Y[d]+30>segI3Y[d]) {
        segI3Y[d]=segI2Y[d]+30;
        segI4Y[d]=segI2Y[d]+30;
      }
      printCoo();
    }

    if (buttonHit(segI3X[d], segI3Y[d], 3+d*3)) { // --------- button3: bottom left 7segmentA 
      segI3X[d]=mouseX;
      segI3Y[d]=mouseY;
      segI4Y[d]=mouseY;
      if (segI3Y[d]-30<segI2Y[d]) {
        segI2Y[d]=segI3Y[d]-30;
      }
      if (segI3X[d]+30>segI4X[d]) {
        segI4X[d]=segI3X[d]+30;
      }
      printCoo();
    }

    if (buttonHit(segI4X[d], segI4Y[d], 4+d*3)) { // --------- button4: bottom right 7segmentA 
      segI4X[d]=mouseX;
      segI4Y[d]=mouseY;
      segI3Y[d]=mouseY;
      if (segI4Y[d]-30<segI2Y[d]) {
        segI2Y[d]=segI4Y[d]-30;
      }
      if (segI4X[d]-30<segI3X[d]) {
        segI3X[d]=segI4X[d]-30;
      }
      printCoo();
    } 

    // ----------------------------------------------------------------------------------------------- draw 7 segment overlay
    line(segIposX, segIposY, segIposX+segIscalX-skew, segIposY );
    line(segIposX, segIposY, segIposX+skew, segIposY+2*segIscalY );
    line(segIposX+segIscalX -skew, segIposY, segIposX+segIscalX, segIposY+2*segIscalY );
    line(segIposX +skew/2, segIposY+segIscalY, segIposX+segIscalX -skew/2, segIposY+segIscalY );
    line(segIposX +skew, segIposY+2*segIscalY, segIposX+segIscalX, segIposY+2*segIscalY );
  }

  // =============================================================================================== end of reading 3 digits

  float value=digit[0]*100+digit[1]*10+digit[2];
  value=value/10;
  if (digit[0]==-1 || digit[1]==-1 || digit[2]==-1) {
    value=-1;
  }
  return value;
}

//-------------------------------------------------- colorgrade: turn value (0 to 100) in fill color
void valToFill(float colorValue /*0-100*/) {
  colorValue=constrain(colorValue,0,100);
  float c = map(colorValue, 0, 100, 55, 5);
  float cOut=0;
  if (c>55) {
    cOut=55;
  }
  if (c<5) {
    cOut=5;
  }
  if (c>=40) {
    cOut=map(c, 40, 55, 50, 60);
  }
  if (c<=30) {
    cOut=map(c, 5, 30, 3, 25);
  }
  if (c<40 && c>30) {
    cOut=map(c, 30, 40, 25, 50);
  }
  fill (cOut, 100, 100);
}

//-------------------------------------------------- draws a temperature scale
void drawTemperatureScale(float min, float max) {  
  
  int temp=int(min);
  int pTemp=int(min);
  int gap=int((max-min)/15+1);
  for (int i=50;i<690;i++){
    valToFill(map(i,50,690,0,100));
    noStroke();
    rect(i,580,1,50);
    temp=int(map(i,50,690,min,max));
    if(temp!=pTemp){
     stroke(0,0,100);
     line(i,580,i,640);
     fill(0,0,100);
     if(temp%gap==0){
       text(temp+"°C",i-15,670);
       line(i,580,i,650);
     }
    }
    pTemp=temp;
  }
}