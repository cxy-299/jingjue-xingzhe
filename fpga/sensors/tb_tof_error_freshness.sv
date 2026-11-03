`timescale 1ns/1ps
// Counter-scaled integration test: exact250ms parameter semantics, not IO STA.
module tb_tof_error_freshness;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, rx = 1;
    wire [15:0] distance;
    wire [3:0] valid;
    wire hard_stop;
    sensor_task1_3_core #(
        .CLK_HZ(100000), .TOF_BAUD(10000), .IMU_BAUD(10000),
        .TOF_COUNT(1), .HARD_STOP_MM(100)
    ) dut (
        .clk(clk), .rst_n(rst_n), .imu_uart_rx_i(1'b1),
        .tof0_uart_rx_i(rx), .tof1_uart_rx_i(1'b1), .tof2_uart_rx_i(1'b1), .tof3_uart_rx_i(1'b1),
        .roll_raw_o(), .pitch_raw_o(), .yaw_raw_o(), .imu_angle_valid_o(),
        .tof0_distance_mm_o(distance), .tof1_distance_mm_o(), .tof2_distance_mm_o(), .tof3_distance_mm_o(),
        .tof_valid_o(valid), .tof_obstacle_o(), .tof_hard_stop_o(hard_stop), .tof_decel_o(),
        .tof_speed_scale_permille_o(), .tof_nearest_mm_o(), .tof0_sample_o()
    );
    task byte_value(input [7:0] b, input bit good_stop);
        begin
            rx = 0; repeat (10) @(negedge clk);
            for (integer k = 0; k < 8; k = k + 1) begin rx = b[k]; repeat (10) @(negedge clk); end
            rx = good_stop; repeat (10) @(negedge clk);
            rx = 1; repeat (30) @(negedge clk);
        end
    endtask
    task text(input string s);
        begin
            for (integer k = 0; k < s.len(); k = k + 1) byte_value(s[k], 1);
            repeat (10) @(negedge clk);
        end
    endtask
    initial begin
        repeat (10) @(negedge clk); rst_n = 1;
        text("1707\r\n");
        if (!valid[0] || hard_stop || distance != 1707) $fatal(1, "Initial valid frame failed");
        repeat (20000) @(negedge clk);
        text("4294968996\r\n");
        if (distance != 1707) $fatal(1, "Overflow changed held distance");
        repeat (5000) @(negedge clk);
        if (valid[0] || !hard_stop) $fatal(1, "Overflow refreshed250ms validity");
        text("1708\r\n");
        if (!valid[0] || hard_stop || distance != 1708) $fatal(1, "Recovery after overflow failed");
        repeat (20000) @(negedge clk);
        text("17"); byte_value("9", 0); text("00\r\n");
        if (distance != 1708) $fatal(1, "Framing-error line changed held distance");
        repeat (5000) @(negedge clk);
        if (valid[0] || !hard_stop) $fatal(1, "Framing-error line refreshed250ms validity");
        text("1709\r\n");
        if (!valid[0] || hard_stop || distance != 1709) $fatal(1, "Recovery after frame error failed");
        text("100\r\n");
        if (!valid[0] || !hard_stop || distance != 100) $fatal(1, "100mm hardstop changed");
        text("4294968996\r\n");
        if (!hard_stop || distance != 100) $fatal(1, "Bad line released near-obstacle stop");
        text("101\r\n");
        if (!valid[0] || hard_stop || distance != 101) $fatal(1, "101mm valid recovery changed");
        repeat (10000) @(negedge clk);
        if (!valid[0] || hard_stop) $fatal(1, "100ms gap now invalid");
        repeat (29100) @(negedge clk);
        if (valid[0] || !hard_stop) $fatal(1, "391ms missing-data stop changed");
        $display("TOF_ERROR_FRESHNESS_AND_100MM_STOP_PASS");
        $finish;
    end
    initial begin #3000000; $fatal(1, "Freshness integration timeout"); end
endmodule
