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

## Hardware interfaces

My bootloader uses SCI and CAN interfaces for communication.

SCI is an assyncron serial port, so called RS232.
SCI port so widely used, known, that even if this port is not standard on personal computers any more,
beu it can be purchased easily as a checp USB-SERIAL interface. 
My default baud rate is 57600. 8 bits. No parity.

CAN is industry and automotive communication interface. CAN hardware components are more expensive,
but in some fields of industry it is comfotrable to update software or change parameters through
the existing and used communication interface, even far from the target hardware.

## Concept

As you may know, Flash memory always consists sectors. Sector is the smalest part of memory what can be erased separately.
This means, when not complete Flash sector content need to be updated, but only a part of a sector, the full sector content
need to be read into RAM, change the needed bytes in RAM, erase the complete sector, and write the complete sector from RAM back to Flash.

In older GZ60 bootloader, the above procedure is implemented in bootloader and the downloader can send only partial sector data,
because GZ60 sector size is only 128 bytes.

Since DZ60 has much larger Flash sectors (768 bytes), I decided to change this concept.
Reason is, the needed RAM buffer is too large. Furthermore if 8 byte data arrive in a CAN message,
a 768 byte long sector would be erased 96 times while the complete sector is updated. This would significantly
decrease the lifetime of Flash memory.

According to my new concept, the management of memory content, 
read (maybe), erase and write shall be managed by PC side downloader.

Read is usually not necessary for a software download, since complete page content is updated.

### Communication Concept

Communication is very similar on both SCI and CAN. CAN message ID bytes are used on SCI also as frame header.
Data not need to be encapsulated into 8 byte long data frames on SCI, like on CAN, but can be transmitted as a long byte stream.

#### Message header

CAN ID and SCI frame head is 0x1CDATTSS, where
- TT is ID of target ECU
- SS is source address of downloader/diagnostic tool 

##### Unique ID

SS is identifier (ID) of ECU on communication bus (like CAN or RS485).
ID is used to address a single ECU on communication bus where several ECUs are connected to each other.
Practically SS can be any value except TT.
ECU answers shall be addressed to revecived SS.

In examples below, ECU ID will be 0x0E (Ecu), tool ID will be 0xDE (Diag Equipment).
Therefore request messages will be started by 0x1CDA0EDE, answers with 0x1CDADE0E.

##### Broadcast ID

ID value 0xFF reserved as broadcast ID. Such a request shall be executed by all ECUs on the communication bus. 
Answer for broadcast request shall be sent from private ID, if exists. If not yet exists, default ID also suitable.
 
#### Services

There are several services. Each service can be requested by a well defined request message.
Every request is answered by some kind of resonse. Not used bytes are filled with 0xFB (Filler Byte)
The available request-answer communications are described below.

##### Tester Present (DLC=0)
1CDA0EDEx   Tx     0     (Tester Present, keep in bootloader)
1CDADE0Ex   Rx     0

##### Instruction without parameter (DLC=1) 
1CDA0EDEx   Tx     1     11 (Reset, no answer)

##### Scan network (DLC=1)
1CDAFFDEx   Tx     1     22 (Read SerNum and CAN ID, only broadcast accepted)  
1CDADEFFx   Rx     7     23 03 06 18 02 22 FF (Report CAN ID of SerNum SerNum)  
1CDADEFFx   Rx     7     23 03 06 18 03 32 FF (Report CAN ID of SerNum SerNum)

##### Erase (DLC=2)
1CDA0EDEx   Tx     2     80 00 (Address)  
1CDADE0Ex   Rx     1     00

##### Read (DLC=3)
1CDA0EDEx   Tx     3     80 00 08 (Address and length)  
1CDADE0Ex   Rx     1     00        - !!! do not send positive answer  
1CDADE0Ex   Rx     8     11 22 33 44 55 66 77 88  
1CDADE0Ex   Rx     8     EC FB FB FB FB FB FB FB

Answer for this request is several 8 byte long messages with the length number of data,
and finally 1 byte simple additional checksum.

##### Write (DLC=4)
1CDA0EDEx   Tx     4     80 00 08 00 (Address, length and !!!?)  
1CDA0EDEx   Tx     8     11 22 33 44 55 66 77 88  
1CDA0EDEx   Tx     8     EC 00 00 00 00 00 00 00  
1CDADE0Ex   Rx     1     00

RAM write is also supported, so any memory can be written by this request.

