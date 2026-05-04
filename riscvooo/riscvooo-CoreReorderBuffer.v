//=========================================================================
// 5-Stage RISCV Reorder Buffer
//=========================================================================

`ifndef RISCV_CORE_REORDERBUFFER_V
`define RISCV_CORE_REORDERBUFFER_V

module riscv_CoreReorderBuffer
(
  input         clk,
  input         reset,

  input         rob_alloc_req_val,
  output        rob_alloc_req_rdy,
  input  [ 4:0] rob_alloc_req_preg,
  
  output [ 3:0] rob_alloc_resp_slot,

  input         rob_fill_val,
  input  [ 3:0] rob_fill_slot,

  output        rob_commit_wen,
  output [ 3:0] rob_commit_slot,
  output [ 4:0] rob_commit_rf_waddr
);

  // State bits
  reg rob_valid [15:0]; // entry is between execute and commit
  reg rob_pending [15:0]; // entry needs to be committed
  reg [4:0] rob_preg [15:0]; // arch reg to commit to

  // head, next free
  reg [3:0] head;
  reg [3:0] tail;

  // combinational
  wire rob_full = rob_valid[tail]; // if tail wraps back to a valid, full

  assign rob_alloc_req_rdy = !rob_full;
  assign rob_alloc_resp_slot = tail;

  // commit when valid and ready
  assign rob_commit_wen = rob_valid[head] && !rob_pending[head];
  assign rob_commit_slot = head;
  assign rob_commit_rf_waddr = rob_preg[head];

  // seq
  integer i; // incrementing
  always @(posedge clk) begin
    if (reset) begin
      head <= 4'b0;
      tail <= 4'b0;
      for (i = 0; i < 16; i = i + 1) begin // set all to 0
        rob_valid[i] <= 1'b0;
        rob_pending[i] <= 1'b0;
        rob_preg[i] <= 5'b0;
      end
    end else begin

      // put in rob if ready
      if (rob_alloc_req_val && rob_alloc_req_rdy) begin
        rob_valid[tail] <= 1'b1;
        rob_pending[tail] <= 1'b1;
        rob_preg[tail] <= rob_alloc_req_preg;
        tail <= tail + 4'd1;  // wraps on overflow
      end

      // mark as not pending once filled
      if (rob_fill_val) begin
        rob_pending[rob_fill_slot] <= 1'b0;
      end

      // move head on commit
      if (rob_commit_wen) begin
        rob_valid[head] <= 1'b0;
        head <= head + 4'd1;  // wraps
      end
    end
  end

endmodule

`endif

