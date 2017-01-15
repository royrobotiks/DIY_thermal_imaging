# DIY_thermal_imaging

The DIY thermal camera software (read_IR_19.pde) is written in Processing (Version 3.2.3) and does the following:

Via webcam, it reads a number from a 3-digit 7-segment LCD display of an IR thermometer. The thermometer is rotated in the X- and Y-axis via two servos. The program sends the servo positions via the USB/serial connection to an Arduino, which addresses the servos. The program draws then a thermal image, based on the X and Y positions of the thermometer and based on the measured temperatures. On the Arduino, there is the firmware "ircam_XY.ino" uploaded, which addresses the servos based on the incoming serial information.

The overlay that is used to read the LCD numbers can be squeezed, stretched and resized to fit on the 7-segment displays. The temperature/color scale can also be stretched and squeezed to point temperature ranges of interest.
Those codes are released under a beer-ware license.

Further explanation and video: http://www.niklasroy.com/project/195/DIY_thermal_imaging
