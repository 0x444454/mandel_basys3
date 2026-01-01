module fb_scanline_writer #(
    // Digilent Basys3 notes:
    //   - We don't have enough BRAM to store a full VGA image, so we only render QVGA (320x240) with pixel doubling.
    //   - We instantiate 15 Mandel cores. Each core uses 6 DSP48E1. The Basys3 has an XC7A35T with 90 DSP, so 15*6=90.
    parameter int FB_W   = 320,        // Framebuffer width.
    parameter int FB_H   = 240,        // Framebuffer height.
    parameter int NCORES = 15,         // Number of Mandel cores.
    parameter int FRAC   = 22          // We use fixed point Q3.22. 
)(
    input  logic                        clk,
    input  logic                        rst,

    output logic                        we,
    output logic [$clog2(FB_W*FB_H)-1:0] addr,
    output logic [15:0]                 data,

    input  logic [31:0]                 t,

    input  logic signed [24:0]          center_x_q,     // Center of image (x).
    input  logic signed [24:0]          center_y_q,     // Center of image (y).
    input  logic signed [24:0]          scale_q,        // Pixel increment.

    input  logic                        restart,
    input  logic [11:0]                 iters_q,

    output logic [7:0]                  cur_y
);
    localparam int ADDR_W = $clog2(FB_W*FB_H);

    // -------------------------------------------------------------------------
    // Mul 160 and mul 120 helper functions.
    // These are needed to find the coords of the upper left corner of the image (first pixel to calc).
    //   ax = center_x - 160*scale
    //   ay = center_y - 120*scale
    // NOTE: We only do shift/add (no mul) to avoid using DSP resources that are better used by Mandel cores.
    // -------------------------------------------------------------------------
    function automatic logic signed [24:0] mul_const_160(input logic signed [24:0] s);
        logic signed [39:0] s40;
        logic signed [39:0] t40;
        begin
            s40 = {{(40-25){s[24]}}, s};
            t40 = (s40 <<< 7) + (s40 <<< 5); // *160
            mul_const_160 = $signed(t40[24:0]);
        end
    endfunction

    function automatic logic signed [24:0] mul_const_120(input logic signed [24:0] s);
        logic signed [39:0] s40;
        logic signed [39:0] t40;
        begin
            s40 = {{(40-25){s[24]}}, s};
            t40 = (s40 <<< 6) + (s40 <<< 5) + (s40 <<< 3); // *120
            mul_const_120 = $signed(t40[24:0]);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Render control / coordinate generator (scanline order)
    // -------------------------------------------------------------------------
    logic rendering;
    logic need_render;

    logic [8:0]           issue_x;
    logic [7:0]           issue_y;
    logic [ADDR_W-1:0]    issue_addr;

    logic signed [24:0]   ax_q;
    logic signed [24:0]   ay_q;
    logic signed [24:0]   cur_cx_q;
    logic signed [24:0]   cur_cy_q;

    logic signed [24:0]   center_x_prev;
    logic signed [24:0]   center_y_prev;
    logic signed [24:0]   scale_prev;

    // -------------------------------------------------------------------------
    // Mandelbrot cores + handling logic
    // -------------------------------------------------------------------------
    logic [NCORES-1:0] core_start;      // Core start signal.
    logic [NCORES-1:0] core_launched;   // One-cycle "launched" flag to avoid double-issuing a core before it asserts busy.
    logic [NCORES-1:0] core_busy;       // Core is busy (calculating pixel).
    logic [NCORES-1:0] core_done;       // Core is done (ready to get pixel color).

    logic signed [24:0] core_cx_q   [NCORES];
    logic signed [24:0] core_cy_q   [NCORES];

    logic [11:0]        core_rgb444 [NCORES];



    // Request metadata (where to store the result).
    logic [ADDR_W-1:0] core_req_addr [NCORES];

    // Completed-results latch (so multiple cores can finish on the same cycle safely).
    logic [NCORES-1:0] res_valid;
    logic [ADDR_W-1:0] res_addr [NCORES];
    logic [11:0]       res_rgb  [NCORES];

    // Create our Mandel cores.
    genvar gi;
    generate
        for (gi = 0; gi < NCORES; gi = gi + 1) begin : G_PX
            pixel_gen_mandelbrot #(
                .FB_W(FB_W),
                .FB_H(FB_H),
                .MAX_ITERS(4095),
                .FRAC(FRAC)
            ) u_px (
                .clk(clk),
                .rst(rst),

                .start(core_start[gi]),
                .cx_q(core_cx_q[gi]),
                .cy_q(core_cy_q[gi]),
                .t(t),
                .max_iters(iters_q),

                .busy(core_busy[gi]),
                .done(core_done[gi]),
                .rgb444(core_rgb444[gi])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Pick one completed result to write each cycle (lowest index wins).
    // -------------------------------------------------------------------------
    logic                       wr_fire;
    logic [$clog2(NCORES)-1:0]  wr_sel;
    logic                       wr_any;

    integer k;
    always_comb begin
        wr_any  = 1'b0;
        wr_sel  = '0;
        for (k = 0; k < NCORES; k = k + 1) begin
            if (!wr_any && res_valid[k]) begin
                wr_any = 1'b1;
                wr_sel = k[$clog2(NCORES)-1:0];     // Pick result from this core.
            end
        end
    end

    always_comb begin
        we   = wr_any;
        addr = res_addr[wr_sel];
        data = {4'h0, res_rgb[wr_sel]};
        wr_fire = we;
    end

    // -------------------------------------------------------------------------
    // Main control.
    // -------------------------------------------------------------------------
    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            rendering   <= 1'b0;
            need_render <= 1'b1;

            issue_x    <= 9'd0;
            issue_y    <= 8'd0;
            issue_addr <= '0;

            ax_q     <= 25'sd0;
            ay_q     <= 25'sd0;
            cur_cx_q <= 25'sd0;
            cur_cy_q <= 25'sd0;

            center_x_prev <= 25'sd0;
            center_y_prev <= 25'sd0;
            scale_prev    <= 25'sd0;

            core_start    <= '0;
            core_launched <= '0;

            for (i = 0; i < NCORES; i = i + 1) begin
                core_cx_q[i]    <= 25'sd0;
                core_cy_q[i]    <= 25'sd0;
                core_req_addr[i] <= '0;

                res_valid[i] <= 1'b0;
                res_addr[i]  <= '0;
                res_rgb[i]   <= 12'h000;
            end
        end
        else begin
            // default: no starts unless we schedule them below.
            core_start <= '0;

            // Clear launched flag once the core has actually gone busy.
            for (i = 0; i < NCORES; i = i + 1) begin
                if (core_launched[i] && core_busy[i]) begin
                    core_launched[i] <= 1'b0;
                end
            end

            // Latch completed results.
            for (i = 0; i < NCORES; i = i + 1) begin
                if (core_done[i]) begin
                    res_valid[i] <= 1'b1;
                    res_addr[i]  <= core_req_addr[i];
                    res_rgb[i]   <= core_rgb444[i];
                end
            end

            // Consume one completed result per cycle (write to BRAM).
            if (wr_fire) begin
                res_valid[wr_sel] <= 1'b0;
            end

            // Start a new render if parameters changed or user action requested.
            if (restart || (center_x_q != center_x_prev) || (center_y_q != center_y_prev) || (scale_q != scale_prev)) begin
                need_render <= 1'b1;
                rendering   <= 1'b0;

                // Flush in-flight work/results (cores may still be running, be we'll ignore result).
                for (i = 0; i < NCORES; i = i + 1) begin
                    res_valid[i]    <= 1'b0;
                    core_launched[i] <= 1'b0;
                end

                center_x_prev <= center_x_q;
                center_y_prev <= center_y_q;
                scale_prev    <= scale_q;
            end
            else begin
                // Keep prevs updated even without restart (defensive).
                center_x_prev <= center_x_q;
                center_y_prev <= center_y_q;
                scale_prev    <= scale_q;
            end

            // (Re)initialize render if needed and we're not currently rendering
            if (need_render && !rendering) begin
                ax_q <= center_x_q - mul_const_160(scale_q);
                ay_q <= center_y_q - mul_const_120(scale_q);

                cur_cx_q   <= center_x_q - mul_const_160(scale_q);
                cur_cy_q   <= center_y_q - mul_const_120(scale_q);

                issue_x    <= 9'd0;
                issue_y    <= 8'd0;
                issue_addr <= '0;

                rendering   <= 1'b1;
                need_render <= 1'b0;
            end

            // Schedule at most 1 new pixel per cycle.
            // This keeps the per-cycle combinational path short while still letting multiple cores run in parallel and finish out-of-order.
            if (rendering) begin
                // Find first free core (priority encoder: lowest index wins)
                logic                       have_free;
                logic [$clog2(NCORES)-1:0]  free_idx;
                have_free = 1'b0;
                free_idx  = '0;

                for (i = 0; i < NCORES; i = i + 1) begin
                    if (!have_free && (!core_busy[i]) && (!core_launched[i]) && (!res_valid[i]) && (!core_done[i])) begin
                        have_free = 1'b1;
                        free_idx  = i[$clog2(NCORES)-1:0];
                    end
                end

                // Launch one pixel if we still have work left.
                if (have_free && (issue_y < FB_H)) begin
                    core_start[free_idx]    <= 1'b1;
                    core_launched[free_idx] <= 1'b1;

                    core_cx_q[free_idx]     <= cur_cx_q;
                    core_cy_q[free_idx]     <= cur_cy_q;
                    core_req_addr[free_idx] <= issue_addr;

                    // Advance to next pixel in scanline order.
                    issue_addr <= issue_addr + 1;

                    if (issue_x == (FB_W - 1)) begin
                        issue_x  <= 9'd0;
                        issue_y  <= issue_y + 1;
                        cur_cx_q <= ax_q;
                        cur_cy_q <= cur_cy_q + $signed(scale_q);
                    end
                    else begin
                        issue_x  <= issue_x + 1;
                        cur_cx_q <= cur_cx_q + $signed(scale_q);
                    end
                end

                // If we have issued all pixels and there is nothing in flight or pending retirement, then nothing to do.
                if (issue_y >= FB_H) begin
                    logic any_active;
                    any_active = (|core_busy) | (|core_launched) | (|res_valid);
                    if (!any_active) begin
                        rendering <= 1'b0;
                    end
                end
            end
        end
    end

    assign cur_y = issue_y;

endmodule
