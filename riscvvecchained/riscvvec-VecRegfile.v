//=========================================================================
// vec regfile (chained version)
//=========================================================================
// 8 vregs, each up to VLMAX=32 elems of 32 bits.
// 3 read ports, 2 wr ports.
// extra read port + 2nd wr port lets us chain: producer reads 2 vregs
// and writes 1, consumer reads its 1 non-forwarded vreg + writes its
// dest in the same cycle. consumer's other oeprand comes combo from
// producer alu out (no regfile read needed for chained one).

`ifndef RISCV_VEC_REGFILE_V
`define RISCV_VEC_REGFILE_V

module riscv_VecRegfile
(
  input         clk,
  input         reset,

  // read port 0 - producer vs1
  input  [ 2:0] raddr0,
  input  [ 4:0] relement0,
  output [31:0] rdata0,

  // read port 1 - producer vs2
  input  [ 2:0] raddr1,
  input  [ 4:0] relement1,
  output [31:0] rdata1,

  // read port 2 - consumer non-fwd opernad
  input  [ 2:0] raddr2,
  input  [ 4:0] relement2,
  output [31:0] rdata2,

  // wr port 0 - producer dst
  input         wen0,
  input  [ 2:0] waddr0,
  input  [ 4:0] welement0,
  input  [31:0] wdata0,

  // wr port 1 - consumer dst
  input         wen1,
  input  [ 2:0] waddr1,
  input  [ 4:0] welement1,
  input  [31:0] wdata1
);

  // 8 regs x 32 elems x 32 bits
  reg [31:0] registers [0:7][0:31];

  assign rdata0 = registers[raddr0][relement0];
  assign rdata1 = registers[raddr1][relement1];
  assign rdata2 = registers[raddr2][relement2];

  // 2 wr ports. ctrl guarantees wen0/wen1 never hit the same (vreg,elem)
  // in same cycle so no tiebreaker. still split for synth.
  always @(posedge clk) begin
    if (wen0)
      registers[waddr0][welement0] <= wdata0;
    if (wen1)
      registers[waddr1][welement1] <= wdata1;
  end

endmodule

`endif
