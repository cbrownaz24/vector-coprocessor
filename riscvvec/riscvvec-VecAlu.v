// vec alu, one lane
// does one 32-bit op per cycle. vec unit makes NUM_LANES copies of thisfor parallel exec
// supports add/sub/mul/div/rem, logic ops, shifts, and the cmp ops

`ifndef RISCV_VEC_ALU_V
`define RISCV_VEC_ALU_V

module riscv_VecAlu
(
  input  [31:0] in0,          // op a
  input  [31:0] in1,          // op b
  input  [ 4:0] fn,           // alu func sel
  output reg [31:0] out       // result
);

  // func encodings
  localparam VEC_ALU_ADD = 5'd0;
  localparam VEC_ALU_SUB = 5'd1;
  localparam VEC_ALU_MUL = 5'd2;
  localparam VEC_ALU_DIV = 5'd3;
  localparam VEC_ALU_REM = 5'd4;
  localparam VEC_ALU_AND = 5'd5;
  localparam VEC_ALU_OR = 5'd6;
  localparam VEC_ALU_XOR = 5'd7;
  localparam VEC_ALU_SLL = 5'd8;
  localparam VEC_ALU_SRL = 5'd9;
  localparam VEC_ALU_SRA = 5'd10;
  localparam VEC_ALU_SEQ = 5'd11;
  localparam VEC_ALU_SLT = 5'd12;
  localparam VEC_ALU_SLE = 5'd13;
  localparam VEC_ALU_SGT = 5'd14;
  localparam VEC_ALU_SGE = 5'd15;
  localparam VEC_ALU_SNE = 5'd16;

  // signed views for cmp
  wire signed [31:0] in0_s = in0;
  wire signed [31:0] in1_s = in1;

  // signed div/rem
  wire signed [31:0] div_result = in0_s / in1_s;
  wire signed [31:0] rem_result = in0_s % in1_s;

  // signed shft
  wire signed [31:0] sra_result = in0_s >>> in1[4:0];

  always @(*) begin
    case (fn)
      VEC_ALU_ADD: out = in0 + in1;
      VEC_ALU_SUB: out = in0 - in1;
      VEC_ALU_MUL: out = in0 * in1;
      VEC_ALU_DIV: out = (in1 != 32'd0) ? div_result : 32'hFFFFFFFF;
      VEC_ALU_REM: out = (in1 != 32'd0) ? rem_result : in0;
      VEC_ALU_AND: out = in0 & in1;
      VEC_ALU_OR: out = in0 | in1;
      VEC_ALU_XOR: out = in0 ^ in1;
      VEC_ALU_SLL: out = in0 << in1[4:0];
      VEC_ALU_SRL: out = in0 >> in1[4:0];
      VEC_ALU_SRA: out = sra_result;
      VEC_ALU_SEQ: out = {31'd0, (in0 == in1)};
      VEC_ALU_SLT: out = {31'd0, (in0_s < in1_s)};
      VEC_ALU_SLE: out = {31'd0, (in0_s <= in1_s)};
      VEC_ALU_SGT: out = {31'd0, (in0_s > in1_s)};
      VEC_ALU_SGE: out = {31'd0, (in0_s >= in1_s)};
      VEC_ALU_SNE: out = {31'd0, (in0 != in1)};
      default: out = 32'bx;
    endcase
  end

endmodule

`endif
