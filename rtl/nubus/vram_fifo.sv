// Simple Dual-Clock FIFO using Altera IP (dcfifo)
module dcfifo_2k_16 (
    input  [15:0] data,
    input         rdclk,
    input         rdreq,
    input         wrclk,
    input         wrreq,
    output [15:0] q,
    output        rdempty,
    output [10:0] rdusedw,
    output        wrfull,
    output [10:0] wrusedw
);
    dcfifo #(
        .intended_device_family("Cyclone V"),
        .lpm_numwords(2048),
        .lpm_showahead("OFF"),
        .lpm_type("dcfifo"),
        .lpm_width(16),
        .lpm_widthu(11),
        .overflow_checking("ON"),
        .rdsync_delaypipe(4),
        .read_aclr("OFF"),
        .underflow_checking("ON"),
        .use_eab("ON"),
        .write_aclr("OFF"),
        .wrsync_delaypipe(4)
    ) dcfifo_component (
        .data (data),
        .rdclk (rdclk),
        .rdreq (rdreq),
        .wrclk (wrclk),
        .wrreq (wrreq),
        .q (q),
        .rdempty (rdempty),
        .rdusedw (rdusedw),
        .wrfull (wrfull),
        .wrusedw (wrusedw),
        .aclr (1'b0),
        .eccstatus ()
    );
endmodule
