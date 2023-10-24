#!/usr/bin/env python
# -*- coding: utf-8 -*-

# Docstring
"""Command Line DownLoader for Motorola/Freescale/NXP MC9S08DZ60"""

# Set built in COM port useable on Ubuntu:
#   List available ports by 'dmesg | grep tty'. My one is '[    1.427419] 00:01: ttyS0 at I/O 0x3f8 (irq = 4, base_baud = 115200) is a 16550A'
#   Add my user to dialout group by 'sudo gpasswd --add ${USER} dialout'

# Import statements
import os, sys, getopt, struct
import array
import serial # I use Python 2.7.17. For this I needed 'sudo apt install python-pip' and 'sudo python -m pip install pyserial'
import re
import time
import ntpath
from datetime import datetime
if sys.platform.startswith("win"): # Windows
  import msvcrt
else:
  import curses # https://docs.python.org/3/library/curses.html#module-curses

# Authorship information
__author__ = "Janos BENCSIK"
__copyright__ = "Copyright 2023, butyi.hu"
__license__ = "GPL"
__version__ = "V0.00 2023.10.24."
__maintainer__ = "Janos BENCSIK"
__email__ = "dzdl.py@butyi.hu"
__status__ = "Prototype"
__date__ = ""

# Code

# ---------------------------------------------------------------------------------------
# Global variables
# ---------------------------------------------------------------------------------------

inputfile = ""
if sys.platform.startswith("linux") or sys.platform.startswith("cygwin") or sys.platform.startswith("darwin"): # linux or OS X
  port = "/dev/ttyUSB0"
elif sys.platform.startswith("win"): # Windows
  port = "COM1"
baud = 57600
mem_dump = False
mem = bytearray(65536)
connected = False
terminal = False
see_val = False
toolid = 222 # = 0xDE -> Diag Equipment
ecuid = 14 # =0x0E -> ECU

# One SCI frame has 6 bytes without data. (CAN needs similar amout of bytes) 
# This means, 7 or more 0xFF value worse to not send in stream,
# but skip those sending and send next non-FF value in another frame
ff_treshold = 7 

# ---------------------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------
def p(s):
  f1.write(s)
  sys.stdout.write(s)
  sys.stdout.flush()

# ---------------------------------------------------------------------------------------
def err(s):
  p("\nERROR! "+s+"\n\n")
  if 'ser' in globals():
    ser.close()
  f1.close() # Close communication log file
  sys.exit(1)

# ---------------------------------------------------------------------------------------
def h(byte,f = "02X"):
  return("$"+format(byte,f))

# ---------------------------------------------------------------------------------------
def ba2hs(ba): # bytearray to hex string
  ret = ""
  for byte in ba:
    ret += format(byte,"02X")+" "
  return(ret)

# ---------------------------------------------------------------------------------------
def DownloadRow(area, address, length):
  buff = bytearray()

  # Frame header
  buff.append(0x1C)
  buff.append(0xDA)
  buff.append(ecuid)
  buff.append(toolid)
  buff.append(0x04)

  # Address
  cs = 0
  addr_hi = (address >> 8) & 0xFF
  cs += addr_hi
  buff.append(addr_hi)
  addr_lo = address & 0xFF
  cs += addr_lo
  buff.append(addr_lo)

  # Length
  cs += length
  buff.append(length)

  # Timeout (not yet supported)
  buff.append(0x00)

  # Data
  dataindex = address - area['start']
  for i in range(length):
    byte = area['data'][i+dataindex]
    cs += byte
    buff.append(byte)

  # Checksum
  cs &= 0xFF
  buff.append(cs)

  # Transmission
  f1.write("\nDat Tx: "+ba2hs(buff)+"\n")
  num = ser.write(buff)
  if num < len(buff):
    err("Too less written bytes ("+h(num)+") for sector "+h(address,"04X"))

  # Receive answer
  answer = bytearray(ser.read(6))
  f1.write("Dat Rx: "+ba2hs(answer)+"\n")

  if 0==len(answer): # If there was any answer
    err("There was no answer for sector "+h(address,"04X"))
  elif 6>len(answer):
    err("Too short answer for sector "+h(address,"04X"))
  elif 6==len(answer):
    if answer[5] == 0:
      p(", Done.\n")
      return True
    else:
      ShowError(answer[5])
  
  return False

