module pixel_gen_mandelbrot #(
    parameter int FB_W      = 320,
    parameter int FB_H      = 240,
    parameter int MAX_ITERS = 4095,
    parameter int FRAC = 22
)(
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  start,
    input  logic signed [24:0]    cx_q,       // complex C real, Q(FRAC)
    input  logic signed [24:0]    cy_q,       // complex C imag, Q(FRAC)
    input  logic [31:0]           t,          // unused (kept for compatibility)
    input  logic [11:0]           max_iters,  // runtime max iters (16..4095), latched per pixel

    output logic                  busy,
    output logic                  done,
    output logic [11:0]           rgb444
);

// Color palette. Currently 256 colors, but can be increased (we store per-pixel colors in the framebuffer).
// Each entry is in RGB 4:4:4 format (4096 possible colors).
localparam int PAL_SIZE = 256;
localparam logic [11:0] PAL [0:PAL_SIZE-1] = '{
    12'h000, 12'h015, 12'h028, 12'h139, 12'h248, 12'h458, 12'h667, 12'h886, 12'hBA5, 12'hEB5, 12'hFC6, 12'hFD9, 12'hEDA, 12'hEDB, 12'hDDC, 12'hDDD,
    12'hDCD, 12'hCBD, 12'hCBD, 12'hCAD, 12'hC9D, 12'hC8D, 12'hC7D, 12'hC6D, 12'hC5D, 12'hC4D, 12'hB3C, 12'hB2C, 12'hB1C, 12'hB1C, 12'hA1C, 12'hA1C,
    12'hA1C, 12'h91C, 12'h91C, 12'h82D, 12'h82D, 12'h73D, 12'h64D, 12'h64D, 12'h55D, 12'h56E, 12'h47E, 12'h47E, 12'h38E, 12'h39E, 12'h29E, 12'h2AE,
    12'h2BE, 12'h2BF, 12'h2CF, 12'h2CF, 12'h2CF, 12'h2DF, 12'h3DF, 12'h3DF, 12'h4EF, 12'h5EF, 12'h6EF, 12'h8EF, 12'h8EF, 12'h9FF, 12'hAFF, 12'hBFF,
    12'hCFF, 12'hCFF, 12'hDFF, 12'hDFF, 12'hDFF, 12'hDFF, 12'hDFF, 12'hCFF, 12'hCFF, 12'hBFF, 12'hAFF, 12'h9FF, 12'h8FF, 12'h8EF, 12'h7EF, 12'h6EF,
    12'h5EF, 12'h4EF, 12'h4EF, 12'h3EF, 12'h3EF, 12'h3DE, 12'h3DE, 12'h3DD, 12'h3DD, 12'h3DC, 12'h3DC, 12'h4CB, 12'h4CB, 12'h5CA, 12'h5C9, 12'h6C9,
    12'h6B8, 12'h7B7, 12'h7B6, 12'h8B6, 12'h8B5, 12'h9A5, 12'h9A4, 12'h9A4, 12'hAA3, 12'hAA2, 12'hBA2, 12'hBA2, 12'hBA1, 12'hCA1, 12'hCA0, 12'hCA0,
    12'hDA0, 12'hDA0, 12'hDA0, 12'hDA0, 12'hDA0, 12'hDA0, 12'hEB0, 12'hEB0, 12'hEB0, 12'hEB0, 12'hEC0, 12'hEC0, 12'hEC0, 12'hED0, 12'hED0, 12'hED0,
    12'hFD0, 12'hFD0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFE0, 12'hFD0, 12'hFD0, 12'hFC0,
    12'hFB0, 12'hFB0, 12'hFA0, 12'hF90, 12'hF80, 12'hF70, 12'hF70, 12'hF60, 12'hF50, 12'hF50, 12'hF40, 12'hF40, 12'hF30, 12'hF30, 12'hF20, 12'hF20,
    12'hF10, 12'hF10, 12'hF00, 12'hF00, 12'hF00, 12'hF00, 12'hE00, 12'hE00, 12'hE00, 12'hE00, 12'hD01, 12'hD01, 12'hC01, 12'hC01, 12'hB01, 12'hB01,
    12'hB01, 12'hA01, 12'hA02, 12'h902, 12'h902, 12'h802, 12'h802, 12'h702, 12'h702, 12'h702, 12'h702, 12'h702, 12'h702, 12'h702, 12'h603, 12'h603,
    12'h603, 12'h603, 12'h603, 12'h603, 12'h603, 12'h603, 12'h503, 12'h503, 12'h503, 12'h503, 12'h503, 12'h503, 12'h503, 12'h503, 12'h403, 12'h413,
    12'h413, 12'h413, 12'h413, 12'h413, 12'h413, 12'h413, 12'h413, 12'h313, 12'h313, 12'h313, 12'h313, 12'h314, 12'h314, 12'h314, 12'h314, 12'h314,
    12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h214, 12'h114, 12'h114, 12'h114, 12'h114, 12'h114,
    12'h114, 12'h114, 12'h114, 12'h114, 12'h114, 12'h114, 12'h114, 12'h014, 12'h014, 12'h014, 12'h014, 12'h014, 12'h014, 12'h014, 12'h014, 12'h014
};


    function automatic [11:0] pal(input [15:0] it, input bit is_inside);
        logic [7:0] idx;
        begin
            if (is_inside) pal = 12'h000;  // Inside Mandelbrot set. Force black.
            else begin
                // Map iter color straight to palette index.
                idx = it[7:0];             // We currently use only a 256 color palette (change this for more).
                pal = PAL[idx];
            end
        end
    endfunction

    // Mandelbrot core calculation routine.

    logic signed [24:0] zx;
    logic signed [24:0] zy;
    logic signed [24:0] cx;
    logic signed [24:0] cy;

    logic [15:0] iter;
    logic [11:0] max_it;

    // Maybe 
    logic signed [49:0] zx_zx_50;
    logic signed [49:0] zy_zy_50;
    logic signed [49:0] zx_zy_50;
    logic signed [50:0] mag2_full;   // zx*zx + zy*zy in Q(2*FRAC)

    logic signed [24:0] zx2;
    logic signed [24:0] zy2;
    logic signed [24:0] two_zxzy;

    logic signed [24:0] zx_next;
    logic signed [24:0] zy_next;
    logic signed [24:0] mag2_q;

    localparam int signed ESCAPE_Q = (4 <<< FRAC);   // 4.0 in Q(FRAC)
    // Use full-precision (Q(2*FRAC)) escape test to avoid wrap/truncation artifacts (probably overkill).
    localparam longint signed ESCAPE_Q2 = (64'sd4 <<< (2*FRAC));  // 4.0 in Q(2*FRAC)

    always_comb begin
        zx_zx_50 = $signed(zx) * $signed(zx);
        zy_zy_50 = $signed(zy) * $signed(zy);
        zx_zy_50 = $signed(zx) * $signed(zy);

        mag2_full = $signed(zx_zx_50) + $signed(zy_zy_50);
        zx2 = $signed(zx_zx_50 >>> FRAC);
        zy2 = $signed(zy_zy_50 >>> FRAC);
        two_zxzy = $signed(zx_zy_50 >>> (FRAC-1));          // 2*zx*zy

        zx_next = (zx2 - zy2) + cx;
        zy_next = $signed(two_zxzy + cy);

        mag2_q = $signed(zx2 + zy2);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            rgb444 <= 12'h000;

            zx <= 25'sd0;
            zy <= 25'sd0;
            cx <= 25'sd0;
            cy <= 25'sd0;

            iter <= 16'd0;
            max_it <= MAX_ITERS[11:0];
        end
        else begin
            done <= 1'b0;

            if (start && !busy) begin
                // Init core pixel calculation.
                busy <= 1'b1;
                cx <= cx_q;
                cy <= cy_q;
                // Latch runtime iteration limit for this pixel.
                // Note: Buttons already clamp to [16..4095]; but we defensively clamp min iters here too.
                max_it <= (max_iters < 12'd16) ? 12'd16 : max_iters;
                zx   <= 25'sd0;
                zy   <= 25'sd0;
                iter <= 16'd0;
            end
            else if (busy) begin
                // Core still busy.
                if (mag2_full > ESCAPE_Q2) begin
                    // DONE: Not black, fetch color from palette based on iters.
                    busy <= 1'b0;
                    done <= 1'b1;
                    rgb444 <= pal(iter, 1'b0);
                end
                else if (iter[11:0] == (max_it - 12'd1)) begin
                    // DONE: Black (inside Mandelbrot set). Force black.
                    busy <= 1'b0;
                    done <= 1'b1;
                    rgb444 <= 12'h000;
                end
                else begin
                    // Continue pixel calculation.
                    zx <= zx_next;
                    zy <= zy_next;
                    iter <= iter + 16'd1;
                end
            end
        end
    end
endmodule
