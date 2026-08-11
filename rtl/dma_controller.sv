// -------------------------------------------------------------------------------
// -- File       : dma_controller.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Edited     : 14/07/2026
// -------------------------------------------------------------------------------
// -- Description: This module implements a DMA controller that handles data transfers 
//    between system memory and on-chip buffers.
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------


import cnn_accel_pkg::*;

module dma_controller (
    input logic clk_i,
    input logic rst_ni,

    
    output logic busy_o,
    output logic done_o,

//   AXI MASTER interface
    AXI_BUS.Master axi_mst,
  

    // DMA configuration registers
    input logic start_i,
    input logic [31:0] src_addr_i,
    input logic [31:0] dst_addr_i,
    input logic [31:0] length_i,
    input logic [1:0] sel_i,  // buffer select
    input logic dir_i,        // 0: load (mem->buf), 1: store (buf->mem)

    // Generic port into the on-chip buffers (muxed by buf_sel_o at top level)
  output logic [1:0]              buf_sel_o,
  output logic                    buf_en_o,
  output logic                    buf_we_o,
  output logic [BUF_ADDR_W-1:0]   buf_addr_o,
  output logic [AXI_DATA_W-1:0]   buf_wdata_o,
  input  logic [AXI_DATA_W-1:0]   buf_rdata_i
  );
  
     
typedef enum logic [4:0] {
    S_IDLE,

    // LOAD: mem -> buf
    S_LOAD_AR,
    S_LOAD_R_WAIT,
    S_LOAD_COMMIT,

    // STORE: buf -> mem
    S_STORE_RDBUF,
    S_STORE_LATCH,
    S_STORE_AW,
    S_STORE_W,
    S_STORE_B_WAIT,

    S_DONE,
    S_ERROR
  } dma_state_e;

  dma_state_e state_q, state_d;

