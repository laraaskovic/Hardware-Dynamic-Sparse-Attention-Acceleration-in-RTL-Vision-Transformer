import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def axi_write(dut, addr, data):
    dut.s_axi_awaddr.value = addr & 0xF
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = data
    dut.s_axi_wvalid.value = 1
    await RisingEdge(dut.s_axi_aclk)
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wvalid.value = 0
    while dut.s_axi_bvalid.value == 0:
        await RisingEdge(dut.s_axi_aclk)
    dut.s_axi_bready.value = 1
    await RisingEdge(dut.s_axi_aclk)
    dut.s_axi_bready.value = 0


async def axi_read(dut, addr):
    dut.s_axi_araddr.value = addr & 0xF
    dut.s_axi_arvalid.value = 1
    await RisingEdge(dut.s_axi_aclk)
    dut.s_axi_arvalid.value = 0
    while dut.s_axi_rvalid.value == 0:
        await RisingEdge(dut.s_axi_aclk)
    val = int(dut.s_axi_rdata.value)
    dut.s_axi_rready.value = 1
    await RisingEdge(dut.s_axi_aclk)
    dut.s_axi_rready.value = 0
    return val


@cocotb.test()
async def run_small_block(dut):
    """End-to-end sanity: load Q/K, set threshold, start, wait done, check counters."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.s_axi_aclk, 10, units="ns").start())

    # Reset
    dut.rst_n.value = 0
    dut.s_axi_aresetn.value = 0
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wvalid.value = 0
    dut.s_axi_bready.value = 0
    dut.s_axi_arvalid.value = 0
    dut.s_axi_rready.value = 0
    await Timer(40, units="ns")
    dut.rst_n.value = 1
    dut.s_axi_aresetn.value = 1
    await RisingEdge(dut.clk)

    # Load Q/K directly into SRAM (addr 0) using internal WE for this demo
    q_vals = [2] * 8
    k_vals = [3] * 8
    q_word = 0
    k_word = 0
    for idx, v in enumerate(q_vals):
        q_word |= ((v & 0xFFFF) << (idx * 16))
    for idx, v in enumerate(k_vals):
        k_word |= ((v & 0xFFFF) << (idx * 16))
    dut.q_we.value = 1
    dut.k_we.value = 1
    dut.q_waddr.value = 0
    dut.k_waddr.value = 0
    dut.q_wdata.value = q_word
    dut.k_wdata.value = k_word
    await RisingEdge(dut.clk)
    dut.q_we.value = 0
    dut.k_we.value = 0

    # threshold: choose low so mask=compute
    await axi_write(dut, 0x08, 1000)

    # start
    await axi_write(dut, 0x00, 1)

    # wait done or timeout
    for _ in range(200):
        if int(dut.done.value):
            break
        await RisingEdge(dut.clk)
    assert int(dut.done.value) == 1, "timeout waiting for done"

    blocks_compute = await axi_read(dut, 0x10)
    blocks_skip = await axi_read(dut, 0x14)
    macs_compute = await axi_read(dut, 0x18)
    macs_skip = await axi_read(dut, 0x1C)

    # Expected: one block, mask=compute -> blocks_compute=1, skip=0
    assert blocks_compute == 1, f"blocks_compute {blocks_compute}"
    assert blocks_skip == 0, f"blocks_skip {blocks_skip}"
    assert macs_compute == dut.DIM.value.integer * dut.DIM.value.integer, "macs_compute mismatch"
    assert macs_skip == 0, "macs_skip mismatch"

    cocotb.log.info(f"PASS: blocks_compute={blocks_compute}, macs_compute={macs_compute}")
