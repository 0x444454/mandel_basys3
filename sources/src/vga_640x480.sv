// Module for 640x480 VGA.
module vga_640x480(
    input  logic       clk,
    input  logic       rst,
    output logic [9:0] x,
    output logic [9:0] y,
    output logic       hsync,
    output logic       vsync,
    output logic       visible
);
    localparam int H_VISIBLE = 640;
    localparam int H_FRONT   = 16;
    localparam int H_SYNC    = 96;
    localparam int H_BACK    = 48;
    localparam int H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800

    localparam int V_VISIBLE = 480;
    localparam int V_FRONT   = 10;
    localparam int V_SYNC    = 2;
    localparam int V_BACK    = 33;
    localparam int V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525

    logic [9:0] hc;
    logic [9:0] vc;

    always_ff @(posedge clk) begin
        if (rst) begin
            hc <= 10'd0;
            vc <= 10'd0;
        end
        else begin
            if (hc == H_TOTAL - 1) begin
                hc <= 10'd0;
                if (vc == V_TOTAL - 1) begin
                    vc <= 10'd0;
                end
                else begin
                    vc <= vc + 10'd1;
                end
            end
            else begin
                hc <= hc + 10'd1;
            end
        end
    end

    assign x = hc;
    assign y = vc;

    always_comb begin
        visible = (hc < H_VISIBLE) && (vc < V_VISIBLE);

        // Active-low sync pulses (typical VGA)
        hsync = ~((hc >= (H_VISIBLE + H_FRONT)) && (hc < (H_VISIBLE + H_FRONT + H_SYNC)));
        vsync = ~((vc >= (V_VISIBLE + V_FRONT)) && (vc < (V_VISIBLE + V_FRONT + V_SYNC)));
    end
endmodule
