// -------------------------------------------------------------------------------
// -- File       : cnn_accel_pkg.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Edited     : 14/07/2026
// -------------------------------------------------------------------------------
// -- Description: 
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------


package cnn_accel_pkg;
 
  // ---------------------------------------------------------------------
  // Compile-time architecture parameters
  // ---------------------------------------------------------------------
  parameter int PE_COUNT      = 4;   // parallel output channels (N-tile width), = 32-bit word / 8
  parameter int ACC_WIDTH     = 32;  // accumulator width per PE
  parameter int DATA_WIDTH    = 8;   // native MAC operand width (INT8). INT16 mode packs 2 cycles.
  parameter int BUF_ADDR_W    = 12;  // 4096 words per on-chip buffer (32-bit words)
  parameter int AXI_ADDR_W    = 32;
  parameter int AXI_DATA_W    = 32;

  parameter int AXI_IW      = 4;
  parameter int AXI_UW      = 1;
 
  // ---------------------------------------------------------------------
  // Register map (byte offsets from the IP's base address, word aligned)
  // ---------------------------------------------------------------------
  parameter logic [7:0] REG_CTRL        = 8'h00; // [0]=START [1]=SOFT_RST
  parameter logic [7:0] REG_STATUS      = 8'h04; // [0]=BUSY  [1]=DONE  [2]=ERROR
  parameter logic [7:0] REG_IRQ_EN      = 8'h08; // [0]=DONE_IE
  parameter logic [7:0] REG_IRQ_CLR     = 8'h0C; // write 1 to clear DONE/ERROR
  parameter logic [7:0] REG_DMA_SRC     = 8'h10; // system-memory address for the current DMA beat
  parameter logic [7:0] REG_DMA_SEL     = 8'h14; // [1:0] buffer select: 0=input 1=weight 2=output
  parameter logic [7:0] REG_DMA_LEN     = 8'h18; // transfer length in 32-bit words
  parameter logic [7:0] REG_DMA_DIR     = 8'h1C; // 0 = mem->buf (load), 1 = buf->mem (store)
  parameter logic [7:0] REG_DMA_START   = 8'h20; // write 1 to kick off the configured DMA op
  parameter logic [7:0] REG_GEMM_M      = 8'h24; // number of output rows (im2col rows)
  parameter logic [7:0] REG_GEMM_K      = 8'h28; // reduction depth (im2col row length)
  parameter logic [7:0] REG_GEMM_NTILES = 8'h2C; // number of PE_COUNT-wide N tiles to sweep
  parameter logic [7:0] REG_QUANT_SCALE = 8'h30; // Q0.16 fixed-point requant multiplier
  parameter logic [7:0] REG_QUANT_SHIFT = 8'h34; // right-shift applied after the multiply
  parameter logic [7:0] REG_QUANT_ZP    = 8'h38; // output zero point (added post-shift)
  parameter logic [7:0] REG_ACT_CTRL    = 8'h3C; // [0]=RELU_EN [1]=POOL_EN (2x2 max pool)
  parameter logic [7:0] REG_OUT_ELEMS   = 8'h40; // RO: number of valid 32-bit words written to out buf
 
  typedef enum logic [2:0] {
    ST_IDLE, ST_LOAD_K, ST_MAC, ST_DRAIN, ST_POOL, ST_DONE
  } compute_state_e;
 
  typedef enum logic [1:0] {
    DMA_SEL_INPUT  = 2'd0,
    DMA_SEL_WEIGHT = 2'd1,
    DMA_SEL_OUTPUT = 2'd2
  } dma_sel_e;
 
endpackage : cnn_accel_pkg