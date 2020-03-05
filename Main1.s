@Katie Loseke
@ECE372
@Design Project 1
@This program waits for a button input, starts a timer with LED, then on second button push reads off the time on the timer
@and sends it in ascii form to the 'talker' to read back to the user


.text
.global _start
.global INT_DIRECTOR
_start:
@.equ 	MSG_LEN, 37				@Length of message
.equ	CLK_LEN, 14				@Length of clock message

	LDR R13, =STACK1			@At base of main stack
	ADD R13, R13, #0x1000		@Set pointer to top of stack
	CPS #0x12					@Switch to IRQ mode
	LDR R13, =STACK2			@At base of IRQ stack
	ADD R13, R13, #0x1000		@Set pointer to top of stack
	CPS #0x13					@Back in SVC mode
	
	LDR R9, =0x02				@Turning on GPIO1 CLK
	LDR R10, =0x44E000AC
	STR R9, [R10]
	
@Initialize USER LED 0
	LDR R5, =0x00200000			@Mask to turn off USER LED 0 off
	LDR R3, =0x4804C190			@Address to clear data
	LDR R6, =0x4804C194			@Adress to set data out
	STR R5, [R3]				@Turn LED off
	
	LDR R0, =0xFFDFFFFF			@Mask to enable LED 0 output
	LDR R1, =0x4804C134			@GPIO1_OE
	LDR R2, [R1]				@Read register
	AND R2, R2, R0				@Masking
	STR R2, [R1]				@Write masked work back
	
@Getting the interrupt for button presses set up
	LDR R1, =0x4804C14C			@Address of GPIO1_FALLINGDETECT register
	MOV R2, #0x20000000			@Mask for bit 29
	LDR R3, [R1]				@Read fall detect register
	ORR R3, R3, R2				@Set bit 29
	STR R3, [R1]				@Write back
	
	LDR R1, =0x4804C034			@Address of GPIO1_IRQSTATUS_SET_0 register
	STR R2, [R1]				@Enable bit 29 request on POINTRPEND1
	
	LDR R1, =0x482000E8			@Address of INTC_MIR_CLEAR3 register
	MOV R2, #0x04			
	STR R2, [R1]
	
@Setting up UART interrupt
	LDR R1, =0x48200000			@Base address for INTC
