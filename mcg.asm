; =============================================================================
; Multi-Purpose Clock Generator (S08MCGV1) for MC9S08DZ60
; =============================================================================


; ===================== Sub-Routines ==========================================
#ROM
; ------------------------------------------------------------------------------
; Using DZ60, the function will switch to PEE Mode (based on AN3499)
;  Fext = 4MHz (crystal)
;  Fmcgout = ((Fext/R)*M/B) - for PEE mode
;  Fbus = Fmcgout/2
MCG_Init
        ; -- First, FEI must transition to FBE mode. MCGC2 should be configured to utilize the
        ;  external reference clock. This is achieved by setting the RANGE for high frequency range
        ;  (4 MHz crystal), EREFS to select external oscillator, and ERCLKEN to initalize the oscillator

        ; MCG Control Register 2 (MCGC2)
        ;  BDIV = 00 - Set clock to divide by 1
        ;  RANGE_SEL = 1 - High Freq range selected (1 MHz to 16 MHz is high freq range)
        ;  HGO = 1 - Ext Osc configured for high gain
        ;  LP = 0 - FLL or PLL is not disabled in bypass modes
        ;  EREFS = 1 - Oscillator requested
        ;  ERCLKEN = 1 - MCGERCLK active
        ;  EREFSTEN = 0 - Ext Reference clock is disabled in stop
        mov     #RANGE_SEL_|EREFS_|ERCLKEN_,MCGC2 ; HGO_|

        ; It is important to wait for OCSINIT in the MCGSC register to be set to indicate that the oscillator
        ; has been initialized
        ; Loop until OSCINIT = 1 - indicates crystal selected by EREFS bit has been initalised
imcg1
        brclr   OSCINIT.,MCGSC,imcg1

        ; To complete the transition to FBE mode, the appropriate bits in MCGC1 should be set. The external
        ; reference clock should be selected as the system clock source using the CLKS bits. The external
        ; reference clock should be selected as the FLL reference clock via the IREFS bit. The reference
        ; divider (RDIV) bits should be configured so that the FLL reference clock is between the required
        ; range of 31.25 – 39.0625 kHz.

        ; MCG Control Register 1 (MCGC1)
        ;  CLKSx    = 10    Select Ext reference clk as clock source 
        ;  RDIVx    = 111   Set to divide by 128 (i.e. 4MHz/128 = 31.25kHz - in range required by FLL)
        ;  IREFS    = 0     Ext Ref clock selected
        ;  IRCLKEN  = 0     MCGIRCLK inactive
        ;  IREFSTEN = 0     Internal ref clock disabled in stop  
        mov     #CLKS1_|RDIV2_|RDIV1_|RDIV0_,MCGC1

        ; Again, wait for the clock mode status (CLKST) and internal reference status (IREFST) bits to
        ; update. Both bits should indicate the external reference clock is being used. The MCG should now
        ; be running in FBE mode.
        ; Loop until IREFST = 0 - indicates ext ref is current source
imcg2
        brset  IREFST.,MCGSC,imcg2

        ; Loop until CLKST = 10 - indiates ext ref clk selected to feed MCGOUT
imcg3
        lda     MCGSC
        and     #CLKST1_|CLKST0_        ; mask CLKST bits
        cmp     #CLKST1_
        bne     imcg3

        ; -- Next FBE must transition to PBE mode
        ; MCGC1's RDIV bits must be set appropriately so that
        ; the PLL uses a reference clock in the range of 1 – 2 MHz.

        ; MCG Control Register 1 (MCGC1)
        ;  CLKSx    = 10    Select Ext reference clk as clock source 
        ;  RDIVx    = 001   Set to divide by 2 (i.e. 4MHz/2 = 2 MHz - in range required by FLL)
        ;  IREFS    = 0     Ext Ref clock selected
        ;  IRCLKEN  = 0     MCGIRCLK inactive
        ;  IREFSTEN = 0     Internal ref clock disabled in stop  
        mov     #CLKS1_|RDIV0_,MCGC1

        ; To enter PBE mode, the FLL must be disabled and PLL enabled by setting the PLLS bit in
        ; MCGC3. As the intention is to migrate to PEE mode it is convenient to set the VDIV multiplier, to
        ; the appropriate value, at this point.
        ;       0001 Encoding 1 — Multiply by 4.
        ;       0010 Encoding 2 — Multiply by 8.
        ;       0011 Encoding 3 — Multiply by 12.
        ;       0100 Encoding 4 — Multiply by 16.
        ;       0101 Encoding 5 — Multiply by 20.
        ;       0110 Encoding 6 — Multiply by 24.
        ;       0111 Encoding 7 — Multiply by 28.
        ;       1000 Encoding 8 — Multiply by 32.
        ;       1001 Encoding 9 — Multiply by 36.
        ;       1010 Encoding 10 — Multiply by 40.

        ; MCG Control Register 3 (MCGC3)
        ;  LOLIE = 0    No request on loss of lock
        ;  PLLS  = 1    PLL selected
        ;  CME   = 0    Clock monitor is disabled
        ;  VDIV  = 0100 Set to multiply by 16 (2Mhz ref x 16 = 32MHz)
        mov     #PLLS_|4,MCGC3

        ; Confirmation that the MCG is in PBE mode is achieved by waiting on the PLLST bit of the
        ; MCGSC register to become set.
        ; Loop until PLLST = 1 - indicates current source for PLLS is PLL
imcg4
        brclr   PLLST.,MCGSC,imcg4

        ; To achieve PEE mode, wait until the LOCK status bit in MCGSC is set indicating the PLL is at its
        ; target frequency. 
        ; Loop until LOCK = 1 - indicates PLL has aquired lock
imcg5
        brclr   LOCK.,MCGSC,imcg5

        ; -- Last, PBE mode transitions into PEE mode

        ; Now, configure the CLKS bits in MCGC1 to select the output of the PLL as the
        ; system clock source.

        ; MCG Control Register 1 (MCGC1)
        ;  CLKS     = 00    Select PLL clock source 
        ;  Keep other bits 
        bclr    CLKS0.,MCGC1
        bclr    CLKS1.,MCGC1

        ; Finally, wait for CLKST bits of MCGSC to indicate the PLL output is the system clock source. The
        ; MCG is now configured in PEE mode.
        ; Loop until CLKST = 11 - PLL O/P selected to feed MCGOUT in current clk mode
imcg6  
        brclr   CLKST1.,MCGSC,imcg6
        brclr   CLKST0.,MCGSC,imcg6

        ; ABOVE CODE ALLOWS ENTRY FROM PBE TO PEE MODE

        ; Since RDIV = 2, VDIV = 16, BDIV = 1
        ; Now
        ;  Fmcgout = ((Fext/R)*M/B) - for PEE mode
        ;  Fmcgout = ((4MHz/2)*16)/1 = 32MHz
        ;  Fbus = Fmcgout/2 = 16MHz

        ; Enable Fbus/2 on PTA0 (6Mhz)
        ;lda     SOPT2
        ;ora     #$81
        ;sta     SOPT2

        rts




