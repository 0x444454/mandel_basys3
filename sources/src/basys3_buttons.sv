module basys3_buttons #(
    parameter int CLK_HZ    = 50000000,
    parameter int SAMPLE_HZ = 1000
)(
    input  logic clk,
    input  logic rst,

    input  logic btnU_raw,
    input  logic btnD_raw,
    input  logic btnL_raw,
    input  logic btnR_raw,
    input  logic btnC_raw,

    output logic btnU,
    output logic btnD,
    output logic btnL,
    output logic btnR,
    output logic btnC,

    output logic move_up,
    output logic move_down,
    output logic move_left,
    output logic move_right,
    output logic move_tick,

    output logic zoom_in_pulse,
    output logic zoom_out_pulse,
    output logic iters_dec_pulse,
    output logic iters_inc_pulse
);
    localparam int SAMPLE_DIV = (CLK_HZ / SAMPLE_HZ);
    localparam int MOVE_DIV   = (CLK_HZ / 256);
    localparam int ITERS_DIV  = (CLK_HZ / 128);

    logic [$clog2(SAMPLE_DIV)-1:0] sample_cnt;
    logic sample_tick;

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_cnt <= '0;
            sample_tick <= 1'b0;
        end
        else begin
            if (sample_cnt == SAMPLE_DIV-1) begin
                sample_cnt <= '0;
                sample_tick <= 1'b1;
            end
            else begin
                sample_cnt <= sample_cnt + 1;
                sample_tick <= 1'b0;
            end
        end
    end

    logic [7:0] shU, shD, shL, shR, shC;

    always_ff @(posedge clk) begin
        if (rst) begin
            shU <= 8'h00; shD <= 8'h00; shL <= 8'h00; shR <= 8'h00; shC <= 8'h00;
            btnU <= 1'b0; btnD <= 1'b0; btnL <= 1'b0; btnR <= 1'b0; btnC <= 1'b0;
        end
        else if (sample_tick) begin
            shU <= {shU[6:0], btnU_raw};
            shD <= {shD[6:0], btnD_raw};
            shL <= {shL[6:0], btnL_raw};
            shR <= {shR[6:0], btnR_raw};
            shC <= {shC[6:0], btnC_raw};

            if (&shU) btnU <= 1'b1;
            else if (~|shU) btnU <= 1'b0;

            if (&shD) btnD <= 1'b1;
            else if (~|shD) btnD <= 1'b0;

            if (&shL) btnL <= 1'b1;
            else if (~|shL) btnL <= 1'b0;

            if (&shR) btnR <= 1'b1;
            else if (~|shR) btnR <= 1'b0;

            if (&shC) btnC <= 1'b1;
            else if (~|shC) btnC <= 1'b0;
        end
    end

    // Movement tick (~256 Hz)
    logic [$clog2(MOVE_DIV)-1:0] move_cnt;
    always_ff @(posedge clk) begin
        if (rst) begin
            move_cnt <= '0;
            move_tick <= 1'b0;
        end
        else begin
            if (move_cnt == MOVE_DIV-1) begin
                move_cnt <= '0;
                move_tick <= 1'b1;
            end
            else begin
                move_cnt <= move_cnt + 1;
                move_tick <= 1'b0;
            end
        end
    end

    always_comb begin
        move_up    = (~btnC) & btnU;
        move_down  = (~btnC) & btnD;
        move_left  = (~btnC) & btnL;
        move_right = (~btnC) & btnR;
    end

    // Zoom one-shot on rising edge of combined condition
    logic zoom_in_cond, zoom_out_cond;
    logic zoom_in_prev, zoom_out_prev;

    always_comb begin
        zoom_in_cond  = btnC & btnU;
        zoom_out_cond = btnC & btnD;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            zoom_in_prev <= 1'b0;
            zoom_out_prev <= 1'b0;
            zoom_in_pulse <= 1'b0;
            zoom_out_pulse <= 1'b0;
        end
        else begin
            zoom_in_pulse  <= zoom_in_cond  & ~zoom_in_prev;
            zoom_out_pulse <= zoom_out_cond & ~zoom_out_prev;

            zoom_in_prev  <= zoom_in_cond;
            zoom_out_prev <= zoom_out_cond;
        end
    end

    // Iters inc/dec at ~128 Hz while button held
    logic [$clog2(ITERS_DIV)-1:0] it_cnt;
    logic it_tick;

    always_ff @(posedge clk) begin
        if (rst) begin
            it_cnt <= '0;
            it_tick <= 1'b0;
        end
        else begin
            if (it_cnt == ITERS_DIV-1) begin
                it_cnt <= '0;
                it_tick <= 1'b1;
            end
            else begin
                it_cnt <= it_cnt + 1;
                it_tick <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            iters_dec_pulse <= 1'b0;
            iters_inc_pulse <= 1'b0;
        end
        else begin
            iters_dec_pulse <= it_tick & btnC & btnL;
            iters_inc_pulse <= it_tick & btnC & btnR;
        end
    end
endmodule
