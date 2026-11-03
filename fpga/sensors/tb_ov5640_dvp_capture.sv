`timescale 1ns/1ps
module tb_ov5640_dvp_capture;
    reg pclk = 0;
    always #5 pclk = ~pclk;
    reg rst_n = 0;
    reg vsync = 0, href = 0;
    reg [7:0] data = 0;
    wire [15:0] pixel;
    wire pixel_valid, frame_start;
    wire [10:0] x, y;
    integer count;
    ov5640_dvp_capture dut (
        .pclk_i(pclk), .rst_n(rst_n), .vsync_i(vsync), .href_i(href),
        .data_i(data), .pixel_o(pixel), .pixel_valid_o(pixel_valid),
        .frame_start_o(frame_start), .x_o(x), .y_o(y)
    );
    always @(posedge pclk) begin
        if (pixel_valid) begin
            if (count == 0 && pixel !== 16'hf800) $fatal(1, "OV5640 pixel 0 mismatch");
            if (count == 1 && pixel !== 16'h07e0) $fatal(1, "OV5640 pixel 1 mismatch");
            count = count + 1;
        end
    end
    task automatic byte_sample(input [7:0] v);
        begin data = v; @(posedge pclk); #1; end
    endtask
    initial begin
        count = 0;
        repeat (3) @(posedge pclk);
        rst_n = 1;
        vsync = 1; @(posedge pclk); #1; vsync = 0;
        href = 1;
        @(posedge pclk); #1; // line-start edge is consumed by the x/y counter
        byte_sample(8'hf8); byte_sample(8'h00);
        byte_sample(8'h07); byte_sample(8'he0);
        href = 0; @(posedge pclk); #1;
        if (count != 2) $fatal(1, "OV5640 pixel count mismatch");
        $display("OV5640_DVP_PASS");
        $finish;
    end
endmodule