# ---------------------------------------------------------------------------------------
def ShowError(response):
  ShowErrorNibble("Memory error: ", (response >> 4) & 0x0F)
  ShowErrorNibble("Protocol error: ", response & 0x0F)

def ShowErrorNibble(errortype, errorcode):
  if errorcode == 0: return # No error
  elif errorcode == 1: err(errortype+"address error. ")
  elif errorcode == 2: err(errortype+"Protection violation. ")
  elif errorcode == 5: err(errortype+"Length is zero. ")
  elif errorcode == 6: err(errortype+"Length is too high. ")
  elif errorcode == 7: err(errortype+"Unexpected command or CAN DLC. ")
  elif errorcode == 8: err(errortype+"Unexpected subservice in request service. ")
  elif errorcode == 0xA: err(errortype+"Address error (Bootloader code range is prohibited to be changed). ")
  elif errorcode == 0xB: err(errortype+"Boundary violation. ")
  elif errorcode == 0xC: err(errortype+"Checksum error. ")
  elif errorcode == 0xD: err(errortype+"Data error (e.g. wrong filler byte value). ")
  elif errorcode == 0xE: err(errortype+"End of time (timeout). ")
  elif errorcode == 0xF: err(errortype+"Fingerprint not written. ")
  else: err("Unknown error "+h(errorcode)+". ")

def RunApplication():
  run = bytearray([0x1C,0xDA,ecuid,toolid,0x01,0x52]) # Run application
  f1.write("\nRun Tx: "+ba2hs(run))
  ser.write(run)
  # No response expected
  p(", Done.\n")
  return True


# ---------------------------------------------------------------------------------------
def BCD(string2): # Convert decimal to BCD, e.g. from 10 to 0x10
  return (int(string2[0], 16)*16) + int(string2[1], 16)

def WriteFingerprint():
  d = datetime.today()
  year = BCD(d.strftime("%y"))
  month = BCD(d.strftime("%m"))
  day = BCD(d.strftime("%d"))
  t = datetime.now()
  hour = BCD(t.strftime("%H"))
  minute = BCD(t.strftime("%M"))
  second = BCD(t.strftime("%S"))
  wrfp = bytearray([0x1C, 0xDA, ecuid, toolid, 0x06, year, month, day, hour, minute, second]) 
  goodresp = bytearray([0x1C,0xDA,toolid,ecuid,0x01,0x00])

  f1.write("\nWfp Tx: "+ba2hs(wrfp))
  ser.write(wrfp)

  answer = bytearray(ser.read(6))
  if 0<len(answer): # If there was any answer
    f1.write("\nWfp Rx: "+ba2hs(answer))
  if 0==len(answer):
    err("No answer")
  elif 6>len(answer):
    err("Too short answer")
  elif 6==len(answer):
    if answer == goodresp:
      p(", Done.\n")
      return True
    else:
      ShowError(answer[5])
  exit(1)

# ---------------------------------------------------------------------------------------
def ConnectDevice():
  conn = bytearray([0x1C,0xDA,ecuid,toolid,0x00])
  goodresp = bytearray([0xDA,toolid,ecuid,0x00])
  ser.timeout = 0
  conn_period_s = 0.1
  timer = time.perf_counter() + conn_period_s
  try:
    while True:

      # TODO!!! Quit by keyboard ESC button

      if timer < time.perf_counter():
        f1.write("\nCon Tx: "+ba2hs(conn))
        ser.send_break() # Send brake to reset application software for auto connect without need of manual reset
        ser.write(conn)
        timer = time.perf_counter() + conn_period_s

      bs = ser.read(1)
      if 0 == len(bs):
        continue
      if ord(bs) != 0x1C:
        continue

      ser.timeout = 1
      answer = bytearray(ser.read(4))
      if 0<len(answer): # If there was any answer
        f1.write("\nCon Rx: "+ba2hs(answer))
      if answer == goodresp:
        break
      #p(h(ord(resp[0])))
  except KeyboardInterrupt:
    p("\nUser abort.\n")
    ser.close()
    f1.close() # Close communication log file
    sys.exit(0)
  else:
    ser.timeout = 1
    p(", Done.\n")
    return

