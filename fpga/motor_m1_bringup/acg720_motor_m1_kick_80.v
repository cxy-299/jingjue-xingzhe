// M1 单轮起动联调：先 100% 短时起动，再切换为 20 kHz、80% PWM。
// 保留 S1 单击启停、S0 立即停车与单次 3 秒上限；此版不是四轮闭环控制。
module acg720_motor_m1_kick_80 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer KICK_MS = 100,
    parameter integer RUN_MAX_MS = 3_000
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       key_s1_n_i,
    output wire       m1_pwm_o,
    output wire       m1_in1_o,
    output wire       m1_in2_o,
    output wire [3:0] led_o
);
    localparam integer KICK_CYCLES = ((CLK_HZ / 1000) * KICK_MS < 1) ? 1 : (CLK_HZ / 1000) * KICK_MS;
    reg [31:0] kick_count = 32'd0;
    wire motor_active;
    wire unused_pwm;
    wire kick_active = motor_active && (kick_count < KICK_CYCLES);
    wire signed [15:0] duty_permille = kick_active ? 16'sd1000 : 16'sd800;

    // 沿用已验证的按键消抖、上电互锁和超时保护；内部 50% 载波在本顶层不使用。
    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(CLK_HZ),
        .PWM_HZ(PWM_HZ),
        .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS),
        .RUN_MAX_MS(RUN_MAX_MS)
    ) u_control (
        .clk_50m_i(clk_50m_i),
        .key_s0_n_i(key_s0_n_i),
        .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(unused_pwm),
        .m1_in1_o(motor_active),
        .m1_in2_o(m1_in2_o),
        .led_o(led_o)
    );

    // 每次停机清零起动计数，下一次按 S1 才重新获得短时全占空比。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i)
            kick_count <= 32'd0;
        else if (!motor_active)
            kick_count <= 32'd0;
        else if (kick_count < KICK_CYCLES)
            kick_count <= kick_count + 1'b1;
    end

    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_motor_pwm (
        .clk(clk_50m_i),
        .rst_n(key_s0_n_i && led_o[1]),
        .enable_i(motor_active),
        .duty_i(duty_permille),
        .pwm_o(m1_pwm_o),
        .direction_o()
    );
    assign m1_in1_o = motor_active;
endmodule
