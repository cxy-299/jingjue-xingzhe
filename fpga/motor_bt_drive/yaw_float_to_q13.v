// Yahboom Euler yaw is IEEE754 float32 radians. Convert to signed Q13 radians.
// No floating point IP or run-time divider; invalid/NaN/Inf values never arm.
module yaw_float_to_q13 (
    input wire clk, rst_n,
    input wire [31:0] bits_i,
    input wire recent_i,
    output reg signed [15:0] yaw_o=0,
    output reg valid_o=0
);
    reg [23:0] magnitude;
    always @* begin
        magnitude=0;
        if(bits_i[30:23]>=8'd114 && bits_i[30:23]<=8'd128)
            magnitude={1'b1,bits_i[22:0]} >> (8'd137-bits_i[30:23]);
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin yaw_o<=0;valid_o<=0;end
        else begin
            valid_o<=recent_i && bits_i[30:0]<=31'h404a3d71;
            yaw_o<=bits_i[31] ? -$signed({1'b0,magnitude[14:0]}) : $signed({1'b0,magnitude[14:0]});
        end
    end
endmodule
