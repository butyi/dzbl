# dzbl

Bootloader for Motorola/Freescale/NXP MC9S08DZ60
based on [gzbl](https://github.com/butyi/gzbl/), what is similar but for older GZ60 microcontroller.

## Terminology

### Monitor loader

Monitor loader is a PC side software which can update program memory of any an microcontroller, even if it is empty (virgin).
Disadvantage is it needs special hardware interface, like USBDM.

### Bootloader

Bootloader is embedded side software in the microcontroller,
which can receive data from once a hardware interface and write data into own program memory. 
This software needs to be downloaded into microcontroller only once by a monitor loader.

### Downloader

Downloader is PC side software. The communication partner of Bootloader. 
It can send the compiled software (or any other data) to data to microcontroller through the supported hardware interface. 
Here this is dzdl.py.

### Application

Application is embedded side software. This is the main software of microcontroller. 
Bootloader is just to make update of application software easier.

## Working

Main function of bootloader is to be able to (re-)download easily and fast the application software.
After power on the bootloader is started. It waits for 1 sec for connection attempt.
If there was no trial to use bootloader services, it calls the application software.
If there is not yet application software downloaded, execution remains in the bootloader,
and bootloader waits for download attempt for infinite.

## Hardware interfaces

My bootloader uses SCI and CAN interfaces for communication.

### SCI

SCI is an assyncron serial port, so called RS232.
SCI port so widely used, known, that even if this port is not standard on personal computers any more,
beu it can be purchased easily as a checp USB-SERIAL interface. 
My default baud rate is 57600. 8 bits. No parity.

On my hardware the two not used pins of 6 pin BDM are connected to SCI1 Tx and Rx. 
This ensures convinient way to update software by a cheap USB TTL serial interface.

### CAN

CAN is industry and automotive communication interface. CAN hardware components are more expensive than SCI,
but in some fields of industry it is comfotrable to update software or change parameters through
the existing and used communication interface, even far from the target hardware.

## Main Concept

As you may know, Flash memory always consists sectors. Sector is the smalest part of memory what can be erased separately.
This means, when not complete Flash sector content need to be updated, but only a part of a sector, the full sector content
need to be saved into RAM, change the needed bytes in RAM, erase the complete sector, and write the complete sector back from RAM to Flash.

In older GZ60 bootloader, the above procedure is implemented in bootloader and the downloader can send only partial sector data,
because GZ60 sector size is only 128 bytes.

Since DZ60 has much larger Flash sectors (768 bytes), I decided to change this concept.
Reason is, the needed RAM buffer is too large. Furthermore if 8 byte data arrive in a CAN message,
a 768 byte long sector would be erased 96 times while the complete sector is updated. This would significantly
decrease the lifetime of Flash memory.

According to my new concept, the management of memory content, 
read (maybe), erase and write shall be managed by PC side downloader.

Read is usually not necessary for a software download, since complete page content is updated.

## Communication Concept

Communication is very similar on both SCI and CAN. CAN message ID bytes are used on SCI also as frame header.
Data not need to be encapsulated into 8 byte long data frames on SCI, like on CAN, but can be transmitted as a long byte stream.

### Message header

CAN ID and SCI frame head is 0x1CDATTSS, where
- TT is ID of target ECU
- SS is source address of downloader/diagnostic tool 

#### Unique ID

SS is identifier (ID) of ECU on communication bus (like CAN or RS485).
ID is used to address a single ECU on communication bus where several ECUs are connected to each other.
Practically SS can be any value except TT.
ECU answers shall be addressed to revecived SS.

In examples below, ECU ID will be 0x0E (Ecu), tool ID will be 0xDE (Diag Equipment).
Therefore request messages will be started by 0x1CDA0EDE, answers with 0x1CDADE0E.

#### Broadcast ID

ID value 0xFF reserved as broadcast ID. Such a request shall be executed by all ECUs on the communication bus. 
Answer for broadcast request shall be sent from private ID, if exists. If not yet exists, default ID (0xFF) also suitable.
 
### Services

There are several services. Each service can be requested by a well defined request message.
Every request is answered by some kind of resonse. Not used bytes are filled with 0xFB (Filler Byte)
The available request-answer communications are described below.

#### Tester Present (DLC=0)

1CDA0EDE    Tx     0     (Tester Present, keep in bootloader)
1CDADE0E    Rx     0

#### Instruction without parameter (DLC=1) 

1CDA0EDE    Tx     1     11 (Reset, no answer)
1CDA0EDE    Tx     1     52 (Run application immediately, no answer)

#### Scan network (DLC=1)

1CDAFFDE    Tx     1     22 (Read SerNum and CAN ID, only broadcast accepted)  
1CDADEFF    Rx     7     23 03 06 18 02 22 FF (Report CAN ID of SerNum)  
1CDADEFF    Rx     7     23 03 06 18 03 32 FF (Report CAN ID of SerNum)

#### Erase (DLC=2)

1CDA0EDE    Tx     2     80 00 (Address)  
1CDADE0E    Rx     1     00

#### Read (DLC=3)

1CDA0EDE    Tx     3     80 00 08 (Address and length)  
1CDADE0E    Rx     8     11 22 33 44 55 66 77 88  
1CDADE0E    Rx     8     EC FB FB FB FB FB FB FB

Answer for this request is several 8 byte long messages with the length number of data,
and finally 1 byte simple additional checksum.

Positive response is not reported for read request, becase sent data will inform about success.
Negative response is reported in case of any error and in this case no data will be sent back.

#### Write (DLC=4)

1CDA0EDE    Tx     4     80 00 08 00 (Address, length and timeout byte)  
1CDA0EDE    Tx     8     11 22 33 44 55 66 77 88  
1CDA0EDE    Tx     8     EC 00 00 00 00 00 00 00  
1CDADE0E    Rx     1     00

Timeout byte is not yet implemented. Its value is don't care.

RAM write is also supported, so any memory can be written by this request.

Length support only 255 bytes (will be limited to 8 like on CAN), so more requests shall be sent to
fill up a complete 768 byte long Flash sector.

#### Diagnostic (DLC=5)

DLC=5 is reserved for normal diagnostic, like DID based EEPROM parameter change or other simple diagnostic sercices.
This is not supported by Bootloader. Bootloader usually has limited diag services, like identification or fault read,
but these services shall be served by simple Read service from the appropriate address.

1CDA0EDEx   Tx     5     SS PP PP PP PP  (SS=Service, PP=Parameter of service)

#### Fingerprint (DLC=6)

1CDA0EDEx   Tx     6     xx xx xx xx xx xx (Value are info about who/when/where does the activity)

#### Update ID (DLC=7)

1CDAFFDEx   Tx     7     23 03 06 18 02 22 2A (Write CAN ID of SerNum SerNum, only broadcast accepted)  
1CDADE2Ax   Rx     1     00 (Positive response)

This command will write ECUID to first byte of 8 byte long EEPROM sector.
Second byte is update counter. To remaining 6 bytes the currently stored fingerprint is copied.
Value 0xFF in last 6 byte means, ID was not yet updated by CAN or SCI command since last bootloader download.

### Use cases

#### Network setup

Init on virgin network or assign ID to virgin ECU.

1CDAFFDEx   Tx     1     22 (Read SerNum and CAN ID, only broadcast accepted)  
1CDADEFFx   Rx     7     23 03 06 18 02 22 FF (Report CAN ID of SerNum)  
1CDADEFFx   Rx     7     23 03 06 18 03 32 FF (Report CAN ID of SerNum)  
1CDAFFDEx   Tx     7     23 03 06 18 02 22 0E (Write CAN ID of SerNum, only broadcast accepted)  
1CDADE0Ex   Rx     1     00 (Positive response)  
1CDAFFDEx   Tx     7     23 03 06 18 03 32 0A (Write CAN ID of SerNum, only broadcast accepted)  
1CDADE0Ax   Rx     1     00 (Positive response)

#### Software download

- Use Fingerprint command
- Use Erase command to clear your fisrt sector
- Use consecutive Write commands to fill up the sector.
- Use Erase command to clear second sector
- Use consecutive Write commands to fill up the sector.

## SCI Concept

SCI communication is very similar to CAN.
Message header is the CAN ID bytes. Next follows a DLC byte and the same data bytes like on CAN.
The only difference is an additional checksum byte, what is simple addition of each prevoius bytes
including message header. Since message header is the CAN ID actually which contains target and
source address, the protocol is suitable on SCI based buses, like RS485 or LIN.

Let me mention, I plan to change this, and same SCI propocol is planned as CAN. This will decrease bootloader code side,
since do not need double protocol implementation. 

## Response codes

Codes in high or low nibble of response error code are same.
- 0x0=Success
- 0x1=Access error
- 0x2=Protection violation
- 0x5=Length is zero
- 0x6=Length is too high
- 0x7=Unexpected command or CAN DLC
- 0x8=Unexpected subservice in request service
- 0xA=Address error (Bootloader code range is prohibited to be changed) 
- 0xB=Boundary violation 
- 0xC=Checksum error
- 0xD=Data error (e.g. wrong filler byte value)
- 0xE=End of time (timeout)
- 0xF=Fingerprint not written 

High nibble reports memory errors.
Low nibble reports protocol errors

## Vector concept

Bootloader does not use any interrupt, to not not disturb application software structure with vector re-mapping difficulties.
Last page, where vectors are stored, is not used by bootloader. Last page is used only for interface with application software.
All interrupt vectors are free for application software.
The only speciality is, reset vector always contains start address of bootloader in ECU.
When last page is attempted to be written, bootloader moves reset vector of application software to 0xFFA0 address.
Later, when download is finished, bootloader will start application software from APPADDRESS (0xFFA0) address.

## Configuration

I have introduced BLCR (BootLoader Configuration Register) for bootloader setting possibility by Application software.
Address of BLCR is 0xFFAC. Default value is 0xFF like an erased Flash byte.
- Bit 0 is Enable Terminal on SCI (BLCR_ET). Terminal is enabled by default with bit value 1.
- Bit 1 is Enable print welcome string on SCI (BLCR_EW). This is enabled by default with bit value 1.

## EEPROM concept

EEPROM is configured into 8 byte mode. Bootloader uses only some last sectors.
As known, only half of EEPROM is mapped into addressable memory and can be accessed.
EPGSEL bit in FCNFG register selects which half of the array can be accessed.
EPGSEL bit is not touched and not handled by bootloader.
Reset clears EPGSEL. This ensures bootloader always see the proper (default) half part.
To program both half of EEPROM, EPGSEL bit need to be updated by application software before write any data to EEPROM.
If this concept does not match to your needs, please modify my bootloader to your needs on a branch.

### Sector 0x17F8 (last)

Eight bytes long sector contains ECU own ID byte at address 0x17F8. Other 7 bytes are not used.

If application software has the feature to update ECU ID. In this case bootloader will communicate with new ID as well.

### Sector 0x17F0 (second last)

Eight bytes long sector contains download fingerprint.
Fingerprint consists of 
- 6 received bytes. These are received from downloader tool.
It can be a timestamp or any meaningfull bytes to identify who/when/why updated the software last time.
- 1 byte update counter. This is incremented by one at each fingerprint update by bootloader.
It gives information about how many times were the memory updated by bootloader.
- 1 byte checksum. This is simple addition of previous 7 bytes. If its value does not match, fingerprint most likely invalid.

Application software may update this fingerprint, but I propose application software should use a separated fingerprint,
to have information about software update.

### Sector 0x17E8

Eight bytes long sector contains CAN baudrate configuration two bytes.
Byte at address 0x17E8 is CANBTR0 value (SJW = 1...4 Tq, Prescaler value = 1...64). 
Byte at address 0x17E9 is CANBTR1 value (Sample per bit = 1 or 3, Tseg2 = 1...8 Tq, Tseg1 = 1...16 Tq).
Other 6 bytes are not used.

When any of two byte has value 0xFF (not programmed EEPROM byte), default 500kbaud values are forced to be possible to connect to ECU.

Examples (CANBTR0,CANBTR1) with 4MHz quarz.
- 0x00,0x01         ; Baud = 4MHz / 1 / (1+2+1) = 1M.    Sample point = (1+2)/(1+2+1) = 75%
- 0x00,0x05         ; Baud = 4MHz / 1 / (1+6+1) = 500k.  Sample point = (1+6)/(1+6+1) = 87.5%
- 0x01,0x05         ; Baud = 4MHz / 2 / (1+6+1) = 250k.  Sample point = (1+6)/(1+6+1) = 87.5%
- 0x03,0x05         ; Baud = 4MHz / 4 / (1+6+1) = 125k.  Sample point = (1+6)/(1+6+1) = 87.5%
 
Examples (CANBTR0,CANBTR1) with 8MHz quarz.
- 0x00,0x05         ; Baud = 8MHz / 1 / (1+6+1) = 1M. Sample point = (1+6)/(1+6+1) = 87.5%
- 0x01,0x05         ; Baud = 8MHz / 2 / (1+6+1) = 500k. Sample point = (1+6)/(1+6+1) = 87.5%
- 0x03,0x05         ; Baud = 8MHz / 4 / (1+6+1) = 250k. Sample point = (1+6)/(1+6+1) = 87.5%
- 0x07,0x05         ; Baud = 8MHz / 8 / (1+6+1) = 125k. Sample point = (1+6)/(1+6+1) = 87.5%

It is proposed for application software to read, use and may update this settings to be bootloader communication same as application software.
 
### Sector 0x17E0

Eight bytes long sector contains SCI baudrate configuration byte at address 0x17E0. Other 7 bytes are not used.

Baudrate = 1Mbaud / byte value, when fBus is 16MHz.

Examples: 
- 1 = 1M
- 2=500k
- 4=250k
- 5=200k
- 9=115200 (3.7%)
- 17=57600 (2.1%)
- 26=38400 (0.2%)
- 52=19200 (0.2%)-
- 104=9600 (0.2%).

It is proposed for application software to read, use and may update this settings to be bootloader communication same as application software.

## Identifications

### Bootloader version

Bootloader version is stored at address 0xFCF0. Lenght is 8 bytes. This is a printable "X.XX" format string with zero byte terminator.

### Serial number

ECU serial number is stored at address 0xFCF8. Lenght is 8 bytes. It is generated from date and time during compilation by compiler.
This means, same bootloader shall not be downloaded into more ECUs, because serial number will not unique.
To prevent this, the downloader bash command file should call the compile before each download.
This is my solution to ensure so not be two ECU with same serial number. You can find other way too to ensure this, but do not forget!

## Shared functions

### Non Volatile Memory manipulation

First two bytes of Bootloader memory page is address of `MEM_doit` function.
Function can be called by application software to modify Flash or EEPROM.

Of course, modification of bootloader pages are disabled by software.
Such attempt will result "Address error" negative response.

While non volatile memory is modified, it is not allowed to be used by any other purpose,
including executing software from the memory. This means, when Flash is erased or written,
the software which do this shall be executed from RAM or EEPROM. EEPROM can only be modified
when software is runnung from RAM or Flash. Since I want to use `MEM_doit` function to
modify both Flash and EEPROM, my routine is executed from RAM. It is called `MEM_inRAM`.
My routine is copied into last 128 bytes of RAM.
Do not forget, if you are using `MEM_doit` service if bootloader in your application software,
do not use and do not overwrite bootloader routine in RAM address range 0x1000 - 0x107F.

More details about how to use the function, refer comment part at top of file mem.asm.

### PCB related 

PCB specific interface is defined to do some hardware related activities already by bootloader, if needed.
It is mostly debug LED handling. Others may also be handled here, like initialization of a display or similar.

The following interface function vectors are supported. If application software implements any of function below,
its entry address to be given to bootloader by interface function vectors.

#### PCB Init

Interface function vector for PCB related initializations. Like LED port direction, display init, or similar. Address is 0xFFA2. 
If a vector not not available, its value id 0xFFFF as erased Flash, call is skipped by bootloader.

#### LED On

Interface function vector for switch debug LED on. Address is 0xFFA4. 

#### LED Off

Interface function vector for switch debug LED off. Address is 0xFFA6. 

### System clock

MCG module is initialized by bootloader to be bus frequency 16MHz with 4MHz quarz.
If this is suitable for application software too, no further MCG init is needed in application software. 

Application software may change this frequency.
In this case and if you use `MEM_doit` function of bootloader,
do not forget to check if FCDIV value is still sufficient.

## Application call

Application is only called, if valid (non 0xFFFF) address is available az address 0xFFA0.

Before application is called
- RAM is erased expect Non Volatile Memory manipulation routine in range 0x1000 - 0x107F.
- SCI, CAN and RTC modules are uninitialized. It means, register values are restored to reset value.
- MCG is kept initialized with fBus = 16Mhz with 4MHz quarz.
- Stack is initialized to XRAM end (0x0FFF)

Application is called by jmp (not by jsr), this means return is not expected. Bootloader to be called by MCU reset.

## SCI Terminal

While bootloader is running, if 't' character is received, bootloader starts a simple terminal software.
This is very helpful during debugging application software development.

Terminal functions

- Help for terminal.
- Print ECU ID.
- Dump 256 bytes of memory. Sub services are Previous, Again and Next 256 bytes.
- Write hexa data into any memory.
- Write simple text into any memory.
- Erase Flash or EEPROM sector.

Terminal have 8s timeout. If you don't push any button for 8s, Terminal will exit to not block calling of application software.
Push '?' for help. Terminal applies echo for every pressed key to be visible which were already pressed.
Write is sector based here also, so it is not supported to write through on sector boundary.
Bootloader memory range is protected, cannot be written also from here.
 
## Compile and Download

- Download assembler from [aspisys.com](http://www.aspisys.com/asm8.htm).
  It works on both Linux and Windows.
- Check out the repo
- Run `asm8 prg.asm` on Linux or `asm8.exe prg.asm` on Windows.
- prg.s19 will be ready to download by [USBDM](https://sourceforge.net/projects/usbdm/).

USBDM is a free software and cheap hardware tool which supports S08 microcontrollers.

## Downloader

Downloader for SCI is `dzdl.py`.

Downloader is a simple Python code. It supports s19 software download and serial terminal client on both Linux and Windows.

To see available command line options, use `-h` option as help. Most of options are clear, does not need any explanation here.

Option `-p` on Linux expects full path to resource. Like `/dev/ttyUSB0`, not only `ttyUSB0` or `/ttyUSB0`

Downloader creates a log file about activities. File is `dzdl.com`. I propose to see file by command `cat dzdl.com`.

With `-m` option, `dzdl.py` will create a memory map file, called `dzdl.mem`. I propose to dump it by command `xxd dzdl.mem`.

> [!IMPORTANT]
> CAN download is not yet implemented, but comming soon hopefully.

First [PCAN USB](https://www.peak-system.com/PCAN-USB.199.0.html?&L=1) will be supported, because I currently have that one.
Future plan is to support also cheap Chinese CAN-USB interfaces. I will order some and when I will have some time, I will implement.

## Getting started common

- Install Python if command `python --version` does not report a valid version. In my case answer is now `Python 3.6.9` (2023.10.23).
- Download assembler from [aspisys.com](http://www.aspisys.com/asm8.htm).
- Store executable in a folder which is visible by PATH environment variable.
- Open a terminal.
- Search or create a folder for files.
- Check out dzbl repo by `git clone https://github.com/butyi/dzbl.git`
- Run `asm8 prg.asm` on Linux or `asm8.exe prg.asm` on Windows to compile the bootloader.
Expected results like  
`Assembled prg.asm (9177 lines)               3862 bytes, RAM:   154, CRC: $D7C6`  
`1 file processed! (Elapsed time: 00:00:01)`  
- Download prg.s19, for example by [USBDM](https://sourceforge.net/projects/usbdm/).
- Run `asm8 app.asm` on Linux or `asm8.exe app.asm` on Windows to compile the exmple application.

### SCI

- Create serial connection between PC and MCU. I propose an USB-TTL serial converter. Search "usb to rs232 ttl converter".
- Call dzdl.py in terminal mode by command `python dzdl.py -t` to see if is connection proper or not.
- Do a power or external reset. You should see this in the already open terminal screen:  
`MC9S08DZ60 BootLoader (github.com/butyi/dzbl) V0.00 ID=0E`  
`Push t button for terminal!`  
`Application is not found. Stay in BootLoader.`  
- Push ESC button to exit from terminal.
- Download example application by command `python dzdl.py -f app.s19`. Expected results is like this:  
`dzdl.py - MC9S08DZ60 DownLoader - V0.00 2023.10.24.`  
`Port '/dev/ttyUSB0'`  
`Baud rate is 57600`  
`Open serial port, Done.`  
`Build up memory model, Done.`  
`Read S19 file app.s19, Done.`  
`Fill memory sectors with data, Done.`  
`Connect to device (Press Ctrl+C to abort), Done.`  
`Write fingerprint, Done.`  
`Erase sector 0xFD00 - 0xFFFF, Reset vector, Done.`  
`Erase sector 0x17e0 - 0x17e7, EEPROM SCI Baud Rate, Done.`  
`Program address 0x17e0 length 8, EEPROM SCI Baud Rate, Done.`  
`Erase sector 0x4000 - 0x42ff, Application software, Done.`  
`Program address 0x4000 length 8, Application software, Done.`  
`Program address 0x4008 length 8, Application software, Done.`  
`Program address 0x4010 length 8, Application software, Done.`  
`Program address 0x4018 length 8, Application software, Done.`  
`Program address 0x4020 length 8, Application software, Done.`  
`Program address 0x4028 length 8, Application software, Done.`  
`Program address 0x4030 length 8, Application software, Done.`  
`Program address 0x4038 length 8, Application software, Done.`  
`Program address 0x4040 length 8, Application software, Done.`  
`Program address 0x4048 length 8, Application software, Done.`  
`Program address 0x4050 length 6, Application software, Done.`  
`Program address 0xffa2 length 6, Done.`  
`Program address 0xffbf length 1, Flash and EEPROM Options Register, Done.`  
`Program address 0xfffe length 2, Reset vector, Done.`  
`Run application, Done.`  
`Done.`  
At this point debug LED is flashing by around half second period.
- Now system is ready to create/download your application software.

 <!---

### CAN

- Create CAN connection between PC and MCU by
[PCAN USB](https://www.peak-system.com/PCAN-USB.199.0.html?&L=1)
  - Install its
    [driver](https://www.peak-system.com/Drivers.523.0.html?&L=1)
  - Check if your CAN bus has terminator resistor.
    Best is one-one 120 Ohm resistor at the two end of CAN bus,
    but for short distance, like on a desk, one resistor between 50 and 500 Ohm will be sufficient.
  - I propose to reach working state of 
    [PCAN-View](https://www.peak-system.com/PCAN-View.242.0.html?&L=1)
    application. Connection is proper if you send a tester present CAN message (ID=0x1CDA0EDE, DLC=0) by
    [PCAN-View](https://www.peak-system.com/PCAN-View.242.0.html?&L=1),
    message is received by MCU, so there is no error frame or message repetition with high bus load
    and response message (ID=0x1CDADE0E, DLC=0) is visible.
  - Exit from
    [PCAN-View](https://www.peak-system.com/PCAN-View.242.0.html?&L=1)
- Download example application by command `python dzdl.py -c -f app.s19`. Here `-c` switch will select the CAN interface. Expected results is like this:  
`dzdl.py - MC9S08DZ60 DownLoader - V0.00 2023.10.24.`  
`Port 'PCAN'`  
...  
At this point debug LED is flashing by around half second period.
- Now system is ready to create/download your application software.

-->

## Example application

File `app.asm` is an example application. It shows how to use all bootloader features, services and interfaces.
It uses
- Already initialized Stack pointer
- Already initialized CPU clock to 16MHz (MCG_Init)
- Already initialized PCB (PCB_Init)
- LED On and Off interfaces
- Read SCI baud rate prescaler from EEPROM
- Call KickCop function of bootloader
- Call MEM_doit to increase an EEPROM byte by one at each start.
- Read serial number to print to SCI
- Read bootloader version string to print to SCI. You can see below in terminal:  
`Example application for dzbl boorloader (github.com/butyi/dzbl)`  
`ID = 0E`  
`New start counter = 02` This 02 is which will be increased by one at each application software restart.   
`Bootloader version = V0.00`  
`ECU Serial number = 23102420202555AA`

## Todo

### Automatic ECUID

dzdl.py

Read ECU IDs by broadcast ID Request and use that ECUID. Aassumption is SCI download is mostly used in point to point connection,
where there are no more ECUs.

### Partial download

dzdl.py

A service would be useful, which always saves last downloaded memory content,
and at net download only the changed sectors would be erased and downloaded.
This way, download could be faster, since not changing part won't be downloaded.
(like function library, character table or picture for display, etc.)
Additionally, this saves number of erase cycles that way,
same content is not erased and downloaded again.
To utilize feature better, software should be linked into separated segments (using `align 32` or similar).
This service is only for active software development period, when software is often downloaded.
Therefore to be allowed this differential download service only if saved content is not older that 1 hour.
If older, full download to be executed and memory content file to be updated.

### Escape connection

dzdl.py

Currently only Ctrl+C can be used to break connection.
Connection loop should also be possible to be interrupted by keyboard ESC button.

### Common protocol

can.asm and ser.asm

Currently SCI protocol is different a bit, therefore same commands are implemented twice for SCI and CAN.
According to my new concept, SCI should use the same protocol like CAN.
- Advantages: Protocol is only implemented once, cause less code, smaller bootloader image, less bug potential.
- Disadvantages: SCI download will be slower, because maximum data package is limited to 8 bytes.

## License

This is free. You can do anything you want with it.
While I am using Linux, I got so many support from free projects, I am happy if I can help for the community.
By the way, this microcontroller is so old, to be honest, I do not really think anybody else than me will use this.

## Keywords

Motorola, Freescale, NXP, MC68HC9S08DZ60, 68HC9S08DZ60, HC9S08DZ60, MC9S08DZ60, 9S08DZ60, MC9S08DZ48, MC9S08DZ32, MC9S08DZ16, S08DZ16

###### 2023 Janos Bencsik

