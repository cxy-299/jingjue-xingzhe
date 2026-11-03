// M1 单轮电机/编码器方向联调：只允许 M1 短时开环转动，其余三路始终关闭。
// 此版尚不是 PID；LED6 记录本次试转是否收到编码器脉冲，LED7 记录最后脉冲是否为负计数。
module acg720_motor_encoder_direction #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer KICK_MS = 100,
    parameter integer RUN_MAX_MS = 700
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       key_s1_n_i,
    input  wire       m1_encoder_a_i,
    input  wire       m1_encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o
);
    wire m1_pwm;
    wire m1_in1;
    wire m1_in2;
    wire [3:0] motor_led;
    wire signed [31:0] position;
    reg signed [31:0] previous_position = 32'sd0;
    reg previous_active = 1'b0;
    reg pulse_seen = 1'b0;
    reg last_pulse_negative = 1'b0;
    wire encoder_rst_n = key_s0_n_i && motor_led[1];

    // 复用先前实测的 M1 起动电路：S1 单击启动/再按停止，S0 立即停车，700 ms 硬超时。
    acg720_motor_m1_kick_80 #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ), .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS), .KICK_MS(KICK_MS), .RUN_MAX_MS(RUN_MAX_MS)
    ) u_m1_drive (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i), .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(m1_pwm), .m1_in1_o(m1_in1), .m1_in2_o(m1_in2), .led_o(motor_led)
    );

    // 仅读取已通过电平转换的 M1 A/B；其余编码器线在本位流中不参与电机控制。
    encoder_speed u_m1_encoder (
        .clk(clk_50m_i), .rst_n(encoder_rst_n),
        .encoder_a_i(m1_encoder_a_i), .encoder_b_i(m1_encoder_b_i),
        .sample_tick_i(1'b0), .position_o(position), .speed_o()
    );

    // 每次电机从停转进入运行时清除旧结果，只记录本次电机驱动期间的编码器变化。
    always @(posedge clk_50m_i or negedge encoder_rst_n) begin
        if (!encoder_rst_n) begin
            previous_position <= 32'sd0;
            previous_active <= 1'b0;
            pulse_seen <= 1'b0;
            last_pulse_negative <= 1'b0;
        end else begin
            previous_position <= position;
            previous_active <= m1_in1;
            if (m1_in1 && !previous_active) begin
                pulse_seen <= 1'b0;
                last_pulse_negative <= 1'b0;
            end else if (m1_in1 && position != previous_position) begin
                pulse_seen <= 1'b1;
                last_pulse_negative <= position < previous_position;
            end
        end
    end

    // M2～M4 所有电机控制线保持低；M1 的 IN2 始终低，S0 可立即关断 M1。
    assign motor_pwm_o = {3'b000, m1_pwm};
    assign motor_in1_o = {3'b000, m1_in1};
    assign motor_in2_o = {3'b000, m1_in2};
    // LED2 心跳、LED3 就绪、LED4 运行、LED5 超时、LED6 有脉冲、LED7 负计数。
    assign led_o = {last_pulse_negative, pulse_seen, motor_led};
endmodule
