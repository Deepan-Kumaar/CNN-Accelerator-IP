// -------------------------------------------------------------------------------
// -- File       : tb_mac_array.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Created    : 20/07/2026
// -- Edited     : 20/07/2026
// -------------------------------------------------------------------------------
// -- Description: This module implements a processing element that performs multiply 
//    and accumulate operation. It takes in data and weight as inputs, multiplies them, 
//    and accumulates the result in an accumulator register. The accumulator can 
// be cleared or reset based on control signals.
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------

import cnn_accel_pkg::*;

module tb_mac_array;

	logic clk_i;
	logic rst_ni;
	logic start_i;

	logic [15:0] m_i;
	logic [15:0] k_i;

	logic busy_o;
	logic done_o;
	

	logic                  in_en_o;
	logic [BUF_ADDR_W-1:0] in_addr_o;
	logic [AXI_DATA_W-1:0] in_rdata_i;

	logic                  w_en_o;
	logic [BUF_ADDR_W-1:0] w_addr_o;
	logic [AXI_DATA_W-1:0] w_rdata_i;

    logic                          row_valid_o;
    logic [15:0]                   row_m_o;
    logic signed [ACC_WIDTH-1:0]   row_acc_o [PE_COUNT];

	localparam int M_VAL = 3;
	localparam int K_VAL = 3;
	localparam int W_PER_WORD = 3;

	logic signed [DATA_WIDTH-1:0] in_mem [0:M_VAL-1][0:K_VAL-1];
	logic signed [DATA_WIDTH-1:0] w_mem  [0:K_VAL-1][0:W_PER_WORD-1];

    logic signed [ACC_WIDTH-1:0] acc_mem [0:M_VAL-1][0:W_PER_WORD-1];

	mac_array dut (
		.clk_i      (clk_i),
		.rst_ni     (rst_ni),
		.start_i    (start_i),
		.m_i        (m_i),
		.k_i        (k_i),
		.busy_o     (busy_o),
		.done_o     (done_o),
		.in_en_o    (in_en_o),
		.in_addr_o  (in_addr_o),
		.in_rdata_i (in_rdata_i),
		.w_en_o     (w_en_o),
		.w_addr_o   (w_addr_o),
		.w_rdata_i  (w_rdata_i),
        .row_valid_o (row_valid_o),
        .row_m_o     (row_m_o),
        .row_acc_o   (row_acc_o)
	);

	always #5 clk_i = ~clk_i;

	initial begin
		clk_i   = 1'b0;
		rst_ni  = 1'b0;
		start_i = 1'b0;
		m_i     = M_VAL;
		k_i     = K_VAL;

		foreach (in_mem[i, j]) in_mem[i][j] = $signed((i + j + 1)*100);
		foreach (w_mem[i, j])  w_mem[i][j]  = $signed(((i + 1) * (j + 1))*100);

		repeat (4) @(posedge clk_i);
		rst_ni = 1'b1;
		@(posedge clk_i);

		start_i = 1'b1;
		@(posedge clk_i);
		start_i = 1'b0;

		wait (done_o);
		@(posedge clk_i);

		$display("mac_array completed. busy=%0b done=%0b row_m=%0d", busy_o, done_o, row_m_o);
		#20;
		$finish;
	end

	always_comb begin
		in_rdata_i = '0;
		w_rdata_i  = '0;

		if (in_addr_o < (M_VAL * K_VAL)) begin
			in_rdata_i[DATA_WIDTH-1:0] = in_mem[in_addr_o / K_VAL][in_addr_o % K_VAL];
        end
       if (w_addr_o < K_VAL) begin
			for (int idx = 0; idx < W_PER_WORD; idx++) begin
				w_rdata_i[idx*DATA_WIDTH +: DATA_WIDTH] = w_mem[w_addr_o][idx];
			end
        
        
		end
        if (row_valid_o) begin
            for (int idx = 0; idx < W_PER_WORD; idx++) begin
                acc_mem[row_m_o][idx] = row_acc_o[idx];
            end
        end
	end

endmodule
