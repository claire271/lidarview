import processing.serial.*;
import javax.swing.JOptionPane;
import javax.swing.JDialog;

//Constants
final int VD = 633;
final int H = 100;

final int iwidth = 640;
final int iheight = 480;
final int scale = 4;
final int GB = 63;

//Buffers used
int[] rxBuf;
int rxBufIndex = 0;
float[] inBuf;
float[] heights;
int nheights = 0;

//Main serial port
Serial port;

//Actual distance for calibration
float distance = 0.0;

//Framerate display
float fps = 0;
long old_time = 0;
final float TDC = 0.8f;

//Set up the program and serial
void setup() {
  //Get the list of serial devices
  String[] rawPortList = Serial.list();
  
  //Filter the list
  int portCount = 0;
  for(int i = 0;i < rawPortList.length;i++) {
    if(!rawPortList[i].contains("ttyS1")) portCount++;
  }
  String[] portList = new String[portCount];
  for(int i = 0, j = 0;i < rawPortList.length;i++) {
    if(!rawPortList[i].contains("ttyS1")) {
      portList[j++] = rawPortList[i];
    }
  }
  
  //Create a string for the dialog
  String dialogQuery = "Please enter a number to choose a port:";
  for(int i = 0;i < portList.length;i++) {
    dialogQuery += "\n" + i + ": " + portList[i];
  }
  
  //Ask the user for a port number
  JDialog dialog = new JDialog();
  dialog.setAlwaysOnTop(true);
  String dialogOutput = JOptionPane.showInputDialog(dialog, dialogQuery);
  
  //Validate the entered number, quit if it is invalid
  String portName = "";
  try {
    int index = Integer.parseInt(dialogOutput);
    if(index < 0 || index >= portList.length) {
      throw new IndexOutOfBoundsException();
    }
    portName = portList[index];
  } catch (NumberFormatException ex) {
    print("Not a number");
    exit();
  } catch (IndexOutOfBoundsException ex) {
    print("Invalid number entered");
    exit();
  }
  
  //Ask the user for a calibration distance
  JDialog dialog2 = new JDialog();
  dialog2.setAlwaysOnTop(true);
  String dialog2Output = JOptionPane.showInputDialog(dialog2, "Enter the calibration distance (in millimeters)\n(Press cancel to skip calibration)");
  try {
    if(dialog2Output != null) {
      distance = Float.parseFloat(dialog2Output);
    }
  } catch (NumberFormatException ex) {
    print("Not a number");
    exit();
  }
  
  //Actually connect to the port
  port = new Serial(this, portName, 115200);
  
  //Reset the offset if we're calibrating
  if(distance > 0) {
    String command = "oo" + Integer.toString(0) + " ";
    byte[] bytes = command.getBytes();
    port.write(bytes);
  }
  
  //Set up buffers
  rxBuf = new int[iwidth * 3 / 2 + 3];
  inBuf = new float[iwidth];
  heights = new float[iwidth];
  
  //Initialize framerate display
  old_time = System.currentTimeMillis();
  
  //Set up drawing
  size(800,600);
  frameRate(10);
}

void draw() {
  //Read data from the serial port
  //Get the data
  while(port.available() > 0) {
    rxBuf[rxBufIndex++] = port.read();
    
    //Check for the end conditions
    if(rxBufIndex >= 3) {
      if(rxBufIndex == rxBuf.length &&
         rxBuf[rxBufIndex - 1] == 0xFF &&
         rxBuf[rxBufIndex - 2] == 0xFF &&
         rxBuf[rxBufIndex - 3] == 0xFF) {
        //Our condition has been met
        //Process data
        rxBufIndex = 0;
        
        //Unpack the actual heights
        for(int i = 0;i < iwidth/2;i++) {
          inBuf[i * 2] = rxBuf[i * 3 + 1] + (rxBuf[i * 3 + 1] == 254 ? 0 : (rxBuf[i * 3] & 0x0F) / 16.0);
          inBuf[i * 2 + 1] = rxBuf[i * 3 + 2] + (rxBuf[i * 3 + 2] == 254 ? 0 : ((rxBuf[i * 3] >> 4) & 0x0F) / 16.0);
        }
        
        //Draw the background
        fill(0, 0, 0);
        rect(0, 0, width, height);
        
        for(int i = 0;i < height;i += 100 / scale) {
          stroke(GB, 0, i == 0 ? GB : 0);
          line(0, i, width, i);
        }
        for(int i = 0;i < width/2;i += 100 / scale) {
          stroke(GB, 0, i == 0 ? GB : 0);
          line(width/2 - i, 0, width/2 - i, height);
          line(width/2 + i, 0, width/2 + i, height);
        }
        
        //Render the data
        loadPixels();
        nheights = 0;
        for(int i = 0;i < iwidth;i++) {
          if(inBuf[i] != 254) {
            float dpos = VD * H / inBuf[i];
            float xpos = dpos * (i - iwidth / 2) / VD;
            
            xpos /= scale;
            dpos /= scale;
            
            boolean outOfRange = false;
            if(xpos < -width/2) {
              xpos = -width/2;
              outOfRange = true;
            }
            if(xpos > width/2-1) {
              xpos = width/2-1;
              outOfRange = true;
            }
            
            if(dpos < 0) {
              dpos = 0;
              outOfRange = true;
            }
            if(dpos > height-1) {
              dpos = height-1;
              outOfRange = true;
            }
            
            pixels[((int)xpos + width/2) + (height - 1 - (int)dpos) * width] = color(outOfRange ? 255 : 0, 255, 0);
            heights[nheights++] = dpos;
          }
        }
        updatePixels();
        
        //Figure out the average line
        if(distance > 0) {
          float average = 0;
          for(int i = 0;i < nheights;i++) {
            average += heights[i];
          }
          average /= nheights;
          float old_avg = average;
          int count = 0;
          average = 0;
      
          for(int i = 0;i < nheights;i++) {
            if(Math.abs(old_avg - heights[i]) < 100) {
              count++;
              average += heights[i];
            }
          }
          average /= count;
          average *= scale;
          stroke(0, GB, GB);
          line(0, height - average/scale, width, height - average/scale);
          
          float in = VD * H / average;
          float err = average - distance;
          float new_offset = (err * in * in) / (H * VD + err * in);
          
          fill(0, 255, 255);
          text("Offset: " + ((int)(new_offset * 100 + 0.5))/100.0,5,30);
         
          String command = "oa" + Integer.toString(Math.round(new_offset)) + " ";
          byte[] bytes = command.getBytes();
          port.write(bytes);
        }
        
        //Calculate framerate
        long cur_time = System.currentTimeMillis();
        float cur_fps = 1000.0f / (cur_time - old_time);
        old_time = cur_time;
        fps = fps * TDC + cur_fps * (1.0f - TDC);
        
        //Draw framerate
        fill(255, 255, 255);
        text("Current FPS: " + ((int)(fps * 100 + 0.5))/100.0,5,15);
      }
      else if(rxBufIndex == rxBuf.length) {
        //Length reached, but end flag not found
        //Discard data
        rxBufIndex = 0;
      }
      else if(rxBuf[rxBufIndex - 1] == 0xFF &&
              rxBuf[rxBufIndex - 2] == 0xFF &&
              rxBuf[rxBufIndex - 3] == 0xFF) {
        //End flag found, but end not reached
        //Discard data
        rxBufIndex = 0;
      }
    }
  }
}