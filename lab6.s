; main.s
; Runs on LM3S1968
; Lab 6 Test of LCD driver
; June 26, 2012

;  size is 1*16
;  because we do not need to read busy, then we will tie R/W=ground
;  10k potentiometer (not the slide pot for Lab 8)
;      one end of pot is +5V, 
;      center of pot to pin 3 of LCD,
;      other end of pot is ground
;  ground = pin 1    Vss
;  power  = pin 2    Vdd   +5V (EE319K LCDs)
;  pot    = pin 3    Vlc   connected to center of pot
;         = pin 4    RS    (1 for data, 0 for control/status)
;  ground = pin 5    R/W   (1 for read, 0 for write)
;         = pin 6    E     (enable)
;         = pin 11   DB4   (4-bit data)
;         = pin 12   DB5
;         = pin 13   DB6
;         = pin 14   DB7
;16 characters are configured as 2 rows of 8
;addr  00 01 02 03 04 05 06 07 40 41 42 43 44 45 46 47

      AREA      DATA, ALIGN=2
; Global variables go here

       ALIGN          
       AREA     |.text|, CODE, READONLY, ALIGN=2
       THUMB
       EXPORT   Start
       IMPORT   PLL_Init
       IMPORT   LCD_Open
       IMPORT   LCD_Clear
       IMPORT   LCD_OutChar
       IMPORT   LCD_GoTo
       IMPORT   LCD_OutString
       IMPORT   LCD_OutChar
       IMPORT   LCD_OutDec
       IMPORT   LCD_OutFix
GPIO_PORTG_DATA_R  EQU 0x400263FC
GPIO_PORTG_DIR_R   EQU 0x40026400
GPIO_PORTG_AFSEL_R EQU 0x40026420
GPIO_PORTG_PUR_R   EQU 0x40026510
GPIO_PORTG_DEN_R   EQU 0x4002651C
SYSCTL_RCGC2_R     EQU 0x400FE108
SYSCTL_RCGC2_GPIOG EQU 0x00000040   ; port G Clock Gating Control

Start  BL   PLL_Init    ; running at 50 MHz
       BL   LCD_Open    ; ***Your function that initializes LCD interface
       BL   IO_Init     ; ***Your function that initialize switch and LED
   
run    BL   LCD_Clear     ;***Your function that clears the display
       LDR  R0,=Welcome
       BL   LCD_OutString ;***Your function that outputs a string
       LDR  R4,=TestData
       LDR  R5,=TestEnd
       BL   IO_Touch     ;***Your function that waits for release and touch 
loop   BL   IO_HeartBeat ;***Your function that toggles LED
       BL   LCD_Clear    ;***Your function that clears the display
       LDR  R0, [R4]            
       BL   LCD_OutDec   ;***Your function that outputs an integer
       MOV  R0, #0x40    ;Cursor location of the 8th position
       BL   LCD_GoTo     ;***Your function that moves the cursor
       LDR  R0, [R4],#4           
       BL   LCD_OutFix   ;***Your function that outputs a fixed-point
       BL   IO_Touch     ;***Your function that waits for release and touch 
       CMP  R4, R5
       BNE  loop      
       B    run    
       ALIGN          
Welcome  DCB "Welcome "
         DCB "                                " ;32 spaces
         DCB "to 319K!",0
         ALIGN          
TestData DCD 0,7,34,117,432,543,4789,9999,10000,21896,65535,12345678
TestEnd  DCD 0
         ALIGN                       
         
;------------IO_Touch------------
; wait for release and touch
; Input: none
; Output: none
; Modifies: R0, R1
IO_Touch  
       PUSH  {R4,LR}
IO_TouchLoop	   
	   LDR R0, =GPIO_PORTG_DATA_R
	   LDR R1, [R0]				
	   AND R1, #0x80					; mask bit 7 (switch)
	   CMP R1, #0x00
	   BEQ IO_TouchLoop
	   PUSH {R0}
	   MOV R0, #0x1E000				; wait ~10ms
wait10ms	  
	   SUBS R0, R0, #0x01
	   BNE wait10ms
	   POP {R0}
IO_TouchLoop2
	   LDR R0, =GPIO_PORTG_DATA_R
	   LDR R1, [R0]
	   AND R1, #0x80
	   CMP R1, #0x80
	   BEQ IO_TouchLoop2
       POP  {R4,PC}

;------------IO_HeartBeat------------
; toggles an LED PG2
; Input: none
; Output: none
; Modifies: R0, R1
IO_HeartBeat
	   LDR R0, =GPIO_PORTG_DATA_R
	   LDR R1, [R0]
	   EOR R1, R1, #0x04
	   STR R1, [R0]
       BX   LR

;------------IO_Init------------
; Activate Port and initialize it for switch and LED
; Input: none
; Output: none
; Modifies: R0, R1
IO_Init
    LDR R1, =SYSCTL_RCGC2_R         ; R1 = &SYSCTL_RCGC2_R
    LDR R0, [R1]                    ; R0 = [R1]
    ORR R0, R0, #SYSCTL_RCGC2_GPIOG ; R0 = R0|SYSCTL_RCGC2_GPIOG
    STR R0, [R1]                    ; [R1] = R0
    NOP
    NOP                             ; allow time to finish activating
    ; set direction register
    LDR R1, =GPIO_PORTG_DIR_R       ; R1 = &GPIO_PORTG_DIR_R
    LDR R0, [R1]                    ; R0 = [R1]
    ORR R0, R0, #0x04               ; R0 = R0|0x04 (make PG2 output)
	BIC R0, R0, #0x80               ; PG7 Input
    STR R0, [R1]                    ; [R1] = R0
    ; regular port function
    LDR R1, =GPIO_PORTG_AFSEL_R     ; R1 = &GPIO_PORTG_AFSEL_R
    LDR R0, [R1]                    ; R0 = [R1]
    BIC R0, R0, #0x84               ; R0 = R0&~0x04 (disable alt funct on PG2) (default setting)
    STR R0, [R1]                    ; [R1] = R0
    ; enable digital port
    LDR R1, =GPIO_PORTG_DEN_R       ; R1 = &GPIO_PORTG_DEN_R
    LDR R0, [R1]                    ; R0 = [R1]
    ORR R0, R0, #0x84               ; R0 = R0|0x04 (enable digital I/O on PG2) (default setting on LM3S811, not default on other microcontrollers)
    STR R0, [R1]                    ; [R1] = R0
    BX  LR                          ; return
	
	
    ALIGN
    END                             ; end of file