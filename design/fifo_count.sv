// Synchronous FIFO, method A: a count register gives full and empty.
// This is the FIFO used in the UART echo (uart-rtl-validation-spartan7), converted to SystemVerilog.
module fifo_count #(
  parameter int WIDTH = 8,     // bits per slot
  parameter int DEPTH = 16     // number of slots
)(
  input  logic             i_Clk,
  // write side
  input  logic             i_Wr_En,
  input  logic [WIDTH-1:0] i_Wr_Data,
  // read side
  input  logic             i_Rd_En,
  output logic [WIDTH-1:0] o_Rd_Data,
  // status
  output logic             o_Empty,
  output logic             o_Full
);

  localparam int PTR_W = $clog2(DEPTH);       // 16 slots - 4-bit pointers

  // ---------- storage ----------
  logic [WIDTH-1:0] r_Mem [DEPTH];
  logic [PTR_W-1:0] r_Wr_Ptr = '0;            // where the next byte goes
  logic [PTR_W-1:0] r_Rd_Ptr = '0;            // the oldest byte
  logic [PTR_W:0]   r_Count  = '0;            // 0..DEPTH - one bit wider than a pointer

  // ---------- safety rules ----------
  logic w_Wr, w_Rd;
  assign w_Wr = i_Wr_En && !o_Full;           // never write when full
  assign w_Rd = i_Rd_En && !o_Empty;          // never read when empty

  // ---------- write, read, count ----------
  always_ff @(posedge i_Clk) begin
    if (w_Wr) begin
      r_Mem[r_Wr_Ptr] <= i_Wr_Data;
      r_Wr_Ptr        <= r_Wr_Ptr + 1'b1;     // wraps 15 to 0
    end

    if (w_Rd)
      r_Rd_Ptr <= r_Rd_Ptr + 1'b1;

    case ({w_Wr, w_Rd})
      2'b10:   r_Count <= r_Count + 1'b1;     // write only
      2'b01:   r_Count <= r_Count - 1'b1;     // read only
      default: ;                              // both or neither: no change
    endcase
  end

  // ---------- outputs ----------
  assign o_Rd_Data = r_Mem[r_Rd_Ptr];         // front byte, always visible
  assign o_Empty   = (r_Count == 0);
  assign o_Full    = (r_Count == DEPTH);

endmodule
