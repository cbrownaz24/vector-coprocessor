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

  // cmd fields
  wire [ 6:0] cmd_opcode_fn = cmd_msg[6:0];
  wire [ 2:0] cmd_vd        = cmd_msg[9:7];
  wire [ 2:0] cmd_vs1       = cmd_msg[12:10];
  wire [ 2:0] cmd_vs2       = cmd_msg[15:13];
  wire [31:0] cmd_scalar    = cmd_msg[47:16];
  wire [31:0] cmd_base_addr = cmd_msg[79:48];
  wire [31:0] cmd_stride    = cmd_msg[111:80];
  wire [ 4:0] cmd_rd_scalar = cmd_msg[116:112];
  wire [ 1:0] cmd_category  = cmd_msg[118:117];

  // consts
  localparam S_IDLE = 3'd0, S_EXEC = 3'd1, S_LOAD = 3'd2, S_LWAIT = 3'd3;
  localparam S_STORE = 3'd4, S_REDUCE = 3'd5;
  localparam CAT_VV = 2'd0, CAT_VS = 2'd1, CAT_MEM = 2'd2, CAT_CFG = 2'd3;

  reg [3:0] state;

  //----------------------------------------------------------------------
  // Latched producer (cmd1) fields
  //----------------------------------------------------------------------

  // latched cmd
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

  always @(*) begin
    // defaults
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
        if (cmd_val && cmd_category == CAT_CFG) begin
          if (cmd_opcode_fn[3:0] == 4'd0) begin // setvl
            reduce_val = 1'b1;
            reduce_rd = cmd_rd_scalar;
            // clamp to VLMAX=32
            reduce_result = (cmd_scalar > 32'd32) ? 32'd32 : {26'd0, cmd_scalar[5:0]};
          end
          if (cmd_opcode_fn[3:0] == 4'd1) // cvm
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
          // publish *final* acc val combo. the registered update `reduce_acc <= reduce_acc + vs1_rdata` fires next clk edge 
          // but scalar regfile wr via reduce_val/result fires **this** cycle so we have to fold in the last elem here
          reduce_val = 1'b1;
          case (lat_sub_opcode[1:0])
            2'd0:    reduce_result = reduce_acc + vs1_rdata;
            2'd1:    reduce_result = reduce_acc & vs1_rdata;
            2'd2:    reduce_result = reduce_acc | vs1_rdata;
            default: reduce_result = reduce_acc;
          endcase
          reduce_rd = lat_rd_scalar;
        end
      end
    endcase
  end

  // registered state transitions
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
            // latch cmd
            lat_vd <= cmd_vd;
            lat_vs1 <= cmd_vs1;
            lat_vs2 <= cmd_vs2;
            lat_scalar <= cmd_scalar;
            lat_base_addr <= cmd_base_addr;
            lat_stride <= cmd_stride;
            lat_rd_scalar <= cmd_rd_scalar;
            lat_category <= cmd_category;
            lat_sub_opcode <= cmd_opcode_fn[3:0];
            lat_is_cmp <= cmd_opcode_fn[4];
            lat_is_reduce <= cmd_opcode_fn[5];
            lat_use_scalar <= (cmd_category == CAT_VS);
            elem_count <= 0;
            mem_addr <= cmd_base_addr;

            // alu func
            if (cmd_opcode_fn[4])
              lat_alu_fn <= 5'd11 + {1'b0, cmd_opcode_fn[3:0]};
            else
              lat_alu_fn <= {1'b0, cmd_opcode_fn[3:0]};

            // transition
            case (cmd_category)
              CAT_VV: begin
                if (cmd_opcode_fn[5])
                  state <= (vl_reg == 0) ? S_IDLE : S_REDUCE;
                else
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
                else if (cmd_opcode_fn[0] == 1'b0) // vlw or vlws (funct7 bit 0 = 0)
                  state <= S_LOAD;
                else
                  state <= S_STORE;
              end
              CAT_CFG: begin
                // handle now, stay in IDLE
                if (cmd_opcode_fn[3:0] == 4'd0) begin // setvl
                  vl_reg <= (cmd_scalar > 32'd32) ? 6'd32 : cmd_scalar[5:0];
                end
                // cvm handled combo above
                state <= S_IDLE;
              end
            endcase

            // reduction acc init
            if (cmd_opcode_fn[5]) begin
              if (cmd_opcode_fn[1:0] == 2'd1)
                reduce_acc <= 32'hFFFFFFFF;
              else
                reduce_acc <= 32'd0;
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
          // acc
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