Length support only 255 bytes, so more requests shall be sent to
fill up a complete 768 byte long Flash sector.


##### Diagnostic (DLC=5)
DLC=5 is reserved for normal diagnostic, like DID based EEPROM parameter change or other simple diagnostic sercices.
This is not supported by Bootloader. Bootloader usually has limited diag services, like identification or fault read,
but these services shall be served by simple Read service from the appropriate address.

1CDA0EDEx   Tx     5     SS PP PP PP PP  (SS=Service, PP=Parameter of service)

##### Fingerprint (DLC=6)
1CDA0EDEx   Tx     6     xx xx xx xx xx xx (Value are info about who/when/where does the activity)

##### Update ID (DLC=7)
1CDAFFDEx   Tx     7     23 03 06 18 02 22 2A (Write CAN ID of SerNum SerNum, only broadcast accepted)  
1CDADE2Ax   Rx     1     00 (Positive response)

#### Use cases

##### Network setup
Init on virgin network
1CDAFFDEx   Tx     1     22 (Read SerNum and CAN ID, only broadcast accepted)  
1CDADEFFx   Rx     7     23 03 06 18 02 22 FF (Report CAN ID of SerNum)  
1CDADEFFx   Rx     7     23 03 06 18 03 32 FF (Report CAN ID of SerNum)  
1CDAFFDEx   Tx     7     23 03 06 18 02 22 0E (Write CAN ID of SerNum, only broadcast accepted)  
1CDADE0Ex   Rx     1     00 (Positive response)  
1CDAFFDEx   Tx     7     23 03 06 18 03 32 0A (Write CAN ID of SerNum, only broadcast accepted)  
1CDADE0Ax   Rx     1     00 (Positive response)

##### Software download

- Use Fingerprint command
- Use Erase command to clear your fisrt sector
- Use consecutive Write commands to fill up the sector.
- Use Erase command to clear second sector
- Use consecutive Write commands to fill up the sector.

### SCI Concept

SCI communication is very similar to CAN.
Message header is the CAN ID bytes. Next follows a DLC byte and the same data bytes like on CAN.
The only difference is an additional checksum byte, what is simple addition of each prevoius bytes
including message header. Since message header is the CAN ID actually which contains target and
source address, the protocol is suitable on SCI based buses, like RS485 or LIN.

### Response codes

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


### Vector concept

Bootloader does not use any interrupt, to not not disturb application software structure with vector re-mapping difficulties.
Last page (where vectors are stored) is not used by bootloader.
Last page is used by application software with its vectors.
The only speciality is, that reset vector apways contains start address of bootloader.
When last page is attempted to write, bootloader moves reset vector of application software to "MCG Loss Of Lock" vector.
Later, when download is finished, bootloader will start application software from "MCG Loss Of Lock" vector.

My assumption was, "MCG Loss Of Lock" vector is the less frequently used interrupt.
If your application software uses "MCG Loss Of Lock" vector, either bootloader shall be modified or cannot be used.


### Configuration

:exclamation: This part is not yet implemented!!!

> [!IMPORTANT]
> This part is not yet implemented!!!

BLCR (Boot Loader Configuration Register) was inttroduced with bootloader setting possibility by Application software.
Address of BLCR is the last application software byte before bootloader. Default value is 0xFF as an erased Flash byte.
- Bit 0-1 is SCI Baud Rate (SBR). 3=57600, 2=38400, 1=19200, 0=9600. Default is 57600 with bit value 11b
- Bit 2-3 is CAN Baud Rate (CBR). 3=500kBaud, 2=250kBaud, 1=125kBaud, 0=1MBaud. Default is 500kBaud with bit value 11b
- Bit 6 is Enable print welcome string on SCI. This is enabled by default with bit value 1b.
- Bit 7 is Enable Terminal (ET) on SCI. Terminal is enabled by default with bit value 1b.

### EEPROM concept

EEPROM is configured into 8 byte mode. Bootloader uses only the two last sectors.
- Last sector (0x17F8) contains ECU own ID in byte LSB.
- Second last sector (0x17F0) contains fingerprint.

As known, only half EEPROM is mapped and can be accessed.
EPGSEL bit in FCNFG register selects which half of the array can be accessed.
To program both half of EEPROM, EPGSEL bit may need to be written before write to EEPROM area.

### Identifications

Bootloader version is stored at address 0xFCF0. This is a "X.XX" format string with zero byte terminator.