# ---------------------------------------------------------------------------------------
def EraseSector(address):
  erase =  bytearray([0x1C,0xDA,ecuid,toolid,0x02,((address>>8)&0xFF),((address>>0)&0xFF)])
  goodresp = bytearray([0x1C,0xDA,toolid,ecuid,0x01,0x00])

  f1.write("\nCon Tx: "+ba2hs(erase))
  ser.write(erase)

  answer = bytearray(ser.read(6))
  if 0<len(answer): # If there was any answer
    f1.write("\nCon Rx: "+ba2hs(answer))
  if answer == goodresp:
    p(", Done.\n")
    return True
  if 0==len(answer):
    err("No answer")
  if 6>len(answer):
    err("Too short answer")
  if 6==len(answer):
    ShowError(answer[5])
  exit(1)

def getaddinfo(s):
  addinfo = ""
  if(s == 0x17E0):addinfo = ", EEPROM SCI Baud Rate"
  if(s == 0x17E8):addinfo = ", EEPROM CAN Baud Rate"
  if(s == 0x17F0):addinfo = ", EEPROM Fingerprint of bootloader"
  if(s == 0x17F8):addinfo = ", EEPROM ECU ID"
  if(0x1900 <= s and s <= 0xEAFF):addinfo = ", Application software"
  if(s == 0xFFAC):addinfo = ", BootLoader Configuration Register"
  if(s == 0xFFAE):addinfo = ", FTRIM bit"
  if(s == 0xFFAF):addinfo = ", TRIM value"
  if(0xFFB0 <= s and s <= 0xFFB7):addinfo = ", Backdoor key"
  if(s == 0xFFBD):addinfo = ", Flash and EEPROM Protection Register"
  if(s == 0xFFBF):addinfo = ", Flash and EEPROM Options Register"
  if(0xFFC0 <= s and s <= 0xFFFD):addinfo = ", Interrupt vector"
  if(s == 0xFFFE):addinfo = ", Reset vector"
  return addinfo

# ---------------------------------------------------------------------------------------
def PrintHelp():
  p("dzdl.py - MC9S08DZ60 DownLoader - " + __version__ +"\n")
  p("Download software into flash memory from an S19 file through RS232\n")
  p("Log file dzdl.com is always created/updated (See with 'cat dzdl.com')\n");
  p("Options: \n")
  p("  -p port      Set serial com PORT used to communicate with target (e.g. COM1 or /dev/ttyS0)\n")
  p("  -b baud      Baud rate of downloading\n")
  p("  -f s19file   S19 file path to be downloaded\n")
  p("  -d toolID    Downloader tool ID (default 0xDE)\n")  
  p("  -e ecuID     Target ECU ID (default=14. 256 means auto)\n")  
  p("  -r           Read out current sector data before erase sector. (Not yet supported)\n");
  p("  -t           Terminal after download.\n");
  p("  -m           Memory dump into text file dzdl.mem (See with 'xxd dzdl.mem')\n")
  p("  -s           See values of bytes (show 41 instead of A for example)\n")
  p("  -h           Print out this HELP text\n")
  p("Examples:\n")
  p("  dzml.py -f xy.s19  Download xy.s19 software into uC\n")
  p("  dzml.py -b 9600 -p /dev/ttyUSB0 -t  Serial terminal on 9600 baud\n")
  f1.close() # Close communication log file
  sys.exit(0)

