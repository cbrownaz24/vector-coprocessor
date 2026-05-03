//=========================================================================
// vec coproc top (chained version)
//=========================================================================

`ifndef RISCV_VEC_UNIT_V
`define RISCV_VEC_UNIT_V

`include "riscvvec-VecCmdQueue.v"
`include "riscvvec-VecCtrl.v"
`include "riscvvec-VecDpath.v"

module riscv_VecUnit
(
  input         clk,
  input         reset,

  // cmd side from scalar core
  input         vec_cmd_val,
  output        vec_cmd_rdy,
  input  [118:0] vec_cmd_msg,

  // status to scalar core
  output        vec_idle,
  output        vec_queue_full,

  // mem req
  output        vec_memreq_val,
  input         vec_memreq_rdy,
  output        vec_memreq_rw,
  output [31:0] vec_memreq_addr,
  output [31:0] vec_memreq_data,

  // mem resp
  input         vec_memresp_val,
  input  [31:0] vec_memresp_data,

  // reduction result -> scalar core
  output        vec_reduce_val,
  output [31:0] vec_reduce_result,
  output [ 4:0] vec_reduce_rd,

  // vfence stall sig
  output        vec_vfence_stall,

  // vl reg
  output [ 5:0] vec_vl
);

  //----------------------------------------------------------------------
  // cmd queue w/ peek-2 for chaining
  //----------------------------------------------------------------------

  wire        q_deq_val;
  wire        q_deq_rdy;
  wire [118:0] q_deq_msg;
  wire        q_deq_val_2;
  wire        q_deq_rdy_2;
  wire [118:0] q_deq_msg_2;
  wire        q_empty;
  wire        q_full;

  riscv_VecCmdQueue cmd_queue
  (
    .clk       (clk),
    .reset     (reset),
    .enq_val   (vec_cmd_val),
    .enq_rdy   (vec_cmd_rdy),
    .enq_msg   (vec_cmd_msg),
    .deq_val   (q_deq_val),
    .deq_rdy   (q_deq_rdy),
    .deq_msg   (q_deq_msg),
    .deq_val_2 (q_deq_val_2),
    .deq_msg_2 (q_deq_msg_2),
    .deq_rdy_2 (q_deq_rdy_2),
    .empty     (q_empty),
    .full      (q_full)
  );

  assign vec_queue_full = q_full;

  //----------------------------------------------------------------------
  // ctrl unit
  //----------------------------------------------------------------------

  // producer sigs
  wire [ 4:0] vec_alu_fn;
  wire [ 2:0] vd_addr;
  wire [ 2:0] vs1_addr;
  wire [ 2:0] vs2_addr;
  wire [ 4:0] elem_idx;
  wire        vrf_wen;
  wire        use_scalar_ctrl;
  wire [31:0] scalar_val_ctrl;
  wire        mask_wen;
  wire        mask_clear;
  wire [31:0] mask_reg;

  // consumer sigs
  wire        chain_active;
  wire [ 4:0] cons_alu_fn;
  wire [ 2:0] cons_vd_addr;
  wire [ 2:0] cons_vsnf_addr;
  wire        cons_vrf_wen;
  wire        cons_use_scalar;
  wire [31:0] cons_scalar_val;
  wire        cons_forward_in0;
  wire        cons_forward_in1;

  wire        ctrl_memreq_val;
  wire        ctrl_memreq_rw;
  wire [31:0] ctrl_memreq_addr;
  wire        ctrl_memresp_rdy;
  wire [ 5:0] vl_reg;

  wire [31:0] vs1_rdata_from_dpath;
  wire [31:0] alu_result;

  riscv_VecCtrl ctrl
  (
    .clk             (clk),
    .reset           (reset),

    .cmd_val         (q_deq_val),
    .cmd_rdy         (q_deq_rdy),
    .cmd_msg         (q_deq_msg),
    .cmd_val_2       (q_deq_val_2),
    .cmd_msg_2       (q_deq_msg_2),
    .cmd_rdy_2       (q_deq_rdy_2),

    .vec_idle        (vec_idle),

    .vec_alu_fn      (vec_alu_fn),
    .vd_addr         (vd_addr),
    .vs1_addr        (vs1_addr),
    .vs2_addr        (vs2_addr),
    .elem_idx        (elem_idx),
    .vrf_wen         (vrf_wen),
    .use_scalar      (use_scalar_ctrl),
    .scalar_val      (scalar_val_ctrl),
    .mask_wen        (mask_wen),
    .mask_clear      (mask_clear),
    .mask_reg        (mask_reg),

    .chain_active    (chain_active),
    .cons_alu_fn     (cons_alu_fn),
    .cons_vd_addr    (cons_vd_addr),
    .cons_vsnf_addr  (cons_vsnf_addr),
    .cons_vrf_wen    (cons_vrf_wen),
    .cons_use_scalar (cons_use_scalar),
    .cons_scalar_val (cons_scalar_val),
    .cons_forward_in0(cons_forward_in0),
    .cons_forward_in1(cons_forward_in1),

    .vec_memreq_val  (ctrl_memreq_val),
    .vec_memreq_rdy  (vec_memreq_rdy),
    .vec_memreq_rw   (ctrl_memreq_rw),
    .vec_memreq_addr (ctrl_memreq_addr),
    .vec_memresp_val (vec_memresp_val),
    .vec_memresp_data(vec_memresp_data),
    .vec_memresp_rdy (ctrl_memresp_rdy),

    .reduce_val      (vec_reduce_val),
    .reduce_result   (vec_reduce_result),
    .reduce_rd       (vec_reduce_rd),

    .vl_reg          (vl_reg),
    .vfence_stall    (vec_vfence_stall),
    .vs1_rdata       (vs1_rdata_from_dpath)
  );

  assign vec_vl = vl_reg;

  //----------------------------------------------------------------------
  // dpath
  //----------------------------------------------------------------------

  wire is_load_writeback = vec_memresp_val && !ctrl_memreq_rw;

  riscv_VecDpath dpath
  (
    .clk              (clk),
    .reset            (reset),

    .vec_alu_fn       (vec_alu_fn),
    .vd_addr          (vd_addr),
    .vs1_addr         (vs1_addr),
    .vs2_addr         (vs2_addr),
    .elem_idx         (elem_idx),
    .vrf_wen          (vrf_wen),
    .use_scalar       (use_scalar_ctrl),
    .scalar_val       (scalar_val_ctrl),
    .mask_wen         (mask_wen),
    .mask_clear       (mask_clear),

    .chain_active     (chain_active),
    .cons_alu_fn      (cons_alu_fn),
    .cons_vd_addr     (cons_vd_addr),
    .cons_vsnf_addr   (cons_vsnf_addr),
    .cons_vrf_wen     (cons_vrf_wen),
    .cons_use_scalar  (cons_use_scalar),
    .cons_scalar_val  (cons_scalar_val),
    .cons_forward_in0 (cons_forward_in0),
    .cons_forward_in1 (cons_forward_in1),

    .mask_reg         (mask_reg),

    .memresp_data     (vec_memresp_data),
    .memreq_data      (vec_memreq_data),
    .mem_load_wen     (is_load_writeback),

    .vs1_rdata        (vs1_rdata_from_dpath),
    .alu_result       (alu_result)
  );

  //----------------------------------------------------------------------
  // mem iface outs
  //----------------------------------------------------------------------

  assign vec_memreq_val  = ctrl_memreq_val;
  assign vec_memreq_rw   = ctrl_memreq_rw;
  assign vec_memreq_addr = ctrl_memreq_addr;

endmodule

`endif
