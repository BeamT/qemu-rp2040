/*
 * Microchip MCP23S17 SPI 16-bit I/O expander, register file model.
 *
 * Models the IOCON.BANK=0 register map as storage: firmware can configure
 * the expander and read its registers back. Pins are not modelled: GPIO
 * reads return the output latch, and interrupts are not generated.
 *
 * Chip select is not wired (boards that drive it from a GPIO have no CS line
 * into the SSI bus), so each transfer is framed as three bytes: opcode,
 * register address, one data byte. Sequential multi-byte transfers and the
 * hardware address bits are not modelled.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "qemu/osdep.h"
#include "hw/gpio/mcp23s17.h"
#include "hw/ssi/ssi.h"
#include "migration/vmstate.h"
#include "qemu/log.h"
#include "qemu/module.h"
#include "qom/object.h"

#define MCP23S17_NUM_REGS   0x16
#define MCP23S17_IODIRA     0x00
#define MCP23S17_IODIRB     0x01
#define MCP23S17_GPIOA      0x12
#define MCP23S17_GPIOB      0x13
#define MCP23S17_OLATA      0x14
#define MCP23S17_OLATB      0x15
#define MCP23S17_OPCODE_MASK 0xf0
#define MCP23S17_OPCODE     0x40
#define MCP23S17_OPCODE_READ 0x01

OBJECT_DECLARE_SIMPLE_TYPE(MCP23S17State, MCP23S17)

struct MCP23S17State {
    SSIPeripheral parent_obj;

    uint8_t regs[MCP23S17_NUM_REGS];
    uint8_t phase;
    uint8_t opcode;
    uint8_t addr;
};

static uint8_t mcp23s17_read(MCP23S17State *s, uint8_t addr)
{
    if (addr >= MCP23S17_NUM_REGS) {
        qemu_log_mask(LOG_GUEST_ERROR, "%s: register 0x%02x out of range\n",
                      __func__, addr);
        return 0;
    }
    /* No pin model: the port reads back its output latch. */
    if (addr == MCP23S17_GPIOA || addr == MCP23S17_GPIOB) {
        return s->regs[addr + (MCP23S17_OLATA - MCP23S17_GPIOA)];
    }
    return s->regs[addr];
}

static void mcp23s17_write(MCP23S17State *s, uint8_t addr, uint8_t value)
{
    if (addr >= MCP23S17_NUM_REGS) {
        qemu_log_mask(LOG_GUEST_ERROR, "%s: register 0x%02x out of range\n",
                      __func__, addr);
        return;
    }
    /* Writing a port writes its output latch, as on the device. */
    if (addr == MCP23S17_GPIOA || addr == MCP23S17_GPIOB) {
        addr += MCP23S17_OLATA - MCP23S17_GPIOA;
    }
    s->regs[addr] = value;
}

static uint32_t mcp23s17_transfer(SSIPeripheral *dev, uint32_t value)
{
    MCP23S17State *s = MCP23S17(dev);
    uint32_t out = 0;

    switch (s->phase) {
    case 0:
        s->opcode = value;
        if ((value & MCP23S17_OPCODE_MASK) != MCP23S17_OPCODE) {
            qemu_log_mask(LOG_GUEST_ERROR, "%s: unexpected opcode 0x%02x\n",
                          __func__, value & 0xff);
        }
        break;
    case 1:
        s->addr = value;
        break;
    default:
        if (s->opcode & MCP23S17_OPCODE_READ) {
            out = mcp23s17_read(s, s->addr);
        } else {
            mcp23s17_write(s, s->addr, value);
        }
        break;
    }
    s->phase = (s->phase + 1) % 3;
    return out;
}

static void mcp23s17_reset(DeviceState *dev)
{
    MCP23S17State *s = MCP23S17(dev);

    memset(s->regs, 0, sizeof(s->regs));
    s->regs[MCP23S17_IODIRA] = 0xff;
    s->regs[MCP23S17_IODIRB] = 0xff;
    s->phase = 0;
    s->opcode = 0;
    s->addr = 0;
}

static void mcp23s17_realize(SSIPeripheral *dev, Error **errp)
{
}

static const VMStateDescription vmstate_mcp23s17 = {
    .name = TYPE_MCP23S17,
    .version_id = 1,
    .minimum_version_id = 1,
    .fields = (const VMStateField[]) {
        VMSTATE_SSI_PERIPHERAL(parent_obj, MCP23S17State),
        VMSTATE_UINT8_ARRAY(regs, MCP23S17State, MCP23S17_NUM_REGS),
        VMSTATE_UINT8(phase, MCP23S17State),
        VMSTATE_UINT8(opcode, MCP23S17State),
        VMSTATE_UINT8(addr, MCP23S17State),
        VMSTATE_END_OF_LIST()
    },
};

static void mcp23s17_class_init(ObjectClass *klass, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    SSIPeripheralClass *k = SSI_PERIPHERAL_CLASS(klass);

    k->realize = mcp23s17_realize;
    k->transfer = mcp23s17_transfer;
    k->cs_polarity = SSI_CS_NONE;
    device_class_set_legacy_reset(dc, mcp23s17_reset);
    dc->vmsd = &vmstate_mcp23s17;
    dc->desc = "Microchip MCP23S17 SPI I/O expander (register file)";
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo mcp23s17_info = {
    .name = TYPE_MCP23S17,
    .parent = TYPE_SSI_PERIPHERAL,
    .instance_size = sizeof(MCP23S17State),
    .class_init = mcp23s17_class_init,
};

static void mcp23s17_register_types(void)
{
    type_register_static(&mcp23s17_info);
}

type_init(mcp23s17_register_types)
