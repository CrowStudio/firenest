//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.

//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.

//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <http://www.gnu.org/licenses/>.

/**
 * fireNest - fireCrow transmitter code
 * 6 buttons for 6 channnels and a led for each
 * First button can also fire all channels in succesion
 * Arduino Fio as board
 */

#include <XBee.h>
//#include <NewSoftSerial.h>

#define XBEE_BAUD 9600
#define CHANNELS 6
#define THRESHHOLD 10
#define LED_THRESHHOLD 100
#define ND_WAIT_TIME 3000

struct Channel {
  int button_pin;
  int led_pin;
  int state;
  int time;
};



Channel channels[] = { 
  {2,8,0,0}, 
  {3,9,0,0},
  {4,A3,0,0},
  {5,A0,0,0},
  {6,A1,0,0},
  {7,A2,0,0}
};

//NewSoftSerial mySerial(12, 13);

//used when using first button to fire all channels
uint8_t channel_count = 0;
uint8_t fired_channels = 0;

XBee xbee = XBee();

uint8_t payload[] = { 0 };

// SH + SL Address of receiving XBee
uint32_t sh = 0;
uint32_t sl = 0;

//XBeeAddress64 addr64; //XBeeAddress64(0x0013a200, 0x403141DA);
XBeeAddress64 addr64; //XBeeAddress64(0x0013a200, 0x403141DA);
ZBTxRequest zbTx;
ZBTxStatusResponse txStatus = ZBTxStatusResponse();

//for device discovery
uint8_t atCmd[] = {'N','D'};
AtCommandRequest atRequest = AtCommandRequest(atCmd);
AtCommandResponse atResponse = AtCommandResponse();


void setup() {
  
  //mySerial.begin(4800);
  //mySerial.println("Hello world");
  
  for (int i= 0; i<CHANNELS; i++) {
    pinMode(channels[i].button_pin,INPUT);
    digitalWrite(channels[i].button_pin,HIGH); //enable internal 20K pullup
    
    pinMode(channels[i].led_pin,OUTPUT);
    //blink leds a bit
    digitalWrite(channels[i].led_pin,HIGH);
    delay(200);
    digitalWrite(channels[i].led_pin,LOW);
  }
  
  //debug led
  //pinMode(13,OUTPUT);
  //digitalWrite(13,HIGH);
  //delay(500);
  //digitalWrite(13,LOW);
  
  xbee.begin(XBEE_BAUD);

  //discover the other XBEE's address
  discover();
  zbTx = ZBTxRequest(addr64, payload, sizeof(payload));
  
  //send a no-op packet so that the xbees can do their magic and find each other
  payload[0] = 254;
  xbee.send(zbTx);
  
  //Flash all leds once so the user knows
  flashAll(500);

  //mySerial.println("Discovered address");
  //mySerial.print("MSB: ");
  //mySerial.println(addr64.getMsb());
  //mySerial.println(addr64.getMsb()==0x0013a200?"Yes!":"NO");
  //mySerial.print("LSB: ");
  //mySerial.println(addr64.getLsb());
  //mySerial.println(addr64.getLsb()==0x403141DA?"Yes!":"NO");
}



//State 0 == not pressed, waiting for press

//State 1 == pressed, debouncing time not up
//Fire on press

//State 2 == pressed, waiting for release 

//State 3 == release, debouncing time not up

void loop() {
  int val;
  int m;
  
  for (uint8_t i= 0; i<CHANNELS; i++) {
    m = millis();
    
    if (channels[i].state == 0 || channels[i].state == 2) {
      val = digitalRead(channels[i].button_pin);
      
      if (channels[i].state == 0 && val == LOW) {
          //a press!, fire!
          uint8_t cc = i;
          
          //special case, we can fire all channels by firing the first button repeatably
          if (i == 0) {
            cc = channel_count;
            channel_count = (channel_count + 1) % CHANNELS;
          } 
          
          //fire!
          payload[0] = cc;
          xbee.send(zbTx);
          
          //set as fired 
          fired_channels |= (1 << cc);  
          digitalWrite(channels[cc].led_pin,HIGH);  
          
          //check if all is fired
          if (fired_channels == B00111111) {
            //wait a bit
            delay(500);
            
            //reset all
            channel_count = 0;
            fired_channels = 0;
            for (int j = 0; j<CHANNELS; j++) {
              channels[j].state = 0;
              digitalWrite(channels[j].led_pin,LOW);
              delay(300);
            }
            break;
          }
      }
      
      if ((channels[i].state == 0 && val == LOW) || (channels[i].state == 2 && val == HIGH)) {
        channels[i].state = (channels[i].state + 1) % 4; //change state 
        channels[i].time = m;
      }
            
    } else if (m - channels[i].time >  THRESHHOLD) {
      channels[i].state = (channels[i].state + 1) % 4; //change state   
    }
  } 
}


