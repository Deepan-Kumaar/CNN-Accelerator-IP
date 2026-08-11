// -------------------------------------------------------------------------------
// -- File       : cnn_accel_top.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Created    : 23/07/2026
// -- Edited     : 27/07/2026
// -------------------------------------------------------------------------------
// -- Description:
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------
import  cnn_accel_pkg::*;


module cnn_accel_top (
    input logic         clk_i,
    input logic         rst_ni,

    input logic         start_i,
    output logic        read_ready_o,
    input logic         code_base_addr_i,
    output logic        status_o,
    output logic        gpo_o,

    inout logic [31:0]    LLMI_data_i,

    // FIFO interface
    output logic        fill_o,
    input logic         fifo_empty_i,
    input logic         fifo_low_i,
    input logic         fifo_dout_i,
    input logic         fifo_rd_o,

    // AXI4-Lite interface
    AXI_BUS.Master data_mst,
    AXI_BUS.Slave  data_slv,

    // Results and Debug interface
    output logic        we_o,
    output logic        dout_o,
    output logic        debug_vid_o,
    output logic        debug_ready_o,

	output logic signed [ACC_WIDTH-1:0]   row_acc_o [PE_COUNT],
    output logic [15:0]                   row_m_o,
	

	output logic row_valid_o,
  output logic irq_o

  );



  logic mac_busy_o, mac_done_o;
  logic mac_start_pulse;


  logic row_valid;
  logic [15:0] row_m;
  logic signed [ACC_WIDTH-1:0] row_acc [PE_COUNT];

  logic irq_en_o;

  logic ctrl_start_o;
  logic ctrl_soft_rst_o;

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

  logic dma_start_gated, compute_start_gated;
  logic dma_busy_o, dma_done_o;


  logic ctrl_start_r;


  logic [BUF_ADDR_W-1:0] out_wr_addr_q;
  logic [15:0]           out_row_cnt_q;
  logic                   post_job_done_q;
  wire                    post_job_done = post_job_done_q;
  logic [AXI_DATA_W-1:0]  out_wr_word;


  logic [1:0] dma_buf_sel;
  logic dma_buf_en, dma_buf_we;
  logic [BUF_ADDR_W-1:0] dma_buf_addr;
  logic [AXI_DATA_W-1:0] dma_buf_wdata;
  logic [AXI_DATA_W-1:0] dma_buf_rdata;


  logic input_buf_en, input_buf_we;
  logic weight_buf_en, weight_buf_we;
  logic mac_in_en, mac_w_en;
  logic [BUF_ADDR_W-1:0] in_addr, w_addr;
  logic [AXI_DATA_W-1:0] in_rdata, w_rdata;
  logic [BUF_ADDR_W-1:0]  mac_in_addr;
  logic [BUF_ADDR_W-1:0]  mac_w_addr;

  logic [AXI_DATA_W-1:0] w_wdata,in_wdata;
  logic [AXI_DATA_W-1:0] mac_in_rdata, mac_w_rdata;



  logic                  out_en, out_we;
  logic [BUF_ADDR_W-1:0] out_addr;
  logic [AXI_DATA_W-1:0] out_wdata, out_rdata;

  logic        relu_en, pool_en;
  logic                pool_valid;
  logic [AXI_ADDR_W-1:0] dma_src_addr_r;




  typedef enum logic [1:0] {PH_IDLE, PH_DMA, PH_COMPUTE} phase_e;
  phase_e phase_q, phase_d;




  assign irq_o = irq_en_o & (status_done_o | status_error_o);

  assign dma_start_gated     = dma_start_o && (phase_q == PH_IDLE);

  assign compute_start_gated = ctrl_start_r && (phase_q == PH_IDLE)
         && (gemm_m_o != 16'd0) && (gemm_k_o != 16'd0);

  assign top_busy = (phase_q != PH_IDLE);

  assign top_error = 1'b0;
  assign mac_start_pulse = compute_start_gated;
  assign row_m_o = row_m;
  assign dma_src_addr_r = dma_src_addr_o;


  wire  [15:0] expected_rows = pool_en ? (gemm_m_o >> 1) : gemm_m_o;
  wire         last_pool_out = pool_valid && (out_row_cnt_q == expected_rows - 16'd1);

  assign input_buf_en    = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_INPUT) ? dma_buf_en : mac_in_en;//en act
  assign input_buf_we    = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_INPUT) ? dma_buf_we : 1'b0;// we act
  assign in_addr  = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_INPUT) ? dma_buf_addr : mac_in_addr; //i/p act addr

  assign in_wdata = dma_buf_wdata;//i/p act
  assign mac_in_rdata = (phase_q == PH_COMPUTE ) ? in_rdata : '0; //o/p act
  //WEIGHTS
  assign weight_buf_en    = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_WEIGHT) ? dma_buf_en : mac_w_en;//en act
  assign weight_buf_we    = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_WEIGHT) ? dma_buf_we : 1'b0;// we act
  assign w_addr  = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_WEIGHT) ? dma_buf_addr : mac_w_addr; //w/p act addr

  assign w_wdata = dma_buf_wdata;//w/p act
  assign mac_w_rdata = w_rdata; //o/p act
  assign compute_done_pulse = post_job_done_q;
  assign out_elems = out_row_cnt_q;

  assign row_valid_o = row_valid;

  assign row_acc_o = row_acc;


  wire dma_targets_output = (phase_q == PH_DMA && dma_buf_sel == DMA_SEL_OUTPUT);


  assign out_en    = dma_targets_output ? dma_buf_en : row_valid;
  assign out_we     = dma_targets_output ? dma_buf_we : 1'b1;
  assign out_addr   = dma_targets_output ? dma_buf_addr : out_wr_addr_q;
  assign out_wdata  = dma_targets_output ? dma_buf_wdata : out_wr_word;
  assign dma_buf_rdata = (dma_buf_sel == DMA_SEL_INPUT)  ? in_rdata  :
         (dma_buf_sel == DMA_SEL_WEIGHT) ? w_rdata   :
         out_rdata;

