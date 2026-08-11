// -------------------------------------------------------------------------------
// -- File       : tb_dma_bram_mc.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Created    : 20/07/2026
// -- Edited     : 21/07/2026
// -------------------------------------------------------------------------------
// -- Description: 
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------


import cnn_accel_pkg::*;

module tb_dma_bram_mc ();

  logic clk_i, rst_ni;
  logic dma_start_i, mac_start_i;
  logic [31:0] src_addr_i, dst_addr_i, length_i;
  logic [1:0] dma_sel_i;
  logic dma_dir_i;
  logic dma_busy_o, dma_done_o;
  logic mac_busy_o, mac_done_o;

  AXI_BUS#(
    .AXI_ADDR_WIDTH(AXI_ADDR_W),
    .AXI_DATA_WIDTH(AXI_DATA_W),
    .AXI_ID_WIDTH  (),
    .AXI_USER_WIDTH()

  ) axi_mst();

  // DMA to BRAM connections
  logic buf_en, buf_we;
  logic [BUF_ADDR_W-1:0] buf_addr;
  logic [AXI_DATA_W-1:0] buf_wdata, buf_rdata;

  // BRAM to MAC Array connections
  logic in_en, w_en;
  logic [BUF_ADDR_W-1:0] in_addr, w_addr;
  logic [AXI_DATA_W-1:0] in_rdata, w_rdata;

  // MAC Array outputs
  logic row_valid;
  logic [15:0] row_m;
  logic signed [ACC_WIDTH-1:0] row_acc [PE_COUNT];
  logic signed [ACC_WIDTH-1:0] observed_results [0:2][0:PE_COUNT-1];
  logic signed [31:0] input_matrix [0:2][0:2];
  logic signed [31:0] weight_matrix [0:2][0:PE_COUNT-1];

  // System memory simulation
  logic  signed [31:0] sys_mem [0:4095];
  logic signed [31:0] output_mem [0:255];

  logic [31:0] axi_rdata_q;
  logic        axi_rvalid_q;
  logic [31:0] axi_awaddr_q;
  logic [31:0] axi_araddr_q;
  logic        axi_aw_seen_q;
  logic        axi_w_seen_q;
  logic        axi_write_resp_q;
  int unsigned clk_count;

  // Clock generation
  initial begin
    clk_i = 0;
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
      axi_rdata_q  <= '0;
      axi_rvalid_q <= 1'b0;
      axi_awaddr_q <= '0;
      axi_araddr_q <= '0;
      axi_aw_seen_q <= 1'b0;
      axi_w_seen_q  <= 1'b0;
      axi_write_resp_q <= 1'b0;
    end else begin
      if (axi_mst.ar_valid && axi_mst.ar_ready) begin
        axi_araddr_q  <= axi_mst.ar_addr;
        axi_rdata_q  <= sys_mem[axi_mst.ar_addr[13:2]];
        axi_rvalid_q <= 1'b1;
      end else if (axi_rvalid_q && axi_mst.r_ready) begin
        axi_rvalid_q <= 1'b0;
      end

      if (axi_mst.aw_valid && axi_mst.aw_ready) begin
        axi_awaddr_q  <= axi_mst.aw_addr;
        axi_aw_seen_q  <= 1'b1;
      end

      if (axi_mst.w_valid && axi_mst.w_ready) begin
        if (axi_aw_seen_q) begin
          output_mem[axi_awaddr_q[9:2]] <= axi_mst.w_data;
          axi_write_resp_q <= 1'b1;
        end
        axi_w_seen_q <= 1'b1;
      end

      if (axi_write_resp_q && axi_mst.b_ready) begin
        axi_write_resp_q <= 1'b0;
        axi_aw_seen_q    <= 1'b0;
        axi_w_seen_q     <= 1'b0;
      end
    end
  end

  assign axi_mst.ar_ready = 1'b1;
  assign axi_mst.r_valid  = axi_rvalid_q;
  assign axi_mst.r_data   = axi_rdata_q;
  assign axi_mst.r_resp   = 2'b00;
  assign axi_mst.r_last   = 1'b1;
  assign axi_mst.aw_ready = 1'b1;
  assign axi_mst.w_ready   = 1'b1;
  assign axi_mst.b_valid   = axi_write_resp_q;
  assign axi_mst.b_resp    = 2'b00;

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (axi_mst.ar_valid && !axi_mst.ar_ready) begin
        assert (axi_mst.ar_valid) else $fatal(1, "ARVALID dropped before handshake at cycle %0d", clk_count);
      end
      if (axi_mst.aw_valid && !axi_mst.aw_ready) begin
        assert (axi_mst.aw_valid    ) else $fatal(1, "AWVALID dropped before handshake at cycle %0d", clk_count);
      end
      if (axi_mst.w_valid && !axi_mst.w_ready) begin
        assert (axi_mst.w_valid) else $fatal(1, "WVALID dropped before handshake at cycle %0d", clk_count);
      end
      if (axi_write_resp_q) begin
        assert (axi_mst.b_valid) else $fatal(1, "BVALID missing when write response is pending at cycle %0d", clk_count);
      end
    end
  end

  // DMA Controller instance
  // Note: Simplified - AXI interface mocked with direct memory access
  dma_controller u_dma (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .busy_o(dma_busy_o),
    .done_o(dma_done_o),
    .axi_mst(axi_mst),
    .start_i(dma_start_i),
    .src_addr_i(src_addr_i),
    .dst_addr_i(dst_addr_i),
    .length_i(length_i),
    .sel_i(dma_sel_i),
    .dir_i(dma_dir_i),
    .buf_sel_o(),
    .buf_en_o(buf_en),
    .buf_we_o(buf_we),
    .buf_addr_o(buf_addr),
    .buf_wdata_o(buf_wdata),
    .buf_rdata_i(in_rdata)
  );

  // BRAM instance (input buffer)
  bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_input (
    .clk_i(clk_i),
    .en_i(buf_en | in_en),
    .we_i(buf_we),
    .be_i('1),
    .addr_i(buf_we ? buf_addr : in_addr),
    .wdata_i(buf_wdata),
    .rdata_o(in_rdata)
  );

  // BRAM instance (weight buffer)
  bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_weight (
    .clk_i(clk_i),
    .en_i(w_en),
    .we_i(1'b0),
    .be_i('1),
    .addr_i(w_addr),
    .wdata_i('0),
    .rdata_o(w_rdata)
  );

  // MAC Array instance
  mac_array u_mac (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(mac_start_i),
    .m_i(16'd3),
    .k_i(16'd3),
    .busy_o(mac_busy_o),
    .done_o(mac_done_o),
    .in_en_o(in_en),
    .in_addr_o(in_addr),
    .in_rdata_i(in_rdata),
    .w_en_o(w_en),
    .w_addr_o(w_addr),
    .w_rdata_i(w_rdata),
    .row_valid_o(row_valid),
    .row_m_o(row_m),
    .row_acc_o(row_acc)
  );

  // Test data: 3x3 matrix multiplication
  // Input matrix (3x3): [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
  // Weight matrix packs 4 output channels per word.
  // Expected outputs:
  // Row 0: [3, 5, 4, 6]
  // Row 1: [9, 11, 10, 15]
  // Row 2: [15, 17, 16, 24]

  logic signed [31:0] expected_results [12] = '{
    32'd48,   32'd80,   32'd64,   32'd96,
    32'd144,   32'd176,  32'd160,  32'd240,
    -32'd16,  -32'd240,  32'd0,  -32'd128
  };

  initial begin
    // Initialize system memory with input data.
    // DMA copies these words into the input BRAM before MAC starts.
    sys_mem[0] = 8'h10;
    sys_mem[1] = 8'h20;
    sys_mem[2] = 8'h30;
    sys_mem[3] = 8'h40;
    sys_mem[4] = 8'h50;
    sys_mem[5] = 8'h60;
    sys_mem[6] = 8'h70;
    sys_mem[7] = 8'h80;
    sys_mem[8] = 8'h90;

    input_matrix[0][0] = 8'sd16;
    input_matrix[0][1] = 8'sd32;
    input_matrix[0][2] = 8'sd48;
    input_matrix[1][0] = 8'sd64;
    input_matrix[1][1] = 8'sd80;
    input_matrix[1][2] = 8'sd96;
    input_matrix[2][0] = 8'sd112;
    input_matrix[2][1] = 8'sd128;
    input_matrix[2][2] = 8'sd144;

    // Load weight buffer (3x3 matrix packed)
    // Packed as [PE3, PE2, PE1, PE0] with 8-bit lanes.
    u_bram_weight.mem[0] = 32'h0101_0001;  // k=0: [1, 0, 1, 1]
    u_bram_weight.mem[1] = 32'h0100_0101;  // k=1: [1, 1, 0, 1]
    u_bram_weight.mem[2] = 32'h0101_0100;  // k=2: [0, 1, 1, 1]

    weight_matrix[0][0] = 32'sd1;
    weight_matrix[0][1] = 32'sd0;
    weight_matrix[0][2] = 32'sd1;
    weight_matrix[0][3] = 32'sd1;
    weight_matrix[1][0] = 32'sd1;
    weight_matrix[1][1] = 32'sd1;
    weight_matrix[1][2] = 32'sd0;
    weight_matrix[1][3] = 32'sd1;
    weight_matrix[2][0] = 32'sd0;
    weight_matrix[2][1] = 32'sd1;
    weight_matrix[2][2] = 32'sd1;
    weight_matrix[2][3] = 32'sd1;

    // Reset and initialize
    rst_ni = 1'b0;
    dma_start_i = 1'b0;
    mac_start_i = 1'b0;
    src_addr_i = 32'd0;
    dst_addr_i = 32'd0;
    length_i = 32'd9;
    dma_sel_i = 2'd0;
    dma_dir_i = 1'b0;

    #10 rst_ni = 1'b1;

    $display("=== Starting DMA Load Test ===");
    #20;

    dma_start_i = 1'b1;
    #10 dma_start_i = 1'b0;

    wait(dma_done_o);
    $display("DMA done at cycle %0d", clk_count);
    #20;

    display_matrix_3x3("Input matrix", input_matrix);
    display_matrix_2d_3x4("Weight matrix", weight_matrix);

    $display("=== Starting MAC Array Test ===");

    // Start MAC computation
    mac_start_i = 1'b1;
    #10 mac_start_i = 1'b0;

    // Wait for the MAC array to finish producing all rows.
    wait(mac_done_o);
    $display("MAC done at cycle %0d", clk_count);
    #20;

    // Verification
    check_results();

    #50 $finish;
  end

  task automatic check_results();
    logic signed [31:0] actual_results [12];
    logic test_pass = 1'b1;
    integer i, j, idx;

    $display("\n=== Checking MAC Array Output ===");
    $display("Expected vs Actual Results:");
    display_vector_as_matrix_3x4("Expected output", expected_results);
    display_matrix_2d_3x4("Actual output", observed_results);

    for (i = 0; i < 3; i++) begin
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

  task automatic display_matrix_3x3(string label, logic signed [31:0] matrix [0:2][0:2]);
    $display("%s =", label);
    for (int row = 0; row < 3; row++) begin
      $write("[");
      for (int col = 0; col < 3; col++) begin
        if (col != 0) $write(", ");
        $write("%0d", matrix[row][col]);
      end
      $display("]");
    end
  endtask

  task automatic display_matrix_2d_3x4(string label, logic signed [31:0] matrix [0:2][0:PE_COUNT-1]);
    $display("%s =", label);
    for (int row = 0; row < 3; row++) begin
      $write("[");
      for (int col = 0; col < PE_COUNT; col++) begin
        if (col != 0) $write(", ");
        $write("%0d", matrix[row][col]);
      end
      $display("]");
    end
  endtask

  task automatic display_vector_as_matrix_3x4(string label, logic signed [31:0] vector [12]);
    $display("%s =", label);
    for (int row = 0; row < 3; row++) begin
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

endmodule : tb_dma_bram_mc
