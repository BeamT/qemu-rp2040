/*
 * Raspberry Pi Pico SPI0/SPI1: PL022 loopback through the RP2040 atomic
 * register aliases. Each port is enabled with a SET alias write (as the Pico
 * SDK's hw_set_bits() does), moves one byte in loopback mode and is disabled
 * with a CLR alias write.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

.syntax unified
.cpu cortex-m0plus
.thumb

#define SRAM_END        0x20042000
#define UART0_DR        0x40034000
#define SPI0_BASE       0x4003c000
#define SPI1_BASE       0x40040000
#define SSPCR0          0x00
#define SSPCR1          0x04
#define SSPDR           0x08
#define SSPSR           0x0c
#define SSPCPSR         0x10
#define ALIAS_SET       0x2000
#define ALIAS_CLR       0x3000
#define CR1_LBM         0x01
#define CR1_SSE         0x02
#define SR_RNE          0x04
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
    ldr r4, =SPI0_BASE
    movs r6, 0xa5
    bl check_port
    ldr r0, =spi0_message
    bl puts

    ldr r4, =SPI1_BASE
    movs r6, 0x3c
    bl check_port
    ldr r0, =spi1_message
    bl puts

    ldr r0, =ok_message
    bl puts
    movs r0, SYS_EXIT
    ldr r1, =ADP_STOPPED_APPLICATION_EXIT
    bkpt 0xab

1:
    b 1b

/* r4: port base, r6: byte to loop back. */
.thumb_func
check_port:
    push {lr}
    movs r0, 7                      /* 8-bit frames, Motorola mode 0 */
    str r0, [r4, SSPCR0]
    movs r0, 2
    str r0, [r4, SSPCPSR]
    movs r0, CR1_LBM
    str r0, [r4, SSPCR1]

    ldr r5, =ALIAS_SET + SSPCR1
    movs r0, CR1_SSE
    str r0, [r4, r5]
    ldr r0, [r4, SSPCR1]
    cmp r0, CR1_LBM | CR1_SSE
    bne fail_set

    str r6, [r4, SSPDR]
    ldr r2, =0x100000

2:
    ldr r0, [r4, SSPSR]
    movs r1, SR_RNE
    tst r0, r1
    bne 3f
    subs r2, 1
    bne 2b
    b fail_rx

3:
    ldr r0, [r4, SSPDR]
    cmp r0, r6
    bne fail_data

    ldr r5, =ALIAS_CLR + SSPCR1
    movs r0, CR1_SSE
    str r0, [r4, r5]
    ldr r0, [r4, SSPCR1]
    cmp r0, CR1_LBM
    bne fail_clr
    pop {pc}

fail_set:
    ldr r0, =fail_set_message
    b test_failed

fail_rx:
    ldr r0, =fail_rx_message
    b test_failed

fail_data:
    ldr r0, =fail_data_message
    b test_failed

fail_clr:
    ldr r0, =fail_clr_message
    b test_failed

.thumb_func
default_handler:
    ldr r0, =fail_exception_message

test_failed:
    bl puts
    movs r0, SYS_EXIT
    ldr r1, =ADP_STOPPED_RUNTIME_ERROR
    bkpt 0xab

4:
    b 4b

.thumb_func
puts:
    ldr r2, =UART0_DR

5:
    ldrb r1, [r0]
    cmp r1, 0
    beq 6f
    str r1, [r2]
    adds r0, 1
    b 5b

6:
    bx lr

.section .rodata, "a", %progbits
spi0_message:
    .asciz "PICO TCG SPI0 LOOPBACK OK\n"
spi1_message:
    .asciz "PICO TCG SPI1 LOOPBACK OK\n"
ok_message:
    .asciz "PICO TCG SPI OK\n"
fail_set_message:
    .asciz "PICO TCG SPI FAIL: SET alias\n"
fail_rx_message:
    .asciz "PICO TCG SPI FAIL: no loopback data\n"
fail_data_message:
    .asciz "PICO TCG SPI FAIL: loopback data\n"
fail_clr_message:
    .asciz "PICO TCG SPI FAIL: CLR alias\n"
fail_exception_message:
    .asciz "PICO TCG SPI FAIL: exception\n"
