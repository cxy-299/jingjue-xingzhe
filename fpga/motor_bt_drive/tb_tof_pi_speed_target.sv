`timescale 1ns/1ps
// Verify that ToF limits the PI speed reference, while its PWM output remains
// under PI control until the independent hard-stop gate closes the motor.
module tb_tof_pi_speed_target;
    reg clk = 0, rst_n = 0;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    wire diag_tx, bt_tx;
    always #500 clk = ~clk;

    acg720_motor_bt_drive #(
        .CLK_HZ(1_000_000), .STARTUP_MS(1), .SENSOR_ENABLE(1),
        .DIAG_ENABLE(0), .NAV_ENABLE(0)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(rst_n), .bt_uart_rx_i(1'b1),
        .imu_uart_rx_i(1'b1), .tof0_uart_rx_i(1'b1),
        .encoder_a_i(4'b0), .encoder_b_i(4'b0),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .diag_uart_tx_o(diag_tx), .bt_uart_tx_o(bt_tx)
    );

    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        wait(dut.ready);
        force dut.tof_hard_stop = 1'b0;
        force dut.tof_speed_scale_permille = 10'd1000;
        #1;
        if (dut.effective_target_counts != 20) $fatal(1, "clear target mismatch");
        force dut.tof_speed_scale_permille = 10'd750;
        #1;
        if (dut.effective_target_counts != 15 ||
            dut.wheels[0].u_control.target_counts_i != 15 ||
            dut.wheels[0].applied_duty != dut.wheels[0].wheel_duty)
            $fatal(1, "75%% ToF decel must limit PI target without PWM clipping");
        force dut.tof_speed_scale_permille = 10'd500;
        #1;
        if (dut.effective_target_counts != 10 ||
            dut.wheels[0].u_control.target_counts_i != 10 ||
            dut.wheels[0].applied_duty != dut.wheels[0].wheel_duty)
            $fatal(1, "50%% ToF decel must limit PI target without PWM clipping");
        force dut.tof_hard_stop = 1'b1;
        #1;
        if (dut.effective_target_counts != 0 || dut.wheels[0].applied_duty != 0)
            $fatal(1, "hard stop did not zero target and PWM");
        $display("PASS tb_tof_pi_speed_target: 20/15/10/0 and no post-PI PWM clipping");
        $finish;
    end
endmodule