logic [AXI_ADDR_W-1:0] addr_q, addr_d;
  logic [15:0]           cnt_q, cnt_d;
  logic [15:0]           len_q, len_d;      // latched transfer length
  logic [1:0]            sel_q, sel_d;
  logic                  dir_q, dir_d;
  logic [AXI_DATA_W-1:0] store_data_q, store_data_d;



 wire last_word = (cnt_q == (len_q - 16'd1));

  assign busy_o = (state_q != S_IDLE);

  always_comb begin
    // ---------------- defaults ----------------
    state_d      = state_q;
    addr_d       = addr_q;
    cnt_d        = cnt_q;
    len_d        = len_q;
    sel_d        = sel_q;
    dir_d        = dir_q;
    store_data_d = store_data_q;
    // error_d      = error_q;

    done_o = 1'b0;
    // error_o      = 1'b0;

    // AXI defaults
    // AW
axi_mst.aw_valid  = 1'b0;
axi_mst.aw_addr   = addr_q;
axi_mst.aw_id     = '0;
axi_mst.aw_len    = 8'd0;
axi_mst.aw_size   = 3'b010;
axi_mst.aw_burst  = 2'b01;
axi_mst.aw_lock   = 1'b0;
axi_mst.aw_cache  = 4'b0011;
axi_mst.aw_prot   = 3'b000;
axi_mst.aw_qos    = 4'd0;
axi_mst.aw_region = 4'd0;
axi_mst.aw_atop   = 6'd0;
axi_mst.aw_user   = '0;

// W
axi_mst.w_valid   = 1'b0;
axi_mst.w_data    = store_data_q;
axi_mst.w_strb    = 4'hF;
axi_mst.w_last    = 1'b1;
axi_mst.w_user    = '0;

// B
axi_mst.b_ready   = 1'b0;

// AR
axi_mst.ar_valid  = 1'b0;
axi_mst.ar_addr   = addr_q;
axi_mst.ar_id     = '0;
axi_mst.ar_len    = 8'd0;
axi_mst.ar_size   = 3'b010;
axi_mst.ar_burst  = 2'b01;
axi_mst.ar_lock   = 1'b0;
axi_mst.ar_cache  = 4'b0011;
axi_mst.ar_prot   = 3'b000;
axi_mst.ar_qos    = 4'd0;
axi_mst.ar_region = 4'd0;
axi_mst.ar_user   = '0;

// R
axi_mst.r_ready   = 1'b0;

    // Buffer defaults
    buf_sel_o     = sel_q;
    buf_en_o      = 1'b0;
    buf_we_o      = 1'b0;
    buf_addr_o    = cnt_q[BUF_ADDR_W-1:0];
    buf_wdata_o   = axi_mst.r_data;

    unique case (state_q)
      S_IDLE: begin
        // error_d = 1'b0;
        if (start_i && (length_i != 16'd0)) begin
          addr_d = src_addr_i;
          cnt_d  = 16'd0;
          len_d  = length_i;      // latch length
          sel_d  = sel_i;
          dir_d  = dir_i;
          if (dir_i) state_d = S_STORE_RDBUF;
          else       state_d = S_LOAD_AR;
        end
      end

      // ---------------- LOAD: system memory -> on-chip buffer ----------------
      S_LOAD_AR: begin
        axi_mst.ar_valid = 1'b1;
        axi_mst.ar_addr  = addr_q;
        if (axi_mst.ar_valid && axi_mst.ar_ready) begin
          state_d = S_LOAD_R_WAIT;
        end
      end

      S_LOAD_R_WAIT: begin
        axi_mst.r_ready = 1'b1;
        if (axi_mst.r_valid && axi_mst.r_ready) begin
          // Check AXI read response and last for single-beat transfer
          if ((axi_mst.r_resp != 2'b00) || (axi_mst.r_last != 1'b1)) begin
            // error_d = 1'b1;
            state_d = S_ERROR;
          end else begin
            buf_en_o    = 1'b1;
            buf_we_o    = 1'b1;
            buf_addr_o  = cnt_q[BUF_ADDR_W-1:0];
            buf_wdata_o = axi_mst.r_data;
            state_d     = S_LOAD_COMMIT;
          end
        end
      end

      S_LOAD_COMMIT: begin
        // one cycle for BRAM write to land
        if (last_word) state_d = S_DONE;
        else begin
          cnt_d   = cnt_q + 16'd1;
          addr_d  = addr_q + AXI_ADDR_W'(32'd4);
          state_d = S_LOAD_AR;
        end
      end

      // ---------------- STORE: on-chip buffer -> system memory ----------------
      S_STORE_RDBUF: begin
        buf_en_o   = 1'b1;
        buf_we_o   = 1'b0;
        buf_addr_o = cnt_q[BUF_ADDR_W-1:0];
        state_d    = S_STORE_LATCH;
      end

      S_STORE_LATCH: begin
        // 1-cycle BRAM latency assumption
        store_data_d = buf_rdata_i;
        state_d      = S_STORE_AW;
      end

      S_STORE_AW: begin
        axi_mst.aw_valid = 1'b1;
        axi_mst.aw_addr  = addr_q;
        if (axi_mst.aw_valid && axi_mst.aw_ready) begin
          state_d = S_STORE_W;
        end
      end

      S_STORE_W: begin
        axi_mst.w_valid = 1'b1;
        axi_mst.w_data  = store_data_q;
        axi_mst.w_strb  = 4'hF;
        axi_mst.w_last  = 1'b1;
        if (axi_mst.w_valid && axi_mst.w_ready) begin
          state_d = S_STORE_B_WAIT;
        end
      end

      S_STORE_B_WAIT: begin
        axi_mst.b_ready = 1'b1;
        if (axi_mst.b_valid && axi_mst.b_ready) begin
          if (axi_mst.b_resp != 2'b00) begin
            // error_d = 1'b1;
            state_d = S_ERROR;
          end else if (last_word) begin
            state_d = S_DONE;
          end else begin
            cnt_d   = cnt_q + 16'd1;
            addr_d  = addr_q + AXI_ADDR_W'(32'd4);
            state_d = S_STORE_RDBUF;
          end
        end
      end

      S_DONE: begin
        done_o = 1'b1;
        state_d      = S_IDLE;
      end

      S_ERROR: begin
        // error_o  = 1'b1; // pulse on terminal error
        state_d  = S_IDLE;
      end

      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= S_IDLE;
      addr_q       <= '0;
      cnt_q        <= '0;
      len_q        <= '0;
      sel_q        <= '0;
      dir_q        <= 1'b0;
      store_data_q <= '0;
    //   error_q      <= 1'b0;
    end else begin
      state_q      <= state_d;
      addr_q       <= addr_d;
      cnt_q        <= cnt_d;
      len_q        <= len_d;
      sel_q        <= sel_d;
      dir_q        <= dir_d;
      store_data_q <= store_data_d;
      // error_q      <= error_d;
    end
  end

endmodule : dma_controller
