`timescale 1ns/1ps
module tb_bt_motion_guard_tof;
    reg clk = 0, rst_n = 0, armed = 1, force_stop = 0;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0, framing_error = 0;
    wire [2:0] command;
    wire [15:0] target;
    wire timeout_seen, framing_fault;

    always #5 clk = ~clk;
    bt_motion_guard #(.CLK_HZ(1000), .TIMEOUT_MS(300),
        .NEUTRAL_MS(3), .RUN_LIMIT_MS(3000)) dut (
        .clk(clk), .rst_n(rst_n), .armed_i(armed),
        .force_stop_i(force_stop), .rx_data_i(rx_data),
        .rx_valid_i(rx_valid), .framing_error_i(framing_error),
        .command_o(command), .target_counts_o(target),
        .timeout_seen_o(timeout_seen), .framing_fault_o(framing_fault)
    );

    task automatic send(input [7:0] byte_value);
        begin
            @(negedge clk); rx_data = byte_value; rx_valid = 1;
            @(negedge clk); rx_valid = 0;
        end
    endtask
    task automatic expect_command(input [2:0] expected, input [255:0] step_name);
        begin
            @(negedge clk);
            if (command !== expected)
                $fatal(1, "%s: command=%0d expected=%0d", step_name, command, expected);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst_n = 1;
        send("S"); repeat (5) @(negedge clk);
        send("F"); expect_command(1, "initial forward");

        force_stop = 1;
        expect_command(0, "ToF stop while forward");
        repeat (4) send("F");
        force_stop = 0;
        repeat (5) @(negedge clk);
        send("F"); expect_command(0, "stale F after clearance without S");

        force_stop = 1;
        send("S");
        repeat (3) send("F");
        force_stop = 0;
        repeat (5) @(negedge clk);
        expect_command(0, "clearance must not restart itself");
        send("F"); expect_command(1, "new F after S and clearance");
        $display("PASS tb_bt_motion_guard_tof: hard stop discards old direction and needs S");
        $finish;
    end
endmodule
