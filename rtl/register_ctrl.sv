// -------------------------------------------------------------------------------
// -- File       : register_ctrl.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Edited     : 14/07/2026
// -------------------------------------------------------------------------------
// -- Description: This module implements a register controller for the CNN accelerator.
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------

import cnn_accel_pkg::*;

module register_ctrl (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  // AXI slave port (core -> accelerator)
  AXI_BUS.Slave                   axi_slv,

  // Decoded control fields -> rest of the IP
  output logic                    ctrl_start_o,
  output logic                    ctrl_soft_rst_o,
  output logic                    irq_en_o,
  output logic [AXI_ADDR_W-1:0]    dma_src_addr_o,
  output logic [1:0]               dma_sel_o,
  output logic [15:0]              dma_len_o,
  output logic                    dma_dir_o,
  output logic                    dma_start_o,
  output logic [15:0]              gemm_m_o,
  output logic [15:0]              gemm_k_o,
  output logic [15:0]              gemm_ntiles_o,
  // output logic [17:0]              quant_scale_o,
  // output logic [4:0]               quant_shift_o,
  // output logic [7:0]               quant_zp_o,
  // output logic                    relu_en_o,
  // output logic                    pool_en_o,
 
  // Status feedback -> registers
  input  logic                    busy_i,
  input  logic                    done_pulse_i,
  input  logic                    error_i,
  input  logic                    dma_done_pulse_i,
  input  logic [15:0]             out_elems_i,
 
  // Level status, for the top level to derive the interrupt line
  output logic                    status_done_o,
  output logic                    status_error_o
);


logic        r_busy, r_done, r_error;
logic        r_irq_en;
logic [AXI_ADDR_W-1:0] r_dma_src;
logic [1:0]  r_dma_sel;
logic [15:0] r_dma_len;
logic        r_dma_dir;
logic [15:0] r_gemm_m, r_gemm_k, r_gemm_ntiles;
logic [17:0] r_quant_scale;
logic [4:0]  r_quant_shift;
logic [7:0]  r_quant_zp;
logic        r_relu_en, r_pool_en;

