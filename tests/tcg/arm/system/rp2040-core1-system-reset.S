/*
 * Raspberry Pi Pico: a system reset restarts core 1 in the boot ROM.
 *
 * The first boot launches core 1 into a spin loop and forces a watchdog
 * reset. The second boot, recognised by WATCHDOG_REASON.FORCE, must be able
 * to run the core 1 launch handshake again: on hardware the reset returns
 * proc1 to the mask ROM's FIFO wait. A core 1 left running the previous
 * image's code never echoes, so the bounded wait reports a failure.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

.syntax unified
.cpu cortex-m0plus
.thumb

#define SRAM_END               0x20042000
#define CORE1_STACK            0x20041000
#define UART0_DR               0x40034000
#define WATCHDOG_BASE          0x40058000
#define WATCHDOG_CTRL          0x00
#define WATCHDOG_REASON        0x08
#define WATCHDOG_CTRL_TRIGGER  0x80000000
#define WATCHDOG_REASON_FORCE  0x02
#define SIO_BASE               0xd0000000
#define SIO_FIFO_ST            0x50
#define SIO_FIFO_WR            0x54
#define SIO_FIFO_RD            0x58
#define SIO_FIFO_ST_VLD        0x01
#define SIO_FIFO_ST_RDY        0x02
#define CORE1_ACK              0x0000d01e
#define POP_TIMEOUT            0x00100000
#define SYS_EXIT               0x18
#define ADP_STOPPED_APPLICATION_EXIT 0x20026
#define ADP_STOPPED_RUNTIME_ERROR    0x20023

.section .vectors, "a", %progbits
.global vector_table
vector_table:
    .word SRAM_END
    .word reset_handler + 1
    .word default_handler + 1
    .word default_handler + 1

.section .text, "ax", %progbits
.thumb_func
.global reset_handler
reset_handler:
    ldr r4, =SIO_BASE
    ldr r5, =WATCHDOG_BASE
    ldr r0, [r5, WATCHDOG_REASON]
    movs r1, WATCHDOG_REASON_FORCE
    tst r0, r1
    bne second_boot

    ldr r0, =first_message
    bl puts
    bl launch_core1
    ldr r0, =launched_message
    bl puts
    ldr r0, =WATCHDOG_CTRL_TRIGGER
    str r0, [r5, WATCHDOG_CTRL]

1:
    b 1b

second_boot:
    ldr r0, =second_message
    bl puts
    bl launch_core1
    ldr r0, =ok_message
    bl puts
    movs r0, SYS_EXIT
    ldr r1, =ADP_STOPPED_APPLICATION_EXIT
    bkpt 0xab

2:
    b 2b

/* The SDK launch sequence; each word must be echoed by the ROM. */
.thumb_func
launch_core1:
    push {r6, r7, lr}
    ldr r6, =launch_sequence
    movs r7, 0

3:
    ldr r0, [r6, r7]
    cmp r0, 0
    bne 4f
    bl fifo_drain
    sev

4:
    bl fifo_push
    bl fifo_pop
    ldr r1, [r6, r7]
    cmp r0, r1
    bne fail_echo
    adds r7, 4
    cmp r7, 24
    bne 3b

    bl fifo_pop
    ldr r1, =CORE1_ACK
    cmp r0, r1
    bne fail_ack
    pop {r6, r7, pc}

.thumb_func
core1_entry:
    ldr r4, =SIO_BASE
    ldr r0, =CORE1_ACK
    bl fifo_push

5:
    b 5b

.thumb_func
fifo_drain:
    push {r0, r1, lr}

6:
    ldr r0, [r4, SIO_FIFO_ST]
    movs r1, SIO_FIFO_ST_VLD
    tst r0, r1
    beq 7f
    ldr r0, [r4, SIO_FIFO_RD]
    b 6b

7:
    pop {r0, r1, pc}

.thumb_func
fifo_push:
    push {r1, r2, lr}

8:
    ldr r1, [r4, SIO_FIFO_ST]
    movs r2, SIO_FIFO_ST_RDY
    tst r1, r2
    beq 8b
    str r0, [r4, SIO_FIFO_WR]
    sev
    pop {r1, r2, pc}

/* Bounded pop: a core 1 that never answers fails instead of hanging. */
.thumb_func
fifo_pop:
    push {r1, r2, lr}
    ldr r2, =POP_TIMEOUT

9:
    ldr r1, [r4, SIO_FIFO_ST]
    movs r0, SIO_FIFO_ST_VLD
    tst r1, r0
    bne 10f
    subs r2, 1
    bne 9b
    b fail_timeout

10:
    ldr r0, [r4, SIO_FIFO_RD]
    pop {r1, r2, pc}

fail_timeout:
    ldr r0, =fail_timeout_message
    b test_failed

fail_echo:
    ldr r0, =fail_echo_message
    b test_failed

fail_ack:
    ldr r0, =fail_ack_message

test_failed:
    bl puts
    movs r0, SYS_EXIT
    ldr r1, =ADP_STOPPED_RUNTIME_ERROR
    bkpt 0xab

11:
    b 11b

.thumb_func
default_handler:
    ldr r0, =fail_exception_message
    b test_failed

.thumb_func
puts:
    ldr r2, =UART0_DR

12:
    ldrb r1, [r0]
    cmp r1, 0
    beq 13f
    str r1, [r2]
    adds r0, 1
    b 12b

13:
    bx lr

.section .rodata, "a", %progbits
.align 2
launch_sequence:
    .word 0
    .word 0
    .word 1
    .word vector_table
    .word CORE1_STACK
    .word core1_entry + 1

first_message:
    .asciz "PICO TCG CORE1 RESET FIRST BOOT\n"
launched_message:
    .asciz "PICO TCG CORE1 RESET LAUNCHED\n"
second_message:
    .asciz "PICO TCG CORE1 RESET SECOND BOOT\n"
ok_message:
    .asciz "PICO TCG CORE1 RESET OK\n"
fail_timeout_message:
    .asciz "PICO TCG CORE1 RESET FAIL: no echo after reset\n"
fail_echo_message:
    .asciz "PICO TCG CORE1 RESET FAIL: echo\n"
fail_ack_message:
    .asciz "PICO TCG CORE1 RESET FAIL: ack\n"
fail_exception_message:
    .asciz "PICO TCG CORE1 RESET FAIL: exception\n"
