`timescale 1ns/1ps
// ACG720 unified task 1-4 wrapper.
// Camera/DDR3/HDMI is taken from the verified camera netlist; motor,
// encoder, IMU, ToF and navigation remain in the verified BTD6 path.
module acg720_unified_tasks1_4 (
    input        clk50M,
    input        reset_n,
    input        bt_uart_rx_i,
    input        imu_uart_rx_i,
    input        tof_uart_rx_i,
    input  [3:0] encoder_a_i,
    input  [3:0] encoder_b_i,
    input        camera_vsync,
    input        camera_href,
    input        camera_pclk,
    input  [7:0]  camera_data,
    inout        camera_sdat,
    output       camera_sclk,
    output       camera_xclk,
    output       camera_rst_n,
    output       camera_pwdn,
    output [3:0] led,
    output [3:0] motor_pwm_o,
    output [3:0] motor_in1_o,
    output [3:0] motor_in2_o,
    output       diag_uart_tx_o,
    output       bt_uart_tx_o,
    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_data_p,
    output [2:0] tmds_data_n,
    output [13:0] O_ddr_addr,
    output [2:0]  O_ddr_ba,
    output        O_ddr_cs_n,
    output        O_ddr_ras_n,
    output        O_ddr_cas_n,
    output        O_ddr_we_n,
    output        O_ddr_clk,
    output        O_ddr_clk_n,
    output        O_ddr_cke,
    output        O_ddr_odt,
    output        O_ddr_reset_n,
    output [1:0]  O_ddr_dqm,
    inout  [15:0] IO_ddr_dq,
    inout  [1:0]  IO_ddr_dqs,
    inout  [1:0]  IO_ddr_dqs_n
);
    wire [3:0] camera_led;
    wire [5:0] motor_led_unused;

    gao_ov5640_ddr_hdmi u_camera (
        .clk50M(clk50M), .reset_n(reset_n),
        .camera_sclk(camera_sclk), .camera_sdat(camera_sdat),
        .camera_vsync(camera_vsync), .camera_href(camera_href),
        .camera_pclk(camera_pclk), .camera_xclk(camera_xclk),
        .camera_data(camera_data), .camera_rst_n(camera_rst_n),
        .camera_pwdn(camera_pwdn), .led(camera_led),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .O_ddr_addr(O_ddr_addr), .O_ddr_ba(O_ddr_ba),
        .O_ddr_cs_n(O_ddr_cs_n), .O_ddr_ras_n(O_ddr_ras_n),
        .O_ddr_cas_n(O_ddr_cas_n), .O_ddr_we_n(O_ddr_we_n),
        .O_ddr_clk(O_ddr_clk), .O_ddr_clk_n(O_ddr_clk_n),
        .O_ddr_cke(O_ddr_cke), .O_ddr_odt(O_ddr_odt),
        .O_ddr_reset_n(O_ddr_reset_n), .O_ddr_dqm(O_ddr_dqm),
        .IO_ddr_dq(IO_ddr_dq), .IO_ddr_dqs(IO_ddr_dqs),
        .IO_ddr_dqs_n(IO_ddr_dqs_n)
    );

    // S0 is the shared active-low reset. The motor block has already been
    // verified with four-wheel PI, encoder feedback, ToF hard stop and the
    // FPGA navigation route executor.
    acg720_motor_bt_nav u_motion (
        .clk_50m_i(clk50M), .key_s0_n_i(reset_n),
        .bt_uart_rx_i(bt_uart_rx_i),
        .imu_uart_rx_i(imu_uart_rx_i), .tof0_uart_rx_i(tof_uart_rx_i),
        .encoder_a_i(encoder_a_i), .encoder_b_i(encoder_b_i),
        .motor_pwm_o(motor_pwm_o), .motor_in1_o(motor_in1_o),
        .motor_in2_o(motor_in2_o), .led_o(motor_led_unused),
        .diag_uart_tx_o(diag_uart_tx_o), .bt_uart_tx_o(bt_uart_tx_o)
    );

    assign led = camera_led;
endmodule
