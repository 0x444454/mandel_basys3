// Model a display with 4 digits, 7 segments and a dot per digit.
// Note: We display hex digits [0..F] and dots.
module sevenseg_hex4(
    input  logic [15:0] value,
    input  logic [3:0]  dp_mask,    // 1 = dot ON for that digit
    output logic [7:0]  digits [0:3] // {dp, seg[6:0]} active-low
);
    function automatic logic [6:0] hex_to_seg(input logic [3:0] n);
        begin
            unique case (n)
                4'h0: hex_to_seg = 7'b1000000;
                4'h1: hex_to_seg = 7'b1111001;
                4'h2: hex_to_seg = 7'b0100100;
                4'h3: hex_to_seg = 7'b0110000;
                4'h4: hex_to_seg = 7'b0011001;
                4'h5: hex_to_seg = 7'b0010010;
                4'h6: hex_to_seg = 7'b0000010;
                4'h7: hex_to_seg = 7'b1111000;
                4'h8: hex_to_seg = 7'b0000000;
                4'h9: hex_to_seg = 7'b0010000;
                4'hA: hex_to_seg = 7'b0001000;
                4'hB: hex_to_seg = 7'b0000011;
                4'hC: hex_to_seg = 7'b1000110;
                4'hD: hex_to_seg = 7'b0100001;
                4'hE: hex_to_seg = 7'b0000110;
                4'hF: hex_to_seg = 7'b0001110;
                default: hex_to_seg = 7'b1111111;
            endcase
        end
    endfunction

    always_comb begin
        digits[0] = {~dp_mask[0], hex_to_seg(value[3:0])};
        digits[1] = {~dp_mask[1], hex_to_seg(value[7:4])};
        digits[2] = {~dp_mask[2], hex_to_seg(value[11:8])};
        digits[3] = {~dp_mask[3], hex_to_seg(value[15:12])};
    end
endmodule
