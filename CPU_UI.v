// Listing 17.1 Demonstrate ARM program with memory mapped I/O
//   1) Assembles most ARM instructions including memory mapped LDR/STR
//   2) Executes demonstration of factorial program
//   3) Input data from switches, output to 7-segment displays
//   4) Breakpoint address can be set to "stall" assembler program
//
// Modules and macros contained in this file:
//   1) CPU_UI: User Interface that dumps 32-bit words, 16 bits at a time
//   2) CPU: 32-bit CPU with most ARM instructions and memory mapped I/O
//   3) DataProcIns: 16 "ARM like" DP instructions using 32-bit registers
//   4) Op2Mod: Fill in second operand including all shift possibilities
//   5) ShiftMod: Calculate all shift possibilities for Op2Mod
//   6) MultiplyIns: Module to calculate multiplication
//   7) DataMod: RAM memory, load/store instructions, memory mapped I/O
//   8) Macros for assembling ARM data processing and multiplication instructions
//   9) ProgMod: Program to demonstrate factorial calculated recusively

//
//---------------- User Interface ----------------
//
module CPU_UI (SW, KEY, CLOCK_50, LEDR, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5);
 input  [9:0] SW;
 input  [1:0] KEY;
 input CLOCK_50;
 output [9:0] LEDR;
 output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
 function automatic [7:0] digit;
  input [3:0] num; 
  case (num)
   0:  digit = 8'b11000000;  // 0
   1:  digit = 8'b11111001;  // 1
   2:  digit = 8'b10100100;  // 2
   3:  digit = 8'b10110000;  // 3
   4:  digit = 8'b10011001;  // 4
   5:  digit = 8'b10010010;  // 5
   6:  digit = 8'b10000010;  // 6
   7:  digit = 8'b11111000;  // 7
   8:  digit = 8'b10000000;  // 8
   9:  digit = 8'b10010000;  // 9
   10: digit = 8'b10001000;  // A
   11: digit = 8'b10000011;  // b
   12: digit = 8'b11000110;  // C
   13: digit = 8'b10100001;  // d
   14: digit = 8'b10000110;  // E
   15: digit = 8'b10001110;  // F
  endcase
 endfunction
 wire [31:0] hexDisp;
 wire reset;
 and(reset,~KEY[0],~KEY[1]); // Reset if both keys pushed
 assign HEX0 = KEY[1] ? digit(hexDisp[19:16]) : digit(hexDisp[3:0]);
 assign HEX1 = KEY[1] ? digit(hexDisp[23:20]) : digit(hexDisp[7:4]);
 assign HEX2 = KEY[1] ? digit(hexDisp[27:24]) : digit(hexDisp[11:8]);
 assign HEX3 = KEY[1] ? digit(hexDisp[31:28]) : digit(hexDisp[15:12]);
 assign HEX4 = 8'hFF;
 assign HEX5 = 8'hFF;
CPU (KEY, reset, CLOCK_50, SW[8:4], SW[3:0], hexDisp, LEDR);
endmodule

//
//---------------- "ARM" CPU imitation ----------------
//
module CPU (KEY, reset, clk, PCbp, dmpID, hexDisp, LEDR);
 input  [1:0] KEY;
 input  reset, clk;
 input  [4:0] PCbp; // Breakpoint instruction address
 input  [3:0] dmpID; // Register to dump
 output [9:0] LEDR;
 output [31:0] hexDisp; // Register contents for display
