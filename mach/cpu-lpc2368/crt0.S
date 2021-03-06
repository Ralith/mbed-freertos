@ crt0.s: startup file for NXP LPC230x Family Microprocessors
@
@ Copyright(C) 2006, NXP Semiconductor
@ All rights reserved.
@ Copyright (C) 2010, Hugo Vincent <hugo.vincent@gmail.com>
@
@ History
@     2006.09.01  ver 1.00    Prelimnary version, first Release
@
@ modified by Martin Thomas:
@  - changed comment char to @ for GNU assembler (arm-elf-as)
@    "The line comment character is [...] '@' on the ARM [...]"
@    (GNU-as manual from binutils V 2.17)
@  - ported RV-ASM to GNU-ASM (sections, import/export equ,
@    :OR:, Labels etc.)
@  - added .data and .bss inits
@  - call main instead for "RV runtime-init" __main
@  - call main with bx so it can be thumb-code
@  - added IRQ-Wrapper for easier porting of IAR, RV etc. ISR-codes.
@  - TargetResetInit can be a thumb-function (using BX instead of BL)
@  - moved TargetResetInit call before the stack-inits and use
@    a temporary stack-pointer
@
@ modified by Hugo Vincent:
@  - style changes
@  - removed a lot of commented-out stuff that we don't need
@  - removed IRQ-Wrapper (need to use the FreeRTOS macros)
@  - added call to LowLevelInit to enable clocks etc before C main().
@  - added hardware-exception debug info support.
@  - added C++ main support.
@

@  ----------------------------------------------------------------------------
@ Standard definitions of Mode bits and Interrupt (I & F) flags in PSRs

.equ Mode_USR,           0x10
.equ Mode_FIQ,           0x11
.equ Mode_IRQ,           0x12
.equ Mode_SVC,           0x13
.equ Mode_ABT,           0x17
.equ Mode_UND,           0x1B
.equ Mode_SYS,           0x1F

.equ I_Bit,              0x80            @ when I bit is set, IRQ is disabled
.equ F_Bit,              0x40            @ when F bit is set, FIQ is disabled

@  ----------------------------------------------------------------------------
@  Exception vectors (mapped to 0x0 by linker script)
@      Note: absolute addressing mode must be used.

