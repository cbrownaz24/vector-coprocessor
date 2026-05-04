//=========================================================================
// Vector Coprocessor Control Unit (FSM) - chaining edition
//=========================================================================
// Adds a chain-issue path: when the head of the command queue is an
// arithmetic op and the second entry has a RAW dependency on it, both
// commands are dequeued together and executed in lockstep in
// S_EXEC_CHAIN. The consumer's chained operand is forwarded from the
// producer's ALU output (combinational), and the consumer's other
// operand comes from the regfile's third read port.

`ifndef RISCV_VEC_CTRL_V
`define RISCV_VEC_CTRL_V

module riscv_VecCtrl
(
  input         clk,
  input         reset,

  // Head-of-queue command interface
  input         cmd_val,
  output        cmd_rdy,
  input  [118:0] cmd_msg,

  // Second-entry peek (for chaining)
  input         cmd_val_2,
  input  [118:0] cmd_msg_2,
  output        cmd_rdy_2,

  output        vec_idle,

  // Producer datapath signals
  output reg [ 4:0] vec_alu_fn,
  output reg [ 2:0] vd_addr,
  output reg [ 2:0] vs1_addr,
  output reg [ 2:0] vs2_addr,
  output reg [ 4:0] elem_idx,
  output reg        vrf_wen,
  output reg        use_scalar,
  output reg [31:0] scalar_val,
  output reg        mask_wen,
  output reg        mask_clear,
  input      [31:0] mask_reg,

  // Consumer datapath signals (chain mode)
  output reg        chain_active,
  output reg [ 4:0] cons_alu_fn,
  output reg [ 2:0] cons_vd_addr,
  output reg [ 2:0] cons_vsnf_addr,
  output reg        cons_vrf_wen,
  output reg        cons_use_scalar,
  output reg [31:0] cons_scalar_val,
  output reg        cons_forward_in0,
  output reg        cons_forward_in1,

  // Memory interface
  output reg        vec_memreq_val,
  input             vec_memreq_rdy,
  output reg        vec_memreq_rw,
  output reg [31:0] vec_memreq_addr,
  input             vec_memresp_val,
  input      [31:0] vec_memresp_data,
  output reg        vec_memresp_rdy,

  // Reduction result back to scalar core
  output reg        reduce_val,
  output reg [31:0] reduce_result,
  output reg [ 4:0] reduce_rd,

  output reg [ 5:0] vl_reg,
  output reg        vfence_stall,

  input      [31:0] vs1_rdata
);

  //----------------------------------------------------------------------
  // Command field extraction
  //----------------------------------------------------------------------

  // cmd1 (head)
  wire [ 6:0] cmd1_opcode_fn = cmd_msg[6:0];
  wire [ 2:0] cmd1_vd        = cmd_msg[9:7];
  wire [ 2:0] cmd1_vs1       = cmd_msg[12:10];
  wire [ 2:0] cmd1_vs2       = cmd_msg[15:13];
  wire [31:0] cmd1_scalar    = cmd_msg[47:16];
  wire [31:0] cmd1_base_addr = cmd_msg[79:48];
  wire [31:0] cmd1_stride    = cmd_msg[111:80];
  wire [ 4:0] cmd1_rd_scalar = cmd_msg[116:112];
  wire [ 1:0] cmd1_category  = cmd_msg[118:117];
  wire        cmd1_is_cmp    = cmd1_opcode_fn[4];
  wire        cmd1_is_reduce = cmd1_opcode_fn[5];

  // cmd2 (second entry, peeked)
  wire [ 6:0] cmd2_opcode_fn = cmd_msg_2[6:0];
  wire [ 2:0] cmd2_vd        = cmd_msg_2[9:7];
  wire [ 2:0] cmd2_vs1       = cmd_msg_2[12:10];
  wire [ 2:0] cmd2_vs2       = cmd_msg_2[15:13];
  wire [31:0] cmd2_scalar    = cmd_msg_2[47:16];
  wire [ 1:0] cmd2_category  = cmd_msg_2[118:117];
  wire        cmd2_is_cmp    = cmd2_opcode_fn[4];
  wire        cmd2_is_reduce = cmd2_opcode_fn[5];

  //----------------------------------------------------------------------
  // States
  //----------------------------------------------------------------------

  localparam S_IDLE       = 4'd0;
  localparam S_EXEC       = 4'd1;
  localparam S_LOAD       = 4'd2;
  localparam S_LWAIT      = 4'd3;
  localparam S_STORE      = 4'd4;
  localparam S_REDUCE     = 4'd5;
  localparam S_EXEC_CHAIN = 4'd6;

  localparam CAT_VV = 2'd0, CAT_VS = 2'd1, CAT_MEM = 2'd2, CAT_CFG = 2'd3;

  reg [3:0] state;

  //----------------------------------------------------------------------
  // Latched producer (cmd1) fields
  //----------------------------------------------------------------------

  reg [ 2:0] lat_vd, lat_vs1, lat_vs2;
  reg [31:0] lat_scalar, lat_base_addr, lat_stride;
  reg [ 4:0] lat_rd_scalar, lat_alu_fn;
  reg [ 1:0] lat_category;
  reg [ 3:0] lat_sub_opcode;
  reg        lat_is_cmp, lat_is_reduce, lat_use_scalar;

  // Latched consumer (cmd2) fields, valid when chain_pending=1
  reg [ 2:0] lat_cons_vd, lat_cons_vs1, lat_cons_vs2, lat_cons_vsnf;
  reg [31:0] lat_cons_scalar;
  reg [ 4:0] lat_cons_alu_fn;
  reg        lat_cons_use_scalar;
  reg        lat_cons_forward_in0;
  reg        lat_cons_forward_in1;
  reg        chain_pending;  // set when latching; cleared at end of S_EXEC_CHAIN

  reg [ 5:0] elem_count;
  reg [31:0] mem_addr;
  reg [31:0] reduce_acc;

  //----------------------------------------------------------------------
  // Chain-detection (combinational)
  //----------------------------------------------------------------------
  // Both cmd1 and cmd2 must be plain arithmetic (CAT_VV or CAT_VS,
  // non-comparison, non-reduction). We require cmd2 to RAW-depend on
  // cmd1's destination, and forbid WAW/WAR for safety.

  wire cmd1_chainable_prod =
       cmd_val &&
       (cmd1_category == CAT_VV || cmd1_category == CAT_VS) &&
       !cmd1_is_cmp && !cmd1_is_reduce;

  wire cmd2_chainable_cons =
       cmd_val_2 &&
       (cmd2_category == CAT_VV || cmd2_category == CAT_VS) &&
       !cmd2_is_cmp && !cmd2_is_reduce;

  // RAW: cmd2 reads cmd1's destination
  wire cmd2_reads_cmd1_vd_via_vs1 = (cmd2_vs1 == cmd1_vd);
  wire cmd2_reads_cmd1_vd_via_vs2 = (cmd2_category == CAT_VV) &&
                                    (cmd2_vs2 == cmd1_vd);
  wire raw_dep = cmd2_reads_cmd1_vd_via_vs1 || cmd2_reads_cmd1_vd_via_vs2;

  // WAW: cmd2 writes the same register cmd1 writes
  wire waw_haz = (cmd2_vd == cmd1_vd);

  // WAR: cmd2 writes a register cmd1 reads. Producer reads its vs1
  // every cycle; vs2 only if CAT_VV.
  wire war_haz = (cmd2_vd == cmd1_vs1) ||
                 ((cmd1_category == CAT_VV) && (cmd2_vd == cmd1_vs2));

  wire chain_possible = cmd1_chainable_prod &&
                        cmd2_chainable_cons &&
                        raw_dep && !waw_haz && !war_haz &&
                        (vl_reg != 0);

  // Forwarding flags computed at detection time
  wire detect_forward_in0 = cmd2_reads_cmd1_vd_via_vs1;
  wire detect_forward_in1 = cmd2_reads_cmd1_vd_via_vs2;
  wire [2:0] detect_cons_vsnf =
       detect_forward_in0 ? cmd2_vs2 : cmd2_vs1;

  //----------------------------------------------------------------------
  // Queue handshake
  //----------------------------------------------------------------------

  assign cmd_rdy   = (state == S_IDLE) && cmd_val;
  assign cmd_rdy_2 = (state == S_IDLE) && cmd_val && chain_possible;
  assign vec_idle  = (state == S_IDLE) && !cmd_val;

  //----------------------------------------------------------------------
  // Combinational output logic
  //----------------------------------------------------------------------

  always @(*) begin
    // Producer defaults
    vrf_wen = 1'b0;
    mask_wen = 1'b0;
    mask_clear = 1'b0;
    vec_memreq_val = 1'b0;
    vec_memreq_rw = 1'b0;
    vec_memreq_addr = mem_addr;
    vec_memresp_rdy = 1'b1;
    reduce_val = 1'b0;
    reduce_result = reduce_acc;
    reduce_rd = lat_rd_scalar;
    vfence_stall = 1'b0;
    vec_alu_fn = lat_alu_fn;
    vd_addr = lat_vd;
    vs1_addr = lat_vs1;
    vs2_addr = lat_vs2;
    elem_idx = elem_count[4:0];
    use_scalar = lat_use_scalar;
    scalar_val = lat_scalar;

    // Consumer defaults (off when not chaining)
    chain_active     = 1'b0;
    cons_alu_fn      = lat_cons_alu_fn;
    cons_vd_addr     = lat_cons_vd;
    cons_vsnf_addr   = lat_cons_vsnf;
    cons_vrf_wen     = 1'b0;
    cons_use_scalar  = lat_cons_use_scalar;
    cons_scalar_val  = lat_cons_scalar;
    cons_forward_in0 = lat_cons_forward_in0;
    cons_forward_in1 = lat_cons_forward_in1;

    case (state)
      S_IDLE: begin
        if (cmd_val && cmd1_category == CAT_CFG) begin
          if (cmd1_opcode_fn[3:0] == 4'd0) begin // SETVL
            reduce_val = 1'b1;
            reduce_rd = cmd1_rd_scalar;
            reduce_result = (cmd1_scalar[5:0] > 6'd32) ? 32'd32 :
                            {26'd0, cmd1_scalar[5:0]};
          end
          if (cmd1_opcode_fn[3:0] == 4'd1) // CVM
            mask_clear = 1'b1;
        end
      end

      S_EXEC: begin
        if (elem_count < vl_reg) begin
          if (mask_reg[elem_count[4:0]]) begin
            if (lat_is_cmp)
              mask_wen = 1'b1;
            else
              vrf_wen = 1'b1;
          end
        end
      end

      S_EXEC_CHAIN: begin
        chain_active = 1'b1;
        if (elem_count < vl_reg) begin
          if (mask_reg[elem_count[4:0]]) begin
            // Producer is plain arithmetic in chain mode (cmp ruled out)
            vrf_wen = 1'b1;
            cons_vrf_wen = 1'b1;
          end
        end
      end

      S_LOAD: begin
        vec_memreq_val = 1'b1;
        vec_memreq_rw = 1'b0;
      end

      S_LWAIT: begin
        if (vec_memresp_val && mask_reg[elem_count[4:0]])
          vrf_wen = 1'b1;
      end

      S_STORE: begin
        vec_memreq_val = 1'b1;
        vec_memreq_rw = 1'b1;
        vs1_addr = lat_vs1;
      end

      S_REDUCE: begin
        vs1_addr = lat_vs1;
        if (elem_count + 1 >= vl_reg) begin
          reduce_val = 1'b1;
          reduce_result = reduce_acc;
          reduce_rd = lat_rd_scalar;
        end
      end
    endcase
  end

  //----------------------------------------------------------------------
  // Sequential state
  //----------------------------------------------------------------------

  // Helper: decode an arithmetic command's alu_fn
  // (consumer can never be a comparison in chain mode, so simpler)
  function [4:0] decode_alu_fn;
    input [6:0] opcode_fn;
    begin
      if (opcode_fn[4])
        decode_alu_fn = 5'd11 + {1'b0, opcode_fn[3:0]};
      else
        decode_alu_fn = {1'b0, opcode_fn[3:0]};
    end
  endfunction

  always @(posedge clk) begin
    if (reset) begin
      state <= S_IDLE;
      vl_reg <= 6'd4;
      elem_count <= 0;
      reduce_acc <= 0;
      chain_pending <= 1'b0;
      lat_cons_forward_in0 <= 1'b0;
      lat_cons_forward_in1 <= 1'b0;
      lat_cons_use_scalar  <= 1'b0;
    end
    else begin
      case (state)
        S_IDLE: begin
          if (cmd_val) begin
            // Latch producer
            lat_vd <= cmd1_vd;
            lat_vs1 <= cmd1_vs1;
            lat_vs2 <= cmd1_vs2;
            lat_scalar <= cmd1_scalar;
            lat_base_addr <= cmd1_base_addr;
            lat_stride <= cmd1_stride;
            lat_rd_scalar <= cmd1_rd_scalar;
            lat_category <= cmd1_category;
            lat_sub_opcode <= cmd1_opcode_fn[3:0];
            lat_is_cmp <= cmd1_is_cmp;
            lat_is_reduce <= cmd1_is_reduce;
            lat_use_scalar <= (cmd1_category == CAT_VS);
            lat_alu_fn <= decode_alu_fn(cmd1_opcode_fn);
            elem_count <= 0;
            mem_addr <= cmd1_base_addr;

            // Maybe latch consumer for chaining
            if (chain_possible) begin
              lat_cons_vd          <= cmd2_vd;
              lat_cons_vs1         <= cmd2_vs1;
              lat_cons_vs2         <= cmd2_vs2;
              lat_cons_vsnf        <= detect_cons_vsnf;
              lat_cons_scalar      <= cmd2_scalar;
              lat_cons_alu_fn      <= decode_alu_fn(cmd2_opcode_fn);
              lat_cons_use_scalar  <= (cmd2_category == CAT_VS);
              lat_cons_forward_in0 <= detect_forward_in0;
              lat_cons_forward_in1 <= detect_forward_in1;
              chain_pending        <= 1'b1;
              state                <= (vl_reg == 0) ? S_IDLE : S_EXEC_CHAIN;
            end
            else begin
              chain_pending <= 1'b0;
              // Plain (non-chained) dispatch — original logic
              case (cmd1_category)
                CAT_VV: begin
                  if (cmd1_is_reduce)
                    state <= (vl_reg == 0) ? S_IDLE : S_REDUCE;
                  else
                    state <= (vl_reg == 0) ? S_IDLE : S_EXEC;
                end
                CAT_VS:
                  state <= (vl_reg == 0) ? S_IDLE : S_EXEC;
                CAT_MEM: begin
                  if (vl_reg == 0)
                    state <= S_IDLE;
                  else if (cmd1_opcode_fn[0] == 1'b0)
                    state <= S_LOAD;
                  else
                    state <= S_STORE;
                end
                CAT_CFG: begin
                  if (cmd1_opcode_fn[3:0] == 4'd0)
                    vl_reg <= (cmd1_scalar[5:0] > 6'd32) ? 6'd32 :
                              cmd1_scalar[5:0];
                  state <= S_IDLE;
                end
              endcase

              // Reduction accumulator init
              if (cmd1_is_reduce) begin
                if (cmd1_opcode_fn[1:0] == 2'd1)
                  reduce_acc <= 32'hFFFFFFFF;
                else
                  reduce_acc <= 32'd0;
              end
            end
          end
        end

        S_EXEC: begin
          if (elem_count < vl_reg)
            elem_count <= elem_count + 1;
          if (elem_count + 1 >= vl_reg)
            state <= S_IDLE;
        end

        S_EXEC_CHAIN: begin
          if (elem_count < vl_reg)
            elem_count <= elem_count + 1;
          if (elem_count + 1 >= vl_reg) begin
            state <= S_IDLE;
            chain_pending <= 1'b0;
          end
        end

        S_LOAD: begin
          if (vec_memreq_rdy)
            state <= S_LWAIT;
        end

        S_LWAIT: begin
          if (vec_memresp_val) begin
            elem_count <= elem_count + 1;
            if (lat_sub_opcode[1])
              mem_addr <= mem_addr + lat_stride;
            else
              mem_addr <= mem_addr + 32'd4;
            if (elem_count + 1 >= vl_reg)
              state <= S_IDLE;
            else
              state <= S_LOAD;
          end
        end

        S_STORE: begin
          if (vec_memreq_rdy) begin
            elem_count <= elem_count + 1;
            if (lat_sub_opcode[1])
              mem_addr <= mem_addr + lat_stride;
            else
              mem_addr <= mem_addr + 32'd4;
            if (elem_count + 1 >= vl_reg)
              state <= S_IDLE;
          end
        end

        S_REDUCE: begin
          case (lat_sub_opcode[1:0])
            2'd0: reduce_acc <= reduce_acc + vs1_rdata;
            2'd1: reduce_acc <= reduce_acc & vs1_rdata;
            2'd2: reduce_acc <= reduce_acc | vs1_rdata;
          endcase
          elem_count <= elem_count + 1;
          if (elem_count + 1 >= vl_reg)
            state <= S_IDLE;
        end
      endcase
    end
  end

endmodule

`endif
