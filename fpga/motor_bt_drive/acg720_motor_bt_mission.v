`timescale 1ns/1ps
// Experimental 100 mm hard-stop variant. SIN6 remains the 250 mm fallback.
// Identical board ports/pins; keep this as a separate top and user code.
module acg720_motor_bt_mission (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire bt_uart_rx_i,
    input wire pi_uart_rx_i,
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
    acg720_motor_bt_drive #(
        .MISSION_ENABLE(1), .ROTATE_ENABLE(1), .VISION_ENABLE(1), .NAV_ENABLE(1), .SENSOR_ENABLE(1), .DIAG_ENABLE(0),
        .STAGGER_MS(125), .TOF_HARD_STOP_MM(100)
    ) u_drive (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i),
        .bt_uart_rx_i(bt_uart_rx_i), .pi_uart_rx_i(pi_uart_rx_i), .imu_uart_rx_i(imu_uart_rx_i),
        .tof0_uart_rx_i(tof0_uart_rx_i),
        .encoder_a_i(encoder_a_i), .encoder_b_i(encoder_b_i),
        .motor_pwm_o(motor_pwm_o), .motor_in1_o(motor_in1_o),
        .motor_in2_o(motor_in2_o), .led_o(led_o),
        .diag_uart_tx_o(diag_uart_tx_o), .bt_uart_tx_o(bt_uart_tx_o)
    );
endmodule
