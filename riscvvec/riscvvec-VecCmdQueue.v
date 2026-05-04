//=========================================================================
// Vector Command Queue
//=========================================================================
// 4-entry FIFO queue between the scalar core and the vector unit.
// Exposes the head AND the second entry so the control unit can detect
// chaining opportunities and dequeue two commands in one cycle.

`ifndef RISCV_VEC_CMD_QUEUE_V
`define RISCV_VEC_CMD_QUEUE_V

module riscv_VecCmdQueue
(
  input         clk,
  input         reset,

  // Enqueue interface (from scalar core)
  input         enq_val,
  output        enq_rdy,
  input  [118:0] enq_msg,

  // Dequeue interface (head entry)
  output        deq_val,
  input         deq_rdy,
  output [118:0] deq_msg,

  // Peek at second entry (for chaining)
  output        deq_val_2,
  output [118:0] deq_msg_2,
  input         deq_rdy_2,    // when high together with deq_rdy, double-dequeue

  // Status
  output        empty,
  output        full
);

  localparam NUM_ENTRIES = 4;
  localparam PTR_SZ = 2;

  reg [118:0] entries [0:NUM_ENTRIES-1];
  reg [PTR_SZ:0] head;
  reg [PTR_SZ:0] tail;

  wire [PTR_SZ-1:0] head_idx = head[PTR_SZ-1:0];
  wire [PTR_SZ-1:0] tail_idx = tail[PTR_SZ-1:0];
  wire [PTR_SZ-1:0] head_idx_p1 = head_idx + 1'b1;

  // Occupancy: tail - head, in modular arithmetic with the extra MSB
  wire [PTR_SZ:0] occupancy = tail - head;

  assign empty = (head == tail);
  assign full  = (head_idx == tail_idx) && (head[PTR_SZ] != tail[PTR_SZ]);

  assign enq_rdy = !full;
  assign deq_val = !empty;
  assign deq_msg = entries[head_idx];

  // Second-entry peek: only valid if at least 2 entries occupied
  assign deq_val_2 = (occupancy >= 3'd2);
  assign deq_msg_2 = entries[head_idx_p1];

  always @(posedge clk) begin
    if (reset) begin
      head <= 0;
      tail <= 0;
    end
    else begin
      if (enq_val && enq_rdy) begin
        entries[tail_idx] <= enq_msg;
        tail <= tail + 1;
      end
      // Single or double dequeue
      if (deq_val && deq_rdy) begin
        if (deq_rdy_2 && deq_val_2)
          head <= head + 2;
        else
          head <= head + 1;
      end
    end
  end

endmodule

`endif
