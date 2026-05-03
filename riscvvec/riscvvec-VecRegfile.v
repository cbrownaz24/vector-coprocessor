//=========================================================================
// Vector Register File
//=========================================================================
// 8 vector registers, each holding up to VLMAX (32) elements of 32 bits.
// Provides 2 read ports and 1 write port per lane.
// Lane-addressed: each cycle, one element index is presented and all
// lanes read/write the element at that index from/to their respective
// vector registers.

`ifndef RISCV_VEC_REGFILE_V
`define RISCV_VEC_REGFILE_V

module riscv_VecRegfile
(
  input         clk,
  input         reset,

  // Read port 0
  input  [ 2:0] raddr0,       // Vector register index (0-7)
  input  [ 4:0] relement0,    // Element index (0-31)
  output [31:0] rdata0,       // Read data

  // Read port 1
  input  [ 2:0] raddr1,       // Vector register index (0-7)
  input  [ 4:0] relement1,    // Element index (0-31)
  output [31:0] rdata1,       // Read data

  // Write port
  input         wen,          // Write enable
  input  [ 2:0] waddr,        // Vector register index (0-7)
  input  [ 4:0] welement,     // Element index (0-31)
  input  [31:0] wdata         // Write data
);

  // Storage: 8 registers x 32 elements x 32 bits
  // Organized as a flat array: registers[vreg_index][element_index]
  reg [31:0] registers [0:7][0:31];

  // Combinational read ports
  assign rdata0 = registers[raddr0][relement0];
  assign rdata1 = registers[raddr1][relement1];

  // Write port - active on rising edge when wen is asserted
  always @(posedge clk) begin
    if (wen) begin
      registers[waddr][welement] <= wdata;
    end
  end

endmodule

`endif
