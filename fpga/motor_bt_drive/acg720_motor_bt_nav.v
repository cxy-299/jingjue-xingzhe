`timescale 1ns/1ps
// BTD6：在 BTD5 四轮闭环蓝牙遥控基础上打开 FPGA 片上 BFS 导航。
// BTD5 顶层保留 NAV_ENABLE=0，避免旧位流意外接受导航帧。
module acg720_motor_bt_nav (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire bt_uart_rx_i,
    input wire imu_uart_rx_i,
    input wire tof0_uart_rx_i,
    input wire [3:0] encoder_a_i,
    input wire [3:0] encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o,
    output wire diag_uart_tx_o,
    output wire bt_uart_tx_o
);
    // SIN5 isolation trial: 125 ms between 100 ms full-duty kicks.  This
    // prevents overlapping startup pulses on the shared 12 V supply.
    acg720_motor_bt_drive #(.NAV_ENABLE(1), .SENSOR_ENABLE(1),
                            .DIAG_ENABLE(0), .STAGGER_MS(125)) u_btd6 (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i),
        .bt_uart_rx_i(bt_uart_rx_i), .imu_uart_rx_i(imu_uart_rx_i),
        .tof0_uart_rx_i(tof0_uart_rx_i), .encoder_a_i(encoder_a_i),
        .encoder_b_i(encoder_b_i), .motor_pwm_o(motor_pwm_o),
        .motor_in1_o(motor_in1_o), .motor_in2_o(motor_in2_o),
        .led_o(led_o), .diag_uart_tx_o(diag_uart_tx_o),
        .bt_uart_tx_o(bt_uart_tx_o)
    );
endmodule
