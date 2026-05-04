//=========================================================================
// Vector Coprocessor Datapath
//=========================================================================
// Two functional units (producer ALU + consumer ALU) so a chained
// producer/consumer pair can execute in lockstep on the same element.
// The consumer's chained operand is forwarded combinationally from the
// producer ALU output, avoiding the need to read the producer's result
// from the (newly-written) register file.

`ifndef RISCV_VEC_DPATH_V
`define RISCV_VEC_DPATH_V

`include "riscvvec-VecRegfile.v"
`include "riscvvec-VecAlu.v"

module riscv_VecDpath
(
  input         clk,
  input         reset,

  // Producer control signals
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

  // Consumer control signals (chain mode)
  input         chain_active,         // 1 = consumer is active this cycle
  input  [ 4:0] cons_alu_fn,
  input  [ 2:0] cons_vd_addr,
  input  [ 2:0] cons_vsnf_addr,       // non-forwarded source vreg
  input         cons_vrf_wen,
  input         cons_use_scalar,
  input  [31:0] cons_scalar_val,
  input         cons_forward_in0,     // forward producer output to in0
  input         cons_forward_in1,     // forward producer output to in1

  // Mask register output to ctrl
  output reg [31:0] mask_reg,

  // Memory data interface
  input  [31:0] memresp_data,
  output [31:0] memreq_data,
  input         mem_load_wen,

  // Reduction read
  output [31:0] vs1_rdata,

  // Producer ALU result (for comparison mask writes)
  output [31:0] alu_result
);

  //----------------------------------------------------------------------
  // Vector Register File (3 read, 2 write)
  //----------------------------------------------------------------------

  wire [31:0] vrf_rdata0;  // producer vs1
  wire [31:0] vrf_rdata1;  // producer vs2
  wire [31:0] vrf_rdata2;  // consumer non-forwarded operand

  wire [31:0] prod_alu_out;
  wire [31:0] cons_alu_out;

  // Producer write data: ALU result OR memory load response
  wire [31:0] prod_wdata = mem_load_wen ? memresp_data : prod_alu_out;
  wire        prod_wen   = vrf_wen;

  // Consumer write data: only the consumer ALU result (consumer cannot
  // be a memory op or a chain target of a load in this minimum impl)
  wire [31:0] cons_wdata = cons_alu_out;
  wire        cons_wen   = cons_vrf_wen;

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
    .raddr2    (cons_vsnf_addr),
    .relement2 (elem_idx),
    .rdata2    (vrf_rdata2),
    .wen0      (prod_wen),
    .waddr0    (vd_addr),
    .welement0 (elem_idx),
    .wdata0    (prod_wdata),
    .wen1      (cons_wen),
    .waddr1    (cons_vd_addr),
    .welement1 (elem_idx),
    .wdata1    (cons_wdata)
  );

  //----------------------------------------------------------------------
  // Producer ALU
  //----------------------------------------------------------------------

  wire [31:0] prod_in1 = use_scalar ? scalar_val : vrf_rdata1;

  riscv_VecAlu prod_alu
  (
    .in0 (vrf_rdata0),
    .in1 (prod_in1),
    .fn  (vec_alu_fn),
    .out (prod_alu_out)
  );

  //----------------------------------------------------------------------
  // Consumer ALU with forwarding muxes
  //----------------------------------------------------------------------
  // in0: forward path OR regfile read 2
  // in1: scalar OR forward path OR regfile read 2
  //
  // The control unit guarantees:
  //   - cons_forward_in0=1 means cons_vs1 == prod_vd; in0 takes the
  //     forwarded value, and vrf_rdata2 (if used) provides cons_vs2.
  //   - cons_forward_in1=1 means cons_vs2 == prod_vd; in1 takes the
  //     forwarded value, and vrf_rdata2 (if used) provides cons_vs1.
  //   - When both forward_in0 and forward_in1 are 1 (cmd2 reads
  //     prod_vd on both operands), both consumer inputs get the
  //     forwarded value and vrf_rdata2 is unused.
  //   - cons_use_scalar=1 (cat-VS consumer) overrides in1 with the
  //     scalar value.

  wire [31:0] cons_in0 = cons_forward_in0 ? prod_alu_out : vrf_rdata2;
  wire [31:0] cons_in1 = cons_use_scalar  ? cons_scalar_val :
                         cons_forward_in1 ? prod_alu_out :
                                            vrf_rdata2;

  riscv_VecAlu cons_alu_inst
  (
    .in0 (cons_in0),
    .in1 (cons_in1),
    .fn  (cons_alu_fn),
    .out (cons_alu_out)
  );

  //----------------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------------

  // Memory store data comes from producer's vs1 read
  assign memreq_data = vrf_rdata0;

  // Reductions read producer's vs1
  assign vs1_rdata = vrf_rdata0;

  // Producer ALU result exposed for comparison mask writes
  assign alu_result = prod_alu_out;

  //----------------------------------------------------------------------
  // Mask Register (driven by producer comparisons only; consumer in
  // chain mode is restricted to non-comparison arithmetic)
  //----------------------------------------------------------------------

  always @(posedge clk) begin
    if (reset || mask_clear) begin
      mask_reg <= 32'hFFFFFFFF;
    end
    else if (mask_wen) begin
      mask_reg[elem_idx] <= prod_alu_out[0];
    end
  end

  // Suppress unused warning when not chaining
  wire _unused_chain = chain_active;

endmodule

`endif
