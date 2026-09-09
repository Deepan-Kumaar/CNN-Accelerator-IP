#ifndef CNN_H
#define CNN_H

#include <stdint.h>
// #include "drivers/cnn.c"


#define CNN_PE_COUNT 4


void cnn_init(void);
void cnn_reset(void);

void cnn_start(void);

uint32_t cnn_status(void);

int cnn_is_busy(void);
int cnn_is_done(void);
int cnn_has_error(void);

int cnn_wait(void);


void cnn_config_gemm(
    uint16_t m,
    uint16_t k,
    uint16_t n
);


int cnn_dma_load_input(
    const void *src_addr,
    uint32_t words
);


int cnn_dma_load_weights(
    const void *src_addr,
    uint32_t words
);


int cnn_dma_store_output(
    const void *dst_addr,
    uint32_t words
);


int cnn_matmul_4x4(
    const int8_t input[4][4],
    const int8_t weight[4][4]
    // int8_t output[4][4]
);

#endif