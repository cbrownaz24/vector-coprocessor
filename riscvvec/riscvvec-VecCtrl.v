//=========================================================================
// Vector Coprocessor Control Unit (FSM) - v3 (combinational outputs)
//=========================================================================

`ifndef RISCV_VEC_CTRL_V
`define RISCV_VEC_CTRL_V

module riscv_VecCtrl
(
  input         clk,
  input         reset,

  input         cmd_val,
  output        cmd_rdy,
  input  [118:0] cmd_msg,

  output        vec_idle,

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

  output reg        vec_memreq_val,
  input             vec_memreq_rdy,
  output reg        vec_memreq_rw,
  output reg [31:0] vec_memreq_addr,
  input             vec_memresp_val,
  input      [31:0] vec_memresp_data,
  output reg        vec_memresp_rdy,

  output reg        reduce_val,
  output reg [31:0] reduce_result,
  output reg [ 4:0] reduce_rd,

  output reg [ 5:0] vl_reg,
  output reg        vfence_stall,

  input      [31:0] vs1_rdata
);

  // Command fields
  wire [ 6:0] cmd_opcode_fn = cmd_msg[6:0];
  wire [ 2:0] cmd_vd        = cmd_msg[9:7];
  wire [ 2:0] cmd_vs1       = cmd_msg[12:10];
  wire [ 2:0] cmd_vs2       = cmd_msg[15:13];
  wire [31:0] cmd_scalar    = cmd_msg[47:16];
  wire [31:0] cmd_base_addr = cmd_msg[79:48];
  wire [31:0] cmd_stride    = cmd_msg[111:80];
  wire [ 4:0] cmd_rd_scalar = cmd_msg[116:112];
  wire [ 1:0] cmd_category  = cmd_msg[118:117];

  // Constants
  localparam S_IDLE = 3'd0, S_EXEC = 3'd1, S_LOAD = 3'd2, S_LWAIT = 3'd3;
  localparam S_STORE = 3'd4, S_REDUCE = 3'd5;
  localparam CAT_VV = 2'd0, CAT_VS = 2'd1, CAT_MEM = 2'd2, CAT_CFG = 2'd3;

  reg [2:0] state;

  // Latched command
  reg [ 2:0] lat_vd, lat_vs1, lat_vs2;
  reg [31:0] lat_scalar, lat_base_addr, lat_stride;
  reg [ 4:0] lat_rd_scalar, lat_alu_fn;
  reg [ 1:0] lat_category;
  reg [ 3:0] lat_sub_opcode;
  reg        lat_is_cmp, lat_is_reduce, lat_use_scalar;

  reg [ 5:0] elem_count;
  reg [31:0] mem_addr;
  reg [31:0] reduce_acc;

  assign cmd_rdy = (state == S_IDLE) && cmd_val;
  assign vec_idle = (state == S_IDLE) && !cmd_val;

  //----------------------------------------------------------------------
  // Combinational output logic - drives datapath THIS cycle
  //----------------------------------------------------------------------
  always @(*) begin
    // Defaults
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

    case (state)
      S_IDLE: begin
        if (cmd_val && cmd_category == CAT_CFG) begin
          if (cmd_opcode_fn[3:0] == 4'd0) begin // SETVL
            reduce_val = 1'b1;
            reduce_rd = cmd_rd_scalar;
            reduce_result = (cmd_scalar[5:0] > 6'd32) ? 32'd32 : {26'd0, cmd_scalar[5:0]};
          end
          if (cmd_opcode_fn[3:0] == 4'd1) // CVM
            mask_clear = 1'b1;
        end
      end

      S_EXEC: begin
        elem_idx = elem_count[4:0];
        vd_addr = lat_vd;
        vs1_addr = lat_vs1;
        vs2_addr = lat_vs2;
        vec_alu_fn = lat_alu_fn;
        use_scalar = lat_use_scalar;
        scalar_val = lat_scalar;
        if (elem_count < vl_reg) begin
          if (mask_reg[elem_count[4:0]]) begin
            if (lat_is_cmp)
              mask_wen = 1'b1;
            else
              vrf_wen = 1'b1;
          end
        end
      end

      S_LOAD: begin
        vec_memreq_val = 1'b1;
        vec_memreq_rw = 1'b0;
        vec_memreq_addr = mem_addr;
        elem_idx = elem_count[4:0];
        vd_addr = lat_vd;
      end

      S_LWAIT: begin
        elem_idx = elem_count[4:0];
        vd_addr = lat_vd;
        if (vec_memresp_val && mask_reg[elem_count[4:0]])
          vrf_wen = 1'b1;
      end

      S_STORE: begin
        vec_memreq_val = 1'b1;
        vec_memreq_rw = 1'b1;
        vec_memreq_addr = mem_addr;
        elem_idx = elem_count[4:0];
        vs1_addr = lat_vs1;
      end

      S_REDUCE: begin
        elem_idx = elem_count[4:0];
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
  // Registered state transitions
  //----------------------------------------------------------------------
  always @(posedge clk) begin
    if (reset) begin
      state <= S_IDLE;
      vl_reg <= 6'd4;
      elem_count <= 0;
      reduce_acc <= 0;
    end
    else begin

      // Debug output (uncomment for debugging)
      // `ifndef SYNTHESIS
      // if (state != S_IDLE || cmd_val)
      //   $display("VEC_CTRL: st=%0d ec=%0d/%0d mval=%b mrdy=%b mresp=%b addr=%08h",
      //     state, elem_count, vl_reg, vec_memreq_val, vec_memreq_rdy, vec_memresp_val, vec_memreq_addr);
      // `endif

      case (state)
        S_IDLE: begin
          if (cmd_val) begin
            // Latch command
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

            // ALU function
            if (cmd_opcode_fn[4])
              lat_alu_fn <= 5'd11 + {1'b0, cmd_opcode_fn[3:0]};
            else
              lat_alu_fn <= {1'b0, cmd_opcode_fn[3:0]};

            // Transition
            case (cmd_category)
              CAT_VV: begin
                if (cmd_opcode_fn[5])
                  state <= (vl_reg == 0) ? S_IDLE : S_REDUCE;
                else
                  state <= (vl_reg == 0) ? S_IDLE : S_EXEC;
              end
              CAT_VS:
                state <= (vl_reg == 0) ? S_IDLE : S_EXEC;
              CAT_MEM: begin
                if (vl_reg == 0)
                  state <= S_IDLE;
                else if (cmd_opcode_fn[0] == 1'b0) // VLW or VLWS (funct7 bit 0 = 0)
                  state <= S_LOAD;
                else
                  state <= S_STORE;
              end
              CAT_CFG: begin
                // Handle immediately, stay in IDLE
                if (cmd_opcode_fn[3:0] == 4'd0) begin // SETVL
                  vl_reg <= (cmd_scalar[5:0] > 6'd32) ? 6'd32 : cmd_scalar[5:0];
                end
                // CVM handled combinationally above
                state <= S_IDLE;
              end
            endcase

            // Reduction accumulator init
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
          // Accumulate
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
