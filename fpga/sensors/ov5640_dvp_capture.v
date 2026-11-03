// Board-independent OV5640 DVP byte-pair capture.
// The camera is configured for RGB565: two 8-bit DVP samples form one pixel.
// SCCB initialization, clock generation and frame buffering remain board-level
// blocks because their pins and DDR resources depend on the ACG720 schematic.
module ov5640_dvp_capture (
    input wire pclk_i,
    input wire rst_n,
    input wire vsync_i,
    input wire href_i,
    input wire [7:0] data_i,
    output reg [15:0] pixel_o,
    output reg pixel_valid_o,
    output reg frame_start_o,
    output reg [10:0] x_o,
    output reg [10:0] y_o
);
    reg vsync_d, href_d, byte_phase;
    reg [7:0] high_byte;
    always @(posedge pclk_i or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d <= 1'b0;
            href_d <= 1'b0;
            byte_phase <= 1'b0;
            high_byte <= 8'd0;
            pixel_o <= 16'd0;
            pixel_valid_o <= 1'b0;
            frame_start_o <= 1'b0;
            x_o <= 11'd0;
            y_o <= 11'd0;
        end else begin
            vsync_d <= vsync_i;
            href_d <= href_i;
            pixel_valid_o <= 1'b0;
            frame_start_o <= vsync_i & ~vsync_d;
            if (vsync_i & ~vsync_d) begin
                x_o <= 0;
                y_o <= 0;
                byte_phase <= 1'b0;
            end else if (href_i & ~href_d) begin
                x_o <= 0;
                byte_phase <= 1'b0;
                y_o <= y_o + 1'b1;
            end else if (!href_i) begin
                byte_phase <= 1'b0;
            end else if (!byte_phase) begin
                high_byte <= data_i;
                byte_phase <= 1'b1;
            end else begin
                pixel_o <= {high_byte, data_i};
                pixel_valid_o <= 1'b1;
                x_o <= x_o + 1'b1;
                byte_phase <= 1'b0;
            end
        end
    end
endmodule
