#include "cnn.h"
#include "cnn_regs.h"


/*
 * Temporary buffers in Data SRAM.
 *
 * Input:
 *   16 words
 *
 * Weight:
 *    4 words
 *
 * Output:
 *    4 words
 */
static uint32_t input_dma_buf[16]
    __attribute__((aligned(4)));

static uint32_t weight_dma_buf[4]
    __attribute__((aligned(4)));

// static uint32_t output_dma_buf[4]
//     __attribute__((aligned(4)));


/*
 * Clear sticky DONE/ERROR bits before launching a new job.
 */
static void cnn_clear_status(void)
{
    CNN_IRQ_CLR = 0xFFFFFFFFu;
}


/*
 * ---------------------------------------------------------
 * Reset / initialization
 * ---------------------------------------------------------
 */

void cnn_reset(void)
{
    CNN_CTRL = CNN_CTRL_SOFT_RST;

    for (volatile int i = 0; i < 16; i++) {
        __asm__ volatile ("nop");
    }

    CNN_CTRL = 0;
}


void cnn_init(void)
{
    cnn_reset();

    /*
     * Polling mode for initial bring-up.
     */
    CNN_IRQ_EN = 0;

    /*
     * Clear stale interrupt/status state.
     */
    cnn_clear_status();
}


/*
 * ---------------------------------------------------------
 * Status
 * ---------------------------------------------------------
 */

uint32_t cnn_status(void)
{
    return CNN_STATUS;
}


int cnn_is_busy(void)
{
    return (CNN_STATUS & CNN_STATUS_BUSY) != 0;
}


int cnn_is_done(void)
{
    return (CNN_STATUS & CNN_STATUS_DONE) != 0;
}


int cnn_has_error(void)
{
    return (CNN_STATUS & CNN_STATUS_ERROR) != 0;
}


/*
 * ---------------------------------------------------------
 * GEMM configuration
 * ---------------------------------------------------------
 */

void cnn_config_gemm(
    uint16_t m,
    uint16_t k,
    uint16_t n
)
{
    CNN_GEMM_M = m;
    CNN_GEMM_K = k;

    /*
     * Number of 4-PE output tiles.
     *
     * N = 4
     * PE_COUNT = 4
     *
     * => NTILES = 1
     */
    CNN_GEMM_NTILES =
        (n + CNN_PE_COUNT - 1) / CNN_PE_COUNT;
}


/*
 * ---------------------------------------------------------
 * Start / wait
 * ---------------------------------------------------------
 */

void cnn_start(void)
{
    /*
     * Make sure old completion bits do not confuse the next poll loop.
     */
    cnn_clear_status();

    CNN_CTRL = CNN_CTRL_START;
}


int cnn_wait(void)
{
    while (1) {

        uint32_t status = CNN_STATUS;

        if (status & CNN_STATUS_ERROR) {
            return -1;
        }

        if (status & CNN_STATUS_DONE) {
            return 0;
        }
    }
}


/*
 * ---------------------------------------------------------
 * DMA helper
 * ---------------------------------------------------------
 */

static int cnn_dma(
    uintptr_t address,
    uint32_t selection,
    uint32_t words,
    uint32_t direction
)
{
    /*
     * Program DMA.
     */
    CNN_DMA_SRC = (uint32_t)address;
    CNN_DMA_SEL = selection;

    /*
     * DMA controller increments address by 4.
     *
     * Therefore this is number of 32-bit words.
     */
    CNN_DMA_LEN = words;

    CNN_DMA_DIR = direction;


    /*
     * Start DMA.
     */
    CNN_DMA_START = 1;


    /*
     * Wait for the engine to actually enter the busy state first.
     *
     * This avoids a false success if the start pulse has not yet been
     * sampled when the CPU reaches the polling loop.
     */
    while (!cnn_is_busy()) {
        if (cnn_has_error()) {
            return -1;
        }
    }


    /*
     * Wait until DMA completes.
     */
    while (cnn_is_busy()) {

        if (cnn_has_error()) {
            return -1;
        }
    }


    return 0;
}


/*
 * ---------------------------------------------------------
 * Input DMA
 * ---------------------------------------------------------
 */

int cnn_dma_load_input(
    const void *src_addr,
    uint32_t words
)
{
    return cnn_dma(
        (uintptr_t)src_addr,
        CNN_DMA_SEL_INPUT,
        words,
        CNN_DMA_MEM_TO_BUF
    );
}


/*
 * ---------------------------------------------------------
 * Weight DMA
 * ---------------------------------------------------------
 */

