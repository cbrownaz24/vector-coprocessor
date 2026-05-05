//=========================================================================
// 5-Stage RISCV Core with Vector Coprocessor
//=========================================================================

`ifndef RISCV_CORE_V
`define RISCV_CORE_V

`include "vc-MemReqMsg.v"
`include "vc-MemRespMsg.v"
`include "riscvvec-CoreCtrl.v"
`include "riscvvec-CoreDpath.v"
`include "riscvvec-VecUnit.v"

module riscv_Core
(
  input         clk,
  input         reset,

  // Instruction Memory Request Port

  output [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] imemreq_msg,
  output                                 imemreq_val,
  input                                  imemreq_rdy,

  // Instruction Memory Response Port

  input [`VC_MEM_RESP_MSG_SZ(32)-1:0] imemresp_msg,
  input                               imemresp_val,

  // Data Memory Request Port

  output [`VC_MEM_REQ_MSG_SZ(32,32)-1:0] dmemreq_msg,
  output                                 dmemreq_val,
  input                                  dmemreq_rdy,

  // Data Memory Response Port

  input [`VC_MEM_RESP_MSG_SZ(32)-1:0] dmemresp_msg,
  input                               dmemresp_val,

  // CSR Status Register Output to Host

  output [31:0] csr_status
);

  wire [31:0] imemreq_msg_addr;
  wire [31:0] imemresp_msg_data;

  // Scalar core data memory signals (before arbitration)
  wire        scalar_dmemreq_msg_rw;
  wire  [1:0] scalar_dmemreq_msg_len;
  wire [31:0] scalar_dmemreq_msg_addr;
  wire [31:0] scalar_dmemreq_msg_data;
  wire [31:0] dmemresp_msg_data;

  wire  [1:0] pc_mux_sel_Phl;
  wire  [1:0] op0_byp_mux_sel_Dhl;
  wire  [1:0] op0_mux_sel_Dhl;
  wire  [1:0] op1_byp_mux_sel_Dhl;
  wire  [2:0] op1_mux_sel_Dhl;
  wire [31:0] inst_Dhl;
  wire  [3:0] alu_fn_Xhl;
  wire  [2:0] muldivreq_msg_fn_Xhl;
  wire        muldivreq_val;
  wire        muldivreq_rdy;
  wire        muldivresp_val;
  wire        muldivresp_rdy;
  wire        muldiv_mux_sel_Xhl;
  wire        execute_mux_sel_Xhl;
  wire  [2:0] dmemresp_mux_sel_Mhl;
  wire        dmemresp_queue_en_Mhl;
  wire        dmemresp_queue_val_Mhl;
  wire        wb_mux_sel_Mhl;
  wire        rf_wen_Whl;
  wire  [4:0] rf_waddr_Whl;
  wire        stall_Fhl;
  wire        stall_Dhl;
  wire        stall_Xhl;
  wire        stall_Mhl;
  wire        stall_Whl;

  wire        branch_cond_eq_Xhl;
  wire        branch_cond_ne_Xhl;
  wire        branch_cond_lt_Xhl;
  wire        branch_cond_ltu_Xhl;
  wire        branch_cond_ge_Xhl;
  wire        branch_cond_geu_Xhl;
  wire [31:0] proc2csr_data_Whl;

  // Vector coprocessor interface wires
  wire         vec_cmd_val_Dhl;
  wire         vec_cmd_rdy;
  wire [118:0] vec_cmd_msg_Dhl;
  wire         vec_idle;
  wire         vec_queue_full;
  wire         vec_reduce_val;
  wire [31:0]  vec_reduce_result;
  wire [ 4:0]  vec_reduce_rd;

  // Vector memory interface wires
  wire        vec_memreq_val;
  wire        vec_memreq_rdy;
  wire        vec_memreq_rw;
  wire [31:0] vec_memreq_addr;
  wire [31:0] vec_memreq_data;
  wire        vec_memresp_val;
  wire [31:0] vec_memresp_data;

  // Scalar datapath bypass outputs (needed for vector command packing)
  wire [31:0] op0_byp_mux_out_Dhl_wire;
  wire [31:0] op1_byp_mux_out_Dhl_wire;

  //----------------------------------------------------------------------
  // Memory Arbitration
  //----------------------------------------------------------------------

  wire vec_mem_active = !vec_idle;

  // Actual memory request signals (after arbitration)
  wire        dmemreq_msg_rw;
  wire  [1:0] dmemreq_msg_len;
  wire [31:0] dmemreq_msg_addr;
  wire [31:0] dmemreq_msg_data;

  assign dmemreq_msg_rw   = vec_mem_active ? vec_memreq_rw          : scalar_dmemreq_msg_rw;
  assign dmemreq_msg_len  = vec_mem_active ? 2'd0                   : scalar_dmemreq_msg_len;
  assign dmemreq_msg_addr = vec_mem_active ? vec_memreq_addr        : scalar_dmemreq_msg_addr;
  assign dmemreq_msg_data = vec_mem_active ? vec_memreq_data        : scalar_dmemreq_msg_data;

  // Memory ready/valid routing
  assign vec_memreq_rdy  = vec_mem_active ? dmemreq_rdy  : 1'b0;
  assign vec_memresp_val  = vec_mem_active ? dmemresp_val : 1'b0;
  assign vec_memresp_data = dmemresp_msg_data;

  // Scalar core sees dmemreq_rdy only when vector is not active
  wire scalar_dmemreq_rdy  = vec_mem_active ? 1'b0 : dmemreq_rdy;
  wire scalar_dmemresp_val = vec_mem_active ? 1'b0 : dmemresp_val;

  //----------------------------------------------------------------------
  // Pack Memory Request Messages
  //----------------------------------------------------------------------

  vc_MemReqMsgToBits#(32,32) imemreq_msg_to_bits
  (
    .type (`VC_MEM_REQ_MSG_TYPE_READ),
    .addr (imemreq_msg_addr),
    .len  (2'd0),
    .data (32'bx),
    .bits (imemreq_msg)
  );

  vc_MemReqMsgToBits#(32,32) dmemreq_msg_to_bits
  (
    .type (dmemreq_msg_rw),
    .addr (dmemreq_msg_addr),
    .len  (dmemreq_msg_len),
    .data (dmemreq_msg_data),
    .bits (dmemreq_msg)
  );

  // dmemreq_val: either scalar or vector has a valid request
  wire scalar_dmemreq_val;
  assign dmemreq_val = vec_mem_active ? vec_memreq_val : scalar_dmemreq_val;

  //----------------------------------------------------------------------
  // Unpack Memory Response Messages
  //----------------------------------------------------------------------

  vc_MemRespMsgFromBits#(32) imemresp_msg_from_bits
  (
    .bits (imemresp_msg),
    .type (),
    .len  (),
    .data (imemresp_msg_data)
  );

  vc_MemRespMsgFromBits#(32) dmemresp_msg_from_bits
  (
    .bits (dmemresp_msg),
    .type (),
    .len  (),
    .data (dmemresp_msg_data)
  );

  //----------------------------------------------------------------------
  // Vector Command Message Assembly
  //----------------------------------------------------------------------
  // The ctrl module provides a template with register indices.
  // We fill in the scalar values from the datapath's bypass muxes.

  // Detect instruction types for proper operand routing
  wire is_vec_inst_core = (inst_Dhl[6:0] == 7'b0001011);
  wire is_setvl       = is_vec_inst_core && (inst_Dhl[14:12] == 3'b011)
                      && (inst_Dhl[31:25] == 7'b0000000);
  // VSW: funct3=010, funct7=0000001. rs1 field = vector src, rs2 field = base addr
  wire is_vsw         = is_vec_inst_core && (inst_Dhl[14:12] == 3'b010)
                      && (inst_Dhl[31:25] == 7'b0000001);

  // scalar_val: for SETVL use rs1 (op0), for VS_ARITH use rs2 (op1)
  wire [31:0] vec_scalar_val = is_setvl ? op0_byp_mux_out_Dhl_wire : op1_byp_mux_out_Dhl_wire;

  // base_addr: for VSW use rs2 (op1), for everything else use rs1 (op0)
  wire [31:0] vec_base_addr = is_vsw ? op1_byp_mux_out_Dhl_wire : op0_byp_mux_out_Dhl_wire;

  // stride: always rs2 (op1) for strided ops
  wire [31:0] vec_stride_val = op1_byp_mux_out_Dhl_wire;

  wire [118:0] vec_cmd_msg_final = {
    vec_cmd_msg_Dhl[118:117],         // [118:117] category
    vec_cmd_msg_Dhl[116:112],         // [116:112] rd_scalar
    vec_stride_val,                   // [111:80]  stride / rs2 value
    vec_base_addr,                    // [79:48]   base_addr
    vec_scalar_val,                   // [47:16]   scalar_val
    vec_cmd_msg_Dhl[15:0]             // [15:0]    vs2, vs1, vd, opcode_fn
  };

  //----------------------------------------------------------------------
  // Control Unit
  //----------------------------------------------------------------------

  riscv_CoreCtrl ctrl
  (
    .clk                    (clk),
    .reset                  (reset),

    // Instruction Memory Port

    .imemreq_val            (imemreq_val),
    .imemreq_rdy            (imemreq_rdy),
    .imemresp_msg_data      (imemresp_msg_data),
    .imemresp_val           (imemresp_val),

    // Data Memory Port

    .dmemreq_msg_rw         (scalar_dmemreq_msg_rw),
    .dmemreq_msg_len        (scalar_dmemreq_msg_len),
    .dmemreq_val            (scalar_dmemreq_val),
    .dmemreq_rdy            (scalar_dmemreq_rdy),
    .dmemresp_val           (scalar_dmemresp_val),

    // Controls Signals (ctrl->dpath)

    .pc_mux_sel_Phl         (pc_mux_sel_Phl),
    .op0_byp_mux_sel_Dhl    (op0_byp_mux_sel_Dhl),
    .op0_mux_sel_Dhl        (op0_mux_sel_Dhl),
    .op1_byp_mux_sel_Dhl    (op1_byp_mux_sel_Dhl),
    .op1_mux_sel_Dhl        (op1_mux_sel_Dhl),
    .inst_Dhl               (inst_Dhl),
    .alu_fn_Xhl             (alu_fn_Xhl),
    .muldivreq_msg_fn_Xhl   (muldivreq_msg_fn_Xhl),
    .muldivreq_val          (muldivreq_val),
    .muldivreq_rdy          (muldivreq_rdy),
    .muldivresp_val         (muldivresp_val),
    .muldivresp_rdy         (muldivresp_rdy),
    .muldiv_mux_sel_Xhl     (muldiv_mux_sel_Xhl),
    .execute_mux_sel_Xhl    (execute_mux_sel_Xhl),
    .dmemresp_mux_sel_Mhl   (dmemresp_mux_sel_Mhl),
    .dmemresp_queue_en_Mhl  (dmemresp_queue_en_Mhl),
    .dmemresp_queue_val_Mhl (dmemresp_queue_val_Mhl),
    .wb_mux_sel_Mhl         (wb_mux_sel_Mhl),
    .rf_wen_out_Whl         (rf_wen_Whl),
    .rf_waddr_Whl           (rf_waddr_Whl),
    .stall_Fhl              (stall_Fhl),
    .stall_Dhl              (stall_Dhl),
    .stall_Xhl              (stall_Xhl),
    .stall_Mhl              (stall_Mhl),
    .stall_Whl              (stall_Whl),

    // Control Signals (dpath->ctrl)

    .branch_cond_eq_Xhl     (branch_cond_eq_Xhl),
    .branch_cond_ne_Xhl     (branch_cond_ne_Xhl),
    .branch_cond_lt_Xhl     (branch_cond_lt_Xhl),
    .branch_cond_ltu_Xhl    (branch_cond_ltu_Xhl),
    .branch_cond_ge_Xhl     (branch_cond_ge_Xhl),
    .branch_cond_geu_Xhl    (branch_cond_geu_Xhl),
    .proc2csr_data_Whl      (proc2csr_data_Whl),

    // CSR Status

    .csr_status             (csr_status),

    // Vector Coprocessor Interface

    .vec_cmd_val_Dhl_out    (vec_cmd_val_Dhl),
    .vec_cmd_rdy            (vec_cmd_rdy),
    .vec_cmd_msg_Dhl_out    (vec_cmd_msg_Dhl),
    .vec_idle               (vec_idle),
    .vec_reduce_val         (vec_reduce_val),
    .vec_reduce_result      (vec_reduce_result),
    .vec_reduce_rd          (vec_reduce_rd)
  );

  //----------------------------------------------------------------------
  // Datapath
  //----------------------------------------------------------------------

  riscv_CoreDpath dpath
  (
    .clk                     (clk),
    .reset                   (reset),

    // Instruction Memory Port

    .imemreq_msg_addr        (imemreq_msg_addr),

    // Data Memory Port

    .dmemreq_msg_addr        (scalar_dmemreq_msg_addr),
    .dmemreq_msg_data        (scalar_dmemreq_msg_data),
    .dmemresp_msg_data       (dmemresp_msg_data),

    // Controls Signals (ctrl->dpath)

    .pc_mux_sel_Phl          (pc_mux_sel_Phl),
    .op0_byp_mux_sel_Dhl     (op0_byp_mux_sel_Dhl),
    .op0_mux_sel_Dhl         (op0_mux_sel_Dhl),
    .op1_byp_mux_sel_Dhl     (op1_byp_mux_sel_Dhl),
    .op1_mux_sel_Dhl         (op1_mux_sel_Dhl),
    .inst_Dhl                (inst_Dhl),
    .alu_fn_Xhl              (alu_fn_Xhl),
    .muldivreq_msg_fn_Xhl    (muldivreq_msg_fn_Xhl),
    .muldivreq_val           (muldivreq_val),
    .muldivreq_rdy           (muldivreq_rdy),
    .muldivresp_val          (muldivresp_val),
    .muldivresp_rdy          (muldivresp_rdy),
    .muldiv_mux_sel_Xhl      (muldiv_mux_sel_Xhl),
    .execute_mux_sel_Xhl     (execute_mux_sel_Xhl),
    .dmemresp_mux_sel_Mhl    (dmemresp_mux_sel_Mhl),
    .dmemresp_queue_en_Mhl   (dmemresp_queue_en_Mhl),
    .dmemresp_queue_val_Mhl  (dmemresp_queue_val_Mhl),
    .wb_mux_sel_Mhl          (wb_mux_sel_Mhl),
    .rf_wen_Whl              (rf_wen_Whl),
    .rf_waddr_Whl            (rf_waddr_Whl),
    .stall_Fhl               (stall_Fhl),
    .stall_Dhl               (stall_Dhl),
    .stall_Xhl               (stall_Xhl),
    .stall_Mhl               (stall_Mhl),
    .stall_Whl               (stall_Whl),

    // Control Signals (dpath->ctrl)

    .branch_cond_eq_Xhl      (branch_cond_eq_Xhl),
    .branch_cond_ne_Xhl      (branch_cond_ne_Xhl),
    .branch_cond_lt_Xhl      (branch_cond_lt_Xhl),
    .branch_cond_ltu_Xhl     (branch_cond_ltu_Xhl),
    .branch_cond_ge_Xhl      (branch_cond_ge_Xhl),
    .branch_cond_geu_Xhl     (branch_cond_geu_Xhl),
    .proc2csr_data_Whl       (proc2csr_data_Whl),

    // Vector bypass mux outputs (for command packing)
    .op0_byp_mux_out_Dhl_out (op0_byp_mux_out_Dhl_wire),
    .op1_byp_mux_out_Dhl_out (op1_byp_mux_out_Dhl_wire),

    // Vector reduction writeback
    .vec_reduce_val          (vec_reduce_val),
    .vec_reduce_result       (vec_reduce_result),
    .vec_reduce_rd           (vec_reduce_rd)
  );

  //----------------------------------------------------------------------
  // Vector Coprocessor
  //----------------------------------------------------------------------

  wire [5:0] vec_vl;
  wire       vec_vfence_stall;

  riscv_VecUnit vecunit
  (
    .clk               (clk),
    .reset             (reset),

    // Command interface
    .vec_cmd_val       (vec_cmd_val_Dhl),
    .vec_cmd_rdy       (vec_cmd_rdy),
    .vec_cmd_msg       (vec_cmd_msg_final),

    // Status
    .vec_idle          (vec_idle),
    .vec_queue_full    (vec_queue_full),

    // Memory interface
    .vec_memreq_val    (vec_memreq_val),
    .vec_memreq_rdy    (vec_memreq_rdy),
    .vec_memreq_rw     (vec_memreq_rw),
    .vec_memreq_addr   (vec_memreq_addr),
    .vec_memreq_data   (vec_memreq_data),
    .vec_memresp_val   (vec_memresp_val),
    .vec_memresp_data  (vec_memresp_data),

    // Reduction result
    .vec_reduce_val    (vec_reduce_val),
    .vec_reduce_result (vec_reduce_result),
    .vec_reduce_rd     (vec_reduce_rd),

    // VFENCE
    .vec_vfence_stall  (vec_vfence_stall),

    // Vector length
    .vec_vl            (vec_vl)
  );

endmodule

`endif

// vim: set textwidth=0 ts=2 sw=2 sts=2 :