// assign hexDisp = R[dmpID];
 assign LEDR[5:0] = PCir[5:0];   // Address of current instruction
 assign LEDR[9:6] = CPSR[31:28]; // N, Z, C, V status bits

 reg run; // Flag indicating CPU is running

 // CPU instruction cycle
 
 reg [1:0] CPU_state;
 parameter fetch     = 2'b01;
 parameter decode    = 2'b10;
 parameter execute   = 2'b11;
 parameter writeBack = 2'b00;

 // Instruction format
 
 wire [3:0] opCode; // Operation code value
 wire iFlag; // Immedite data flag
 wire SU;    // Update status flag
 wire [3:0] cond; // Condition code in instruction.
 wire [11:0] op2raw; // Second operand raw code
 wire [31:0] op2Val; // Calculated value of second oeprand
 wire [31:0] RdVal_DP; // Destination register value
 reg  [31:0] RnVal; // Source data register value
 reg  [31:0] RmVal; // 2nd op data register value
 reg  [31:0] RsVal; // 2nd op shift register value
 wire [3:0] RdID; // Destination register number
 wire [3:0] RnID; // Source register number
 wire [3:0] RmID; // Second operand data register number
 wire [3:0] RsID; // Second operand shift register number
 wire [31:0] IR; // Instruction register
 assign cond   = IR[31:28];  // Conditions needed to execute
 assign iFlag  = IR[25]; // Immediate data flag
 assign opCode = IR[24:21]; // Opcode is in upper 4 bits
 assign SU     = IR[20]; // Update status flag
 assign RnID   = IR[19:16]; // Source data register
 assign RdID   = IR[15:12]; // Destination register
 assign RmID   = IR[3:0]; // 2nd operand data register
 assign RsID   = IR[11:8]; // 2nd operand shift register
 assign op2raw = IR[11:0]; // Operand is in lower 12 bits
 
 // General purpose registers R0 - R15

 reg [31:0] R[0:15]; // 16 registers
 parameter PC = 15; // Program Counter
 parameter LR = 14; // Link REgister

 // Current Program Status Register (CPSR)
 
 reg [31:0] CPSR; // Current Program Status
 wire [31:0] CPSR_DP; // New values for CPSR 
 wire N_flag, Z_flag, C_flag, V_flag;
 assign N_flag = CPSR[31]; // Negative condition
 assign Z_flag = CPSR[30]; // Zero condition
 assign C_flag = CPSR[29]; // Carry condition
 assign V_flag = CPSR[28]; // Overflow condition
 reg ok2exe; // True if condition met for execution
 reg [31:0] PCir; // Address of current instruction
 wire RdVal_DPU; // Flag indicating Rd needs updating
 wire [31:0] CPSR_M; // New values for CPSR from multiply
 wire [63:0] RdV64_M;  // Destination register value (multiplication)
 wire [63:0] RdVal_RAM; // Destination register for LDR/STR
 wire [31:0] BrOff; // Branch offset value
 
 // Instantiate program memory and ALU processing
 
 wire SelDP, SelMul, Sel64, SelRAM, SelB, SelBL, SelBX;
 assign SelDP  = ok2exe && IR[27:26]==0 && IR[7:4]!=4'b1001;
 assign SelMul = ok2exe && IR[27:24]==0 && IR[7:4]==4'b1001;
 assign SelM64 = SelMul && IR[23];
 assign SelRAM = ok2exe && IR[27:26]==2'b01;

 ProgMod (R[PC], CPU_state==fetch, reset, IR);
 Op2Mod (RmVal, RsVal, op2raw, iFlag, op2Val);
 DataProcIns (opCode, RnVal, op2Val, CPU_state==execute && SelDP, CPSR, RdVal_DP, RdVal_DPU, CPSR_DP);
 MultiplyIns (opCode, RdVal, RmVal, RnVal, RsVal, CPU_state==execute && SelMul, CPSR, RdV64_M, CPSR_M);
 DataMod (IR[25:20], R[RdID], RnVal, RmVal, op2raw, CPU_state==execute && SelRAM, dmpID, hexDisp, RdVal_RAM);

 assign SelB   = ok2exe && IR[27:24]==4'b1010;
 assign SelBL  = ok2exe && IR[27:24]==4'b1011;
 assign SelBX  = ok2exe && IR[27:4]==24'h12FFF1;
 assign BrOff  = IR[23] ? {6'h3F,IR[23:0],2'b00} : IR[23:0]<<2;

 // Instruction cycle and reset
 
 always @ (posedge(clk), posedge(reset))
  begin
   if (reset)
    begin
     R[PC] <= 0; // Boot address is 0000
     CPU_state <= fetch;
    end
   else
    case (CPU_state)
     fetch:   // Get next instruction in program
      begin
       PCir <= R[PC];  // Save address of PC for breakpoint
       R[PC] <= R[PC] + 4;
       CPU_state <= decode;
      end
     decode:  // Disassemble the instruction 
      begin
       RnVal <= R[RnID]; // Source data register
       RmVal <= R[RmID]; // 2nd op data register
       RsVal <= R[RsID]; // 2nd op shift register
       if (~KEY[1]) // Instruction cycle interlock
        run <= 0;
       if (~run && (~KEY[0] || PCir[6:2]!=PCbp)) // Only stop at breakpoint
        begin
         run <= 1;
         case (cond)
          0: ok2exe <=  Z_flag;      // EQual (zero); Z set
          1: ok2exe <=  ~Z_flag;     // Not Equal (non-zero); Z clear
          2: ok2exe <=  C_flag;      // Carry Set (Unsigned Higher or Same)
          3: ok2exe <=  ~C_flag;     // Carry Clear (Unsigned LOwer)
          4: ok2exe <=  N_flag;      // MInus or negative; N set
          5: ok2exe <=  ~N_flag;     // PLus or positive; N clear
          6: ok2exe <=  V_flag;      // Overflow; V Set
          7: ok2exe <=  ~V_flag;     // No overflow; V Clear
          8: ok2exe <=  C_flag & ~Z_flag;  // Unsigned HIgher; C set and Z clear
          9: ok2exe <=  ~C_flag | Z_flag;  // Unsigned Lower or Same
          10: ok2exe <=  N_flag == V_flag; // Signed Greater than or Equal to
          11: ok2exe <=  N_flag != V_flag; // Signed Less Than
          12: ok2exe <=  ~Z_flag & (N_flag==V_flag); // Signed Greater Than
          13: ok2exe <=  Z_flag | (N_flag!=V_flag);  // Signed Less than or Equal
          14: ok2exe <=  1;          // ALways; any status bits ok2exe
         endcase
         CPU_state <= execute;
        end
      end
     execute: // Perform desired operation
      CPU_state <= ok2exe ? writeBack : fetch;
     writeBack: // Update specific register
      begin
       {R[RnID],R[RdID]} <= (RdVal_DPU & SelDP) ? {R[RnID],RdVal_DP} :
        (SelM64) ? RdV64_M :
        (SelMul) ? {RdV64_M[31:0],R[RdID]} :
        (SelRAM) ? {RdVal_RAM} :
         {R[RnID],R[RdID]};
       if (SU) CPSR <=
        SelDP ? CPSR_DP :
        SelMul ? CPSR_M :
         CPSR;
       {R[LR],R[PC]} <= (SelBX) ? {R[LR],RmVal} :
        (SelBL) ? {R[PC],PCir+8+BrOff}:
        (SelB) ? {R[LR],PCir+8+BrOff} :
         {R[LR],R[PC]};
       CPU_state <= fetch;
      end
    endcase
  end
