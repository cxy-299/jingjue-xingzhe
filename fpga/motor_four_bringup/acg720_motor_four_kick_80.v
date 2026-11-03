// 四轮离地联调：一次按 S1 依次错峰起动四路，随后四路同时保持 20 kHz、80% PWM。
// 这里只验证电气通道，不使用编码器，不代表四轮方向已经标定或形成闭环。
module acg720_motor_four_kick_80 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer KICK_MS = 100,
    parameter integer STAGGER_MS = 125,
    parameter integer RUN_MAX_MS = 3_000
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       key_s1_n_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o
);
    localparam integer KICK_CYCLES = ((CLK_HZ / 1000) * KICK_MS < 1) ? 1 : (CLK_HZ / 1000) * KICK_MS;
    localparam integer STAGGER_CYCLES = ((CLK_HZ / 1000) * STAGGER_MS < 1) ? 1 : (CLK_HZ / 1000) * STAGGER_MS;
    localparam integer PHASE_END = 3 * STAGGER_CYCLES + KICK_CYCLES;

    reg [31:0] phase_count = 32'd0;
    wire motor_active;
    wire unused_pwm;
    wire unused_in2;
    wire [3:0] control_led;
    wire [3:0] channel_enable;

    // 复用 M1 已实测的 S1 单击启停、上电松键互锁、S0 复位和 3 秒超时逻辑。
    // 内部原有 50% 载波不连接任何输出，综合时可以安全优化掉。
    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ),
        .STARTUP_MS(STARTUP_MS), .DEBOUNCE_MS(DEBOUNCE_MS),
        .RUN_MAX_MS(RUN_MAX_MS)
    ) u_control (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i),
        .key_s1_n_i(key_s1_n_i), .m1_pwm_o(unused_pwm),
        .m1_in1_o(motor_active), .m1_in2_o(unused_in2),
        .led_o(control_led)
    );

    // 四轮依次间隔 125 ms 起动，避免四路同时进入 100% 起动窗口。
    // 停机立即清零；下一次单击重新从 M1 开始。计数饱和后保持四路 80%。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i)
            phase_count <= 32'd0;
        else if (!motor_active)
            phase_count <= 32'd0;
        else if (phase_count < PHASE_END)
            phase_count <= phase_count + 1'b1;
    end

    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : motors
        localparam integer START_CYCLES = i * STAGGER_CYCLES;
        wire kick_active = channel_enable[i] && (phase_count < START_CYCLES + KICK_CYCLES);
        wire signed [15:0] duty_permille = kick_active ? 16'sd1000 : 16'sd800;

        // 电气正转均为 IN1=1、IN2=0；机械前进方向须逐轮实测后另行标定。
        assign channel_enable[i] = motor_active && (phase_count >= START_CYCLES);
        assign motor_in1_o[i] = channel_enable[i];
        assign motor_in2_o[i] = 1'b0;
        motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && control_led[1]),
            .enable_i(channel_enable[i]), .duty_i(duty_permille),
            .pwm_o(motor_pwm_o[i]), .direction_o()
        );
    end endgenerate

    // LED2 心跳、LED3 就绪、LED4 总运行、LED5 超时、LED6 四路均已使能、LED7 保留。
    assign led_o = {1'b0, (&channel_enable), control_led};
endmodule
