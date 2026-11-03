// M1 使能端恒高的独立诊断顶层：用于区分 PWM 波形问题和方向/接线问题。
// S1 单击启动、再次单击停止；100% 占空比只允许最多 1 秒，不作常规运行位流。
module acg720_motor_m1_toggle_dc #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer RUN_MAX_MS = 1_000
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       key_s1_n_i,
    output wire       m1_pwm_o,
    output wire       m1_in1_o,
    output wire       m1_in2_o,
    output wire [3:0] led_o
);
    wire pwm_unused;
    wire motor_active;

    // 复用已经仿真通过的按键消抖、上电互锁、S0 复位及超时保护。
    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(CLK_HZ),
        .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS),
        .RUN_MAX_MS(RUN_MAX_MS)
    ) u_control (
        .clk_50m_i(clk_50m_i),
        .key_s0_n_i(key_s0_n_i),
        .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(pwm_unused),
        .m1_in1_o(motor_active),
        .m1_in2_o(m1_in2_o),
        .led_o(led_o)
    );

    // 仅诊断版旁路 PWM 载波：使能与方向 1 同时为高、停机时同时为低。
    assign m1_pwm_o = motor_active;
    assign m1_in1_o = motor_active;
endmodule