//  assign mac_done_o = (phase_q == PH_COMPUTE) && post_job_done_q;
		 assign status_o = mac_done_o || dma_done_o || status_error_o;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni)
    begin
      ctrl_start_r <= 1'b0;
    end
    else
    begin
      ctrl_start_r <= ctrl_start_o;
    end
  end


  always_comb
  begin
    phase_d = phase_q;
    unique case (phase_q)
             PH_IDLE:
               if (dma_start_gated)
                 phase_d = PH_DMA;
               else if (compute_start_gated)
                 phase_d = PH_COMPUTE;
             PH_DMA:
               if (dma_done_o)
                 phase_d = PH_IDLE;
             PH_COMPUTE:
               if (mac_done_o)
                 phase_d = PH_IDLE;
             default:
               phase_d = PH_IDLE;
           endcase
         end

         always_ff @(posedge clk_i or negedge rst_ni)
         begin
           if (!rst_ni)
             phase_q <= PH_IDLE;
           else
             phase_q <= phase_d;
         end


  dma_controller u_dma (
                   .clk_i(clk_i),
                   .rst_ni(rst_ni),
                   .busy_o(dma_busy_o),
                   .done_o(dma_done_o),
                   .axi_mst(data_mst),
                   .start_i(dma_start_gated),
                   .src_addr_i(dma_src_addr_o),
                   .dst_addr_i(32'd0),
                   .length_i({16'd0, dma_len_o}),
                   .sel_i(dma_sel_o),
                   .dir_i(dma_dir_o),
                   .buf_sel_o(dma_buf_sel),
                   .buf_en_o(dma_buf_en),
                   .buf_we_o(dma_buf_we),
                   .buf_addr_o(dma_buf_addr),
                   .buf_wdata_o(dma_buf_wdata),
                   .buf_rdata_i(dma_buf_rdata)
                 );




  register_ctrl u_reg_ctrl (
                  .clk_i(clk_i),
                  .rst_ni(rst_ni),
                  .axi_slv(data_slv),
                  .ctrl_start_o(ctrl_start_o),
                  .ctrl_soft_rst_o(ctrl_soft_rst_o),
                  .irq_en_o(irq_en_o),
                  .dma_src_addr_o(dma_src_addr_o),
                  .dma_sel_o(dma_sel_o),
                  .dma_len_o(dma_len_o),
                  .dma_dir_o(dma_dir_o),
                  .dma_start_o(dma_start_o),
                  .gemm_m_o(gemm_m_o),
                  .gemm_k_o(gemm_k_o),
                  .gemm_ntiles_o(gemm_ntiles_o),
                  .busy_i(dma_busy_o | mac_busy_o),
                  .done_pulse_i(mac_done_o),
                  .error_i(1'b0),
                  .dma_done_pulse_i(dma_done_o),
                  .out_elems_i(out_row_cnt_q),
                  .status_done_o(status_done_o),
                  .status_error_o(status_error_o)
                );



  //ACT BRAM
  bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_input (
         .clk_i(clk_i),
         .en_i(input_buf_en ),
         .we_i(input_buf_we),
         .be_i('1),
         .addr_i( in_addr),
         .wdata_i(in_wdata),
         .rdata_o(in_rdata)
       );
  //WEIGHT BRAM
  bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_weight (
         .clk_i(clk_i),
         .en_i(weight_buf_en ),
         .we_i(weight_buf_we),
         .be_i('1),
         .addr_i( w_addr),
         .wdata_i(w_wdata),
         .rdata_o(w_rdata)
       );

  // MAC ARRAY



  mac_array u_mac (
              .clk_i(clk_i),
              .rst_ni(rst_ni),
              .start_i(mac_start_pulse),
              .m_i(gemm_m_o),
              .k_i(gemm_k_o),
              .busy_o(mac_busy_o),
              .done_o(mac_done_o),
              .in_en_o(mac_in_en),
              .in_addr_o(mac_in_addr),
              .in_rdata_i(mac_in_rdata),
              .w_en_o(mac_w_en),
              .w_addr_o(mac_w_addr),
              .w_rdata_i(mac_w_rdata),
              .row_valid_o(row_valid),
              .row_m_o(row_m),
              .row_acc_o(row_acc)
            );

			 bram #(.WIDTH(AXI_DATA_W), .DEPTH(1024), .ADDRW(BUF_ADDR_W)) u_bram_output (
    .clk_i(clk_i), .en_i(out_en), .we_i(out_we), .be_i('1),
    .addr_i(out_addr), .wdata_i(out_wdata), .rdata_o(out_rdata)
  );




         genvar gp;

  generate
    for (gp = 0; gp < PE_COUNT; gp++)
    begin : g_pack
      assign out_wr_word[gp*8 +: 8] = row_acc[gp];
    end
  endgenerate



  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if (!rst_ni)
    begin
      out_row_cnt_q   <= '0;
      out_wr_addr_q   <= '0;
      post_job_done_q <= 1'b0;
    end
    else
    begin
      post_job_done_q <= 1'b0;
      if (phase_q != PH_COMPUTE)
      begin
        out_row_cnt_q <= '0;
        out_wr_addr_q <= '0;
      end
      else if (row_valid)
      begin
        out_row_cnt_q <= out_row_cnt_q + 16'd1;
        out_wr_addr_q <= out_wr_addr_q + BUF_ADDR_W'(1);
        if (last_pool_out)
          post_job_done_q <= 1'b1;
      end
    end
  end

endmodule
