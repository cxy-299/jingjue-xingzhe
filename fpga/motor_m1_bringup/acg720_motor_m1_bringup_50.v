// M1 单轮 50% 占空比试转顶层：保留原有 10% 工程，便于对照和回退。
// 为降低首次起动时的风险，每次按住 S1 最多使能 500 ms；松手立即停止。
module acg720_motor_m1_bringup_50 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer HOLD_MAX_MS = 500
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       key_s1_n_i,
    output wire       m1_pwm_o,
    output wire       m1_in1_o,
    output wire       m1_in2_o,
    output wire [3:0] led_o
);
    acg720_motor_m1_bringup #(
        .CLK_HZ(CLK_HZ),
        .PWM_HZ(PWM_HZ),
        .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS),
        .HOLD_MAX_MS(HOLD_MAX_MS),
        .DUTY_PERMILLE(500)
    ) u_test (
        .clk_50m_i(clk_50m_i),
        .key_s0_n_i(key_s0_n_i),
        .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(m1_pwm_o),
        .m1_in1_o(m1_in1_o),
        .m1_in2_o(m1_in2_o),
        .led_o(led_o)
    );
endmodule
