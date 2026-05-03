// 8 vregs, each up to VLMAX=32 elems of 32 bits
// 2 read ports, 1 write port per lane
// each cycle one elem idx is presented and all lanes do the read/write
// at that idx from/to their vregs

`ifndef RISCV_VEC_REGFILE_V
`define RISCV_VEC_REGFILE_V

module riscv_VecRegfile
(
  input clk,
  input reset,

  // read port 0
  input [ 2:0] raddr0, // vreg idx 0-7
  input [ 4:0] relement0, // elem idx 0-31
  output [31:0] rdata0, // read data

  // read port 1
  input [ 2:0] raddr1, // vreg idx 0-7
  input [ 4:0] relement1, // elem idx 0-31
  output [31:0] rdata1, // read data

  // write port
  input wen, // wr enable
  input [ 2:0] waddr, // vreg idx 0-7
  input [ 4:0] welement, // elem idx 0-31
  input [31:0] wdata // wr data
);

  // 8 regs x 32 elems x 32 bits, flat: registers[vreg][elem]
  reg [31:0] registers [0:7][0:31];

  // combo reads
  assign rdata0 = registers[raddr0][relement0];
  assign rdata1 = registers[raddr1][relement1];

  // wr on posedge if wen
  always @(posedge clk) begin
    if (wen) begin
      registers[waddr][welement] <= wdata;
    end
  end

endmodule

`endif