logic [15:0] r_out_elems;

  logic [1:0] ctrl_start_ctr, ctrl_soft_rst_ctr, dma_start_ctr;
  logic ctrl_start_hold, ctrl_soft_rst_hold, dma_start_hold;

  logic [AXI_ADDR_W-1:0] awaddr_q, araddr_q;
  logic [AXI_DATA_W-1:0] wdata_q;
  logic [3:0]            wstrb_q;
  logic aw_seen_q, w_seen_q;
  logic bvalid_q, rvalid_q;
  logic [AXI_DATA_W-1:0] rdata_q;

  logic aw_fire, w_fire, ar_fire;
  logic write_complete;
  logic [AXI_ADDR_W-1:0] write_addr;
  logic [AXI_DATA_W-1:0] write_data;
  logic [3:0]            write_strb;

  assign ctrl_start_o    = ctrl_start_hold;
  assign ctrl_soft_rst_o = ctrl_soft_rst_hold;
  assign irq_en_o        = r_irq_en;
  assign dma_src_addr_o  = r_dma_src;
  assign dma_sel_o       = r_dma_sel;
  assign dma_len_o       = r_dma_len;
  assign dma_dir_o       = r_dma_dir;
  assign dma_start_o     = dma_start_hold;
  assign gemm_m_o        = r_gemm_m;
  assign gemm_k_o        = r_gemm_k;
  assign gemm_ntiles_o   = r_gemm_ntiles;
  // assign quant_scale_o   = r_quant_scale;
  // assign quant_shift_o   = r_quant_shift;
  // assign quant_zp_o      = r_quant_zp;
  // assign relu_en_o       = r_relu_en;
  // assign pool_en_o       = r_pool_en;
  assign status_done_o   = r_done;
  assign status_error_o  = r_error;

  assign aw_fire = axi_slv.aw_valid && axi_slv.aw_ready;
  assign w_fire  = axi_slv.w_valid  && axi_slv.w_ready;
  assign ar_fire = axi_slv.ar_valid && axi_slv.ar_ready;

  assign axi_slv.aw_ready = !bvalid_q && !aw_seen_q;
  assign axi_slv.w_ready  = !bvalid_q && !w_seen_q;
  assign axi_slv.b_valid  = bvalid_q;
  assign axi_slv.b_resp   = 2'b00;
  assign axi_slv.b_id     = '0;
  assign axi_slv.b_user   = '0;
  assign axi_slv.ar_ready = !rvalid_q;
  assign axi_slv.r_valid  = rvalid_q;
  assign axi_slv.r_data   = rdata_q;
  assign axi_slv.r_resp   = 2'b00;
  assign axi_slv.r_last   = 1'b1;
  assign axi_slv.r_id     = '0;
  assign axi_slv.r_user   = '0;

  assign write_complete = (aw_seen_q || aw_fire) && (w_seen_q || w_fire);
  assign write_addr     = aw_fire ? axi_slv.aw_addr : awaddr_q;
  assign write_data     = w_fire  ? axi_slv.w_data  : wdata_q;
  assign write_strb     = w_fire  ? axi_slv.w_strb  : wstrb_q;

  function automatic logic [AXI_DATA_W-1:0] read_reg(input logic [AXI_ADDR_W-1:0] addr);
    unique case (addr[7:0])
      REG_CTRL:        read_reg = '0;
      REG_STATUS:      read_reg = {29'd0, r_error, r_done, busy_i};
      REG_IRQ_EN:      read_reg = {31'd0, r_irq_en};
      REG_DMA_SRC:     read_reg = r_dma_src;
      REG_DMA_SEL:     read_reg = {30'd0, r_dma_sel};
      REG_DMA_LEN:     read_reg = {16'd0, r_dma_len};
      REG_DMA_DIR:     read_reg = {31'd0, r_dma_dir};
      REG_GEMM_M:      read_reg = {16'd0, r_gemm_m};
      REG_GEMM_K:      read_reg = {16'd0, r_gemm_k};
      REG_GEMM_NTILES: read_reg = {16'd0, r_gemm_ntiles};
      REG_QUANT_SCALE: read_reg = {14'd0, r_quant_scale};
      REG_QUANT_SHIFT: read_reg = {27'd0, r_quant_shift};
      REG_QUANT_ZP:    read_reg = {24'd0, r_quant_zp};
      REG_ACT_CTRL:    read_reg = {30'd0, r_pool_en, r_relu_en};
      REG_OUT_ELEMS:   read_reg = {16'd0, r_out_elems};
      default:         read_reg = 32'hDEAD_BEEF;
    endcase
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_busy <= 1'b0; r_done <= 1'b0; r_error <= 1'b0;
      r_irq_en <= 1'b0;
      r_dma_src <= '0; r_dma_sel <= '0; r_dma_len <= '0; r_dma_dir <= 1'b0;
      r_gemm_m <= '0; r_gemm_k <= '0; r_gemm_ntiles <= '0;
      r_quant_scale <= 18'd65536;
      r_quant_shift <= 5'd16;
      r_quant_zp <= '0;
      r_relu_en <= 1'b0; r_pool_en <= 1'b0;
      r_out_elems <= '0;
      ctrl_start_hold <= 1'b0; ctrl_start_ctr <= 2'd0;
      ctrl_soft_rst_hold <= 1'b0; ctrl_soft_rst_ctr <= 2'd0;
      dma_start_hold  <= 1'b0; dma_start_ctr  <= 2'd0;
      awaddr_q <= '0; araddr_q <= '0; wdata_q <= '0; wstrb_q <= '0;
      aw_seen_q <= 1'b0; w_seen_q <= 1'b0;
      bvalid_q  <= 1'b0; rvalid_q <= 1'b0; rdata_q <= '0;
    end else begin
      // count down the hold timers each cycle
      if (ctrl_start_ctr > 2'd0) ctrl_start_ctr <= ctrl_start_ctr - 2'd1;
      else                         ctrl_start_hold <= 1'b0;
      if (ctrl_soft_rst_ctr > 2'd0) ctrl_soft_rst_ctr <= ctrl_soft_rst_ctr - 2'd1;
      else                           ctrl_soft_rst_hold <= 1'b0;
      if (dma_start_ctr  > 2'd0) dma_start_ctr  <= dma_start_ctr  - 2'd1;
      else                         dma_start_hold  <= 1'b0;

      // status updates from datapath
      r_busy  <= busy_i;
      if (done_pulse_i) begin r_done <= 1'b1;r_out_elems <= out_elems_i;end
      if (error_i)       r_error <= 1'b1;
      // if (dma_done_pulse_i)  ;// status observed via BUSY only in v1
      // r_out_elems <= out_elems_i;

      if (aw_fire) begin
        awaddr_q <= axi_slv.aw_addr;
        aw_seen_q <= 1'b1;
      end
      if (w_fire) begin
        wdata_q <= axi_slv.w_data;
        wstrb_q <= axi_slv.w_strb;
        w_seen_q <= 1'b1;
      end

      if (!bvalid_q && write_complete) begin
        unique case (write_addr[7:0])
          REG_CTRL: begin
            if (write_strb[0] && write_data[0]) begin
              ctrl_start_hold <= 1'b1; ctrl_start_ctr <= 2'd3;
            end
            if (write_strb[0] && write_data[1]) begin
              ctrl_soft_rst_hold <= 1'b1; ctrl_soft_rst_ctr <= 2'd3;
            end
          end
          REG_IRQ_EN:      if (write_strb[0]) r_irq_en <= write_data[0];
          REG_IRQ_CLR:     if (write_strb[0] && write_data[0]) begin
                             r_done <= 1'b0; r_error <= 1'b0;
                           end
          REG_DMA_SRC:     r_dma_src     <= write_data;
          REG_DMA_SEL:     if (write_strb[0]) r_dma_sel <= write_data[1:0];
          REG_DMA_LEN:     if (|write_strb[1:0]) r_dma_len <= write_data[15:0];
          REG_DMA_DIR:     if (write_strb[0]) r_dma_dir <= write_data[0];
          REG_DMA_START:   if (write_strb[0] && write_data[0]) begin
                             dma_start_hold <= 1'b1; dma_start_ctr <= 2'd3;
                           end
          REG_GEMM_M:      r_gemm_m      <= write_data[15:0];
          REG_GEMM_K:      r_gemm_k      <= write_data[15:0];
          REG_GEMM_NTILES: r_gemm_ntiles <= write_data[15:0];
          // REG_QUANT_SCALE: r_quant_scale <= write_data[17:0];
          // REG_QUANT_SHIFT: r_quant_shift <= write_data[4:0];
          // REG_QUANT_ZP:    r_quant_zp    <= write_data[7:0];
          REG_ACT_CTRL:    begin
                             r_relu_en <= write_data[0];
                             r_pool_en <= write_data[1];
                           end
          default: ;
        endcase
        bvalid_q <= 1'b1;
        aw_seen_q <= 1'b0;
        w_seen_q  <= 1'b0;
      end

      if (bvalid_q && axi_slv.b_ready) begin
        bvalid_q <= 1'b0;
      end

      if (ar_fire) begin
        araddr_q <= axi_slv.ar_addr;
        rdata_q  <= read_reg(axi_slv.ar_addr);
        rvalid_q <= 1'b1;
      end else if (rvalid_q && axi_slv.r_ready) begin
        rvalid_q <= 1'b0;
      end
    end
  end





endmodule
