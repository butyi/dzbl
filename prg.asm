; =============================================================================
; Bootloader for MC9S08DZ60
; =============================================================================
; The function from outside is very similar to https://github.com/butyi/gzbl
; Start first in uC and check if download is requested from SCI1 or CAN 
;  If not, starts user software if there is
;  If yes, receives data from SCI or CAN and write them to Flash or EEPROM memory.
; It has a simple terminal also for debug purpose 
; Differences to github.com/butyi/gzbl
;  Application start address is stored at address APPADDRESS
;  Usual data packet length is 768 byte long full sector
;  Flash erase and write need to be done by different way 
;  BLCR (BootLoaderConfigRegister) is inttroduced with bootloader setting possibility by Application software
; Same
;  SCI communication protocol on bitrate 57600
;  Program Flash memory code executed in RAM
; Considerations
;  Do not use any interrupt
;  Use internal clock only to work with any external crystal
NVOPT_VALUE     def       %11100010           ;NVFEOPT transfers to FOPT on reset
                         ; |||||||+----------- SEC00 \ 00:secure  10:unsecure
                         ; ||||||+------------ SEC01 / 01:secure  11:secure
                         ; |||+++------------- Not Used (Always 0)
                         ; ||+---------------- EPGMOD - EEPROM Sector Mode (0=4-byte, 1=8-byte)
                         ; |+----------------- FNORED - Vector Redirection Disable (No Redirection)
                         ; +------------------ KEYEN - Backdoor key mechanism enable

#LISTOFF
#include "dz60.inc"             ; Load microcontroller specific register definitions
#LISTON

; Storage place of application start address
APPADDRESS      def     $FFA0
PCBINITADDR     def     $FFA2
LEDONADDR       def     $FFA4
LEDOFFADDR      def     $FFA6

; Application Flash area
; BootLoader Configuration Register
BLCR            def     $FFAC   ; $FF (erased) is default settings
        @bitnum BLCR_ET,0       ; 1 = Enable Terminal
        @bitnum BLCR_EW,1       ; 1 = Enable welcome string on SCI

; EEPROM area

; Baudrate = 1Mbaud / byte value, when fBus = 16MHz
; Examples: 1=1M, 2=500k, 4=250k, 5=200k, 9=115200(3.7%), 17=57600(2.1%), 26=38400(0.2%), 52=19200(0.2%), 104=9600(0.2%).
ECUID           def     $17F8   ; Own ID of ECU (Last page of EEPROM)
FINGERPR        def     $17F0   ; Fingerprint of bootloader usage (usually user info and timestamp) 
EECANBAUD       def     $17E8   ; CAN CANBTR0 (SJW and BPR) and CANBTR1 (TSEG1 and TSEG2) in EEPROM
EESCIBAUD       def     $17E0   ; SCI BaudRate setting in EEPROM. 

; Bootloader Flash area
BL_VERSION      def     $FCF0   ; Bootloader version string
SERIAL_NUMBER   def     $FCF8   ; Hardware serial number (6 bytes + 0x55AA)

NL              equ     $0A     ; New line character (Linux)

; Constants
SHORTWAIT       equ     30      ; Short wait time 32ms/increment (1s) for protocol communication
LONGWAIT        equ     250     ; Short wait time 32ms/increment (8s) for terminal

        #RAM
wr_datac        ds      1  	; Number of data byte to be written (source for flash writer)
dump_addr       ds      2  	; Address variable for general purpose
wr_datat        ds      2
checksum        ds      1  	; frame checksum
nosysinfo       ds      1       ; Administration that "no application software" info was already printed out (do not print it again)
diag_sa         ds      1       ; Source Address of diag tool
fpavail         ds      1       ; Fact than FP is written (0=not yet written)
fp_cs           ds      1       ; FP checksum

        #XRAM
wr_data         ds      $80  	; 128 byte write data buffer.  


;Start of bootloader. This shall be as much as possible in last part of Flash1.
; This ensures compatibility with smaller memory variant uCs, and most space for application software.
; To be adjusted manually without overlap in dz60.inc.
        #ROM
        align 4
        jmp     KickCop         ; Fresh watchdog without damage any register
        align 4
        jmp     MEM_doit        ; Address of non-volatile memory write routine
        
