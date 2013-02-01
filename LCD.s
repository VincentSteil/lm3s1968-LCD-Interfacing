; LCD.s
; Runs on LM3S1968
; EE319K lab 6 device driver for the LCD
; Valvano
; June 26, 2012
;
; Vincent Steil
;
;  size is 1*16
;  because we do not need to read busy, then we will tie R/W=ground
;  10k potentiometer 
;      one end of pot is +5V, 
;      center of pot to pin 3 of LCD,
;      other end of pot is ground
;  ground = pin 1    Vss
;  power  = pin 2    Vdd   +5V (EE319K LCDs)
;  pot    = pin 3    Vlc   connected to center of pot
;  PF4    = pin 4    RS    (1 for data, 0 for control/status)
;  ground = pin 5    R/W   (1 for read, 0 for write)
;  PF5    = pin 6    E     (enable)
;  PF0    = pin 11   DB4   (4-bit data)
;  PF1    = pin 12   DB5
;  PF2    = pin 13   DB6
;  PF3    = pin 14   DB7
;16 characters are configured as 2 rows of 8
;addr  00 01 02 03 04 05 06 07 40 41 42 43 44 45 46 47

        IMPORT  SysTick_Init
        IMPORT  SysTick_Wait
        IMPORT  SysTick_Wait10ms

        EXPORT   LCD_Open
        EXPORT   LCD_Clear
        EXPORT   LCD_OutChar
        EXPORT   LCD_GoTo
        EXPORT   LCD_OutString
        EXPORT   LCD_OutChar
        EXPORT   LCD_OutDec
        EXPORT   LCD_OutFix
SYSCTL_RCGC2_R          EQU 0x400FE108
SYSCTL_RCGC2_GPIOE      EQU 0x00000010   ; port E Clock Gating Control
SYSCTL_RCGC2_GPIOF      EQU 0x00000020   ; port F Clock Gating Control
SYSCTL_RCGC2_GPIOG      EQU 0x00000040   ; port G Clock Gating Control
NVIC_ST_CURRENT_R       EQU 0xE000E018
GPIO_PORTE_DATA_R       EQU 0x400243FC
GPIO_PORTE_DIR_R        EQU 0x40024400
GPIO_PORTE_IS_R         EQU 0x40024404
GPIO_PORTE_IBE_R        EQU 0x40024408
GPIO_PORTE_IEV_R        EQU 0x4002440C
GPIO_PORTE_IM_R         EQU 0x40024410
GPIO_PORTE_RIS_R        EQU 0x40024414
GPIO_PORTE_MIS_R        EQU 0x40024418
GPIO_PORTE_ICR_R        EQU 0x4002441C
GPIO_PORTE_AFSEL_R      EQU 0x40024420
GPIO_PORTE_DR2R_R       EQU 0x40024500
GPIO_PORTE_DR4R_R       EQU 0x40024504
GPIO_PORTE_DR8R_R       EQU 0x40024508
GPIO_PORTE_ODR_R        EQU 0x4002450C
GPIO_PORTE_PUR_R        EQU 0x40024510
GPIO_PORTE_PDR_R        EQU 0x40024514
GPIO_PORTE_SLR_R        EQU 0x40024518
GPIO_PORTE_DEN_R        EQU 0x4002451C
GPIO_PORTF_DATA_R		EQU 0x400253FC
GPIO_PORTF_DIR_R		EQU 0x40025400
GPIO_PORTF_AFSEL_R		EQU 0x40025420
GPIO_PORTF_DEN_R		EQU 0x4002551C
PG2                     EQU 0x40026010
GPIO_PORTG_DATA_R       EQU 0x400263FC
GPIO_PORTG_DIR_R        EQU 0x40026400
GPIO_PORTG_AFSEL_R      EQU 0x40026420
GPIO_PORTG_DEN_R        EQU 0x4002651C
      AREA    |.text|, CODE, READONLY, ALIGN=2
      THUMB
      ALIGN          

;--------------- wait --------------------------
; waits for the specified amount of time
; t = ~R0*4/50 us
; Input: R0 
; Output: none
wait
	  PUSH {LR}
waitloop	  
	  SUBS R0, R0, #0x01
	  BNE waitloop
	  POP {PC}
