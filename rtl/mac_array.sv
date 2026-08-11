// -------------------------------------------------------------------------------
// -- File       : mac_array.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Edited     : 14/07/2026
// -------------------------------------------------------------------------------
// -- Description: This module implements a MAC array that performs matrix multiplication. 
// It takes in input data and weights, multiplies them, and accumulates the results in 
// an accumulator register. The MAC array can be started and will signal when it is busy 
// or done with the computation.
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------

import cnn_accel_pkg::*;

module mac_array (
    input logic clk_i,
    input logic rst_ni,
    input logic start_i,

    input logic  [15:0] m_i,
    input logic  [15:0] k_i,

    output logic busy_o,
    output logic done_o,

    
    // Input buffer read port
    output logic                  in_en_o,
    output logic [BUF_ADDR_W-1:0] in_addr_o,
    input  logic [AXI_DATA_W-1:0] in_rdata_i,

    // Weight buffer read port
    output logic                  w_en_o,
    output logic [BUF_ADDR_W-1:0] w_addr_o,
    input  logic [AXI_DATA_W-1:0] w_rdata_i,

     // One completed output row -> post-processing pipeline
    output logic                          row_valid_o,
    output logic [15:0]                   row_m_o,
    output logic signed [ACC_WIDTH-1:0]   row_acc_o [PE_COUNT]

  );

  //state def
  typedef enum logic [2:0] {S_IDLE, S_ISSUE, S_WAIT, S_ROW_DONE, S_JOB_DONE} state_e;
  state_e state_q, state_d;

  //row and column counters
  logic [15:0] m_q, m_d;
  logic [15:0] k_q, k_d;
   logic        clear_q;

   assign busy_o = (state_q != S_IDLE);

   // im2col row-major addressing: input_buf[m*K + k]
logic [31:0] in_addr_full;
assign in_addr_full = m_q * k_i + k_q;
assign in_addr_o = in_addr_full;
assign w_addr_o  = k_q;
assign in_en_o   = (state_q == S_ISSUE);
assign w_en_o    = (state_q == S_ISSUE);

   logic signed [DATA_WIDTH-1:0] act_val;
logic signed [DATA_WIDTH-1:0] wt_val [PE_COUNT];
assign act_val = in_rdata_i[DATA_WIDTH-1:0];

genvar gp;
generate
  for (gp = 0; gp < PE_COUNT; gp++) begin : g_wt_unpack
    assign wt_val[gp] = w_rdata_i[gp*DATA_WIDTH +: DATA_WIDTH];
  end
endgenerate



  logic pe_en;
  assign pe_en = (state_q == S_WAIT);

  logic signed [ACC_WIDTH-1:0] pe_acc [PE_COUNT];

  //input datt and weight to the processing elements
genvar gd;
  generate
    for (gd = 0; gd < PE_COUNT; gd++) begin : g_pe
      processing_element #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .en_i    (pe_en),
        .clear_i (clear_q),
        .data_i     (act_val),
        .weight_i     (wt_val[gd]),
        .acc_o   (pe_acc[gd])
      );
    end
  endgenerate

  assign row_acc_o = pe_acc;
  assign row_m_o    = m_q;

  //comb block to traverse the rows and columns of the input matrix

  always_comb
  begin

    state_d = state_q;
    m_d          = m_q;
    k_d          = k_q;
    row_valid_o  = 1'b0;
    done_o   = 1'b0;

    unique case (state_q)
      S_IDLE: begin
        if (start_i&& m_i != 16'd0 && k_i != 16'd0)
        begin
          
          m_d     = '0;
          k_d     = '0;
          state_d = S_ISSUE;
        end
      end

      S_ISSUE: begin
        state_d = S_WAIT;
      end

      S_WAIT: begin
        if (k_q == k_i-16'd1) begin
          state_d = S_ROW_DONE;
        end else begin
          state_d = S_ISSUE;
          k_d     = k_q + 16'd1;
        end
      end

      S_ROW_DONE: begin
        row_valid_o = 1'b1;
        if (m_q == m_i-16'd1) begin
          state_d = S_JOB_DONE;
        end else begin
          state_d = S_ISSUE;
          m_d     = m_q + 16'd1;
          k_d     = '0;
        end
      end

      S_JOB_DONE: begin
        done_o   = 1'b1;
        state_d = S_IDLE;
      end

      default: begin
        state_d = S_IDLE;
      end
    endcase

  end

  //FSM to change the states and values of the row and column counters

   always_ff @(posedge clk_i or negedge rst_ni) begin
   if (!rst_ni) begin
     state_q <= S_IDLE;
     m_q     <= '0;
     k_q     <= '0;
     clear_q <= 1'b1;
   end else begin
     state_q <= state_d;
     m_q     <= m_d;
     k_q     <= k_d;
     clear_q <= (state_q == S_ROW_DONE) || (state_q == S_IDLE);
   end
 end



endmodule