//discover target node
void discover() {
  //mySerial.println("discover");
  //if we don't get a address we can't fire
  while (true) {
    //send node discovery
    xbee.send(atRequest);
    
    //default value is that responding XBEE can wait up to six seconds before answering
    //so spamming it with node discoverys might be a bad thing, but waiting so long is booring so
    //we we'll try it and see if it works...
    
    //knight rider on the diodes let's the users know we're looking
    for (int i=0; i<CHANNELS; i++) {
      clearLeds();
      digitalWrite(channels[i % CHANNELS].led_pin,HIGH);

      if (checkNDResponse()) {
        return;
      }      
    }

    for (int i=CHANNELS-1; i>=0; i--) {
      clearLeds();
      digitalWrite(channels[i % CHANNELS].led_pin,HIGH);

      if (checkNDResponse()) {
        return;
      }      
    }
  }
}

boolean checkNDResponse() { 
  //mySerial.println("checkNDResponse");
  // wait a small bit so the animation looks good
  if (xbee.readPacket(ND_WAIT_TIME / 6)) {
    // got a response!

    // should be an AT command response
    if (xbee.getResponse().getApiId() == AT_COMMAND_RESPONSE) {
      xbee.getResponse().getAtCommandResponse(atResponse);

      if (atResponse.isOk()) {
        if (atResponse.getCommand()[0] == atCmd[0] && atResponse.getCommand()[1] == atCmd[1] && atResponse.getValueLength() > 3) {

          //mySerial.println(pack(atResponse.getValue()[2],atResponse.getValue()[3],atResponse.getValue()[4],atResponse.getValue()[5]));          
          //mySerial.println(pack(atResponse.getValue()[6],atResponse.getValue()[7],atResponse.getValue()[8],atResponse.getValue()[9]));
          
          addr64 = XBeeAddress64( pack(atResponse.getValue()[2],atResponse.getValue()[3],atResponse.getValue()[4],atResponse.getValue()[5]),pack(atResponse.getValue()[6],atResponse.getValue()[7],atResponse.getValue()[8],atResponse.getValue()[9]) );
          
          
          return true;
        }
      } 
      else {
        //nss.print("Command return error code: ");
        //nss.println(atResponse.getStatus(), HEX);
        nr(1);
      }
    } else {
      //nss.print("Expected AT response but got ");
      //nss.print(xbee.getResponse().getApiId(), HEX);
      nr(2);
    }   
  } else {
    // at command failed
    if (xbee.getResponse().isError()) {
      //nss.print("Error reading packet.  Error code: ");  
      //nss.println(xbee.getResponse().getErrorCode());
      nr(3);
    } 
    else {
      //nss.print("No response from radio");  
      nr(4);
    }
  }
  return false;
}

void error(int code) {
  //flash all diods once slowly then change to a binary error code representation
  flashAll(500);
}

//flash leds once, variable time
void flashAll(int ms) {
  for (int i=0;i<CHANNELS; i++) {
    digitalWrite(channels[i].led_pin,HIGH);
  }
  
  delay(ms);
  clearLeds();  
}

//clear all leds
void clearLeds() {
  for (int i=0;i<CHANNELS; i++) {
    digitalWrite(channels[i].led_pin,LOW);
  }
}

//light up a nr, binary code
void nr(uint8_t nr) {
  //TODO: smarter code...
  if (nr & B00000001) {
    digitalWrite(8,HIGH);
  }
  if (nr & B00000010) {
    digitalWrite(9,HIGH);
  }
  if (nr & B00000100) {
    digitalWrite(A3,HIGH);
  }
  if (nr & B00001000) {
    digitalWrite(A0,HIGH);
  }
  if (nr & B00010000) {
    digitalWrite(A1,HIGH);
  }
  if (nr & B00100000) {
    digitalWrite(A2,HIGH);
  }
}
 
uint32_t pack(uint32_t c1, uint32_t c2, uint32_t c3, uint32_t c4) {
    return (c1 << 24) | (c2 << 16) | (c3 << 8) | (c4);
}