endmodule

//
//---------------- ALU for ARM data processing instructions ----------------
//
module DataProcIns (opCode, Rn, op2, clk, CPSR, Rd, RdVal_DPU, CPSR_DP);
 input [3:0] opCode; // Data processing instruction opcode
 input [31:0] Rn; // Source register contents
 input [31:0] op2; // 2nd operand value
 input  clk; // Pulse to produce calculation
 input [31:0] CPSR; // Current Program Status Register (CPSR)
 output reg [31:0] Rd; // Value calculated by this module
 output RdVal_DPU; // Set to "true" if Rd is updated
 output [31:0] CPSR_DP; // Updated CPSR

 wire N, Z, V, CI; // Individual status bits in CPSR
 reg C; 
 assign CI = CPSR[29]; // Carry (In) condition
 assign CPSR_DP[31] = N; // Negative condition
 assign CPSR_DP[30] = Z; // Zero condition
 assign CPSR_DP[29] = C; // Carry (Out) condition
 assign CPSR_DP[28] = V; // Overflow condition

 assign RdVal_DPU = opCode < 8 | opCode > 11; 
 assign N = Rd[31];
 assign Z = (Rd) ? 0 : 1;
 assign V = Rd[31] ^ Rd[30];
 always @ (posedge(clk))
  case (opCode)
   0:  {C,Rd} <= Rn & op2;      // AND
   1:  {C,Rd} <= Rn ^ op2;      // EOR (exclusive OR)
   2:  {C,Rd} <= Rn - op2;      // SUB
   3:  {C,Rd} <= op2 - Rn;      // RSB (reverse subtract)
   4:  {C,Rd} <= Rn + op2;      // ADD
   5:  {C,Rd} <= Rn + op2 + CI; // ADC Add with carry
   6:  {C,Rd} <= Rn - op2 - CI; // SBC Subtract with carry
   7:  {C,Rd} <= op2 - Rn - CI; // RSC (reverse SUB with carry)
   8:  {C,Rd} <= Rn & op2;      // TST Test (like AND)
   9:  {C,Rd} <= Rn ^ op2;      // TEQ Test Equal (like EOR)
   10: {C,Rd} <= Rn - op2;      // CMP Compare (like SUB)
   11: {C,Rd} <= Rn + op2;      // CMN Compare Negative (like ADD)
   12: {C,Rd} <= Rn | op2;      // ORR (inclusive OR)
   13: {C,Rd} <= op2;           // MOV
   14: {C,Rd} <= Rn & ~op2;     // BIC (bit clear)
   15: {C,Rd} <= ~op2;          // MVN (move NOT)
  endcase
endmodule

//
//------- Evaluate Second Operand (lower 12 bits of instruction) -----
//
module Op2Mod (RmVal, RsVal, op2raw, iFlag, op2Val);
 input [31:0] RmVal; // Possible 2nd operand data register contents
 input [31:0] RsVal; // Possible 2nd operand shift register contents
 input [11:0] op2raw; // Second operand "as is" in instruction
 input  iFlag; // Immediate value flag
 output [31:0] op2Val; // Calculated value of second operand

 wire [31:0] op2imVal; // Value if 2nd op. is immediate
 wire [31:0] shiftCount; // Calculated shift count (fixed or Rs)
 wire [31:0] op2shifted; // Value if 2nd op. is in Rm
 assign op2imVal = {op2raw[7:0],24'b0,op2raw[7:0]} >> {op2raw[11:8],1'b0};
 assign shiftCount = (op2raw[4]) ? RsVal : op2raw[11:7];
 ShiftMod (RmVal, op2raw[6:5], shiftCount, op2shifted);
 assign op2Val = (iFlag) ? op2imVal : op2shifted;
endmodule

