// SIN12 R5 candidate: feedback startup, explicit blocked recovery, local avoidance.
module sin12_hdmi_system(
 input wire clk_50m_i,key_s0_n_i,bt_uart_rx_i,pi_uart_rx_i,imu_uart_rx_i,tof0_uart_rx_i,
 input wire[3:0] encoder_a_i,encoder_b_i,
 output wire[3:0] motor_pwm_o,motor_in1_o,motor_in2_o,
 output wire[5:0]led_o,output wire diag_uart_tx_o,bt_uart_tx_o,
 input wire camera_vsync,camera_href,camera_pclk,input wire[7:0]camera_data,
 output wire camera_sclk,camera_xclk,camera_rst_n,camera_pwdn,inout wire camera_sdat,
 output wire tmds_clk_p,tmds_clk_n,output wire[2:0]tmds_data_p,tmds_data_n
);
 acg720_motor_bt_autonav #(.REV5_ENABLE(16)) u_robot(
  .clk_50m_i(clk_50m_i),.key_s0_n_i(key_s0_n_i),.bt_uart_rx_i(bt_uart_rx_i),.pi_uart_rx_i(pi_uart_rx_i),
  .imu_uart_rx_i(imu_uart_rx_i),.tof0_uart_rx_i(tof0_uart_rx_i),.encoder_a_i(encoder_a_i),.encoder_b_i(encoder_b_i),
  .motor_pwm_o(motor_pwm_o),.motor_in1_o(motor_in1_o),.motor_in2_o(motor_in2_o),.led_o(led_o),
  .diag_uart_tx_o(diag_uart_tx_o),.bt_uart_tx_o(bt_uart_tx_o));
 sin12_camera_hdmi u_camera(
  .clk50M(clk_50m_i),.reset_n(key_s0_n_i),.camera_vsync(camera_vsync),.camera_href(camera_href),
  .camera_pclk(camera_pclk),.camera_data(camera_data),.camera_sclk(camera_sclk),.camera_sdat(camera_sdat),
  .camera_xclk(camera_xclk),.camera_rst_n(camera_rst_n),.camera_pwdn(camera_pwdn),
  .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n),
  .init_done_o(),.frame_valid_o());
endmodule
