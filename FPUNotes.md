
For years I've had to just enable the FPU for nearly every 030 machine in MAME because otherwise the OS would die immediately after Welcome to Macintosh with an unexpected F-line trap. I just found out it's because of the extremely non-intuitive way Apple was detecting the FPU.

This is from the Quadra 700/900 and PowerBook 140/170 ROM, but many other pre-1992 ROMs have the same code at the same place:

Code:

ROM:40803DBA CheckOptionals:
ROM:40803DBA                 btst    #$1C,d2       ; did the Universal table say this machine can have an FPU?
ROM:40803DBE                 beq.w   FPUDone       ; if not, no need for more checking
ROM:40803DC2                 movea.l a6,a2         ; this is the "BSR6" macro you see all over the SuperMario tree
ROM:40803DC4                 lea     CheckFPUReturn,a6
ROM:40803DC8                 jmp     TestForFPU
ROM:40803DCC
ROM:40803DCC CheckFPUReturn:
ROM:40803DCC                 beq.s   HaveFPU
ROM:40803DCE                 bclr    #$1C,d2      ; clear the HasFPU bit in the hardware config word
ROM:40803DD2
ROM:40803DD2 HaveFPU:
ROM:40803DD2                 movea.l a2,a6
ROM:40803DD4                 bra.w   FPUDone

ROM:40803DEC GotBusError:
ROM:40803DEC                 btst    #$1B,d7    ; Make the BEQ at 40803DCC fall through
ROM:40803DF0                 movea.l a5,sp
ROM:40803DF2                 jmp     (a6)

ROM:40804640 TestForFPU:
ROM:40804640                 movec   cacr,d1
ROM:40804644                 bset    #$1F,d1
ROM:40804648                 movec   d1,cacr
ROM:4080464C                 movec   cacr,d1
ROM:40804650                 bclr    #$1F,d1
ROM:40804654                 beq.s   Not040
ROM:40804656                 movec   d1,cacr
ROM:4080465A                 bra.s   Its040
ROM:4080465C
ROM:4080465C Not040:
ROM:4080465C                 move.b  #7,d1               ; select FC 7 (CPU space)
ROM:40804660                 movec   d1,sfc
ROM:40804664                 moves.w (unk_22000).l,d1    ; read an arbitrary RAM location, but with FC 7
ROM:4080466C
ROM:4080466C Its040:
ROM:4080466C                 cmp.b   d1,d1  ; make the BEQ at 40803DCC succeed
ROM:4080466E                 jmp     (a6)


The comments should be pretty self-explanatory, but the upshot is that it uses the rarely seen MOVES instruction to read RAM with the 68k set to assert function code 7 (CPU private) instead of Mac OS's normal FC 5 (supervisor mode data). I'm unclear if this is a 68K feature or a Mac hardware feature, as I certainly haven't seen it documented either place.

Interestingly, in 1992 Apple threw away this code and switched to a more obvious and straightforward detection method, which you see in the SuperMario tree. This is from the PowerBook 160/180/165c/180c ROM:

Code:

ROM:40804640 TestForFPU:
ROM:40804640                 movec   vbr,d1          ; mess with the vector table so F-line traps are caught
ROM:40804644                 subi.l  #$24,d1
ROM:4080464A                 movec   d1,vbr
ROM:4080464E                 moveq   #1,d1
ROM:40804650                 lea     NoFPU,a6        ; tell the F-line trap handler where to jump to
ROM:40804654                 fnop                    ; this will cause an F-line trap if there's no FPU
ROM:40804658                 moveq   #0,d1           ; if there is an FPU this instruction will execute
ROM:4080465A NoFPU:


This is ultimately how they differentiate a PowerBook 140 from a 170 or a 160 from a 180. If you've played with unirom you've seen that there are only entries in the tables for the 170 and 180, and some code we don't see in the SuperMario tree fudges the Gestalt values for those machines if an FPU is not present.


So I've finally researched this properly and it's indeed an MC680x0 feature, at least for '020 and '030. In CPU space (function code 7), addresses of the form $0002xxxx access CIRs, Coprocessor Interface Registers. Bits 15-13 are the standard 3-bit coprocessor ID, same as you see in F-line instructions, where coprocessor %001 is the 68881 or 68882. And bits 0-4 are the address. So Apple's read of FC7:$00022000 is reading the "Response CIR" from the FPU.

The Motorola manuals aren't explicit about what happens when you read a CIR for a coprocessor that isn't present, but they do hint that a bus error will occur when the transaction times out.

The 68040 doesn't have CIRs at all as far as I've been able to tell. The ROM code that uses the CIR method to detect an FPU assumes that an '040 means you have an FPU. And that leads me to believe they changed the detection method to the more straightforward version because of the impending use of machines with the cheaper no-FPU LC040.


For F-line instruction, in the '020 and '030 using an external coprocessor, normally:
(a) the CPU decode the F-line instruction
(b) based on the *class* of the instruction, it initiates the standardized 'dialog' for that class with the coprocessor using the (address of the) appropriate CIRs
Note that the '020/'030 has no idea what types of coprocessor it is talking to. It's entirely abstract for it.

Meanwhile, the coprocessors implement the CIRs (and their own logic) and react to them being written/read in the appropriate way. For a FADD mem,freg, the '881/'882 will first request the CPU to decode the address of the memory operand and send it, and then will free the CPU to continue while it executes the addition internally. This will involve the command CIR, the response CIR, the operand CIR (more than once if the operand is larger than 32 bits), etc. It's quite neat as you can expand the instruction set in any way you want (don't tell the RISC-V crowd, they think they invented extending the ISA...). However, the dialog is quite slow over the bus, even if you move from asynchronous (as the '851, '881, '882 do) to synchronous (which I don't think any coprocessor used back in the day, but I know it works with the '030 because that's what my prototypes coprocessors use).

For the MMU in the MC68030 and later, and the FPU in the MC68040 and later, they are integrated directly in the CPU so there's no need for any of this. FADD is decoded entirely, and the MC680[46]0 will simply execute the memory access and the addition in its internal pipelines directly. Which is much, much, much faster.

MOVES ('Move Alternate Address Space') is the standard way of moving data between registers and arbitrary address in an arbitrary memory space (i.e. Function Code). It's a privileged instruction. On the MC68010, you can use it to implement the coprocessor dialog 'by hand' in SW to use a coprocessor as they don't implement it in hardware. I'm not sure anyone ever did that in production, but it was documented by Motorola at the time. Coprocessor lives in the $7 address space, which is the CPU space. No memory/peripherals should be there, which is why PDS device have to check that the FC aren't $7 before answering (they really should check for the appropriate address space, but Apple collapsed everything into just one to make everyone's life easier, 68k were a bit overengineered in some area, the '851 is way overcomplicated for a MMU and had to be trimmed down a lot for the '030).