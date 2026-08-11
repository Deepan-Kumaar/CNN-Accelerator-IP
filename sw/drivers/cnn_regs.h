#ifndef CNN_REGS_H
#define CNN_REGS_H

#include <stdint.h>

/*
 * CNN AXI slave base address
 */
#define CNN_BASE        0x10000000


/* Register offsets */
#define CNN_REG_CTRL        0x00
#define CNN_REG_STATUS      0x04
#define CNN_REG_IRQ_EN      0x08
#define CNN_REG_IRQ_CLR     0x0C

#define CNN_REG_DMA_SRC     0x10
#define CNN_REG_DMA_SEL     0x14
#define CNN_REG_DMA_LEN     0x18
#define CNN_REG_DMA_DIR     0x1C
#define CNN_REG_DMA_START   0x20

#define CNN_REG_GEMM_M      0x24
#define CNN_REG_GEMM_K      0x28
#define CNN_REG_GEMM_NTILES 0x2C

#define CNN_REG_QUANT_SCALE 0x30
#define CNN_REG_QUANT_SHIFT 0x34
#define CNN_REG_QUANT_ZP    0x38
#define CNN_REG_ACT_CTRL    0x3C

#define CNN_REG_OUT_ELEMS   0x40


/* Register access */
#define CNN_CTRL \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_CTRL))

#define CNN_STATUS \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_STATUS))

#define CNN_IRQ_EN \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_IRQ_EN))

#define CNN_IRQ_CLR \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_IRQ_CLR))

#define CNN_DMA_SRC \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_DMA_SRC))

#define CNN_DMA_SEL \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_DMA_SEL))

#define CNN_DMA_LEN \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_DMA_LEN))

#define CNN_DMA_DIR \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_DMA_DIR))

#define CNN_DMA_START \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_DMA_START))

#define CNN_GEMM_M \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_GEMM_M))

#define CNN_GEMM_K \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_GEMM_K))

#define CNN_GEMM_NTILES \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_GEMM_NTILES))

#define CNN_QUANT_SCALE \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_QUANT_SCALE))

#define CNN_QUANT_SHIFT \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_QUANT_SHIFT))

#define CNN_QUANT_ZP \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_QUANT_ZP))

#define CNN_ACT_CTRL \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_ACT_CTRL))

#define CNN_OUT_ELEMS \
    (*(volatile uint32_t *)(CNN_BASE + CNN_REG_OUT_ELEMS))


/* CTRL */
#define CNN_CTRL_START       (1u << 0)
#define CNN_CTRL_SOFT_RST    (1u << 1)


/* STATUS */
#define CNN_STATUS_BUSY      (1u << 0)
#define CNN_STATUS_DONE      (1u << 1)
#define CNN_STATUS_ERROR     (1u << 2)


/* DMA buffer selection */
#define CNN_DMA_SEL_INPUT    0
#define CNN_DMA_SEL_WEIGHT   1
#define CNN_DMA_SEL_OUTPUT   2


/* DMA direction */
#define CNN_DMA_MEM_TO_BUF   0
#define CNN_DMA_BUF_TO_MEM   1


#endif