.section .vectors, "ax"
.arm
.global vectors
vectors:        LDR     pc, Reset_Addr
                LDR     pc, Undef_Addr
                LDR     pc, SWI_Addr
                LDR     pc, PAbt_Addr
                LDR     pc, DAbt_Addr
                NOP                            @ Reserved Vector
                LDR     pc, [pc, #-0x0120]     @ Vector from VICVectAddr
                LDR     pc, FIQ_Addr

Reset_Addr:     .word     Reset_Handler
Undef_Addr:     .word     Undef_Handler
SWI_Addr:       .word     SWI_Handler
PAbt_Addr:      .word     PAbt_Handler
DAbt_Addr:      .word     DAbt_Handler
FIQ_Addr:       .word     Exception_UnhandledFIQ

@ The SWI is used for YieldProcessor in FreeRTOS.
SWI_Handler:    B       vPortYieldProcessor

@  ----------------------------------------------------------------------------
@  Reset Handler: setup stacks, copy/initialise data, and jump to C main.

Reset_Handler:
                @  Enter Undefined Instruction Mode and set its Stack Pointer
                MSR     CPSR_c, #Mode_UND | I_Bit | F_Bit
                LDR     SP, =__irq_stack_top__

                @  Enter Abort Mode and set its Stack Pointer
                MSR     CPSR_c, #Mode_ABT | I_Bit | F_Bit
                LDR     SP, =__abt_stack_top__

                @  Enter FIQ Mode and set its Stack Pointer
                MSR     CPSR_c, #Mode_FIQ | I_Bit | F_Bit
                LDR     SP, =__fiq_stack_top__

                @  Enter IRQ Mode and set its Stack Pointer
                MSR     CPSR_c, #Mode_IRQ | I_Bit | F_Bit
                LDR     SP, =__irq_stack_top__

                @  Enter Supervisor Mode and set its Stack Pointer
                MSR     CPSR_c, #Mode_SVC | I_Bit | F_Bit
                LDR     SP, =__svc_stack_top__

@  For FreeRTOS, leave in Supervisor Mode with Interrupts disabled.
@  We don't use User Mode with FreeRTOS so leave it's stack uninitialised.

@  ----------------------------------------------------------------------------
@  Relocate .data section (Copy from ROM to RAM)
                LDR     R1, =__text_end__
                LDR     R2, =__data_start__
                LDR     R3, =__data_end__
                CMP     R2, R3
                BEQ     DataIsEmpty
LoopReloc:      CMP     R2, R3
                LDRLO   R0, [R1], #4
                STRLO   R0, [R2], #4
                BLO     LoopReloc
DataIsEmpty:

@  ----------------------------------------------------------------------------
@  Clear .bss section (Fill with zeros)

                MOV     R0, #0
                LDR     R1, =__bss_start__
                LDR     R2, =__bss_end__
                CMP     R1,R2
                BEQ     BSSIsEmpty
LoopFill:       CMP     R1, R2
                STRLO   R0, [R1], #4
                BLO     LoopFill
BSSIsEmpty:

@  ----------------------------------------------------------------------------
@  Jump into C Boot_Init() code (lib/os_init.c).
                .extern Boot_Init
                LDR     R0, =Boot_Init
                MOV     LR, PC
                BX      R0

@  The C main should never return, but if it does, reset the device
                LDR     R0, =Reset_Handler
                BX      R0

@  ----------------------------------------------------------------------------
@  Undefined Instruction, Prefetch Abort, and Data Abort Handlers
@      (all store the current register contents to a C-accessible array and save
@      the offending address in R0 before branching to the C handler).

@ Code from http://www.eetimes.com/design/other/4006695/How-to-use-ARM-s-data-abort-exception
PAbt_Handler:
                PUSH    {R0-R12,LR}             @ save superset of the AAPCS scheme (r4-r11)
                LDR     SP, =SavedRegs          @ set sp_abt to data array (restore later)
                STMIA   SP, {R0-R12}            @ save 1st dataset in r0-r12 registers to array
                SUB     R0, LR, #4              @ calculate pc value of abort instr: r0 = lr-4
                MRS     R5, CPSR                @ save current mode to r5 for mode switching
                MRS     R6, SPSR                @ spsr_abt = CPSR of abort originating mode:
                                                @ save to r6 for mode switching
                MOV     R2, R6                  @ building 2nd dataset: r2 = CPSR (of exception)
                TST     R6, #0xF                @ test for the mode which raised exception:
                ORREQ   R6, R6, #0xF            @ if EQ => change mode usr->sys; else do not
                BIC     R7, R6, #0x20           @ go to forced ARM state via r7
                MSR     CPSR, R7                @ switch out from Mode_ABT to
                MOV     R3, LR                  @ dabt generating mode and state
                MOV     R4, SP                  @ get lr (= r3) and sp (= r4)
                MSR     CPSR, R5                @ switch back to Mode_ABT 
                LDR     SP, =(SavedRegs + 13*4) @ reset sp to array's starting addr
                STMIA   SP, {R0-R4}             @ and save the 2nd dataset from r0 to r4

                @ cleanup & restoration follows:
                                                @ restored full context, sp first
                LDR     SP, =__abt_stack_top__
                                                @ sp uses abort stack (which is top of stack
                                                @ minus undefined stack length)
                POP     {R0-R12,LR}             @ r0-r12 and lr using restored stack pointer
                LDR     R0, =Exception_PrefetchAbort
                BX      R0                      @ call C-compiled handler

@ See comments for PAbt_Handler above.
DAbt_Handler:
                PUSH    {R0-R12,LR}
                LDR     SP, =SavedRegs
                STMIA   SP, {R0-R12}
                SUB     R0, LR, #8
                MRS     R5, CPSR
                MRS     R6, SPSR
                MOV     R2, R6
                TST     R6, #0xF
                ORREQ   R6, R6, #0xF
                BIC     R7, R6, #0x20
                MSR     CPSR, R7
                MOV     R3, LR
                MOV     R4, SP
                MSR     CPSR, R5
                TST     R6, #0x20               @ Thumb state raised exception?
                LDRNEH  R1, [R0]                @ yes T-state, load 16-bit instr: r1 = [pc](dabt)
                LDREQ   R1, [R0]                @ no A-state, load 32-bit instr: r1 = [pc](dabt)
                LDR     SP, =(SavedRegs + 13*4)
                STMIA   SP, {R0-R4}
                LDR     SP, =__abt_stack_top__
                POP     {R0-R12,LR}
                LDR     R0, =Exception_DataAbort
                BX      R0

@ See comments for PAbt_Handler above.
@ FIXME this probably needs some other changes?
Undef_Handler:
                PUSH    {R0-R12,LR}
                LDR     SP, =SavedRegs
                STMIA   SP, {R0-R12}
                SUB     R0, LR, #4
                MRS     R5, CPSR
                MRS     R6, SPSR
                MOV     R2, R6
                TST     R6, #0xF
                ORREQ   R6, R6, #0xF
                BIC     R7, R6, #0x20
                MSR     CPSR, R7
                MOV     R3, LR
                MOV     R4, SP
                MSR     CPSR, R5
                TST     R6, #0x20
                LDRNEH  R1, [R0]
                LDREQ   R1, [R0]
                LDR     SP, =(SavedRegs + 13*4)
                STMIA   SP, {R0-R4}
                LDR     SP, =__und_stack_top__
                POP     {R0-R12,LR}
                LDR     R0, =Exception_UndefinedInstruction
                BX      R0
.end


