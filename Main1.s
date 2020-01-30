@Katie Loseke
@ECE372
@Design Project 1
@This program sends a testing message to be read by the 'talker' when the button is pushed


.text
.global _start
.global INT_DIRECTOR
_start:
.equ 	TIMING, 0x001FFFFF		@Setting up constant for timer loop

	LDR R13, =STACK1			@At base of main stack
	ADD R13, R13, #0x1000		@Set pointer to top of stack
	CPS #0x12					@Switch to IRQ mode
	LDR R13, =STACK2			@At base of IRQ stack
	ADD R13, R13, #0x1000		@Set pointer to top of stack
	CPS #0x13					@Back in SVC mode
	
	LDR R9, =0x02				@Turning on GPIO1 CLK
	LDR R10, =0x44E000AC
	STR R9, [R10]
	
@Getting the interrupt for button presses set up
	LDR R1, =0x4804C14C			@Address of GPIO1_FALLINGDETECT register
	MOV R2, #0x20000000			@Mask for bit 29
	LDR R3, [R1]				@Read fall detect register
	ORR R3, R3, R2				@Set bit 29
	STR R3, [R1]				@Write back
	
	LDR R1, =0x4804C034			@Address of GPIO1_IRQSTATUS_SET_0 register
	STR R2, [R1]				@Enable bit 29 request on POINTRPEND1
	