//
//------------ Evaluate Shift within Second Operand ----------
//
module ShiftMod (RmVal, shiftType, shiftCount, op2Val);
 parameter REGSIZE = 32; // Size of ARM 32-bit register
 parameter LSL = 2'b00;  // Logical Shift Left
 parameter LSR = 2'b01;  // Logical Shift Right
 parameter ASR = 2'b10;  // Algebraic Shift Right
 parameter ROR = 2'b11;  // Rotate (circular) Right
 input [REGSIZE-1:0] RmVal; // Value to be shifted
 input [1:0] shiftType; // Type of shift to perform
 input [4:0] shiftCount; // How many bits to shift
 output [REGSIZE-1:0] op2Val; // Shifted value

 genvar i;
 generate
 for (i=0;i<REGSIZE;i=i+1)
  begin:blkname
   assign op2Val[i] = (shiftType==LSL) &&
    (i >= shiftCount) ? RmVal[i-shiftCount] :
    (shiftType==LSL) ? 0 :
    (i < REGSIZE-shiftCount) ? RmVal[i+shiftCount] :
    (shiftType==LSR) ? 0 :
    (shiftType==ASR) ? RmVal[REGSIZE-1] :
    RmVal[i+shiftCount-REGSIZE];
  end
 endgenerate
endmodule

//
//---------------- ALU for multiplication instructions ----------------
//
module MultiplyIns (opCode, Rn, Rm, Rd, Rs, clk, CPSR, Rd64, CPSRMul);
 input [3:0] opCode;
 input [31:0] Rd,Rm,Rn,Rs; // Note: Rn and Rd switched
 input  clk;
 input [31:0] CPSR;
 output reg [63:0] Rd64;    // 64-bit product
 output reg [31:0] CPSRMul; // Updated N and Z
 always @ (posedge(clk))
  begin
   case (opCode)
    0:  Rd64 <= Rs * Rm;           // MUL
    1:  Rd64 <= Rs * Rm + Rn;      // MLA
    4:  Rd64 <= Rs * Rm;           // SMULL
    5:  Rd64 <= Rs * Rm + {Rd,Rn}; // SMLAL
    6:  Rd64 <= Rs * Rm;           // UMULL
    7:  Rd64 <= Rs * Rm + {Rd,Rn}; // UMLAL
   endcase 
   CPSRMul <= 
    {opCode[1]==0 & {Rs[31]^Rm[31],Rs==0 | Rm==0},
    CPSR[1:0]};
  end
endmodule

