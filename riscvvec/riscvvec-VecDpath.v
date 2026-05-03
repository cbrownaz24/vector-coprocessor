//=========================================================================
// Vector Coprocessor Datapath
//=========================================================================
// Wires together the vector register file, ALU, and mask register.
// Single-lane implementation (processes 1 element per cycle).
// The control unit iterates over elements.

`ifndef RISCV_VEC_DPATH_V
`define RISCV_VEC_DPATH_V

`include "riscvvec-VecRegfile.v"
`include "riscvvec-VecAlu.v"

module riscv_VecDpath
(
  input         clk,
  input         reset,

  // Control signals from VecCtrl
  input  [ 4:0] vec_alu_fn,
  input  [ 2:0] vd_addr,
  input  [ 2:0] vs1_addr,
  input  [ 2:0] vs2_addr,
  input  [ 4:0] elem_idx,
  input         vrf_wen,
  input         use_scalar,
  input  [31:0] scalar_val,
  input         mask_wen,
  input         mask_clear,

  // Mask register output to ctrl
  output reg [31:0] mask_reg,

  // Memory data interface
  input  [31:0] memresp_data,     // Data from memory (for loads)
  output [31:0] memreq_data,      // Data to memory (for stores)
  input         mem_load_wen,     // Write memory response to vrf

  // ALU result data (for reduction reads)
  output [31:0] vs1_rdata,

  // ALU result output (for comparison mask writes)
  output [31:0] alu_result
);

  //----------------------------------------------------------------------
  // Vector Register File
  //----------------------------------------------------------------------

  wire [31:0] vrf_rdata0;  // vs1 read data
  wire [31:0] vrf_rdata1;  // vs2 read data

  // Write data mux: ALU result or memory load data
  wire [31:0] vrf_wdata = mem_load_wen ? memresp_data : alu_result;
  wire        vrf_wen_actual = vrf_wen;

  riscv_VecRegfile vregfile
  (
    .clk       (clk),
    .reset     (reset),
    .raddr0    (vs1_addr),
    .relement0 (elem_idx),
    .rdata0    (vrf_rdata0),
    .raddr1    (vs2_addr),
    .relement1 (elem_idx),
    .rdata1    (vrf_rdata1),
    .wen       (vrf_wen_actual),
    .waddr     (vd_addr),
    .welement  (elem_idx),
    .wdata     (vrf_wdata)
  );

  //----------------------------------------------------------------------
  // ALU Operand Selection
  //----------------------------------------------------------------------

  // Operand B is either vs2 data or scalar value
  wire [31:0] alu_in1 = use_scalar ? scalar_val : vrf_rdata1;

  //----------------------------------------------------------------------
  // Vector ALU
  //----------------------------------------------------------------------

  riscv_VecAlu vec_alu
  (
    .in0 (vrf_rdata0),
    .in1 (alu_in1),
    .fn  (vec_alu_fn),
    .out (alu_result)
  );

  //----------------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------------

  // For stores, send vs1 read data to memory
  assign memreq_data = vrf_rdata0;

  // For reductions, expose vs1 read data to ctrl
  assign vs1_rdata = vrf_rdata0;

  //----------------------------------------------------------------------
  // Mask Register
  //----------------------------------------------------------------------

  always @(posedge clk) begin
    if (reset || mask_clear) begin
      mask_reg <= 32'hFFFFFFFF;   // All elements active by default
    end
    else if (mask_wen) begin
      // Write comparison result bit into mask at current element position
      mask_reg[elem_idx] <= alu_result[0];
    end
  end

endmodule

`endif
