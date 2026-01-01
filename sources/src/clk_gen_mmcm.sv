module clk_gen_mmcm(
    input  logic clk100,
    input  logic rst,       // Active-high.
    output logic clk25,
    output logic clk50,
    output logic locked
);
    // 100 MHz in -> VCO 800 MHz (x8) -> /32 = 25 MHz, /16 = 50 MHz
    logic clkfb, clkfb_buf;
    logic clk25_i, clk50_i;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(10.000),
        .CLKFBOUT_MULT_F(8.000),
        .DIVCLK_DIVIDE(1),

        .CLKOUT0_DIVIDE_F(32.000),  // 25 MHz
        .CLKOUT1_DIVIDE(16),        // 50 MHz

        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT1_DUTY_CYCLE(0.5),

        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk100),
        .CLKFBIN(clkfb_buf),
        .RST(rst),
        .PWRDWN(1'b0),

        .CLKFBOUT(clkfb),
        .CLKOUT0(clk25_i),
        .CLKOUT1(clk50_i),
        .CLKOUT2(),
        .CLKOUT3(),
        .CLKOUT4(),
        .CLKOUT5(),

        .LOCKED(locked)
    );

    BUFG u_bufg_fb(.I(clkfb),   .O(clkfb_buf));
    BUFG u_bufg25 (.I(clk25_i), .O(clk25));
    BUFG u_bufg50 (.I(clk50_i), .O(clk50));
endmodule
