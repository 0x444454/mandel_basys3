// Driver for the Digilent Basys3 embedded 4 digits display.
module sevenseg_mux #(
    parameter logic [7:0] BRIGHTNESS = 8'd48 // 0..255, higher = brighter
)(
    input  logic       clk,
    input  logic       rst,

    input  logic [7:0] digits [0:3], // {dp, seg[6:0]} active-low
    input  logic [3:0] digit_en,      // 1 = digit enabled

    output logic [3:0] an,            // active-low
    output logic [6:0] seg,           // active-low, seg[0]=a ... seg[6]=g
    output logic       dp             // active-low
);
    logic [15:0] mux_cnt;
    logic [1:0]  sel;
    logic [7:0]  pwm_cnt;
    logic        pwm_on;

    always_ff @(posedge clk) begin
        if (rst) begin
            mux_cnt <= 16'd0;
            pwm_cnt <= 8'd0;
        end
        else begin
            mux_cnt <= mux_cnt + 16'd1;
            pwm_cnt <= pwm_cnt + 8'd1;
        end
    end

    assign sel = mux_cnt[15:14];
    assign pwm_on = (pwm_cnt < BRIGHTNESS);

    logic [7:0] cur;
    always_comb begin
        cur = digits[sel];

        an = 4'b1111;
        seg = 7'b1111111;
        dp = 1'b1;

        if (digit_en[sel] && pwm_on) begin
            an[sel] = 1'b0;
            seg = cur[6:0];
            dp  = cur[7];
        end
    end
endmodule
