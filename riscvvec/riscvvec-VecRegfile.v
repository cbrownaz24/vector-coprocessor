//=========================================================================
// Vector Register File
//=========================================================================
// 8 vector registers, each holding up to VLMAX (32) elements of 32 bits.
// 3 read ports, 2 write ports.
//
// The third read port and second write port enable chaining: while the
// producer reads 2 vregs and writes 1 vreg, the consumer can read 1
// non-forwarded vreg and write its own destination in the same cycle.
// The consumer's other operand is forwarded combinationally from the
// producer's ALU output (no regfile read needed for the chained operand).

`ifndef RISCV_VEC_REGFILE_V
`define RISCV_VEC_REGFILE_V

module riscv_VecRegfile
(
  input         clk,
  input         reset,

  // Read port 0 (producer vs1)
  input  [ 2:0] raddr0,
  input  [ 4:0] relement0,
  output [31:0] rdata0,

  // Read port 1 (producer vs2)
  input  [ 2:0] raddr1,
  input  [ 4:0] relement1,
  output [31:0] rdata1,

  // Read port 2 (consumer non-forwarded operand)
  input  [ 2:0] raddr2,
  input  [ 4:0] relement2,
  output [31:0] rdata2,

  // Write port 0 (producer destination)
  input         wen0,
  input  [ 2:0] waddr0,
  input  [ 4:0] welement0,
  input  [31:0] wdata0,

  // Write port 1 (consumer destination)
  input         wen1,
  input  [ 2:0] waddr1,
  input  [ 4:0] welement1,
  input  [31:0] wdata1
);

  // Storage: 8 registers x 32 elements x 32 bits
  reg [31:0] registers [0:7][0:31];

  assign rdata0 = registers[raddr0][relement0];
  assign rdata1 = registers[raddr1][relement1];
  assign rdata2 = registers[raddr2][relement2];

  // Two write ports. The control unit guarantees that wen0 and wen1
  // never target the same (vreg, element) pair in the same cycle, so
  // we don't need a tie-breaker. We still write them in two always
  // blocks to keep the synthesizer happy.
  always @(posedge clk) begin
    if (wen0)
      registers[waddr0][welement0] <= wdata0;
    if (wen1)
      registers[waddr1][welement1] <= wdata1;
  end

endmodule

`endif