int cnn_dma_load_weights(
    const void *src_addr,
    uint32_t words
)
{
    return cnn_dma(
        (uintptr_t)src_addr,
        CNN_DMA_SEL_WEIGHT,
        words,
        CNN_DMA_MEM_TO_BUF
    );
}


/*
 * ---------------------------------------------------------
 * Output DMA
 * ---------------------------------------------------------
 */

int cnn_dma_store_output(
    const void *dst_addr,
    uint32_t words
)
{
    return cnn_dma(
        (uintptr_t)dst_addr,
        CNN_DMA_SEL_OUTPUT,
        words,
        CNN_DMA_BUF_TO_MEM
    );
}


/*
 * ---------------------------------------------------------
 * Pack input
 * ---------------------------------------------------------
 *
 * Accelerator expects:
 *
 * input BRAM word 0 = input[0][0]
 * input BRAM word 1 = input[0][1]
 * ...
 *
 * Only bits [7:0] are consumed.
 */

static void pack_input(
    const int8_t input[4][4]
)
{
    for (int i = 0; i < 4; i++) {

        for (int k = 0; k < 4; k++) {

            input_dma_buf[i * 4 + k] =
                (uint32_t)(uint8_t)input[i][k];
        }
    }
}


/*
 * ---------------------------------------------------------
 * Pack weights
 * ---------------------------------------------------------
 *
 * One BRAM word contains four weights:
 *
 * bits [7:0]   = W[k][0]
 * bits [15:8]  = W[k][1]
 * bits [23:16] = W[k][2]
 * bits [31:24] = W[k][3]
 */

static void pack_weights(
    const int8_t weight[4][4]
)
{
    for (int k = 0; k < 4; k++) {

        uint32_t word = 0;

        for (int n = 0; n < 4; n++) {

            word |=
                ((uint32_t)(uint8_t)weight[k][n])
                << (8 * n);
        }

        weight_dma_buf[k] = word;
    }
}


/*
 * ---------------------------------------------------------
 * Unpack output
 * ---------------------------------------------------------
 *
 * Output BRAM:
 *
 * word 0:
 *
 * [31:24] output[0][3]
 * [23:16] output[0][2]
 * [15:8]  output[0][1]
 * [7:0]   output[0][0]
 *
 * word 1 = row 1
 * word 2 = row 2
 * word 3 = row 3
 */

// static void unpack_output(
//     int8_t output[4][4]
// )
// {
//     for (int i = 0; i < 4; i++) {

//         uint32_t word = output_dma_buf[i];

//         for (int j = 0; j < 4; j++) {

//             output[i][j] =
//                 (int8_t)((word >> (8 * j)) & 0xFF);
//         }
//     }
// }


/*
 * ---------------------------------------------------------
 * 4x4 Matrix Multiplication
 * ---------------------------------------------------------
 */

int cnn_matmul_4x4(
    const int8_t input[4][4],
    const int8_t weight[4][4]
    // int8_t output[4][4]
)
{
    /*
     * Prepare data in exactly the format
     * expected by the CNN BRAMs.
     */
    pack_input(input);
    pack_weights(weight);


    /*
     * -----------------------------------------------------
     * Load input
     * -----------------------------------------------------
     *
     * 16 x 32-bit words.
     */
    cnn_dma_load_input(
            input_dma_buf,
            16) ;


    /*
     * -----------------------------------------------------
     * Load weights
     * -----------------------------------------------------
     *
     * 4 x 32-bit words.
     */
   cnn_dma_load_weights(
            weight_dma_buf,
            4) ;


    /*
     * -----------------------------------------------------
     * Configure GEMM
     * -----------------------------------------------------
     *
     * M = 4
     * K = 4
     * N = 4
     *
     * NTILES = 1
     */
    cnn_config_gemm(4, 4, 4);


    // /*
    //  * -----------------------------------------------------
    //  * Start CNN
    //  * -----------------------------------------------------
    //  */
    // cnn_start();


    // /*
    //  * -----------------------------------------------------
    //  * Wait for computation
    //  * -----------------------------------------------------
    //  */
    // cnn_wait() ;


    // /*
    //  * -----------------------------------------------------
    //  * Copy output BRAM → Data SRAM
    //  * -----------------------------------------------------
    //  *
    //  * Four rows × one 32-bit word per row.
    //  */
    // cnn_dma_store_output(
    //         output_dma_buf,
    //         4) ;


    // /*
    //  * Convert packed output words into
    //  * output[4][4].
    //  */
    // unpack_output(output);


    return 0;
}