bl_start_addr
;-----------------------------------------
; STRING
;-----------------------------------------
welcome fcs     NL,"MC9S08DZ60 BootLoader (github.com/butyi/dzbl) "
wstrid  fcs     " ID="
sysstr  fcs     " Application is starting.",NL
nsstr   fcs     " Application is not found. Stay in BootLoader.",NL

;-----------------------------------------
;RUTINOK
;-----------------------------------------

; Special COP reset sequence for DZ/FL and compatible derivatives
KickCop
        psha
        lda     #$55
        sta     COP
        coma
        sta     COP
        pula
        rts

startmcg
#include "mcg.asm"
sizemcg        def     $-startmcg
;#Message  Size of MCG is {sizemcg(0)} bytes
startmem
#include "mem.asm"
sizemem        def     $-startmem
;#Message  Size of MEM is {sizemem(0)} bytes
startsci
#include "sci.asm"
sizesci        def     $-startsci
;#Message  Size of SCI is {sizesci(0)} bytes
startrtc
#include "rtc.asm"
sizertc        def     $-startrtc
;#Message  Size of RTC is {sizertc(0)} bytes
startterm
#include "term.asm"
sizeterm        def     $-startterm
;#Message  Size of TERM is {sizeterm(0)} bytes
startcan
#include "can.asm"
sizecan        def     $-startcan
;#Message  Size of CAN is {sizecan(0)} bytes
startser
#include "ser.asm"
sizeser        def     $-startser
;#Message  Size of SER is {sizeser(0)} bytes

;-----------------------------------------
; MAIN rutinok
;-----------------------------------------


; Main entry point. This address shall be in Reset Vector.
entry

	; Disable interrupts
        sei

	; Init Stack       
        ldhx    #XRAM_END
        txs

Stack
	; Multi Purpose Clock Generator init
        jsr     MCG_Init

	; Clear RAM variables
        clr     nosysinfo
        clr     checksum
        clr     dump_addr
        clr     dump_addr+1
        clr     diag_sa
        clr     fpavail

	; LED Init
        jsr     LED_Off

	; PCB specific initialization (if needed, like LED init or intro on LCD display.) 
        ldhx    PCBINITADDR
        cphx    #$FFFF
        beq     pcb_noinit       ; Do not call if no valid address is available 
        jsr     ,x
pcb_noinit

        ; Memory write init
        jsr     MEM_Init
        
	; Time related inits
        jsr     RTC_Init
        
	; SCI module init
        jsr     SCI_Init
        lda     BLCR            ; BootLoader Configuration Register
        and     #BLCR_EW_       ; Check if welcome is enabled
        beq     no_welcome      ; if not enabled, do not print welcome string
        ldhx    #welcome
        jsr     SCI_puts
        ldhx    #BL_VERSION
        jsr     SCI_puts
        ldhx    #wstrid
        jsr     SCI_puts
        lda     ECUID
        jsr     SCI_putb
        lda     #NL
        jsr     SCI_putc
no_welcome
        
	; CAN module init
        jsr     CAN_Init
        
	; Terminal init on SCI
        lda     BLCR            ; BootLoader Configuration Register
        and     #BLCR_ET_       ; Check if terminal is enabled
        beq     no_terminal     ; if not enabled, do not init terminal
        jsr     TERM_Init
no_terminal

        bra     main_time       ; jump to wait a bit for download attempt
; Call of application software
application

        jsr     LED_Off

        ; Check APPADDRESS, if here data is not $FFFF there is application software to call
        ;  Do not forget: Bootloader can download standalone software, where the start address
        ;  is allocated to vector Vreset. The bootloader will move start address from Vreset
        ;  to APPADDRESS, and keep bootloader start address in Vreset.
        ldhx    APPADDRESS
        cphx    #$FFFF        
        bne     issys		;there is application software

; Here comes if there is no application software
nosys
        ; Print "no sys" info only once (first time)
        tst     nosysinfo	; if "no sys" info was already printed
        bne     main_time	; do not write it again
        inc     nosysinfo	; set flag to not print "no sys" info again

        ; Print "no sys" info
        ldhx    #nsstr
        jsr     SCI_puts 

        ; Stay in bootloader further
        bra     main_time

; There is application software, jump to there
issys
	; Print "is sys" info
        lda     BLCR            ; BootLoader Configuration Register
        and     #BLCR_EW_       ; Check if welcome is enabled
        beq     no_sysstr       ; if not enabled, do not print application starting string
        ldhx    #sysstr
        jsr     SCI_puts 