ECU serial number is stored at address 0xFCF8. It is generated from date and time during compilation by compiler.
This means, same bootloader shall not be downloaded into more ECUs, because serial number will not unique.
To prevent this, the downloader bash command file should call the compile before each download.

### Shared functions

#### Non Volatile Memory manipulation

First two bytes of Bootloader memory page is address of `MEM_doit` function.
Function can be called by application software to modify Flash or EEPROM.

Of course, modification of bootloader pages are disabled by software.
Such attempt will result "Address error" negative response.

While non volatile memory is modified, it is not allowed to be used by any other purpose,
including executing software from the memory. This means, when Flash is erased or written
the software which do this shall be executed from RAM or EEPROM. EEPROM can only be modified
when software is runnung from RAM or Flash. Since I want to use `MEM_doit` function for
modify both Flash and EEPROM, my routine is executed from RAM. It is called `MEM_inRAM`.
My routine is copied into last 128 bytes of RAM.
Do not forget, if you are using `MEM_doit` service if bootloader in your application software,
do not use and do not overwrite bootloader routine in RAM address range 0x1000 - 0x107F.

More details about how to use the function, refer comment part at top of file mem.asm.

#### PCB related 

PCB specific interface is defined to do some hardware related activities already by bootloader, if needed.
This is mostly debug LED initialization. Others may also be handled here, like initialization of a display or similar.

> [!IMPORTANT]
> LED handler interface is not yet implemented!!!

### System clock

MCG module is initialized by bootloader to be bus frequency 12MHz.
If this is suitable for application software too, no MCG init is needed. 
Application software may change this frequency.
In this case and if you use `MEM_doit` function of bootloader,
do not forget to check if FCDIV value is still sufficient.

## Working

Main function of bootloader is to be able to (re-)download easily and fast the application software.
After power on the bootloader is started. It waits for 1 sec for connection attempt.
If there was no trial to use bootloader services, it calls the application software.
If there is not yet application software downloaded, execution remains in the bootloader,
and bootloader waits for download attempt for infinite.

## SCI Terminal

While bootloader is running, if 't' character is received, bootloader starts a simple terminal software.
This is helpful during debugging user software development.

Terminal functions

- Help for terminal.
- Dump 256 bytes of memory. Sub services are Previous, Again and Next 256 bytes.
- Write hexa data into any memory.
- Write simple text into any memory.
- Erase Flash or EEPROM sector.

Terminal have 8s timeout. If you don't push any button for 8s, Terminal will exit to not block calling of user software.
Push '?' for help. Terminal applies echo for every pressed key to be visible which were already pressed.
Write is sector based here also, so it is not supported to write through on sector boundary.
Bootloader memory range is protected, cannot be written also from here.
 
## Compile and Download

Just call `asm8 prg.asm`. 
prg.s19 will be ready to download by [USBDM](https://sourceforge.net/projects/usbdm/).

USBDM is a free software and cheap hardware tool which supports S08 microcontrollers.

## Downloader

Downloader for SCI is `dzdl.py`.

> [!IMPORTANT]
> CAN downloaderis not yet implemented!!!

Downloader shall ensure to not cross the sector boundary and to not write without erase.

## Todo

dzdl.py:
A service would be useful, which always saves last downloaded memory content,
and at next download only the changed sectors would be erased and downloaded.
This way, download could be faster, since not changing part won't be downloaded.
(like function library, character table or picture for display, etc.)
Additionally, this saves number of erase cycles that way,
same content is not erased and downloaded again.
This service is only for active software development period, when software is often downloaded.
Therefore allow this differential download service only is saved content is not oldar that 1 hour.

dzdl.py
Read out page data and compare with target content before call erase.
Call erase and write only if content is different.
This method saves number of erase cycles of Flash memory.
This method does not save time because read out data needs same time as write data. 

dzdl.py: Read ECU IDs by broadcast ID Request and use that ECUID 

dzbl: Inhibit read of bootloader code (unlock algorithm)

dzbl: code files review, cleaning, review comments

dzbl: implement management of last EEPROM sector (place of ECUID) with data error

## License

This is free. You can do anything you want with it.
While I am using Linux, I got so many support from free projects, I am happy if I can help for the community.

## Keywords

Motorola, Freescale, NXP, MC68HC9S08DZ60, 68HC9S08DZ60, HC9S08DZ60, MC9S08DZ60, 9S08DZ60, MC9S08DZ48, MC9S08DZ32, MC9S08DZ16, S08DZ16

###### 2023 Janos Bencsik

