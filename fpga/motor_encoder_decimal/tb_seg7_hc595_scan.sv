`timescale 1ns/1ps
module tb_seg7_hc595_scan;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire ds, sh, st;
    reg [15:0] received = 16'd0;
    integer bits_seen = 0;

    always #5 clk = ~clk;

    seg7_hc595_scan #(.SCAN_CYCLES(1000), .SHIFT_CYCLES(1)) dut (
        .clk(clk), .rst_n(rst_n),
        .ones_i(4'd5), .tens_i(4'd2), .hundreds_i(4'd1),
        .ds_o(ds), .sh_cp_o(sh), .st_cp_o(st)
    );

    always @(posedge sh) begin
        received <= {received[14:0], ds};
        bits_seen <= bits_seen + 1;
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge st);
        #1;
        // 个位为 5：段码 0010010（低有效）；位选低位为 1（高有效）。
        if (bits_seen !== 16 || received !== {1'b0, 7'b0010010, 8'b0000_0001}) begin
            $display("FAIL: HC595 serial frame wrong, bits=%0d data=%h", bits_seen, received);
            $finish;
        end
        $display("PASS tb_seg7_hc595_scan: 16-bit data, active-low segments, one-hot digit");
        $finish;
    end
endmodule