no_sysstr

        ; Clear RAM and XRAM - except MEM_inRAM in range $1000-$107F - for application software
        ldhx    #RAM
issys_clrloop 
        clr     ,x
        aix     #1
        cphx    #XRAM_END
        blo     issys_clrloop
         
        ; Deinit used periferials and modules. MCG remains initialized.
        jsr     RTC_Deinit
        jsr     CAN_Deinit
        jsr     SCI_Deinit

	; Init Stack for application to $1000       
        ldhx    #XRAM_END
        txs

	; Load start addess of application software, and jump to there
        ldhx    APPADDRESS
        jmp     ,x

; -----------------------------------------------------------------------------------------
; Here start the main loop
; -----------------------------------------------------------------------------------------
main_time
        @tim			; Pull up timer to wait communication attempt
        bsr     LED_On

main_loop
        jsr     RTC_Handle
        ; check communication attempt on CAN
        lda     CANRFLG
        and     #CAN_RXF_
        beq     can_nothing
        jsr     CAN_RxHandler   ; Process received CAN message
        bra     main_time       ; Loop with pull up timer to keep CAN frames the execution in  bootloader 
can_nothing 
        ; check communication attempt on UART
	brclr	RDRF.,SCI1S1,sci_nothing ; no received byte
        lda     SCI1D
        cmp     #$1C
        jeq     serialtask      ; If frame first byte received, jump to process frame
        cmp     #'t'
        jeq     terminal        ; Jump to terminal, it will jump back to main_loop
sci_nothing
        ; Check time
        tst     comtimer
        beq     application     ;If time spent, call application software
        bra     main_loop       ;If time not yet spent, wait further





addcs   add     checksum
        sta     checksum
        rts

nvm_doit
        tst     fpavail         ; Check if fingerprint was written already
        bne     nvm_doit_fpok   ; If yes, jump
        lda     #$0F            ; If not, error code of missing fingerprint
        rts        
nvm_doit_fpok
        ; Write data into non-volatile memory 
        ; Source address
        ldhx    #wr_data
        pshhx
        ; Target MEM address
        ldhx    dump_addr
        pshhx
        ; Length of data
        ldx     wr_datat
        pshx                    ; lo
        clrh
        pshh                    ; hi
        jsr     MEM_doit        ; call
        ais     #6              ; release 6 byte parameters
        rts                     ; error code of MEM_doit in A

LED_On
        psha
        ldhx    LEDONADDR
        cphx    #$FFFF
        beq     led_noon       ; Do not call if no valid address is available 
        jsr     ,x
led_noon
        pula
        rts

LED_Off
        psha
        ldhx    LEDOFFADDR
        cphx    #$FFFF
        beq     led_nooff      ; Do not call if no valid address is available 
        jsr     ,x
led_nooff
        pula
        rts


bl_end_addr     equ     $
bl_remaining    equ     $FCF0-1-bl_end_addr
#if bl_remaining < 128
  #Warning  Bootloader code: {bl_start_addr(h)} - {bl_end_addr(h)}. Remaining code size till $FCF0 is {bl_remaining(0)} bytes
#endif

; Fingerprint: 6 received bytes + 1 byte update counter + 1 byte validity constant
        org     FINGERPR
        dw      $FFFF,$FFFF,$FFFF       ; Default empty
        dw      $FFAA           ; Was not yet updated

; Bootloader version and build date, in format to be easy to read in S19 and hex memory dump
        org     ECUID
        db      $0E             ; Default ECUID
        db      $FF             ; Counter how many time ID was changed. 0xFF=Was not yet updated. Incremented by this bootloader.  

; Bootloader version string. 7 characters reserved plus string terminator zero
        org     BL_VERSION
blverstart
        db      "V0.00",0
blverlen        equ     $-blverstart
#if 8 < blverlen
  #Error Bootloader version string is too long: {blverlen(0)}
#endif

; Hardware serial number (6 bytes + 0xAA as validity check)
;  I prefer bootloader compile date in bcd format
;  bash/bat file shall ensure always call compiler before download
        org     SERIAL_NUMBER
        db      ${:year-2000}
        db      ${:month}
        db      ${:date}
        db      ${:hour}
        db      ${:min}
        db      ${:sec}
        db      $55,$AA

        #ROM
        org     Vreset
        dw      entry

