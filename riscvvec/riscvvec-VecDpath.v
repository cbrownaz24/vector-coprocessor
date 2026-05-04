// hooks up vrf, alu, and mask reg
// single lane (1 elem/cycle). ctrl walks the elems

`ifndef RISCV_VEC_DPATH_V
`define RISCV_VEC_DPATH_V

`include "riscvvec-VecRegfile.v"
`include "riscvvec-VecAlu.v"

module riscv_VecDpath
(
  input clk,
  input reset,

  // ctrl sigs from VecCtrl
  input [ 4:0] vec_alu_fn,
  input [ 2:0] vd_addr,
  input [ 2:0] vs1_addr,
  input [ 2:0] vs2_addr,
  input [ 4:0] elem_idx,
  input vrf_wen,
  input use_scalar,
  input [31:0] scalar_val,
  input mask_wen,
  input mask_clear,

  // mask reg out to ctrl
  output reg [31:0] mask_reg,

  // mem data side
  input [31:0] memresp_data, // load resp data
  output [31:0] memreq_data, // store data
  input mem_load_wen, // write mem resp into vrf

  // for reduction reads
  output [31:0] vs1_rdata,

  // alu result out (used for cmp mask wr)
  output [31:0] alu_result
);

  // VRF
  wire [31:0] vrf_rdata0; // vs1 read
  wire [31:0] vrf_rdata1; // vs2 read

  // wdata mux: alu result or load data
  wire [31:0] vrf_wdata = mem_load_wen ? memresp_data : alu_result;
  wire vrf_wen_actual = vrf_wen;

  riscv_VecRegfile vregfile
  (
    .clk (clk),
    .reset (reset),
    .raddr0 (vs1_addr),
    .relement0 (elem_idx),
    .rdata0 (vrf_rdata0),
    .raddr1 (vs2_addr),
    .relement1 (elem_idx),
    .rdata1 (vrf_rdata1),
    .wen (vrf_wen_actual),
    .waddr (vd_addr),
    .welement (elem_idx),
    .wdata (vrf_wdata)
  );

  // alu opernad sel; op b: vs2 data or scalar
  wire [31:0] alu_in1 = use_scalar ? scalar_val : vrf_rdata1;

  // vec alu
  riscv_VecAlu vec_alu
  (
    .in0 (vrf_rdata0),
    .in1 (alu_in1),
    .fn (vec_alu_fn),
    .out (alu_result)
  );

  // outputs: stores: send vs1 read to mem, reductions: expose vs1 read to ctrl
  assign memreq_data = vrf_rdata0;
  assign vs1_rdata = vrf_rdata0;

  // mask reg
  always @(posedge clk) begin
    if (reset || mask_clear) begin
      mask_reg <= 32'hFFFFFFFF; // all elems active by default
    end
    else if (mask_wen) begin
      // wr cmp bit into mask at curr elem pos
      mask_reg[elem_idx] <= alu_result[0];
    end
  end

  // Suppress unused warning when not chaining
  wire _unused_chain = chain_active;

endmodule

`endif