# ---------------------------------------------------------------------------------------
# MAIN()
# ---------------------------------------------------------------------------------------

# Open communication log file
f1 = open("./dzdl.com", "w") # "w" means: truncate file to zero length or create text file for writing. The stream is positioned at the beginning of the file.

#Parsing command line options
argv = sys.argv[1:]
try:
  opts, args = getopt.getopt(argv,"p:b:f:i:e:mtsh",["port=","baud=","file=","toolid=","ecuid=","memory","terminal","seeval","help"])
except getopt.GetoptError:
  p("Wrong option.\n")
  PrintHelp()
for opt, arg in opts:
  if opt in ("-h", "--help"):
    PrintHelp()
  elif opt in ("-p", "--port"):
    port = arg
  elif opt in ("-b", "--baud"):
    baud = int(arg)
  elif opt in ("-f", "--file"):
    inputfile = arg
  elif opt in ("-i", "--toolid"):
    toolid = int(arg)
  elif opt in ("-e", "--ecuid"):
    ecuid = int(arg)
  elif opt in ("-m", "--memory"):
    mem_dump = True
  elif opt in ("-s", "--seeval"):
    see_val = True
  elif opt in ("-t", "--terminal"):
    terminal = True

# Inform user about parsed parameters
p("dzdl.py - MC9S08DZ60 DownLoader - " + __version__ + "\n")
p("Port '" + port + "'\n")

if(port != "printsectors"):
  p("Baud rate is " + str(baud) + "\n")
  
  # Open serial port
  p("Open serial port")
  try:
    ser = serial.Serial(port, baud, timeout=1)
  except:
    err("Cannot open serial port " + port)
  p(", Done.\n")



