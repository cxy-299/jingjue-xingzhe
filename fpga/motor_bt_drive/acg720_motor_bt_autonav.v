`include "../nav/sin12_map.vh"
// Independent SIN12 build. Same physical pins, legacy SIN11 functions retained.
module acg720_motor_bt_autonav #(parameter integer REV5_ENABLE=0, VISUAL_PRIMARY_ENABLE=0)(
    input wire clk_50m_i,key_s0_n_i,bt_uart_rx_i,pi_uart_rx_i,imu_uart_rx_i,tof0_uart_rx_i,
    input wire [3:0] encoder_a_i,encoder_b_i,
    output wire [3:0] motor_pwm_o,motor_in1_o,motor_in2_o,
    output wire [5:0] led_o,output wire diag_uart_tx_o,bt_uart_tx_o
);
    acg720_motor_bt_drive #(.AUTO_NAV_ENABLE(1),.AUTO_MAP_ID(`SIN12_MAP_ID),.AUTO_MAP_BITS(`SIN12_MAP_BITS),
        .MISSION_ENABLE(1),.VISUAL_PRIMARY_ENABLE(VISUAL_PRIMARY_ENABLE),.ROTATE_ENABLE(1),.VISION_ENABLE(1),.NAV_ENABLE(1),.SENSOR_ENABLE(1),
        .DIAG_ENABLE(0),.STAGGER_MS(0),.TOF_HARD_STOP_MM(100),.REV5_ENABLE(REV5_ENABLE)) u_drive(
        .clk_50m_i(clk_50m_i),.key_s0_n_i(key_s0_n_i),.bt_uart_rx_i(bt_uart_rx_i),
        .pi_uart_rx_i(pi_uart_rx_i),.imu_uart_rx_i(imu_uart_rx_i),.tof0_uart_rx_i(tof0_uart_rx_i),
        .encoder_a_i(encoder_a_i),.encoder_b_i(encoder_b_i),.motor_pwm_o(motor_pwm_o),
        .motor_in1_o(motor_in1_o),.motor_in2_o(motor_in2_o),.led_o(led_o),
        .diag_uart_tx_o(diag_uart_tx_o),.bt_uart_tx_o(bt_uart_tx_o));
endmodule