;--------------- outCsrNibble ------------------
; sends 4 bits to the LCD control/status
; Input: R0 is 4-bit command, in bit positions 3,2,1,0 of R0
; Output: none
; PF4 = RS
; PF5 = E
OutCsrNibble
      PUSH {R0,R1,R2,R4,R5,R14}
	  
	  MOV R3, R0
	  LDR R1, =GPIO_PORTF_DATA_R
	  MOV R2, #0x00		; Set E and RS to low
	  STR R2, [R1]		; make the changes		STEP 1
	  AND R3, R3, #0x0F	; set DB 7-4								
	  STR R3, [R1]		; 						STEP 2
	  MOV R0, #75		; wait 6us
	  BL wait
	  ORR R3, R3, #0x20	; set E high					
	  STR R3, [R1]		;						STEP 3
	  MOV R0, #75		; wait 6us
	  BL wait
	  AND R3, R3, #0x0F	; set E low				
	  STR R3, [R1] 		; 						STEP 4
	  MOV R0, #75		; wait 6us
	  BL wait	  		

      POP {R0,R1,R2,R4,R5,PC}



;---------------------outCsr---------------------
; sends one command code to the LCD control/status
; Input: R0 is 8-bit command to execute
; Output: none
;* Entry Mode Set 0,0,0,0,0,1,I/D,S
;*     I/D=1 for increment cursor move direction
;*        =0 for decrement cursor move direction
;*     S  =1 for display shift
;*        =0 for no display shift
;*   Display On/Off Control 0,0,0,0,1,D,C,B
;*     D  =1 for display on
;*        =0 for display off
;*     C  =1 for cursor on
;*        =0 for cursor off
;*     B  =1 for blink of cursor position character
;*        =0 for no blink
;*   Cursor/Display Shift  0,0,0,1,S/C,R/L,*,*
;*     S/C=1 for display shift
;*        =0 for cursor movement
;*     R/L=1 for shift to left
;*        =0 for shift to right
;*   Function Set   0,0,1,DL,N,F,*,*
;*     DL=1 for 8 bit
;*       =0 for 4 bit
;*     N =1 for 2 lines
;*       =0 for 1 line
;*     F =1 for 5 by 10 dots
;*       =0 for 5 by 7 dots 
OutCsr
    PUSH {R0,R1,R2,R3,R4,LR}
	
	MOV R1, R0					; copy R0 into R1 for later use
	LSR R0, R0, #4				; get bits 4-7 of the input
	BL OutCsrNibble				
	MOV R0, R1					; get back the original input
	AND R0, R0, #0xF				; mask the 4 lsb of the input
	BL OutCsrNibble		
	MOV R0, #1125					
	BL wait

	POP  {R0,R1,R2,R3,R4,PC}

;---------------------LCD_Open---------------------
; initialize the LCD display, called once at beginning
; Input: none
; Output: none
; Registers modified: R0,R1,R2
LCD_Open 
    PUSH {R0,R1,R2,R3,LR}
	
	LDR R1, =SYSCTL_RCGC2_R         ; R1 = &SYSCTL_RCGC2_R
    LDR R0, [R1]                    ; R0 = [R1]
    ORR R0, R0, #SYSCTL_RCGC2_GPIOF ; R0 = R0|SYSCTL_RCGC2_GPIOF
    STR R0, [R1]                    ; [R1] = R0
    NOP
    NOP                             ; allow time to finish activating
    ; regular port function
    LDR R1, =GPIO_PORTF_AFSEL_R     ; R1 = &GPIO_PORTG_AFSEL_R
    LDR R0, [R1]                    ; R0 = [R1]
    BIC R0, R0, #0x3F               ; R0 = R0&~0x04 (disable alt funct on PG2) (default setting)
    STR R0, [R1]                    ; [R1] = R0
    ; enable digital port
    LDR R1, =GPIO_PORTF_DEN_R       ; R1 = &GPIO_PORTG_DEN_R
    LDR R0, [R1]                    ; R0 = [R1]
    ORR R0, R0, #0x3F               ; R0 = R0|0x04 (enable digital I/O on PG2) (default setting on LM3S811, not default on other microcontrollers)
    STR R0, [R1]                    ; [R1] = R0
	
	MOV R0, #0x3D000			; wait 20ms
	BL wait
	LDR R2, =GPIO_PORTF_DIR_R	; all pins output
	LDR R3, [R2]				
	ORR R3, R3, #0xFF
	STR R3, [R2]
	MOV R0, #0x03				; OutCsrNibble(0x03)
	BL  OutCsrNibble
	MOV R0, #0xF400			    ; ~wait 5ms
	BL wait
	MOV R0, #0x03
	BL OutCsrNibble				; OutCsrNibble(0x03)
	MOV R0, #1250				; wait 100us
	BL wait
	MOV R0, #0x03
	BL OutCsrNibble				; OutCsrNibble(0x03)
	MOV R0, #1250				; wait 100us
	BL wait
	MOV R0, #0x02
	BL OutCsrNibble				; OutCsrNibble(0x02)
	MOV R0, #1250				; wait 100us
	BL wait	
	MOV R0, #0x28				
	BL OutCsr					; OutCsr(0x28)	
	MOV R0, #0x14				
	BL OutCsr					; OutCsr(0x14)
	MOV R0, #0x06	
	BL OutCsr					; OutCsr(0x06)
	MOV R0, #0x0C
	BL OutCsr					; OutCsr(0x0C)

	POP {R0,R1,R2,R3,PC}