# ---------------------------------------------------------------------------------------
# Download operation
if 0 < len(inputfile):

  p("Build up memory model")
  # Build memory map of MC9S08DZ60 in sectors. This is a list of dictionary (c struct array)
  #  Property sector and len depends on bootloader, start and length depends on used range in sector.
  sectors =        [{"sector":0x1080, "plen":0x280, "used":False, "areas":[] }] # application identification
  sectors.append(   {"sector":0x1300, "plen":0x100, "used":False, "areas":[] }) # bootloader and hardware identification
  for s in range(0x1400,0x1800,0x8): # EEPROM in 8 byte mode
    sectors.append({"sector":s, "plen":0x8, "used":False, "areas":[] })
  for s in range(0x1900,0xF400,0x300): # Application Flash
    sectors.append({"sector":s, "plen":0x300, "used":False, "areas":[] })
  sectors.append({"sector":0xFD00, "plen":0x300, "used":False, "areas":[] }) # Last vector sector 
  p(", Done.\n")

  # Read S19 into data array. Not used bytes are 0xFF.
  p("Read S19 file "+ntpath.basename(inputfile))
  f = open(inputfile, "r")
  mem = [0xFF] * 65536
  meminuse = [0x00] * 65536

  for line in f.readlines():
    line = line.strip() # Trim new line characters

    pointer = 0

    record_type = line[pointer:pointer+2]
    pointer += 2

    record_length = int(line[pointer:pointer+2],16)-1
    pointer += 2

    if record_type == "S1":
      record_address = int(line[pointer:pointer+4],16)
      record_length -= 2
      pointer += 4
    else:
      continue

    for x in range(record_length):
      record_byte = line[pointer:pointer+2]
      pointer += 2
      mem[record_address] = int(record_byte,16)
      meminuse[record_address] = 1
      record_address += 1

    record_cs = line[-2:] # I do not check the checksum, sorry


  f.close()
  p(", Done.\n")

  # Save memory content
  if mem_dump:
    p("Create or update file dzdl.mem")
    f2 = open("./dzdl.mem", "wb")
    f2.write(bytearray(mem))
    f2.close()
    p(", Done.\n")

  # Fill memory map data from S19
  p("Fill memory sectors with data")
  for s in sectors:
    ff_counter = 0 # Number of consecutive 0xFF value
    start = 0
    end = 0
    data = bytearray() # Init with empty list
    for a in range(s["sector"], s["sector"] + s["plen"]): # Go forward on sector addresses
      if meminuse[a]: # non-empty data value
        s["used"] = True # Mark as sector is used
        ff_counter = 0 # Reset FF counter
        if start == 0: # If used area is not yet started 
          start = a # Start used area
        end = 0 # Clear end address was maybe previously saved due to FF value 
        data.append(mem[a]) # Add data byte to array
      else: # not used
        if start == 0: # if area not yet started 
          continue # wait further for non-FF byte
        if end == 0: # If end not yet saved, save since this is now an empty data byte 
          end = a-1 # Save end address of last non-FF values area
        data.append(mem[a]) # Add data bytes
        ff_counter += 1 # Count number of empty (0xFF) values
        if ff_treshold < ff_counter: # Too many consecutive FF value
          length = end-start+1 # Get number of non empty data bytes 
          s["areas"].append({"start":start, "len":length, "data":data[:length] }) # Add area dictionary to areas
          ff_counter = 0 # Clear number of consecutive 0xFF value
          start = 0     
          end = 0       
          data = bytearray() # Init with empty list
    if 0 < start: # There is open area
      length = a-start+1 # Get length of area
      s["areas"].append({"start":start, "len":length, "data":data[:length] }) # close it

  # Delete not used sectors from list
  sectors[:] = [s for s in sectors if s.get("used") != False]
  p(", Done.\n")

  # Debug service to check if sectors were processed well
  if(port == "printsectors"):
    for sector in sectors:
      print("Sector "+hex(sector['sector'])+" - "+hex(sector['sector']+sector['plen']-1)+":")
      for area in sector['areas']:
        print(" Area "+hex(area['start'])+" - "+hex(area['start']+area['len']-1) + " ("+hex(area['len'])+") ")
    exit(0)

  # Connecting to devive
  p("Connect to device (Press Ctrl+C to abort)");
  ConnectDevice()

  # Write fingerprint
  p("Write fingerprint");
  WriteFingerprint()

  # Erase start vector sector first. This will be written last time, what ensures that interrupted download will finally not be called.
  p("Erase sector 0xFD00 - 0xFFFF"+getaddinfo(0xFFFE))
  EraseSector(0xFFFE) # Here it is not problem, that the complete sector is erased. Content will be written again during download.

  # Download sectors
  for sector in sectors:
    if(sector['sector'] != 0xFD00): # Do not need here to erase last (vector) page, because it was already erased before  
      p("Erase sector "+hex(sector['sector'])+" - "+hex(sector['sector']+sector['plen']-1)+getaddinfo(sector['sector']))
      EraseSector(sector['sector'])
    for area in sector['areas']:
      #p("Program area "+hex(area['start'])+" - "+hex(area['start']+area['len']-1) + " ("+hex(area['len'])+")\n")
      cs = 0
      l = area['len']
      s = area['start']
      while(0<l):
        if(8<=l): # full frame with 8 data bytes
          p("Program address "+hex(s)+" length 8"+getaddinfo(s))
          DownloadRow(area,s,8)
          s+=8
          l-=8
        else: # less than 8 data bytes 
          p("Program address "+hex(s)+" length "+str(l)+getaddinfo(s))
          DownloadRow(area,s,l)
          l=0

  # Run application immediately
  p("Run application");
  RunApplication()



# ---------------------------------------------------------------------------------------

