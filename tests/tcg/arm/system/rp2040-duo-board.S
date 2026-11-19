/*
 * duo-rp2040 board: 16 MiB flash, MCP23S17 on SPI1, PIO TX DMA sink.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

.syntax unified
.cpu cortex-m0plus
.thumb

#define SRAM_END        0x20042000
#define UART0_DR        0x40034000
#define SPI1_BASE       0x40040000
#define SSPCR0          0x00
#define SSPCR1          0x04
#define SSPDR           0x08
#define SSPSR           0x0c
#define SSPCPSR         0x10
#define ALIAS_SET       0x2000
#define CR1_SSE         0x02
#define SR_RNE          0x04
#define MCP_WRITE       0x40
#define MCP_READ        0x41
#define MCP_IODIRA      0x00
#define MCP_IOCON       0x0a
#define MCP_IOCON_HAEN  0x08
#define FLASH_LAST_WORD 0x10fffffc
#define DMA_BASE        0x50000000
#define DMA_READ_ADDR   0x00
#define DMA_WRITE_ADDR  0x04
#define DMA_TRANS_COUNT 0x08
#define DMA_CTRL_TRIG   0x0c
#define DMA_CTRL_BUSY   0x01000000
/* EN, DATA_SIZE 32-bit, TREQ_SEL PIO0 TX0 (0), CHAIN_TO itself (0). */
#define DMA_CTRL_PIO0_TX0 0x00000009
#define DMA_SRC         0x20010000
#define DMA_DST         0x20010010
#define SYS_EXIT        0x18
#define ADP_STOPPED_APPLICATION_EXIT 0x20026
#define ADP_STOPPED_RUNTIME_ERROR    0x20023

.section .vectors, "a", %progbits
vector_table:
    .word SRAM_END
    .word reset_handler + 1
    .word default_handler + 1
    .word default_handler + 1

.section .text, "ax", %progbits
.thumb_func
.global reset_handler
reset_handler:
    /* Flash: the last word of 16 MiB reads as erased. */
    ldr r0, =FLASH_LAST_WORD
    ldr r0, [r0]
    movs r1, 0
    mvns r1, r1
    cmp r0, r1
    bne fail_flash
    ldr r0, =flash_message
    bl puts

    /* MCP23S17 on SPI1: reset value, then the IOCON write and readback. */
    ldr r4, =SPI1_BASE
    movs r0, 7
    str r0, [r4, SSPCR0]
    movs r0, 2
    str r0, [r4, SSPCPSR]
    ldr r5, =ALIAS_SET + SSPCR1
    movs r0, CR1_SSE
    str r0, [r4, r5]

    movs r0, MCP_READ
    movs r1, MCP_IODIRA
    movs r2, 0
    bl mcp_transfer
    cmp r0, 0xff
    bne fail_iodir

    movs r0, MCP_WRITE
    movs r1, MCP_IOCON
    movs r2, MCP_IOCON_HAEN
    bl mcp_transfer
    movs r0, MCP_READ
    movs r1, MCP_IOCON
    movs r2, 0
    bl mcp_transfer
    cmp r0, MCP_IOCON_HAEN
    bne fail_iocon
    ldr r0, =mcp_message
    bl puts

    /* DMA paced by PIO0 TX0 completes. */
    ldr r4, =DMA_BASE
    ldr r0, =DMA_SRC
    ldr r1, =0x5a5aa5a5
    str r1, [r0]
    str r0, [r4, DMA_READ_ADDR]
    ldr r0, =DMA_DST
    str r0, [r4, DMA_WRITE_ADDR]
    movs r0, 1
    str r0, [r4, DMA_TRANS_COUNT]
    ldr r0, =DMA_CTRL_PIO0_TX0
    str r0, [r4, DMA_CTRL_TRIG]
    ldr r2, =0x100000

1:
    ldr r0, [r4, DMA_CTRL_TRIG]
    ldr r1, =DMA_CTRL_BUSY
    tst r0, r1
    beq 2f
    subs r2, 1
    bne 1b
    b fail_dma

2:
    ldr r0, =DMA_DST
    ldr r0, [r0]
    ldr r1, =0x5a5aa5a5
    cmp r0, r1
    bne fail_dma
    ldr r0, =dma_message
    bl puts

    ldr r0, =ok_message
    bl puts
    movs r0, SYS_EXIT
    ldr r1, =ADP_STOPPED_APPLICATION_EXIT
    bkpt 0xab

3:
    b 3b

/* r0 opcode, r1 register, r2 data: three SPI1 bytes; returns the third RX byte. */
.thumb_func
mcp_transfer:
    push {r5, r6, lr}
    mov r6, r2
    bl spi_byte
    mov r0, r1
    bl spi_byte
    mov r0, r6
    bl spi_byte
    pop {r5, r6, pc}

/* r4 SPI base, r0 byte out; returns the byte in. */
.thumb_func
spi_byte:
    push {r1, r2, lr}
    str r0, [r4, SSPDR]
    ldr r2, =0x100000

4:
    ldr r0, [r4, SSPSR]
    movs r1, SR_RNE
    tst r0, r1
    bne 5f
    subs r2, 1
    bne 4b
    b fail_spi

5:
    ldr r0, [r4, SSPDR]
    pop {r1, r2, pc}

fail_flash:
    ldr r0, =fail_flash_message
    b test_failed

fail_iodir:
    ldr r0, =fail_iodir_message
    b test_failed

fail_iocon:
    ldr r0, =fail_iocon_message
    b test_failed

fail_spi:
    ldr r0, =fail_spi_message
    b test_failed

fail_dma:
    ldr r0, =fail_dma_message
    b test_failed

.thumb_func
default_handler:
    ldr r0, =fail_exception_message

test_failed:
    bl puts
    movs r0, SYS_EXIT
    ldr r1, =ADP_STOPPED_RUNTIME_ERROR
    bkpt 0xab

6:
    b 6b

.thumb_func
puts:
    push {r1, r2, lr}
    ldr r2, =UART0_DR

7:
    ldrb r1, [r0]
    cmp r1, 0
    beq 8f
    str r1, [r2]
    adds r0, 1
    b 7b

8:
    pop {r1, r2, pc}

.section .rodata, "a", %progbits
flash_message:
    .asciz "DUO TCG FLASH 16MIB OK\n"
mcp_message:
    .asciz "DUO TCG MCP23S17 OK\n"
dma_message:
    .asciz "DUO TCG PIO TX DMA OK\n"
ok_message:
    .asciz "DUO TCG BOARD OK\n"
fail_flash_message:
    .asciz "DUO TCG FAIL: flash end not erased\n"
fail_iodir_message:
    .asciz "DUO TCG FAIL: MCP23S17 IODIRA reset value\n"
fail_iocon_message:
    .asciz "DUO TCG FAIL: MCP23S17 IOCON readback\n"
fail_spi_message:
    .asciz "DUO TCG FAIL: no SPI1 data\n"
fail_dma_message:
    .asciz "DUO TCG FAIL: PIO TX paced DMA\n"
fail_exception_message:
    .asciz "DUO TCG FAIL: exception\n"
