// M2～M4 前进方向复核：每次 S1 仅驱动一轮 700 ms，绝不可落地测试。
// 按用户更正：M2/M4 原方向已前进，只有 M3 需要交换 IN1/IN2。
module acg720_motor_three_forward #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer BAUD = 115_200,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer KICK_MS = 100,
    parameter integer RUN_MAX_MS = 700,
    parameter integer LOSS_TICKS = 20
) (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire key_s1_n_i,
    input wire [3:0] encoder_a_i,
    input wire [3:0] encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o,
    output wire uart_tx_o
);
    acg720_motor_three_calibrate #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ), .BAUD(BAUD),
        .STARTUP_MS(STARTUP_MS), .DEBOUNCE_MS(DEBOUNCE_MS),
        .KICK_MS(KICK_MS), .RUN_MAX_MS(RUN_MAX_MS),
        .LOSS_TICKS(LOSS_TICKS), .REVERSE_MASK(4'b0100)
    ) u_forward (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i),
        .key_s1_n_i(key_s1_n_i), .encoder_a_i(encoder_a_i),
        .encoder_b_i(encoder_b_i), .motor_pwm_o(motor_pwm_o),
        .motor_in1_o(motor_in1_o), .motor_in2_o(motor_in2_o),
        .led_o(led_o), .uart_tx_o(uart_tx_o)
    );
endmodule