@	MOV R2, #0x02				@Value to reset INTC
@	STR R2, [R1, #0x10]			@Write to INTC Config Register
	MOV R2, #0x4000				@Unmask UART5
	STR R2, [R1, #0xA8]			@Write to INTC_MIR_CLEAR1 register
	
@Turn on timer2 CLK
	MOV R2, #0x2				@Value to turn on CLK
	LDR R1, =0x44E00080			@CM_PER_TIMER2_CLKCTRL
	STR R2, [R1]				@Turn on CLK
	LDR R1, =0x44E00508			@Setting CLK
	STR R2, [R1]				@Setting to 32kHz CLK
	
@Initialize timer2
	LDR R1, =0x48040000			@Base address of timer2 registers
	MOV R2, #0x1				@Value to reset Timer 2
	STR R2, [R1, #0x10]			@Write to Timer2 CFG register (timer ignores Debug suspend)
	@Don't need interrupt from timer, just need to start and stop it
	LDR R2, =0x00000000			@Value to set CLK to 0
	STR R2, [R1, #0x3C]			@Setting TCRR/count to 0
	
@Set mode for MUX  ***
	LDR R1, =0x44E10000			@Base for control module
	MOV R2, #0x14				@Mode 4 out
	STRB R2, [R1, #0x8C0]		@TxD
	MOV R2, #0x34				@Mode 4 in
	STRB R2, [R1, #0x8C4]		@RxD
	MOV R2, #0x36				@Mode 6 in
	STRB R2, [R1, #0x8D8]		@CTSN
	MOV R2, #0x16				@Mode 6 out
	STRB R2, [R1, #0x8DC]		@RTSN
	
@Turn on UART5 CLK
	MOV R2, #0x02				@Enable UART5 CLK
	LDR R1, =0x44E00038			@Address of CM_PER_UART5_CLKCTRL
	STR R2, [R1]				@Turn on UART5
	
@Disabling FIFO (Data sheet notes that baud CLK needs to be 0 to set FIFO)
	LDR R1, =0x481AA000			@UART base address
	MOV R2, #0x06				@Bits to disable FIFO
	STRB R2, [R1, #0x08]		@Disabling FIFO
	
@Setting the Baud rate
	LDR R1, =0x481AA000			@UART base address
	MOV R2, #0x83				@Conf mode A set
	STRB R2, [R1, #0x0C]		@Setting to Conf mode A
	
@Setting baud CLK
	MOV R2, #0x00				@DLH bits
	STRB R2, [R1, #0x04]		@Setting DLH
	
	MOV R2, #0x4E				@DLL bits
	STRB R2, [R1, #0x00]		@Setting DLL
	
@MDR1 setting to 16x
	MOV R2, #0x00				@16x mode bits
	STRB R2, [R1, #0x20]		@Setting to 16x mode in MDR1
	
@Setting back to OP mode
	MOV R2, #0x03				@Op mode bits
	STRB R2, [R1, #0x0C]		@Setting to OP mode in LCR
	
@Processor IRQ enabled in CPSR
	MRS R3, CPSR				@Copy CPSR to R3
	BIC R3, #0x80				@Clear bit 7
	MSR CPSR_c, R3				@Write back to CPSR
	
	LDR R0, =0x00000000			@Sets state for IRQ purposes to 0 (button state)

@Empty loop to wait for the interrupt from the button
WAITBUTTON:
	NOP							@Wait for button
	b WAITBUTTON
	
INT_DIRECTOR:
	STMFD SP!, {R3-R8, LR}		@Push main registers to stack
@See if not user interrupt, if so go back
	LDR R3, =0x482000B8			@Address of INTC-PENDING_IRQ1 register
	LDR R1, [R3]				@Read that register
	TST R1, #0x00004000			@Test pin 14
	BEQ BCHK					@Not UART, check button
	
	LDR R3, =0x481AA008			@Address of IIR_UART for UART5
	LDR R1, [R3]				@Read that register
	TST R1, #0x2				@Check bit 1 (IIT?)***
	BNE TALKER_SVC				@Interrupt from UART, go to talker
	
	LDR R3, =0x48200048			@UART not ready, then go back
	MOV R1, #0x1				@Value to clear bit 0 of INTC_CONTROL
	STR R1, [R3]				@Write it
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Back to mainline
	
BCHK:
	LDR R3, =0x482000F8			@Address of INTC-PENDING_IRQ3 register
	LDR R1, [R3]				@Read that register
	TST R1, #0x00000004			@Test bit 2
	BEQ PASS_ON					@Not button, return time
	
	LDR R3, =0x4804C02C			@Load GPIO1_IRQSTATUS_0 register
	LDR R1, [R3]				@Read status register
	TST R1, #0x20000000			@Check if bit 29 = 1
	BNE BUTTON_SVC				@IF bit 29 = 1 then button pushed
	
	LDR R3, =0x48200048			@No button, then go back
	MOV R1, #0x1				@Value to clear bit 0 of INTC_CONTROL
	STR R1, [R0]				@Write it
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Back to mainline

PASS_ON:			
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to			
	LDMFD SP!, {R3-R8, LR}		@Restore registers
	SUBS PC, LR, #4				@Go back to loop

TALKER_SVC:
	LDR R3, =0x481AA018			@Address of MSR
	LDR R1, [R3]				@Read register
	TST R1, #0x10				@Check bit 4
	BNE CAN_SEND				@Bit 4 is 1
@	BEQ NO_SEND					@Bit 4 is 0
	BEQ CAN_SEND				@Bit 4 is 0 (hard coded because of sticky pin)
	
CAN_SEND:
	LDR R3, =0x481AA014			@Address of LSR
	LDR R1, [R3]				@Read register
	TST R1, #0x20				@Check bit 5
	BEQ PASS_ON					@THR is 0, exit to wait
	
	
@Code for testing write **
@	LDR R3, =0x481AA000			@Address of THR (it is at the base)
@	LDR R2, =CHAR_PTR			@Load current pointer
@	LDR R5, [R2]				@Address of desired character
@	LDR R6, =CHAR_COUNT			@Address of count
@	LDR R7, [R6]				@Current counter
@	LDRB R8, [R5], #1			@Read byte and increment
@	STR R5, [R2]				@Store incremented pointer
@	STRB R8, [R3]				@Send character to THR
@	
@	SUBS R7, R7, #1				@Decrement counter
@	STR R7, [R6]				@Store decremented counter
@	BPL PASS_ON					@Not end of string
@
@At end of string	
@	LDR R3, =MESSAGE			@Address of top of string
@	STR R3, [R2]				@Reset pointer
@	MOV R3, #MSG_LEN			@Length of message
@	STR R3, [R6]				@Reset length
@ ************************

@Reading to UART
	LDR R3, =0x481AA000			@Address of THR (it is at the base)

	CMP R10, #14					@First byte
	BEQ CLKTOP
	CMP R10, #13					@Control to set to character mode
	BEQ CLKCMD
	CMP R10, #12					@Set to character mode
	BEQ CLKCHR
	CMP R10, #11					@Control to change voice
	BEQ CLKCMD
	CMP R10, #10					@Voice number
	BEQ CLKVN
	CMP R10, #9				@Set voice
	BEQ CLKSV	
	CMP R10, #0					@Dummy send
	BEQ DUMMY
	
@Sent initial to talker, now to send clock
	AND R6, R9, #0xF0000000		@Just want first bit
	LSL R9, R9, #4				@Shift to next number
	LSR R6, R6, #28				@Shift to right end
	CMP R6, #9					@Checking if number or letter
	BHI HEXLETTER				@Branch if higher than 9 (its a letter)
	ADD R6, R6, #0x30			@Convert to ascii
	B SENDING					@Send to talker
	
@Fixing for letters
HEXLETTER:
	ADD R6, R6, #0x37			@Convert to ascii letter

SENDING:
	STRB R6, [R3]				@Send to talker
	SUBS R10, R10, #1			@Decrement counter
	BPL PASS_ON					@Not end of counter
	
ENDCNT:	
@Last character, send and exit
	LDR R3, =0x481AA000			@Address of THR (it is at the base)
	MOV R2, #0x0D				@Last byte to send to talker
	STRB R2, [R3]				@Send to talker
	
	LDR R3, =0x481AA004			@Address of IER_UART for UART5
	MOV R2, #0x00				@Clear bits 1 and 3
	STRB R2, [R3]				@Clearing interrupts in UART
	B PASS_ON					@Exit to wait loop to wait for next button push
		
DUMMY:
	MOV R2, #0x0D				@Start sending to talker
	STRB R2, [R3]				@Send to talker
	SUB R10, R10, #1			@Decrement counter
	B ENDCNT					@Return
	
CLKTOP:
	MOV R2, #0x0D				@Start sending to talker
	STRB R2, [R3]				@Send to talker
	SUB R10, R10, #1			@Decrement counter
	B PASS_ON					@Return

CLKCHR:
	MOV R2, #0x43				@Set to character mode
	STRB R2, [R3]				@Send to talker
	SUB R10, R10, #1			@Decremnt counter
	B PASS_ON					@Return

CLKCMD:
	MOV R2, #0x01				@Send command to change voice
	STRB R2, [R3]				@Send to talker
	SUB R10, R10, #1			@Decrement counter
	B PASS_ON					@Return

CLKVN:
	MOV R2, #0x37				@Voice number
	STRB R2, [R3]				@Send to talker
	SUB R10, R10, #1			@Decrement counter
	B PASS_ON					@Return

CLKSV:
	MOV R2, #0x4F				@Set as voice
	STRB R2, [R3]				@Send to talker
	SUB R10, R10, #1			@Decrement counter
	B PASS_ON					@Return
	

NO_SEND:
	LDR R3, =0x481AA014			@Address of LSR
	LDR R1, [R3]				@Read register
	TST R1, #0x05				@Check bit 5
	BEQ PASS_ON					@THR is 0, exit to wait
	
@If breaks, set bit 3 as well ***
	LDR R3, =0x481AA004			@Address of IER_UART for UART5
	MOV R2, #0x01				@Set bit 1 for THR
	STR R2, [R1]				@Setting interrupts in UART
	B PASS_ON					@Done resetting, return to wait

BUTTON_SVC:
	MOV R1, #0x20000000			@Bit 29 mask
	STR R1, [R3]				@Write to status to turn off interrupt request
	
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to register
	
	MOV R12, #0x1				@Value for XOR to invert
	EOR R0, R0, R12				@Switches state by inverting bit
	
@Turn off NEWIRQA bit in INTC_CONTROL, so can respond to new IRQ
	LDR R3, =0x48200048			@Address of INTC_CONTROL register
	MOV R1, #0x1				@Value to clear bit 0
	STR R1, [R3]				@Write to

@State check (First or second press)
	TST R0, #0x1				@Checking if first or second button push
	BNE STARTTMR				@First button push, start timer and LED
	
@Second button push	
@Stopping timer
	MOV R2, #0x00				@Value to stop timer
	LDR R1, =0x48040038			@Timer2 TCLR
	STR R2, [R1]				@Stopping timer
	LDR R1, =0x4804003C			@Address of TCRR
	LDR R9, [R1]				@Read timer to get time
	MOV R11, R9					@Copy timer over to extra register for debug reasons
	MOV R10, #CLK_LEN			@Setting counter
	
@Turn off LED
	LDR R1, =0x4804C190			@Clear Data Out
	MOV R2, #0x00200000			@Mask to turn off
	STR R2, [R1]				@Turning off LED
	
@Enable UART5 interrupts
	LDR R3, =0x481AA004			@Address of IER_UART for UART5
	MOV R2, #0x0A				@Set bits 1 and 3 for THR and Modem status
	STR R2, [R3]				@Setting interrupts in UART
	
	MOV R2, #0x00004000			@Short timer to hold (helps with sketchy buttons) before turning on LED and starting timer
	
HOLDLOOP:
	NOP							@Hold timer before switching
	SUBS R2, #1
	BNE HOLDLOOP
	
	LDMFD SP!, {R3-R8, LR}
	SUBS PC, LR, #4
	
STARTTMR:
	MOV R10, #CLK_LEN
	MOV R2, #0x0080000			@Short timer before turning on LED and timer
	
READYWAIT:
	NOP							@Timer to ready before LED and timer are turned on
	SUBS R2, #1
	BNE READYWAIT

@Making sure timer is clear
	LDR R1, =0x48040000			@Base address of timer2 registers
	LDR R2, =0x00000000			@Value to set CLK to 0
	STR R2, [R1, #0x3C]			@Setting TCRR/count to 0

@Starting timer
	MOV R2, #0x03				@Value to start timer with auto reload
	LDR R1, =0x48040038			@Timer2 TCLR
	STR R2, [R1]				@Turning on timer
		
@Turning on LED
	LDR R3, =0x4804C194			@GPIO1_SETDATAOUT
	MOV R1, #0x00200000			@Value to turn on LED 0
	STR R1, [R3]				@Turn on LED
	
	LDMFD SP!, {R3-R8, LR}		@Back to wait for next button
	SUBS PC, LR, #4

.align 2
SYS_IRQ:   .WORD 0				@Location to store systems IRQ address
.data
.align 2
MESSAGE:	
.byte 0x0D				@Test message for part 1
.byte 0x01				@ascii for CTRL+A (To change voice)
.ascii "7O"				@Change to Robo voice
.ascii "Part one of project one finished"		@Message
.byte 0x0D				@End message
.align 2
CHAR_PTR:	.word MESSAGE		@PTR to next character to send
CHAR_COUNT:	.word 37			@Counter for number of characters to send
STACK1:		.rept 1024			@Main stack
		.word 0x0000
		.endr
STACK2:		.rept 1024			@IRQ stack
		.word 0x0000
		.endr
.END
