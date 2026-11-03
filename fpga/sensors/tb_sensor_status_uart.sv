`timescale 1ns/1ps
module tb_sensor_status_uart;
    reg clk=0, rst_n=0;
    always #500 clk=~clk; // 1 MHz
    wire tx, rx_valid, rx_error;
    wire [7:0] rx_data;
    reg [7:0] got [0:52];
    integer count=0;

    sensor_status_uart #(.CLK_HZ(1_000_000), .BAUD(100_000), .REPORT_MS(100)) dut (
        .clk(clk), .rst_n(rst_n), .imu_valid_i(1'b1), .tof_valid_i(1'b1),
        .distance_i(16'd455), .hard_stop_i(1'b0),
        .fault_flags_i(8'h12), .wheel_fault_i(4'h5), .roll_bits_i(32'h3f800000),
        .pitch_bits_i(32'hbf000000), .yaw_bits_i(32'h3e800000), .tx_o(tx)
    );
    uart_rx #(.CLK_HZ(1_000_000), .BAUD(100_000)) rx (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(tx), .data_o(rx_data),
        .data_valid_o(rx_valid), .framing_error_o(rx_error)
    );
    always @(posedge clk) if (rx_valid && count < 53) begin
        got[count] <= rx_data;
        count <= count+1;
    end
    initial begin
        repeat(10) @(posedge clk);
        rst_n=1;
        wait(count==53);
        repeat(2) @(posedge clk);
        if (got[0]!="I" || got[1]!="1" || got[3]!="T" || got[4]!="1" ||
            got[6]!="D" || got[7]!="0" || got[8]!="4" || got[9]!="5" || got[10]!="5" ||
            got[12]!="H" || got[13]!="0" || got[15]!="F" || got[16]!="1" || got[17]!="2" ||
            got[19]!="R" || got[20]!="3" || got[27]!="0" ||
            got[29]!="P" || got[30]!="B" || got[37]!="0" ||
            got[39]!="Y" || got[40]!="3" || got[47]!="0" ||
            got[48]!=" " || got[49]!="W" || got[50]!="5" ||
            got[51]!=8'h0d || got[52]!=8'h0a || rx_error)
            $fatal(1,"extended sensor status UART mismatch");
        $display("SENSOR_STATUS_UART_PASS");
        $finish;
    end
    initial begin
        #10_000_000;
        $fatal(1,"sensor status UART timeout");
    end
endmodule