# Terminal
#cmd_testpres = bytearray([0x1C,0xDA,ecuid,toolid,0x00])
#cmd_reset =  bytearray([0x1C,0xDA,ecuid,toolid,0x01,0x11])
#cmd_erase =  bytearray([0x1C,0xDA,ecuid,toolid,0x02,0x80,0x00])
#cmd_read =   bytearray([0x1C,0xDA,ecuid,toolid,0x03,0x17,0xF0,0x10]) #Read ECUID
#cmd_read =   bytearray([0x1C,0xDA,ecuid,toolid,0x03,0x80,0x00,0x08]) 
#cmd_read =   bytearray([0x1C,0xDA,ecuid,toolid,0x03,0xFF,0xBE,0x02]) 
#cmd_write =  bytearray([0x1C,0xDA,ecuid,toolid,0x04,0x80,0x00,0x08,0x10,ord('b'),ord('u'),ord('t'),ord('y'),ord('i'),ord('.'),ord('h'),ord('u'),0xD0])
#cmd_write =  bytearray([0x1C,0xDA,ecuid,toolid,0x04,0xFF,0xBE,0x02,0x10,0x55,0xAA,(0x1C+0xDA+ecuid+toolid+0x04+0xFF+0xBE+0x02+0x10+0x55+0xAA)&0xFF])
#cmd_scanet = bytearray([0x1C,0xDA,0xFF,toolid,0x01,0x22]) 
#cmd_setid =  bytearray([0x1C,0xDA,0xFF,toolid,0x07,0x23,0x03,0x10,0x22,0x28,0x41,0x0E]) 
#cmd_wrfp =   bytearray([0x1C,0xDA,ecuid,toolid,0x06,0x23,0x03,0x10,0x22,0x28,0x41]) 

if terminal:
  f1.write("\nTerminal started\n")
  ser.timeout = 0 # clear timeout to speed up terminal response
  if not sys.platform.startswith("win"): # Linux
    stdscr = curses.initscr()
    curses.noecho() # switch off echo
    stdscr.nodelay(True) # set getch() non-blocking
    stdscr.scrollok(True)
    stdscr.idlok(True)
  while True:

    if sys.platform.startswith("win"): # Windows
      # From keyboard to UART
      if msvcrt.kbhit():
        c = msvcrt.getch()
        if ord(c) == 0x1B: # ESC button
          break
        if ord(c) != -1:
          ser.write(c)
          f1.write(str(chr(c[0])))
      # From UART to display
      bs = ser.read(1)
      if len(bs) != 0:
        p(str(chr(bs[0])))
    else: # Linux
      # From keyboard to UART
      c = stdscr.getch()
#      if c == curses.KEY_F3:
#        ser.write(cmd_connect)
#        continue
#      if c == ord('C'):
#        ser.write(cmd_testpres)
#        continue
#      if c == ord('I'): # Instruction
#        ser.write(cmd_reset)
#        continue
#      if c == ord('E'):
#        ser.write(cmd_erase)
#        continue
#      if c == ord('W'):
#        ser.write(cmd_write)
#        continue
#      if c == ord('R'):
#        ser.write(cmd_read)
#        continue
#      if c == ord('S'):
#        ser.write(cmd_scanet)
#        continue
#      if c == ord('F'):
#        ser.write(cmd_wrfp)
#        continue
#      if c == ord('O'): # OWNID set
#        ser.write(cmd_setid)
#        continue        
      if c == 0x1B:
        break
      if c != -1:
        ser.write(chr(c).encode())
        f1.write(chr(c))

      # From UART to display
      try:
        bs = ser.read(1)
      except:
        # Restore original window mode
        if not sys.platform.startswith("win"): # Windows
          curses.echo()
          curses.reset_shell_mode()
        err("\rPort " + port + " broken")
      if len(bs) != 0:
        if see_val and ord(bs) != 0x0A:
          s = format(ord(bs),"02X")
          stdscr.addch(s[0])
          stdscr.addch(s[1])
          stdscr.addch(0x20)
        else:
          stdscr.addch(bs)
        f1.write(str(bs))

  # Restore original window mode
  if not sys.platform.startswith("win"): # Windows
    curses.echo()
    curses.reset_shell_mode()
  p("\n")

# ---------------------------------------------------------------------------------------

p("Done.\n")
if 'ser' in globals():
  ser.close()
f1.close() # Close communication log file
sys.exit(0)