//
//---------------- ALU for load/store instructions and RAM memory ----------------
//
module DataMod (IPUBWL, Rd, Rn, Rm, op2raw, clk, iPort, oPort, Rd64);
 input [5:0] IPUBWL;
 input [31:0] Rd,Rn,Rm,op2raw; 
 input  clk;
 input [3:0] iPort;
 output reg [31:0] oPort;
 output reg [63:0] Rd64;    // 
 wire [31:0] op2shifted; // Value if 2nd op. is in Rm
 wire [31:0] offset;
 wire [31:0] MAR, MARup;
 reg [7:0] RAM[0:149]; // Read/Write Random Access Memory

 ShiftMod LDRSTR (Rm, op2raw[6:5],  op2raw[11:7], op2shifted);
 assign offset = (IPUBWL[5]) ? op2shifted : op2raw;
 assign MAR = (~IPUBWL[4]) ? Rn :  // ~P
  (IPUBWL[3]) ? Rn + offset :  Rn - offset; 
 assign MARup = (~IPUBWL[1] && IPUBWL[4]) ? Rn :  // ~W && P
  (IPUBWL[3]) ? Rn + offset :  Rn - offset; 

 always @ (posedge(clk))
  if (IPUBWL[0]) // Load
   if (MAR>=1000) // Range to read input devices
    Rd64 <= {MARup,28'b0,iPort};
   else // Range for reading from memory
    if (IPUBWL[2]) // byte
     Rd64 <= {MARup,24'b0,RAM[MAR]};
    else // Load word
     Rd64 <= {MARup,RAM[MAR+3],RAM[MAR+2],RAM[MAR+1],RAM[MAR]};
  else  // Store
   begin
    if (MAR>=1000) // Range to write to output devices
     oPort <= Rd;
    else // Range for writing to memory
     if (IPUBWL[2]) // byte
      RAM[MAR]   <= Rd[7:0];
     else // Store word
      begin
       RAM[MAR+3] <= Rd[31:24];
       RAM[MAR+2] <= Rd[23:16];
       RAM[MAR+1] <= Rd[15:8];
       RAM[MAR]   <= Rd[7:0];
      end
    Rd64 <= {MARup,Rd}; 
   end
endmodule

//
//---------------- Macro definitions for assembly language ----------------
//
 `define AND asdp (4'b0000, // [Rd] = [Rn] AND (2nd operand)
 `define EOR asdp (4'b0001, // [Rd] = [Rn] Exclusive Or (2nd operand)
 `define SUB asdp (4'b0010, // [Rd] = [Rn] - (2nd operand)
 `define RSB asdp (4'b0011, // [Rd] = (2nd operand) - [Rn]
 `define ADD asdp (4'b0100, // [Rd] = [Rn] + (2nd operand)
 `define ADC asdp (4'b0101, // [Rd] = [Rn] + (2nd operand) + C
 `define SBC asdp (4'b0110, // [Rd] = [Rn] (2nd operand) + C - 1
 `define RSC asdp (4'b0111, // [Rd] = (2nd operand) - [Rn] + C - 1
 `define TST asdp (4'b1000, // [Rn] AND (2nd operand) => status bits
 `define TEQ asdp (4'b1001, // [Rn] Exclusive Or (2nd operand) => stats bits
 `define CMP asdp (4'b1010, // [Rn] + (2nd operand) => status bits
 `define CMN asdp (4'b1011, // [Rn] - (2nd operand) => s tatus bits
 `define ORR asdp (4'b1100, // [Rd] = [Rn] Inclusive OR (2nd operand)
 `define MOV asdp (4'b1101, // [Rd] = [Rn]
 `define BIC asdp (4'b1110, // [Rd] = [Rn] AND NOT (2nd operand)
 `define MVN asdp (4'b1111, // [Rd] = NOT [Rn]

 `define LSL ash (16'h1000, // Logical Shift Left
 `define LSR ash (16'h1001, // Logical Shift Right
 `define ASR ash (16'h1002, // Algebraic Shift Right
 `define ROR ash (16'h1003, // Rotate (circular) Right

 `define MUL   asmul (3'b000, // Multiply giving 32-bit product
 `define MLA   asmul (3'b001, // Multiply, accumulate 32-bit product
 `define UMULL asmul (3'b100, // Unsigned 64-bit product
 `define UMLAL asmul (3'b101, // Unsigned 64-bit product, accumulate
 `define SMULL asmul (3'b110, // Signed 64-bit product
 `define SMLAL asmul (3'b111, // Signed 64-bit product, accumulate

 `define STR   asmem (3'b000, // Store full 32-bit R register
 `define STRB  asmem (3'b100, // Store low-order byte in register
 `define LDR   asmem (3'b001, // Load full 32-bit R register
 `define LDRB  asmem (3'b101, // Load lower 8 bits and zero fill
 `define PUSH  asSP  (7'b1010010,  // Append 32-bit value to stack
 `define POP   asSP  (7'b1001001,  // Reload 32-bit value from stack
 `define WORD  asdat (4,      // Initialize 32-bit word in memory
 `define BYTE  asdat (1,      // Initialize 8-bit byte in memory
 `define ALIGN asdat (0,      // Align IP to multiple of bytes

 `define B     asbr (4'b1010, // Branch
 `define BL    asbr (4'b1011, // Branch with Link
 `define BX    asbr (4'b0001, // Branch and Exchange

 `define _1   ,0,0,0,0,0,0,0);  // End instruction of 1 field
 `define _2   ,0,0,0,0,0,0);    // End instruction of 2 fields
 `define _3   ,0,0,0,0,0);      // End instruction of 3 fields
 `define _4   ,0,0,0,0);        // End instruction of 4 fields
 `define _5   ,0,0,0);          // End instruction of 5 fields
 `define _6   ,0,0);            // End instruction of 6 fields
 `define _7   ,0);              // End instruction of 7 fields
 `define _8   );                // End instruction of 8 fields
 
 `define EQ 4'b0000, // EQual (zero); Z set
 `define NE 4'b0001, // Not Equal (non-zero); Z clear
 `define HS 4'b0010, // Unsigned Higher or Same; C set -- also "CS"
 `define CS 4'b0010, // Carry set
 `define LO 4'b0011, // Unsigned LOwer; C clear --also "CC"
 `define CC 4'b0011, // Carry clear
 `define MI 4'b0100, // MInus or negative; N set
 `define PL 4'b0101, // PLus or positive; N clear
 `define VS 4'b0110, // Overflow; V Set
 `define VC 4'b0111, // No overflow; V Clear
 `define HI 4'b1000, // Unsigned HIgher; C set and Z clear
 `define LS 4'b1001, // Unsigned Lower or Same; C clear or Z set
 `define GE 4'b1010, // Signed Greater than or Equal to; N equals V
 `define LT 4'b1011, // Signed Less Than; N not same as V
 `define GT 4'b1100, // Signed Greater Than; Z clear and N equals V
 `define LE 4'b1101, // Signed Less than or Equal; Z set or N not same as V
 `define AL 4'b1110, // ALways; any status bits OK -- usually omitted
 `define S  4'b1111, // Status update (code for NeVer, i.e., reserved)

 `define IB  6'b110000, // Increment Before (used with LDR/STR)
 `define IBW 6'b110010, // Increment Before with write back
 `define IA  6'b100000, // Increment After (implies write back)

//
//---------------- Memory containing "ARM" program ----------------
//
module ProgMod (adr, clk, reset, instr);
 input  [6:0] adr;
 input clk, reset;
 output [31:0] instr;
 
 parameter R0  = 16'h1000; // General purpose register set names
 parameter R1  = 16'h1001;
 parameter R2  = 16'h1002;
 parameter R3  = 16'h1003;
 parameter R4  = 16'h1004;
 parameter R5  = 16'h1005;
 parameter R6  = 16'h1006;
 parameter R7  = 16'h1007;
 parameter R8  = 16'h1008;
 parameter R9  = 16'h1009;
 parameter R10 = 16'h100A;
 parameter R11 = 16'h100B;
 parameter R12 = 16'h100C;
 parameter R13 = 16'h100D; // a.k.a. "SP"
 parameter R14 = 16'h100E; // a.k.a. "LR"
 parameter R15 = 16'h100F; // a.k.a. "PC"
 parameter SP  = 16'h100D; // a.k.a. "R13"
 parameter LR  = 16'h100E; // a.k.a. "R14"

 parameter LSL = 16'h1000;  // Logical Shift Left
 parameter LSR = 16'h1001;  // Logical Shift Right
 parameter ASR = 16'h1002;  // Algebraic Shift Right
 parameter ROR = 16'h1003;  // Rotate (circular) Right

 integer IP;

// ----- Tasks and Functions that implement the "assembler" -----

// Task asdp is called by the data processing opcode macros `SUB, `AND, ...
// The number of parameters will vary between three and eight.
 // `SUB`EQ`S  R1,R2,R3,LSR,R4  `_8 // General format with 8 parameters
 // `SUB       R1,R2            `_3 // Many parameters are optional

 task asdp ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6,P7;
  {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]}
   <= asdp1(P0,P1,P2,P3,P4,P5,P6,P7);
  IP = IP + 4;
 endtask

// Function asdp1 is called by task asdp to construct the opcode, condition, and status fields.
 // `SUB      Format 1: Always do subtraction, but don't set status
 // `SUB`S    Format 2: Always do subtraction, and also update status
 // `SUB`EQ   Format 3: Do subtraction only if Z-flag, but don't set status
 // `SUB`EQ`S Format 4: Do subtraction and update status only if Z-flag set

 function [31:0] asdp1 ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6,P7;
  if (P1 >= R0)  // Format 1
   asdp1 = 'hE<<28 | asdp2(P0,P1,P2,P3,P4,P5);
  else
   if (P1 == 'hF)  // Update the CPSR? (S flag),  Format 2
    asdp1 = 'hE<<28 | 1<<20 | asdp2(P0,P2,P3,P4,P5,P6);
   else
    if (P2 != 'hF)  // Format 3
     asdp1 = P1<<28 | asdp2(P0,P2,P3,P4,P5,P6);
    else // Format 4
     asdp1 = P1<<28 | 1<<20 | asdp2(P0,P3,P4,P5,P6,P7);
 endfunction

// Function asdp2 constructs the instruction's operand fields for function asdp1.
 // `SUB  R1,7,4    Format 1: Rd = Rd - constant
 // `SUB  R1,R2     Format 2: Rd = Rd - Rm
 // `SUB  R1,R2,7,4 Format 3: Rd = Rn - constant
 // `SUB  R1,R2,R3  Format 4: Rd = Rn - Rm
 // For MOV and MVN, force Rn to be 0

 function [31:0] asdp2 ();
  input [15:0] opCode, Q1, Q2, Q3, Q4, Q5;
  if (opCode[3:2]=='b10) // TST, TEQ, CMP, CMN
   asdp2 = 1<<20 | asdp3(opCode, R0, Q1, Q2, Q3, Q4);
  else
   if (opCode==13 || opCode==15) // MOV, MVN
    asdp2 = opCode<<21 | asdp4(Q1, R0, Q2, Q3, Q4);
   else // R1,R2
    asdp2 = asdp3(opCode, Q1, Q2, Q3, Q4, Q5);
 endfunction

// Function asdp3 constructs the instruction's operand fields for function asdp2.
 // Basically, check for omitted Rn field such as
 // `SUB  R1,7,4    Format 1: Rd = Rd - constant

 function [31:0] asdp3 ();
  input [15:0] opCode, Q1, Q2, Q3, Q4, Q5;
  if (Q3>0 && Q2>=R0) 
   asdp3 = opCode<<21 | asdp4(Q1, Q2, Q3, Q4, Q5);
  else // Rn is same as Rd
   asdp3 = opCode<<21 | asdp4(Q1, Q1, Q2, Q3, Q4);
 endfunction

// Function asdp4 fills in the Rd, Rn, and 12-bit second operand field Rm/constant.

 function [31:0] asdp4 ();
  input [15:0] Rd,Rn,Rm,Sh,Rs;
   if (Rm<R0) // Rm is a constant?
    asdp4 = 1<<25 | Rd[3:0]<<12 | Rn[3:0]<<16 | Rm[7:0] | Sh[4:1]<<8;
   else
    if (Rs<R0) // Shift value is constant?
     asdp4 = Rd[3:0]<<12 | Rn[3:0]<<16 | {Rs[4:0],Sh[1:0],1'b0,Rm[3:0]};
    else
     asdp4 = Rd[3:0]<<12 | Rn[3:0]<<16 | {Rs[3:0],1'b0,Sh[1:0],1'b1,Rm[3:0]};
 endfunction

// Task ash is called by bit-shift opcode macros `LSL, `LSR, `ASR, `ROR
// The number of parameters will vary between three and six.
 // `LSL`EQ`S  R1,R2,R3  `_6 // General format with 6 parameters.
 // `LSL       R1,R2     `_3 // Default values chosen for 3 parameters.

 task ash ();
  input [15:0] Shft,P1,P2,P3,P4,P5,P6,P7;
  {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]}
   <= ash1(Shft,P1,P2,P3,P4,P5);
  IP = IP + 4;
 endtask

// Function ash1 is called by task ash to construct a MOV instruction (4'b1101).

 function [31:0] ash1 ();
  input [15:0] Shft,P1,P2,P3,P4,P5;
  if (P5 > 0)  
   ash1 = asdp1 (4'b1101,P1,P2,P3,P4,Shft,P5,0);
  else
   if (P4 > 0)  
    if (P2 < R0)  
     ash1 = asdp1 (4'b1101,P1,P2,P3,P3,Shft,P4,0);
    else
     ash1 = asdp1 (4'b1101,P1,P2,P2,Shft,P3,0,0);
   else
    if (P3 > 0)  
     if (P1 < R0)  
      ash1 = asdp1 (4'b1101,P1,P2,P2,Shft,P3,0,0);
     else
      ash1 = asdp1 (4'b1101,P1,P2,Shft,P3,0,0,0);
    else
     ash1 = asdp1 (4'b1101,P1,P1,Shft,P2,0,0,0);
 endfunction
 
// Task asmul is called by multiplication opcode macros `MUL, `MLA, `UMULL...
// The number of parameters will vary between three and seven.
 // `MLA`EQ`S  R1,R2,R3,R4      `_7 // General format with 7 parameters
 // `MUL       R1,R2            `_3 // Some parameters are optional

 task asmul ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6,P7;
  {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]}
   <= asmul1(P0,P1,P2,P3,P4,P5,P6);
  IP = IP + 4;
 endtask

// Function asmul1 is called by task asmul to construct the opcode, condition, and status fields.
 // `MUL      Format 1: Always multiply, but don't set status
 // `MUL`S    Format 2: Always multiply, and also update status
 // `MUL`EQ   Format 3: Multiply only if Z-flag, but don't set status
 // `MUL`EQ`S Format 4: Multiply and update status only if Z-flag set

 function [31:0] asmul1 ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6;
  if (P1 >= R0)  // Format 1
   asmul1 = 'hE<<28 | asmul2(P0,P1,P2,P3,P4);
  else
   if (P1 == 'hF)  // Update? (S flag),  Format 2
    asmul1 = 'hE<<28 | 1<<20 | asmul2(P0,P2,P3,P4,P5);
   else
    if (P2 != 'hF)  // Format 3
     asmul1 = P1<<28 | asmul2(P0,P2,P3,P4,P5);
    else // Format 4
     asmul1 = P1<<28 | 1<<20 | asmul2(P0,P3,P4,P5,P6);
 endfunction

// Function asmul2 fills the multiplication's register fields.

 function [31:0] asmul2 ();
  input [15:0] opCode, RdL, Q2, Q3, Q4;
   if (opCode==0) // MUL
    if (Q3==0) // MUL  Rd,Rm   where Rs<-Rd and Rd/Rn switched 
     asmul2 =  {RdL[3:0],4'b0,RdL[3:0],4'b1001,Q2[3:0]};
    else  // MUL Rd,Rm,Rs   where Rd/Rn switched 
     asmul2 =  {RdL[3:0],4'b0,Q3[3:0],4'b1001,Q2[3:0]};
   else
    if (opCode==1) // MLA Rd,Rm,Rs,Rn   where Rd/Rn switched
     asmul2 =  {opCode, 1'b0, RdL[3:0],Q4[3:0],Q3[3:0],4'b1001,Q2[3:0]};
    else // 64-bit products UMULL Rd,Rn,Rm,Rs
     asmul2 =  {opCode, 1'b0, Q2[3:0],RdL[3:0],Q4[3:0],4'b1001,Q3[3:0]};
 endfunction

// Task asmem is called by load/store opcode macros `LDR, `STR, ...
// The number of parameters will vary between three and eight.
 // `LDR`EQ`IA  R1,(R2),R3,LSL,4  `_8 // General format with 8 parameters
 // `LDR        R1,(R2)           `_3 // Many parameters are optional

 task asmem ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6,P7;
  {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]}
   <= asmem1(P0,P1,P2,P3,P4,P5,P6,P7);
  IP = IP + 4;
 endtask

// Function asmem1 is called by task asmem to construct the opcode, condition, and status fields.
 // `LDR       Format 1: Always load register, but don't update base register
 // `LDR`IA    Format 2: Always load register, and also update base register
 // `LDR`EQ    Format 3: Load register only if Z-flag, but don't update base register
 // `LDR`EQ`IA Format 4: Load register and update base register only if Z-flag set

 function [31:0] asmem1 ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6,P7;
  if (P1 >= R0)  // Format 1
   asmem1 = 'hE<<28 | asmem2(P0|8'h10,P1,P2,P3,P4,P5);
  else
   if (P1 > 'hF)  // `IA,`B,`IBW;  Format 2
    asmem1 = 'hE<<28 | asmem2(P0|P1,P2,P3,P4,P5,P6);
   else
    if (P2 >= R0)  // Format 3
     asmem1 = P1<<28 | asmem2(P0|8'h10,P2,P3,P4,P5,P6);
    else // Format 4
     asmem1 = P1<<28 | asmem2(P0|P2,P3,P4,P5,P6,P7);
 endfunction

// Function asmem2 constructs the instruction's operand fields for function asmem1.
 // `LDR  R1,(R2),R3,LSL,4  Format 1: Offset is scaled register
 // `LDR  R1,(R2),-4        Format 2: Offset is constant

 function [31:0] asmem2 ();
  input [15:0] PUBWL, Q1, Q2, Q3, Q4, Q5;
  if (Q3>=R0&&Q3<=R15) // Offset is scaled register
   asmem2 = {8'H68|PUBWL[4:0],Q2[3:0],Q1[3:0],Q5[4:0],Q4[1:0],Q3[4:0]};
  else
   if (Q3[12]==0) // Positive constant offset
    asmem2 = {8'H48|PUBWL[4:0],Q2[3:0],Q1[3:0],Q3[11:0]};
   else // Negative constant offset
    asmem2 = {8'H40|PUBWL[4:0],Q2[3:0],Q1[3:0],-Q3[11:0]};
 endfunction

// Task asSP is called to do PUSH or POP for only one register
 // `PUSH R5 is `STR`IB  R5,(SP),-4
 // `POP  R5 is `LDR`IAW R5,(SP),4

 task asSP ();
  input [31:0] P0,P1,P2,P3,P4,P5,P6,P7;
  begin
   if (P1>=R0) // No conditions
    {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]} <= 
     'hE<<28 | {P0,SP[3:0],P1[3:0],12'H4};
   else        // EQ, GT, ...
    {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]} <= 
     P1[3:0]<<28 | {P0,SP[3:0],P2[3:0],12'H4};
   IP = IP + 4;
  end
 endtask

// Task asdat is called by WORD, BYTE, ALIGN macros

 task asdat ();
  input [31:0] P0,P1,P2,P3,P4,P5,P6,P7;
  if (P0==0) // align
   IP = (IP+P1-1) & ~(P1-1);
  else
   if (P0==1) // byte
    begin
     progMem[IP] <= P1;
     IP = IP + 1;
    end
   else
    if (P0==4) // word
     begin
      {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]} <= P1;
      IP = IP + 4;
     end
 endtask
 
// Task asbr is called by branch opcode macros `B, `BL, and `BX
// The number of parameters will be either two and three.
 // `B`EQ  TopAdr   `_3 // General format is 3 parameters
 // `BX    R14      `_2 // Conditional parameter is optional

 task asbr ();
  input [15:0] P0,P1,P2,P3,P4,P5,P6,P7;
  {progMem[IP+3],progMem[IP+2],progMem[IP+1],progMem[IP]} <= asbr1(P0,P1,P2);
  IP = IP + 4;
 endtask

// Function asbr1 is called by task asbr to construct the condition fields.
 // `BL      Format 1: Always branch (no status change possible)
 // `BL`EQ   Format 2: Branch only if Z-flag set

 function [31:0] asbr1 ();
  input [15:0] P0,P1,P2;
  if (P2 == 0)  // Format 1
   asbr1 = 'hE<<28 | asbr2(P0,P1);
  else
   asbr1 = P1<<28 | asbr2(P0,P2);
 endfunction

// Function asbr2 fills the branch's register or address field.

 function [31:0] asbr2 ();
  input [15:0] Q0, Q1;
  integer IPoff;
  IPoff = Q1 - IP - 8;
  if (Q0 == 1)  // BX
   asbr2 = {24'h12FFF1, Q1[3:0]};
  else  // B or BL
   asbr2 = {Q0, IPoff[25:2]};
 endfunction

 reg [7:0] progMem[0:149];  // 4 bytes per instruction
 reg [31:0] IR;            // Instruction Register
 assign instr = IR;
 
 always @ (posedge(clk))
  IR <= {progMem[adr+3],progMem[adr+2],progMem[adr+1],progMem[adr]};
 always @ (posedge(reset))
  begin
   integer Fact, FLoop;
   IP = 0;
   `MOV     R0,0     `_3  // 0: Reset "boot" address

// Program to calculate factorial of numbers between 2 and 12 in SW[3:0]
//     2! =            2 =          2 H
//     6! =          720 =        2D0 H
//    12! =  479,001,600 =  1C8C,FC00 H

Fact        =  IP;        //    Program to calculate factorials
   `MOV     R6,1,2   `_4  // 1: Load 'h40000000 into base register
   `LDR     R2,(R6)  `_3  // 2: Load SW[3:0] contents
   `SUB     R1,R2,1  `_4  // 3: Initialize R1 as multiplier (loop counter).
FLoop    =  IP;           //    Loop: Calculate the factorial
   `MUL     R2,R1    `_3  // 4: On each pass, multiply by one lower
   `SUB     R1,1     `_3  // 5: Decrement multiplier for next pass.
   `CMP     R1,2     `_3  // 6: Compare multiplier to loop ending condition.
   `B`GE    FLoop    `_3  // 7: Go back until multiplier = 2.
   `STR     R2,(R6)  `_3  // 8: Copy result to output device for display
   `B       Fact     `_2  // 9: Go back for new value for factorial
	
   progMem[149] = 0;
  end
endmodule
