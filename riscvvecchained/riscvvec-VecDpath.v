//=========================================================================
// vec coproc dpath (chained version)
//=========================================================================
// 2 fus (producer alu + consumer alu) so a chained producer/consumer
// pair can run in lockstep on the same elem.
// consumer's chained opernad is forwarded combo from producer alu out,
// so we dont need to read the (just-written) regfile slot.

`ifndef RISCV_VEC_DPATH_V
`define RISCV_VEC_DPATH_V

`include "riscvvec-VecRegfile.v"
`include "riscvvec-VecAlu.v"

module riscv_VecDpath
(
  input         clk,
  input         reset,

  // producer ctrl sigs
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

  // consumer ctrl sigs (chain mode)
  input         chain_active,         // 1 = consumer running this cycle
  input  [ 4:0] cons_alu_fn,
  input  [ 2:0] cons_vd_addr,
  input  [ 2:0] cons_vsnf_addr,       // non-fwd src vreg
  input         cons_vrf_wen,
  input         cons_use_scalar,
  input  [31:0] cons_scalar_val,
  input         cons_forward_in0,     // fwd producer out -> in0
  input         cons_forward_in1,     // fwd producer out -> in1

  // mask reg out to ctrl
  output reg [31:0] mask_reg,

  // mem data side
  input  [31:0] memresp_data,
  output [31:0] memreq_data,
  input         mem_load_wen,

  // reduction read
  output [31:0] vs1_rdata,

  // producer alu result (for cmp mask wrs)
  output [31:0] alu_result
);

  //----------------------------------------------------------------------
  // vrf - 3 read, 2 wr
  //----------------------------------------------------------------------

  wire [31:0] vrf_rdata0;  // prod vs1
  wire [31:0] vrf_rdata1;  // prod vs2
  wire [31:0] vrf_rdata2;  // cons non-fwd opernad

  wire [31:0] prod_alu_out;
  wire [31:0] cons_alu_out;

  // producer wdata: alu out OR load resp
  wire [31:0] prod_wdata = mem_load_wen ? memresp_data : prod_alu_out;
  wire        prod_wen   = vrf_wen;

  // consumer wdata: just cons alu out (cant be a mem op or chain a load
  // in this min impl)
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
  // producer alu
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
  // consumer alu w/ fwd muxes
  //----------------------------------------------------------------------
  // in0: fwd path OR rf read 2
  // in1: scalar OR fwd path OR rf read 2
  // ctrl guarantees:
  //   - cons_forward_in0=1 -> cons_vs1 == prod_vd; in0 takes fwd val,
  //     vrf_rdata2 (if used) gives cons_vs2.
  //   - cons_forward_in1=1 -> cons_vs2 == prod_vd; in1 takes fwd val,
  //     vrf_rdata2 (if used) gives cons_vs1.
  //   - both fwd_in0 + fwd_in1 set -> cmd2 reads prod_vd on both, both
  //     cons inputs get fwd val, vrf_rdata2 unused.
  //   - cons_use_scalar=1 (cat-VS cons) overrides in1 w/ scalar.

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
  // outs
  //----------------------------------------------------------------------

  // store data = producer vs1 read
  assign memreq_data = vrf_rdata0;

  // reductions read producer vs1
  assign vs1_rdata = vrf_rdata0;

  // expose producer alu out for cmp mask wrs
  assign alu_result = prod_alu_out;

  //----------------------------------------------------------------------
  // mask reg - producer cmps only (cons in chain mode is restrcited
  // to non-cmp arith)
  //----------------------------------------------------------------------

  always @(posedge clk) begin
    if (reset || mask_clear) begin
      mask_reg <= 32'hFFFFFFFF;
    end
    else if (mask_wen) begin
      mask_reg[elem_idx] <= prod_alu_out[0];
    end
  end

  // shut up unused warning when not chaining
  wire _unused_chain = chain_active;

endmodule

`endif
