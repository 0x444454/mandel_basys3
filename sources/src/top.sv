// Mandel_basys3
// DDT's fixed-point Mandelbrot generator for Digilent Basys3 FPGA board (XC7A35T).
// Should be easily portable to other boards.
//
// https://github.com/0x444454/mandel_basys3
//
// Use Xilinx Vivado to build.
//
// Revision history [authors in square brackets]:
//   2025-12-30: First implementation, 100 MHz, 15 Mandel cores. Still some timings warnings, but seems to work ok. [DDT]

module top(
    input  logic       clk100,

    input  logic       btnU,
    input  logic       btnD,
    input  logic       btnL,
    input  logic       btnR,
    input  logic       btnC,

    output logic [3:0] vgaRed,
    output logic [3:0] vgaGreen,
    output logic [3:0] vgaBlue,
    output logic       Hsync,
    output logic       Vsync,

    output logic [6:0] seg,
    output logic       dp,
    output logic [3:0] an
);
    
// -------------------------------------------------------------------------
// Clocks: generate clk50 and clk25 from clk100 using MMCM + BUFG (safe clocks).
// -------------------------------------------------------------------------
logic clk50;
logic clk25;
logic mmcm_locked;

clk_gen_mmcm u_clkgen(
    .clk100(clk100),
    .rst(1'b0),
    .clk25(clk25),
    .clk50(clk50),
    .locked(mmcm_locked)
);

// Power-on reset (held until MMCM locked, then for a short counter interval on clk50).
logic [22:0] por_cnt = 23'd0;

always_ff @(posedge clk50 or negedge mmcm_locked) begin
    if (!mmcm_locked) begin
        por_cnt <= 23'd0;
    end
    else begin
        if (por_cnt != 23'h7FFFFF) por_cnt <= por_cnt + 23'd1;
    end
end

logic rst_async;
assign rst_async = (!mmcm_locked) || (por_cnt != 23'h7FFFFF);

// Reset synchronizers for each clock domain (active-high reset)
logic [1:0] rst100_sync;
logic [1:0] rst25_sync;
logic [1:0] rst50_sync;

always_ff @(posedge clk100 or posedge rst_async) begin
    if (rst_async) rst100_sync <= 2'b11;
    else rst100_sync <= {rst100_sync[0], 1'b0};
end
always_ff @(posedge clk25 or posedge rst_async) begin
    if (rst_async) rst25_sync <= 2'b11;
    else rst25_sync <= {rst25_sync[0], 1'b0};
end
always_ff @(posedge clk50 or posedge rst_async) begin
    if (rst_async) rst50_sync <= 2'b11;
    else rst50_sync <= {rst50_sync[0], 1'b0};
end

logic rst100, rst25, rst50;
assign rst100 = rst100_sync[1];
assign rst25  = rst25_sync[1];
assign rst50  = rst50_sync[1];

// Keep legacy name 'rst' for the clk100 domain (most logic).
logic rst;
assign rst = rst100;

    // -------------------------------------------------------------------------
    // VGA timing  (H-freq 31 kHz, V-freq 60 Hz, P-freq 25 MHz).
    // -------------------------------------------------------------------------
    logic [9:0] vx;
    logic [9:0] vy;
    logic       vvis;

    vga_640x480 u_vga(
        .clk(clk25),
        .rst(rst25),
        .x(vx),
        .y(vy),
        .hsync(Hsync),
        .vsync(Vsync),
        .visible(vvis)
    );

    // -------------------------------------------------------------------------
    // VGA is 640x480 with 2x nearest-neighbor upscale.
    // NOTE: We don't have enough BRAM to store a full VGA image, so we use QVGA (320x240) resolution.
    // Framebuffer: 320x240 RGB444 stored in 16-bit words [11:0].
    // -------------------------------------------------------------------------
    
    localparam int FB_W  = 320;
    localparam int FB_H  = 240;
    localparam int DEPTH = FB_W * FB_H;
    localparam int FB_AW = $clog2(DEPTH);

    logic [FB_AW-1:0] rd_addr;
    logic [15:0]      pix16;

    always_comb begin
        int sx;
        int sy;
        sx = (vx >> 1);
        sy = (vy >> 1);

        if (sx < 0) sx = 0;
        if (sx > (FB_W-1)) sx = FB_W-1;
        if (sy < 0) sy = 0;
        if (sy > (FB_H-1)) sy = FB_H-1;

        rd_addr = (sy <<< 8) + (sy <<< 6) + sx; // *320 via shifts (don't steal DSPs from Mandel cores).
    end

    // -------------------------------------------------------------------------
    // Time counter.
    // -------------------------------------------------------------------------
    
    logic [31:0] t;
    always_ff @(posedge clk100) begin
        if (rst) t <= 32'd0;
        else t <= t + 32'd1;
    end

    // -------------------------------------------------------------------------
    // Buttons: Up, Down, Left, Right, Center (Action).
    // When Action is not pressed:
    //   - Use U,D,L,R to move around the complex plane.
    // If Action is pressed:
    //   - Use U/D to zoom 2x in/out.
    //   - Use L/R to decrease/increase iterations.
    // -------------------------------------------------------------------------
    logic bU, bD, bL, bR, bC;
    logic move_up, move_down, move_left, move_right, move_tick;
    logic zoom_in_pulse, zoom_out_pulse, iters_dec_pulse, iters_inc_pulse;

    basys3_buttons #(.CLK_HZ(100000000), .SAMPLE_HZ(1000)) u_btn(
        .clk(clk100),
        .rst(rst),

        .btnU_raw(btnU),
        .btnD_raw(btnD),
        .btnL_raw(btnL),
        .btnR_raw(btnR),
        .btnC_raw(btnC),

        .btnU(bU),
        .btnD(bD),
        .btnL(bL),
        .btnR(bR),
        .btnC(bC),

        .move_up(move_up),
        .move_down(move_down),
        .move_left(move_left),
        .move_right(move_right),
        .move_tick(move_tick),

        .zoom_in_pulse(zoom_in_pulse),
        .zoom_out_pulse(zoom_out_pulse),
        .iters_dec_pulse(iters_dec_pulse),
        .iters_inc_pulse(iters_inc_pulse)
    );

    // -------------------------------------------------------------------------
    // Init center position and zoom level.
    // -------------------------------------------------------------------------
    localparam int FRAC = 22;
    localparam int signed SCALE_INIT_INT = (3 <<< FRAC) / 320;  // 39321 (0x9999)
    localparam logic signed [24:0] SCALE_INIT = $signed(SCALE_INIT_INT);

    logic signed [24:0] center_x_q;
    logic signed [24:0] center_y_q;
    logic signed [24:0] scale_q;
    logic [11:0]        max_iters;

    always_ff @(posedge clk100) begin
        if (rst) begin
            center_x_q <= -$signed(25'sd1 <<< (FRAC-1));   // -0.5 in Q22
            center_y_q <= 25'sd0;
            scale_q    <= SCALE_INIT;                      // match Q5.13 startup zoom
            max_iters  <= 12'd128;
        end
        else begin
            // Pan: 1 pixel per move_tick (~256 px/s while holding Action pressed).
            if (move_tick) begin
                if (move_left)  center_x_q <= center_x_q - $signed(scale_q);
                if (move_right) center_x_q <= center_x_q + $signed(scale_q);
                if (move_up)    center_y_q <= center_y_q - $signed(scale_q);
                if (move_down)  center_y_q <= center_y_q + $signed(scale_q);
            end

            // Zoom (2x). Release button to zoom again.
            if (zoom_in_pulse) begin
                logic signed [24:0] s_next;
                s_next = $signed(scale_q) >>> 1;
                if (s_next == 25'sd0) s_next = 25'sd1;
                scale_q <= s_next;
            end
            if (zoom_out_pulse) scale_q <= $signed(scale_q) <<< 1;

            // Iters (repeat ~128/s while holding Action pressed).
            if (iters_dec_pulse) begin
                if (max_iters > 12'd16) max_iters <= max_iters - 12'd1;
            end
            if (iters_inc_pulse) begin
                if (max_iters < 12'd4095) max_iters <= max_iters + 12'd1;
            end
        end
    end

    // Restart render when action happens (zoom/iters); panning is handled live
    logic render_restart;
    assign render_restart = zoom_in_pulse | zoom_out_pulse | iters_inc_pulse | iters_dec_pulse;
    // -------------------------------------------------------------------------
    // Renderer (clk50)
    // -------------------------------------------------------------------------
    logic              fb_we;
    logic [FB_AW-1:0]  gen_addr;
    logic [15:0]       gen_data;

    logic [7:0]        cur_y;

    fb_scanline_writer #(
        .FB_W(FB_W),
        .FB_H(FB_H),
        .NCORES(15),
        .FRAC(FRAC)
    ) u_wr(
        .clk(clk100),
        .rst(rst),

        .we(fb_we),
        .addr(gen_addr),
        .data(gen_data),

        .t(t),

        .center_x_q(center_x_q),
        .center_y_q(center_y_q),
        .scale_q(scale_q),

        .restart(render_restart),
        .iters_q(max_iters),

        .cur_y(cur_y)
    );


    fb_tdpram #(.DEPTH(DEPTH), .ADDR_W(FB_AW)) u_fb(
        .clka(clk100),
        .wea(fb_we),
        .addra(gen_addr),
        .dina(gen_data),

        .clkb(clk25),
        .addrb(rd_addr),
        .doutb(pix16)
    );


    // -------------------------------------------------------------------------
    // VGA output.
    // -------------------------------------------------------------------------
    // VGA output (BRAM read is synchronous: align visible with 1-cycle dout latency)
    // -------------------------------------------------------------------------
    logic        vvis_d;
    logic [15:0] pix16_d;

    always_ff @(posedge clk25) begin
        if (rst25) begin
            vvis_d  <= 1'b0;
            pix16_d <= 16'h0000;
        end
        else begin
            vvis_d  <= vvis;
            pix16_d <= pix16;
        end
    end

    always_comb begin
        if (vvis_d) begin
            vgaRed   = pix16_d[11:8];
            vgaGreen = pix16_d[7:4];
            vgaBlue  = pix16_d[3:0];
        end
        else begin
            vgaRed   = 4'h0;
            vgaGreen = 4'h0;
            vgaBlue  = 4'h0;
        end
    end


    // -------------------------------------------------------------------------
    // 4 digits display:
    // - If Action is pressed: Show max_iters.
    // - If Action is NOT pressed: Show current render line (00..EF).
    // -------------------------------------------------------------------------
    logic [7:0]  ss_digits [0:3];
    logic [15:0] ss_value;
    logic [3:0]  ss_en;

    always_comb begin
        if (bC) begin
            ss_value = {4'h0, max_iters};
            ss_en = 4'b1111;
        end
        else begin
            ss_value = {8'h00, cur_y};
            ss_en = 4'b0011;
        end
    end

    sevenseg_hex4 u_hex(
        .value(ss_value),
        .dp_mask(4'b0000),
        .digits(ss_digits)
    );

    sevenseg_mux #(.BRIGHTNESS(8'd48)) u_ss(
        .clk(clk100),
        .rst(rst),
        .digits(ss_digits),
        .digit_en(ss_en),
        .an(an),
        .seg(seg),
        .dp(dp)
    );
endmodule