;---------------------LCD_OutChar---------------------
; sends one ASCII to the LCD display
; Input: R0 (call by value) letter is 8-bit ASCII code
; Outputs: none
; Registers modified: CCR
LCD_OutChar
   PUSH {R0,R1,R2,R3,R4,LR}

	  MOV R3, R0
	  MOV R4, R0
	  LDR R1, =GPIO_PORTF_DATA_R
	  MOV R2, #0x10		; Set E low and RS high
	  STR R2, [R1]		; make the changes		STEP 1
	  AND R3, R3, #0xF0	; set DB 7-4
	  LSR R3, R3, #4	; shift msb into lsb
	  STR R3, [R1]		; 						STEP 2
	  MOV R0, #75		; wait 6us
	  BL wait
	  ORR R3, R3, #0x30	; set E high					
	  STR R3, [R1]		;						STEP 3
	  MOV R0, #75		; wait 6us
	  BL wait
	  AND R3, R3, #0x1F	; set E low				
	  STR R3, [R1] 		; 						STEP 4
	  MOV R0, #75		; wait 6us
	  BL wait
	  	  
	  MOV R2, #0x10		; Set E low and RS high
	  STR R2, [R1]		; make the changes		STEP 1
	  AND R4, R4, #0x1F	; set DB 7-4								
	  STR R4, [R1]		; 						STEP 2
	  MOV R0, #75		; wait 6us
	  BL wait
	  ORR R4, R4, #0x30	; set E high					
	  STR R4, [R1]		;						STEP 3
	  MOV R0, #75		; wait 6us
	  BL wait
	  AND R4, R4, #0x1F	; set E low				
	  STR R4, [R1] 		; 						STEP 4
	 
	  MOV R0, #1125					;wait 90us				
	  BL wait

   POP {R0,R1,R2,R3,R4,PC}

;---------------------LCD_Clear---------------------
; clear the LCD display, send cursor to home
; Input: none
; Outputs: none
; Registers modified: CCR
LCD_Clear
    PUSH {R0,R1,LR}    

	MOV R0, #0x01
	BL OutCsr
	MOV R0, #20500		;wait ~1.64ms
	BL wait
	MOV R0, #0x02
	BL OutCsr
	MOV R0, #20500		; wait ~1.64
	BL wait	
	
    POP  {R0,R1,PC}


;-----------------------LCD_GoTo-----------------------
; Move cursor (set display address) 
; Input: R0 is display address is 0 to 7, or $40 to $47 
; Output: none
; errors: it will check for legal address
;  0) save any registers that will be destroyed by pushing on the stack
;  1) go to step 3 if DDaddr is $08 to $3F or $48 to $FF
;  2) outCsr(DDaddr+$80)     
;  3) restore the registers by pulling off the stack
LCD_GoTo
		PUSH {R0,LR}
		CMP R0, #0x40
		BMI	cm
		CMP R0, #0x49
		BPL error
		B check
cm		CMP R0, #0x08
		BPL error
check	
		ADD R0, R0, #0x80
		BL OutCsr
		POP {R0, PC}
error	POP  {R0,PC}

; ---------------------LCD_OutString-------------
; Output character string to LCD display, terminated by a NULL(0)
; Inputs:  R0 (call by reference) points to a string of ASCII characters 
; Outputs: none
; Registers modified: CCR
LCD_OutString
		PUSH {R0,R1,R2,R4,LR} 
		MOV R2, R0				;make a copy of R0
loop	LDR R0, [R2]
		AND R0, R0, #0xFF		; mask the correct bytes
		CMP R0, #0				; terminate loop on null
		BEQ	done
		BL	LCD_OutChar			; output the char
		ADD R2, R2,#1			; increment the array position
		B	loop
done   POP {R0,R1,R2,R4,PC}



;-----------------------LCD_OutDec-----------------------
; Output a 32-bit number in unsigned decimal format
; Input: R0 (call by value) 32-bit unsigned number 
; Output: none
; Registers modified: R1 
LCD_OutDec
		PUSH {R0,R4,LR}
