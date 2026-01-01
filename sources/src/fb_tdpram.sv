// Digilent Basys3 (XC7A35T) notes:
//   - We don't have enough BRAM to store a full VGA image, so we only render QVGA (320x240) with pixel doubling.
//   - The framebuffer is 16 bits per pixel, though we only use 12 of them for RGB 4:4:4 (4096 total colors).
module fb_tdpram #(
    parameter int DEPTH = 320*240,
    parameter int ADDR_W = $clog2(DEPTH)
)(
    // Write port A (clk100 domain)
    input  logic              clka,
    input  logic              wea,
    input  logic [ADDR_W-1:0] addra,
    input  logic [15:0]       dina,

    // Read port B (pixel clock domain)
    input  logic              clkb,
    input  logic [ADDR_W-1:0] addrb,
    output logic [15:0]       doutb
);
    // Uses Xilinx XPM macro: true dual-port, independent clocks, BRAM.
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A(ADDR_W),
        .ADDR_WIDTH_B(ADDR_W),
        .BYTE_WRITE_WIDTH_A(16),
        .CLOCKING_MODE("independent_clock"),
        .MEMORY_SIZE(DEPTH * 16),
        .MEMORY_PRIMITIVE("block"),
        .READ_DATA_WIDTH_B(16),
        .READ_LATENCY_B(1),
        .WRITE_DATA_WIDTH_A(16),
        .WRITE_MODE_B("read_first")
    ) u_mem (
        .clka(clka),
        .ena(1'b1),
        .wea(wea),
        .addra(addra),
        .dina(dina),
        .douta(),

        .clkb(clkb),
        .enb(1'b1),
        .web(1'b0),
        .addrb(addrb),
        .dinb(16'h0000),
        .doutb(doutb),

        .rstb(1'b0),
        .regceb(1'b1),
        .rsta(1'b0),
        .regcea(1'b0),
        .sleep(1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .injectsbiterrb(1'b0),
        .injectdbiterrb(1'b0),
        .sbiterrb(),
        .dbiterrb(),
        .sbiterra(),
        .dbiterra()
    );
endmodule
