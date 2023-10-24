; =============================================================================
; Real-Time Counter (S08RTCV1)
; This is periodic timer. (Like PIT in AZ60, TBM in GZ60 in the past) 
; =============================================================================

        #RAM

comtimer        ds      1       ; timeout timer for serial UART communication

        #ROM
;-----------------------------------------
; MAKROS
;-----------------------------------------
tim     macro  
        mov     #SHORTWAIT,comtimer     ; 32.768 ms per increment
        endm

; ------------------------------------------------------------------------------
; Set up 32ms periodic event.
RTC_Init
        ; Select 1kHz low power oscillator (RTCLKS = 0)
        ; Do not use interrupt (RTIE = 0)
        ; RTCPS = 2d (means 2^5 -> 1kHz/32 = 31.25Hz)
        mov     #2,RTCSC
        ; RTCMOD = 0d (31.25Hz/1 = 31.25Hz -> 32ms)
        clr     RTCMOD
        clr     comtimer
        rts

RTC_Deinit
        clr     RTCSC
        rts

; Scheduled decrement of timer, does not damage any register
RTC_Handle
        jsr     KickCop
        brclr   7,RTCSC,RTCH_v
        
        ;Here is the time!
        tst     comtimer
        beq     RTCH_1
        dec     comtimer
RTCH_1
        ;Clear timer flag
        bset    7,RTCSC
RTCH_v
        tst     comtimer        ; Leave timer running or not in A
        rts