;		MOV R1, #0
;loopod	MOV R2, #10
;		UDIV R2, R0, R2
;		CMP R2, #0
;		BEQ	doneod
;		PUSH {R0}
;		ADD R1, R1, #1
;		LDR R0, [R2]
;		B loopod
;doneod	ADD R0, R0, #0x30
;		BL LCD_OutChar
;loopod1 CMP R1, #0
;		B doneod1
;		POP {R0}
;		ADD R0, R0, #0x30
;		BL LCD_OutChar
;		SUB R1, R1, #1
;		B loopod1
;doneod1 LDR R0, R0, #20
		CMP R0, #10			; char <10?
		BLO ODend			; break if so
		MOV R2, #10			; R2 = divisor
		UDIV R3, R0, R2		; R3 = N/10
		MUL R1, R3, R2		; R1 = N/10*10
		SUB R1, R0, R1		; R1 = N%10
		PUSH {R1}			; store the value on the stack
		MOVS R0, R3			; N = N/10
		BL LCD_OutDec		; LCD_OutDec(N/10)
		POP {R0}			; restore R0
ODend
		ADD R0, R0, #'0'	; turn into ASCII
		BL LCD_OutChar		; print R0
		POP  {R0,R4,PC}


; -----------------------LCD _OutFix----------------------
; Output characters to LCD display in fixed-point format
; unsigned decimal, resolution 0.001, range 0.000 to 9.999 
; Inputs:  R0 is an unsigned 16-bit number
; Outputs: none
; Registers modified: R0,R1,R2,R3
; E.g., R0=0,    then output "0.000 " 
;       R0=3,    then output "0.003 " 
;       R0=89,   then output "0.089 " 
;       R0=123,  then output "0.123 " 
;       R0=9999, then output "9.999 " 
;       R0>9999, then output "*.*** "

LCD_OutFix
         PUSH {R0,R1,R2,R3,LR}
		 MOV R2, R0
		 SUB R2, R2, #3000
		 SUB R2, R2, #3000
		 SUBS R2, R2, #4000
		 BGE OutFixTooLarge
		 
		 MOV R2, #10			; R2 = divisor
		 
		 UDIV R3, R0, R2		; R3 = N/10
		 MUL R1, R3, R2			; R1 = N/10*10
		 SUB R1, R0, R1			; R1 = N%10
		 PUSH {R1}				; save the thousandths digit
		 MOV R0, R3				; N = N/10
		 
		 UDIV R3, R0, R2		; R3 = N/10
		 MUL R1, R3, R2			; R1 = N/10*10
		 SUB R1, R0, R1			; R1 = N%10
		 PUSH {R1}				; save the hundredths digit
		 MOV R0, R3				; N = N/10
         
		 UDIV R3, R0, R2		; R3 = N/10
		 MUL R1, R3, R2			; R1 = N/10*10
		 SUB R1, R0, R1			; R1 = N%10
		 PUSH {R1}				; save the tenths digit
		 MOV R0, R3				; N = N/10
		 
		 UDIV R3, R0, R2		; R3 = N/10
		 MUL R1, R3, R2			; R1 = N/10*10
		 SUB R1, R0, R1			; R1 = N%10
		 PUSH {R1}				; save the digit to the left of the decimal
		 MOV R0, R3				; N = N/10
		 
		 POP {R0}				; get digit to the left of the decimal
		 ADD R0, R0, #'0'		; convert digit to ASCII
		 BL LCD_OutChar			; print digit to the left of the decimal
		 
		 MOV R0, #'.'			; get . ASCII code
		 BL LCD_OutChar			; print .
		 
		 POP {R0}				; get tenths digit
		 ADD R0, R0, #'0'		; convert to ASCII
		 BL LCD_OutChar			; print tenths digit
		 
		 POP {R0}				; get hundredths digit
		 ADD R0, R0, #'0'		; convert to ASCII
		 BL LCD_OutChar			; print hundredths
		 
		 POP {R0}				; get thousandths digit
		 ADD R0, R0, #'0'		; convert to ASCII
		 BL LCD_OutChar			; print thousandths digit
		 
		 POP {R0, R1, R2, R3, PC}
		 
OutFixTooLarge 					; print *.*** 

		 MOV R0, #'*'
		 BL LCD_OutChar			; print *
		 MOV R0, #'.'		
		 BL LCD_OutChar			; print .	
		 MOV R0, #'*'			
		 BL LCD_OutChar			; print *
		 BL LCD_OutChar			; print *	
		 BL LCD_OutChar			; print *
		 
		 POP {R0, R1, R2, R3, PC}

    ALIGN                           ; make sure the end of this section is aligned
    END                             ; end of file