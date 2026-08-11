// -------------------------------------------------------------------------------
// -- File       : tb_register_dma.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Created    : 21/07/2026
// -------------------------------------------------------------------------------
// -- Description: Self-checking testbench that drives the register controller AXI
// --              slave, launches DMA loads for weights and activations, then
// --              verifies the MAC array row outputs.
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------

import cnn_accel_pkg::*;

module tb_register_dma ();

	localparam int M_VAL = 3;
	localparam int K_VAL = 3;
	localparam int WEIGHT_WORDS = 4;
	localparam int INPUT_WORDS = 9;
	localparam int OUTPUT_WORDS = 1;
	localparam logic [31:0] WEIGHT_SYS_BASE = 32'h0000_0100;
	localparam logic [31:0] INPUT_SYS_BASE  = 32'h0000_0200;
	localparam logic [31:0] OUTPUT_SYS_BASE = 32'h0000_0250;

	logic clk_i, rst_ni;
	int unsigned clk_count;

	AXI_BUS #(
		.AXI_ADDR_WIDTH(AXI_ADDR_W),
		.AXI_DATA_WIDTH(AXI_DATA_W),
		.AXI_ID_WIDTH  (),
		.AXI_USER_WIDTH()
	) axi_reg ();

	AXI_BUS #(
		.AXI_ADDR_WIDTH(AXI_ADDR_W),
		.AXI_DATA_WIDTH(AXI_DATA_W),
		.AXI_ID_WIDTH  (),
		.AXI_USER_WIDTH()
	) axi_dma ();

	logic ctrl_start_o;
	logic ctrl_soft_rst_o;
	logic irq_en_o;
	logic [AXI_ADDR_W-1:0] dma_src_addr_o;
	logic [1:0] dma_sel_o;
	logic [15:0] dma_len_o;
	logic dma_dir_o;
	logic dma_start_o;
	logic [15:0] gemm_m_o;
	logic [15:0] gemm_k_o;
	logic [15:0] gemm_ntiles_o;
	logic status_done_o;
	logic status_error_o;

	logic dma_busy_o, dma_done_o;
	logic mac_busy_o, mac_done_o;
	logic mac_start_pulse;

	logic [1:0] dma_buf_sel;
	logic dma_buf_en, dma_buf_we;
	logic [BUF_ADDR_W-1:0] dma_buf_addr;
	logic [AXI_DATA_W-1:0] dma_buf_wdata;
	logic [AXI_DATA_W-1:0] dma_buf_rdata;

	logic input_buf_en, input_buf_we;
	logic weight_buf_en, weight_buf_we;
	logic in_en, w_en;
	logic [BUF_ADDR_W-1:0] in_addr, w_addr;
	logic [AXI_DATA_W-1:0] in_rdata, w_rdata;

	logic row_valid;
	logic [15:0] row_m;
	logic signed [ACC_WIDTH-1:0] row_acc [PE_COUNT];
	logic signed [ACC_WIDTH-1:0] observed_results [0:M_VAL-1][0:PE_COUNT-1];
	logic signed [DATA_WIDTH-1:0] input_matrix [0:M_VAL-1][0:K_VAL-1];
	logic signed [DATA_WIDTH-1:0] weight_matrix [0:K_VAL-1][0:PE_COUNT-1];

	logic  [31:0] sys_mem [0:4095];
	logic [31:0] output_mem [0:255];

	logic [31:0] axi_dma_rdata_q;
	logic        axi_dma_rvalid_q;
	logic [31:0] axi_dma_awaddr_q;
	logic        axi_dma_aw_seen_q;
	logic        axi_dma_w_seen_q;
	logic        axi_dma_write_resp_q;
	logic done_o;

	// logic signed [ACC_WIDTH-1:0] expected_results [0:M_VAL*PE_COUNT-1];
    logic signed [31:0] expected_results [12];

	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			clk_count <= 0;
		end else begin
			clk_count <= clk_count + 1;
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			axi_dma_rdata_q      <= '0;
			axi_dma_rvalid_q     <= 1'b0;
			axi_dma_awaddr_q     <= '0;
			axi_dma_aw_seen_q    <= 1'b0;
			axi_dma_w_seen_q     <= 1'b0;
			axi_dma_write_resp_q <= 1'b0;
		end else begin
			if (axi_dma.ar_valid && axi_dma.ar_ready) begin
				axi_dma_rdata_q  <= sys_mem[axi_dma.ar_addr[13:2]];
				axi_dma_rvalid_q <= 1'b1;
			end else if (axi_dma_rvalid_q && axi_dma.r_ready) begin
				axi_dma_rvalid_q <= 1'b0;
			end

			if (axi_dma.aw_valid && axi_dma.aw_ready) begin
				axi_dma_awaddr_q  <= axi_dma.aw_addr;
				axi_dma_aw_seen_q <= 1'b1;
			end

			if (axi_dma.w_valid && axi_dma.w_ready) begin
				if (axi_dma_aw_seen_q) begin
					output_mem[axi_dma_awaddr_q[9:2]] <= axi_dma.w_data;
					axi_dma_write_resp_q <= 1'b1;
				end
				axi_dma_w_seen_q <= 1'b1;
			end

			if (axi_dma_write_resp_q && axi_dma.b_ready) begin
				axi_dma_write_resp_q <= 1'b0;
				axi_dma_aw_seen_q    <= 1'b0;
				axi_dma_w_seen_q     <= 1'b0;
			end
		end
	end

	assign axi_dma.ar_ready = 1'b1;
	assign axi_dma.r_valid  = axi_dma_rvalid_q;
	assign axi_dma.r_data   = axi_dma_rdata_q;
	assign axi_dma.r_resp   = 2'b00;
	assign axi_dma.r_last   = 1'b1;
	assign axi_dma.aw_ready = 1'b1;
	assign axi_dma.w_ready  = 1'b1;
	assign axi_dma.b_valid  = axi_dma_write_resp_q;
	assign axi_dma.b_resp   = 2'b00;

	always_ff @(posedge clk_i) begin
		if (rst_ni) begin
			if (axi_dma.ar_valid && !axi_dma.ar_ready) begin
				assert (axi_dma.ar_valid) else $fatal(1, "ARVALID dropped before handshake at cycle %0d", clk_count);
			end
			if (axi_dma.aw_valid && !axi_dma.aw_ready) begin
				assert (axi_dma.aw_valid) else $fatal(1, "AWVALID dropped before handshake at cycle %0d", clk_count);
			end
			if (axi_dma.w_valid && !axi_dma.w_ready) begin
				assert (axi_dma.w_valid) else $fatal(1, "WVALID dropped before handshake at cycle %0d", clk_count);
			end
			if (axi_dma_write_resp_q) begin
				assert (axi_dma.b_valid) else $fatal(1, "BVALID missing when write response is pending at cycle %0d", clk_count);
			end
		end
	end

	cnn_accel_top dut (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .start_i         (1'b0),           // Started via register write
    .read_ready_o    (),
    .code_base_addr_i(),
    .status_o        (done_o),
    .gpo_o           (),
    .LLMI_data_i     (),            // Unused
    // FIFO interface
    .fill_o          (),
    .fifo_empty_i    (1'b0),          // FIFO has data available
    .fifo_low_i      (1'b0),          // FIFO level not low
    .fifo_dout_i     ('0),
    .fifo_rd_o       (),
    // AXI interfaces
    .data_mst        (axi_dma),
    .data_slv        (axi_reg),
    // Results and Debug
    .we_o            (),
    .dout_o          (),
    .debug_vid_o     (),
    .debug_ready_o   (),
	.row_acc_o		(row_acc)	,
	.row_m_o(row_m),
	.row_valid_o	(row_valid)
  );

	// register_ctrl u_reg_ctrl (
	// 	.clk_i(clk_i),
	// 	.rst_ni(rst_ni),
	// 	.axi_slv(axi_reg),
	// 	.ctrl_start_o(ctrl_start_o),
	// 	.ctrl_soft_rst_o(ctrl_soft_rst_o),
	// 	.irq_en_o(irq_en_o),
	// 	.dma_src_addr_o(dma_src_addr_o),
	// 	.dma_sel_o(dma_sel_o),
	// 	.dma_len_o(dma_len_o),
	// 	.dma_dir_o(dma_dir_o),
	// 	.dma_start_o(dma_start_o),
	// 	.gemm_m_o(gemm_m_o),
	// 	.gemm_k_o(gemm_k_o),
	// 	.gemm_ntiles_o(gemm_ntiles_o),
	// 	.busy_i(dma_busy_o | mac_busy_o),
	// 	.done_pulse_i(mac_done_o),
	// 	.error_i(1'b0),
	// 	.dma_done_pulse_i(dma_done_o),
	// 	.out_elems_i(16'd0),
	// 	.status_done_o(status_done_o),
	// 	.status_error_o(status_error_o)
	// );

	// dma_controller u_dma (
	// 	.clk_i(clk_i),
	// 	.rst_ni(rst_ni),
	// 	.busy_o(dma_busy_o),
	// 	.done_o(dma_done_o),
	// 	.axi_mst(axi_dma),
	// 	.start_i(dma_start_o),
	// 	.src_addr_i(dma_src_addr_o),
	// 	.dst_addr_i(32'd0),
	// 	.length_i({16'd0, dma_len_o}),
	// 	.sel_i(dma_sel_o),
	// 	.dir_i(dma_dir_o),
	// 	.buf_sel_o(dma_buf_sel),
	// 	.buf_en_o(dma_buf_en),
	// 	.buf_we_o(dma_buf_we),
	// 	.buf_addr_o(dma_buf_addr),
	// 	.buf_wdata_o(dma_buf_wdata),
	// 	.buf_rdata_i(dma_buf_rdata)
	// );

	assign dma_buf_rdata = (dma_buf_sel == DMA_SEL_WEIGHT) ? w_rdata :
												 (dma_buf_sel == DMA_SEL_INPUT)  ? in_rdata : '0;

	assign input_buf_en  = dma_buf_en && (dma_buf_sel == DMA_SEL_INPUT);
	assign input_buf_we  = dma_buf_we && (dma_buf_sel == DMA_SEL_INPUT);
	assign weight_buf_en = dma_buf_en && (dma_buf_sel == DMA_SEL_WEIGHT);
	assign weight_buf_we = dma_buf_we && (dma_buf_sel == DMA_SEL_WEIGHT);

	// bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_input (
	// 	.clk_i(clk_i),
	// 	.en_i(input_buf_en | in_en),
	// 	.we_i(input_buf_we),
	// 	.be_i('1),
	// 	.addr_i(input_buf_we ? dma_buf_addr : in_addr),
	// 	.wdata_i(dma_buf_wdata),
	// 	.rdata_o(in_rdata)
	// );

	// bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_weight (
	// 	.clk_i(clk_i),
	// 	.en_i(weight_buf_en | w_en),
	// 	.we_i(weight_buf_we),
	// 	.be_i('1),
	// 	.addr_i(weight_buf_we ? dma_buf_addr : w_addr),
	// 	.wdata_i(dma_buf_wdata),
	// 	.rdata_o(w_rdata)
	// );

	// mac_array u_mac (
	// 	.clk_i(clk_i),
	// 	.rst_ni(rst_ni),
	// 	.start_i(mac_start_pulse),
	// 	.m_i(gemm_m_o),
	// 	.k_i(gemm_k_o),
	// 	.busy_o(mac_busy_o),
	// 	.done_o(mac_done_o),
	// 	.in_en_o(in_en),
	// 	.in_addr_o(in_addr),
	// 	.in_rdata_i(in_rdata),
	// 	.w_en_o(w_en),
	// 	.w_addr_o(w_addr),
	// 	.w_rdata_i(w_rdata),
	// 	.row_valid_o(row_valid),
	// 	.row_m_o(row_m),
	// 	.row_acc_o(row_acc)
	// );

	initial begin
		logic [31:0] status;
		logic [31:0] readback;
		
		int i, j, k, word_idx, byte_idx;
		// logic signed [31:0] expected_results [0:M_VAL*PE_COUNT-1];
		logic signed [7:0] temp_byte;


		// Initialize system memory to zero
		foreach (sys_mem[i]) begin
			sys_mem[i] = '0;
		end

		// Generate random weights and inputs (values between 1 and 10)
		// Weights: K_VAL x PE_COUNT matrix, packed in 32-bit words (4 bytes per word)
		for (k = 0; k < K_VAL; k++) begin
			for (j = 0; j < PE_COUNT; j++) begin
				word_idx = k * (PE_COUNT/4) + j/4; // Assuming PE_COUNT multiple of 4
				byte_idx = j % 4;
				if (j % 4 == 0) begin
					// Generate a new random word for each group of 4 weights (each byte is 1 to 100)
					sys_mem[(WEIGHT_SYS_BASE >> 2) + word_idx] = 
						{ $urandom_range(-127, 128), $urandom_range(-127, 128), 
						$urandom_range(-127, 128), $urandom_range(-127, 128) }; // Example fixed values for testing
						 
				end
			end
		end

		// Inputs: M_VAL x K_VAL matrix (each value is an 8-bit value stored in a 32-bit word)
		for (i = 0; i < M_VAL; i++) begin
			for (k = 0; k < K_VAL; k++) begin
				// Store 8-bit value (-5 to 5) in the lower 8 bits of a 32-bit word
				sys_mem[(INPUT_SYS_BASE >> 2) + i*K_VAL + k] = { 24'h000000, $urandom_range(255)-128 };
			end
		end

		// Extract matrices from system memory for display
		for (i = 0; i < M_VAL; i++) begin
			for (k = 0; k < K_VAL; k++) begin
				// Extract the 8-bit value (bits 7:0) and zero-extend to 32 bits
				input_matrix[i][k] = {sys_mem[(INPUT_SYS_BASE >> 2) + i*K_VAL + k][7:0]};
			end
		end

		for (k = 0; k < K_VAL; k++) begin
			for (j = 0; j < PE_COUNT; j++) begin
				word_idx = k * (PE_COUNT/4) + j/4;
				byte_idx = j % 4;
				// Extract the 8-bit value and zero-extend to 32 bits
				weight_matrix[k][j] = { sys_mem[(WEIGHT_SYS_BASE >> 2) + word_idx][byte_idx*8 +: 8]};
			end
		end

		// Calculate expected results (matrix multiplication)
		for (i = 0; i < M_VAL; i++) begin
			for (j = 0; j < PE_COUNT; j++) begin
				expected_results[i*PE_COUNT + j] = 0;
				for (k = 0; k < K_VAL; k++) begin
					expected_results[i*PE_COUNT + j] += input_matrix[i][k] * weight_matrix[k][j];
				end
			end
		end

		rst_ni = 1'b0;
		mac_start_pulse = 1'b0;

		axi_reg.aw_id = '0;
		axi_reg.aw_addr = '0;
		axi_reg.aw_len = '0;
		axi_reg.aw_size = '0;
		axi_reg.aw_burst = '0;
		axi_reg.aw_lock = 1'b0;
		axi_reg.aw_cache = '0;
		axi_reg.aw_prot = '0;
		axi_reg.aw_qos = '0;
		axi_reg.aw_region = '0;
		axi_reg.aw_atop = '0;
		axi_reg.aw_user = '0;
		axi_reg.aw_valid = 1'b0;
		axi_reg.w_data = '0;
		axi_reg.w_strb = '0;
		axi_reg.w_last = 1'b0;
		axi_reg.w_user = '0;
		axi_reg.w_valid = 1'b0;
		axi_reg.b_ready = 1'b0;
		axi_reg.ar_id = '0;
		axi_reg.ar_addr = '0;
		axi_reg.ar_len = '0;
		axi_reg.ar_size = '0;
		axi_reg.ar_burst = '0;
		axi_reg.ar_lock = 1'b0;
		axi_reg.ar_cache = '0;
		axi_reg.ar_prot = '0;
		axi_reg.ar_qos = '0;
		axi_reg.ar_region = '0;
		axi_reg.ar_user = '0;
		axi_reg.ar_valid = 1'b0;
		axi_reg.r_ready = 1'b0;

		#10 rst_ni = 1'b1;
		repeat (2) @(posedge clk_i);
		$display("====[%0t ns] Simulation started===", $time);

		$display("=== Programming register controller ===");
		axi_write({24'd0, REG_GEMM_M}, M_VAL);
		axi_write({24'd0, REG_GEMM_K}, K_VAL);
		axi_write({24'd0, REG_GEMM_NTILES}, 32'd1);

		axi_read({24'd0, REG_GEMM_M}, readback);
		if (readback[15:0] != M_VAL[15:0]) $fatal(1, "REG_GEMM_M readback mismatch: got %0d", readback);
		axi_read({24'd0, REG_GEMM_K}, readback);
		if (readback[15:0] != K_VAL[15:0]) $fatal(1, "REG_GEMM_K readback mismatch: got %0d", readback);

		$display("=== Loading weight buffer through DMA ===");
		dma_program_and_wait(WEIGHT_SYS_BASE, DMA_SEL_WEIGHT, WEIGHT_WORDS, 1'b0);

		$display("=== Loading input buffer through DMA ===");
		dma_program_and_wait(INPUT_SYS_BASE, DMA_SEL_INPUT, INPUT_WORDS, 1'b0);

		axi_read({24'd0, REG_STATUS}, status);
		if (status[0]) $fatal(1, "STATUS.BUSY should be low after DMA loads complete");

		display_matrix_3x3("Input matrix", input_matrix);
		display_matrix_2d_3x4("Weight matrix",  weight_matrix);

		$display("=== Starting MAC Array ===");

		axi_write({24'd0, REG_CTRL}, 'd1); // Start MAC operation


		// @(negedge clk_i);
		// mac_start_pulse = 1'b1;
		// @(posedge clk_i);
		// mac_start_pulse = 1'b0;
		$display("====[%0t ns] MAC DONE===", $time);
		wait (done_o);
	    @(posedge clk_i);

		// Override expected_results with calculated values for checking
		foreach (expected_results[i]) begin
			// Already calculated above
		end

		check_results();

		axi_read({24'd0, REG_STATUS}, status);
		if (!status[1]) $fatal(1, "STATUS.DONE should be set after MAC completion");

		axi_write({24'd0, REG_IRQ_CLR}, 32'd1);
		axi_read({24'd0, REG_STATUS}, status);
		if (status[1] || status[2]) $fatal(1, "STATUS sticky bits did not clear after IRQ_CLR");

		$display("=== MAC OPERATION DONE ===");
		$display("=== [%0t ns]INITIATING DMA LOADING EXT MEM ===", $time);

		dma_program_and_wait(OUTPUT_SYS_BASE, DMA_SEL_OUTPUT, REG_OUT_ELEMS, 1'b1);
		$display("=== [%0t ns]INITIATING DONE ===", $time);
		// axi_write({24'd0, REG_DMA_START}, 32'd1);
		// wait(done_o);
	    // @(posedge clk_i);



		$display("====[%0t ns] DMA DONE===", $time);




		$display("=== DMA LOADING EXT MEM DONE ===");




		#50 $finish;
	end

	task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
		@(negedge clk_i);
		axi_reg.aw_addr  = addr;
		axi_reg.aw_len   = '0;
		axi_reg.aw_size  = 3'd2;
		axi_reg.aw_burst = 2'b01;
		axi_reg.aw_valid = 1'b1;
		axi_reg.w_data   = data;
		axi_reg.w_strb   = 4'hF;
		axi_reg.w_last   = 1'b1;
		axi_reg.w_valid  = 1'b1;
		axi_reg.b_ready  = 1'b1;
		@(posedge clk_i);
		axi_reg.aw_valid = 1'b0;
		axi_reg.w_valid  = 1'b0;
		do @(posedge clk_i); while (!axi_reg.b_valid);
		axi_reg.b_ready = 1'b0;
	endtask

	task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
		@(negedge clk_i);
		axi_reg.ar_addr  = addr;
		axi_reg.ar_len   = '0;
		axi_reg.ar_size  = 3'd2;
		axi_reg.ar_burst = 2'b01;
		axi_reg.ar_valid = 1'b1;
		axi_reg.r_ready  = 1'b1;
		@(posedge clk_i);
		axi_reg.ar_valid = 1'b0;
		do @(posedge clk_i); while (!axi_reg.r_valid);
		data = axi_reg.r_data;
		axi_reg.r_ready = 1'b0;
	endtask

	task automatic wait_idle();
		logic [31:0] status;
		repeat (2) @(posedge clk_i);
		do begin
			axi_read({24'd0, REG_STATUS}, status);
		end while (status[0]);
	endtask

	task automatic dma_program_and_wait(
		input logic [31:0] sys_addr,
		input logic [1:0]  sel,
		input int unsigned len_words,
		input logic        dir
	);
		axi_write({24'd0, REG_DMA_SRC}, sys_addr);
		axi_write({24'd0, REG_DMA_SEL}, {30'd0, sel});
		axi_write({24'd0, REG_DMA_LEN}, len_words);
		axi_write({24'd0, REG_DMA_DIR}, {31'd0, dir});
		axi_write({24'd0, REG_DMA_START}, 32'd1);
		wait_idle();
	endtask

	task automatic check_results();
		logic  signed [31:0] actual_results [0:M_VAL*PE_COUNT-1];
		logic test_pass = 1'b1;
		integer i, j, idx;

		$display("\n=== Checking MAC Array Output ===");
		$display("Expected vs Actual Results:");
		display_vector_as_matrix_3x4("Expected output", expected_results);
		display_matrix_2d2_3x4("Actual output",  observed_results);

		for (i = 0; i < M_VAL; i++) begin
			for (j = 0; j < PE_COUNT; j++) begin
				idx = i * PE_COUNT + j;
				actual_results[idx] = observed_results[i][j];

				if (actual_results[idx] != expected_results[idx]) begin
					$display("MISMATCH at [%0d][%0d]: Expected %0d, Got %0d",
									 i, j, expected_results[idx], actual_results[idx]);
					test_pass = 1'b0;
				end else begin
					$display("PASS at [%0d][%0d]: %0d", i, j, actual_results[idx]);
				end
			end
		end

		if (test_pass) begin
			$display("\n=== ALL TESTS PASSED ===");
		end else begin
			$display("\n=== TESTS FAILED ===");
			$stop;
		end
	endtask

	task automatic display_matrix_3x3(string label, logic signed [DATA_WIDTH-1:0] matrix [0:M_VAL-1][0:K_VAL-1]);
		$display("%s =", label);
		for (int row = 0; row < M_VAL; row++) begin
			$write("[");
			for (int col = 0; col < K_VAL; col++) begin
				if (col != 0) $write(", ");
				$write("%0d", matrix[row][col]);
			end
			$display("]");
		end
	endtask

	task automatic display_matrix_2d2_3x4(string label, logic signed [ACC_WIDTH-1:0] matrix [0:M_VAL-1][0:PE_COUNT-1]);
	$display("%s =", label);
	for (int row = 0; row < M_VAL; row++) begin
		$write("[");
		for (int col = 0; col < PE_COUNT; col++) begin
			if (col != 0) $write(", ");
			$write("%0d", matrix[row][col]);
		end
		$display("]");
	end
endtask

	task automatic display_matrix_2d_3x4(string label, logic signed [DATA_WIDTH-1:0] matrix [0:M_VAL-1][0:PE_COUNT-1]);
		$display("%s =", label);
		for (int row = 0; row < M_VAL; row++) begin
			$write("[");
			for (int col = 0; col < PE_COUNT; col++) begin
				if (col != 0) $write(", ");
				$write("%0d", matrix[row][col]);
			end
			$display("]");
		end
	endtask

	task automatic display_vector_as_matrix_3x4(string label, logic signed[32-1:0] vector [12]);
		$display("%s =", label);
		for (int row = 0; row < M_VAL; row++) begin
			$write("[");
			for (int col = 0; col < PE_COUNT; col++) begin
				int flat_idx;
				flat_idx = row * PE_COUNT + col;
				if (col != 0) $write(", ");
				$write("%0d", vector[flat_idx]);
			end
			$display("]");
		end
	endtask

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			foreach (observed_results[i, j]) begin
				observed_results[i][j] <= '0;
			end

		end else if (row_valid) begin
			foreach (row_acc[j]) begin
				observed_results[row_m][j] <= row_acc[j];
			end
		end
	end

endmodule : tb_register_dma