@Setting up UART interrupt
	LDR R1, =0x48200000			@Base address for INTC
	MOV R2, #0x2				@Value to reset INTC
	STR R2, [R1, #0x10]			@Write to INTC Config Register
	MOV R2, #0x00004000			@Unmask UART5
	STR R2, [R1, #0xB4]			@Write to INTC_MIR_CLEAR1 register
	MOV R2, #0x4				@Unmask INTC INT 98, GPIOINTA
	STR R2, [R1, #0xE8]			@Write to INTC_MIR_CLEAR3 register
	
@Set mode for MUX  ***
	LDR R1, =0x44E10000			@Base for control module
	MOV R2, #0x4				@Mode 4
	STR R2, [R1, #0x8C0]		@TxD
	STR R2, [R1, #0x8C4]		@RxD
	MOV R2, #0x6				@Mode 6
	STR R2, [R1, #0x8D8]		@CTSN
	STR R2, [R1, #0x8DC]		@RTSN
	
@Turn on UART5 CLK
	MOV R2, #0x2				@Enable UART5 CLK
	LDR R1, =0x44E00038			@Address of CM_PER_UART5_CLKCTRL
	STR R2, [R1]				@Turn on UART5
	
@

@Processor IRQ enabled in CPSR
	MRS R3, CPSR				@Copy CPSR to R3
	BIC R3, #0x80				@Clear bit 7
	MSR CPSR_c, R3				@Write back to CPSR
	LDR R0, =0x00000000			@Sets state for IRQ purposes to 0

@Keep off if holding but don't keep turning off if not
HOLDOFF:
	LDR R5, =0x01E00000			@Mask to turn all LEDs off
	LDR R3, =0x4804C190			@Address of clear data
	STR R5, [R3]				@Set all LEDs to OFF (logic 0)	
	
@Turning first bits on
SWITCHER:
	LDR R5, =0x01E00000			@Mask to turn all LEDs off
	LDR R3, =0x4804C190			@Address of clear data
	LDR R6, =0x4804C194			@Address of set data out
	STR R5, [R3]				@Set all LEDs to OFF (logic 0)
	TST R0, #0x1				@Test first bit
	BNE SWITCHING				@State 1, go to switching lights
	BEQ HOLDOFF				@State 0, go to hold
	
SWITCHING:
@	STR R5, [R3]				@Set all LEDs to OFF (logic 0)
	TST R0, #0x2				@Test second bit
	BNE NEXTSET					@State 1, go to second set of lights
	BEQ FIRSTSET				@State 0, go to first set of lights
FIRSTSET:
	STR R7, [R6]				@Turn on LEDs 0 and 3
	B SWITCHER					@Loop until inetrrupt

NEXTSET:
	STR R8, [R6]				@Turn on LEDs 1 and 2
	B SWITCHER					@Loop until interrupt
	
INT_DIRECTOR:
	STMFD SP!, {R3-R8, LR}		@Push main registers to stack
@See if not user interrupt, if so go back
	LDR R3, =0x482000F8			@Address of INTC-PENDING_IRQ3 register
	LDR R1, [R3]				@Read that register
	TST R1, #0x00000004			@Test bit 2
@	BEQ PASS_ON					@Not button, go back
	BEQ TCHK					@Not button, check timer7
	
	LDR R3, =0x4804C02C			@Load GPIO1_IRQSTATUS_0 register
	LDR R1, [R3]				@Read status register
	TST R1, #0x20000000			@Check if bit 29 = 1
	BNE BUTTON_SVC				@IF bit 29 = 1 then button pushed
@	BEQ PASS_ON					@Otherwise, go back
	LDR R3, =0x48200048			@No button, then go back
	MOV R1, #0x1					@Value to clear bit 0 of INTC_CONTROL
	STR R1, [R0]				@Write it
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Back to mainline
	
TCHK:
	LDR R1, =0x482000D8			@Address of INTC PENDING_1RQ2 register
	LDR R3, [R1]				@Read value
	TST R3, #0x80000000			@Test bit 31 for timer7
	BEQ PASS_ON					@Not CLK, return time
	LDR R1, =0x4804A028			@Address of Timer7 IRQSTATUS register
	LDR R3, [R1]				@Read value
	TST R3, #0x2				@Check bit 1
	BNE SWAPLED					@If overflow, switch LED state
	
PASS_ON:			
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to			
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Go back to loop
				
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Go back to loop

SWAPLED:
@Reset Timer7 IRQ request
	LDR R1, =0x4804A028			@Address of Timer7 IRQSTATUS register
	MOV R2, #0x2				@Value to reset Overflow IRQ request
	STR R2, [R1]				@Write it
	
@Set state
	LDR R1, =0x4804C190			@GPIO1 CLEARDATAOUT
	LDR R5, =0x01E00000			@Mask to turn all LEDs off
	STR R5, [R1]				@Turn all LEDs off
	
	MOV R12, #0x2				@Value to XOR second state bit
	EOR R0, R0, R12				@Switches state by inverting bit
	
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to register
	
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Go back to loop

BUTTON_SVC:
	MOV R1, #0x20000000			@Bit 29 mask
	STR R1, [R3]				@Write to status to turn off interrupt request
	
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to register
	
	LDR R5, =0x4804C190			@Set data out register
	MOV R1, #0x01E00000			@Mask for all LEDs
	STR R1, [R5]				@Turn off all LEDs
	
	MOV R12, #0x1				@Value for XOR to invert
	EOR R0, R0, R12				@Switches state by inverting bit
	
	MOV R2, #0x3				@Value to auto reload timer and start
	LDR R1, =0x4804A038			@Address of Timer7 TCLR register
	STR R2, [R1]				@Write to
	
@Turn off NEWIRQA bit in INTC_CONTROL, so can respond to new IRQ
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to
	
	MOV R2, #0x00040000			@Short timer to hold (about a second)
	
HOLDLOOP:
	NOP							@Hold timer before switching
	SUBS R2, #1
	BNE HOLDLOOP
	
	LDMFD SP!, {R3-R8, LR}
	SUBS PC, LR, #4

.align 2
SYS_IRQ:   .WORD 0				@Location to store systems IRQ address
.data
.align 2
MESSAGE:	.byte 0x0D
.ascii "Testing"
.byte 0x0D
.align 2
CHAR_PTR:	.word MESSAGE		@PTR to next character to send
CHAR_COUNT:	.word 9			@Counter for number of characters to send
STACK1:		.rept 1024			@Main stack
		.word 0x0000
		.endr
STACK2:		.rept 1024			@IRQ stack
		.word 0x0000
		.endr
.END
