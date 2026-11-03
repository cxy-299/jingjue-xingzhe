// M1 单轮持续转动联调：S1 按一下启动、再按一下停止，S0 立即复位停车。
// PWM 为 20 kHz、50%；无编码器反馈时单次运行最多 10 秒，禁止无人看管。
module acg720_motor_m1_toggle_50 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer RUN_MAX_MS = 10_000
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       key_s1_n_i,
    output wire       m1_pwm_o,
    output wire       m1_in1_o,
    output wire       m1_in2_o,
    output wire [3:0] led_o
);
    localparam integer STARTUP_CYCLES = ((CLK_HZ / 1000) * STARTUP_MS < 1) ? 1 : (CLK_HZ / 1000) * STARTUP_MS;
    localparam integer DEBOUNCE_CYCLES = ((CLK_HZ / 1000) * DEBOUNCE_MS < 1) ? 1 : (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer RUN_MAX_CYCLES = ((CLK_HZ / 1000) * RUN_MAX_MS < 1) ? 1 : (CLK_HZ / 1000) * RUN_MAX_MS;
    localparam integer HEARTBEAT_CYCLES = (CLK_HZ / 2 < 1) ? 1 : CLK_HZ / 2;

    // SRAM 配置后的寄存器初值确保电机默认关闭。
    reg [31:0] startup_count = 32'd0;
    reg [31:0] debounce_count = 32'd0;
    reg [31:0] run_count = 32'd0;
    reg [31:0] heartbeat_count = 32'd0;
    reg heartbeat = 1'b0;
    reg s1_meta = 1'b1;
    reg s1_sync = 1'b1;
    reg s1_stable = 1'b1;
    reg press_pulse = 1'b0;
    reg release_seen = 1'b0;
    reg run_latched = 1'b0;
    reg expired = 1'b0;

    wire startup_done = startup_count >= STARTUP_CYCLES;
    // S0 直接门控输出，不必等待下一个时钟沿。
    wire motor_active = key_s0_n_i && startup_done && release_seen && run_latched && !expired;

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            startup_count <= 32'd0;
            heartbeat_count <= 32'd0;
            heartbeat <= 1'b0;
            s1_meta <= 1'b1;
            s1_sync <= 1'b1;
            s1_stable <= 1'b1;
            debounce_count <= 32'd0;
            press_pulse <= 1'b0;
            release_seen <= 1'b0;
        end else begin
            s1_meta <= key_s1_n_i;
            s1_sync <= s1_meta;
            press_pulse <= 1'b0;

            if (!startup_done)
                startup_count <= startup_count + 1'b1;
            if (heartbeat_count >= HEARTBEAT_CYCLES - 1) begin
                heartbeat_count <= 32'd0;
                heartbeat <= ~heartbeat;
            end else
                heartbeat_count <= heartbeat_count + 1'b1;

            // 只有等待完成后观察到 S1 稳定松开，才允许下一次按下启动。
            if (startup_done && s1_stable && key_s1_n_i)
                release_seen <= 1'b1;

            // 两级同步加连续稳定计数，按下边沿仅产生一个时钟的脉冲。
            if (s1_sync == s1_stable)
                debounce_count <= 32'd0;
            else if (debounce_count >= DEBOUNCE_CYCLES - 1) begin
                debounce_count <= 32'd0;
                s1_stable <= s1_sync;
                if (s1_stable && !s1_sync)
                    press_pulse <= 1'b1;
            end else
                debounce_count <= debounce_count + 1'b1;
        end
    end

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            run_latched <= 1'b0;
            run_count <= 32'd0;
            expired <= 1'b0;
        end else if (!startup_done) begin
            run_latched <= 1'b0;
            run_count <= 32'd0;
            expired <= 1'b0;
        end else if (press_pulse && release_seen) begin
            // 每一次经过消抖的按下切换运行状态；停机优先于继续计时。
            run_latched <= !run_latched;
            run_count <= 32'd0;
            expired <= 1'b0;
        end else if (run_latched) begin
            if (run_count >= RUN_MAX_CYCLES - 1) begin
                run_latched <= 1'b0;
                run_count <= 32'd0;
                expired <= 1'b1;
            end else
                run_count <= run_count + 1'b1;
        end else
            run_count <= 32'd0;
    end

    // 方向输入始终为 1/0；PWM 关闭时使能端为低，驱动器不施加动力。
    assign m1_in1_o = motor_active;
    assign m1_in2_o = 1'b0;
    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_m1_pwm (
        .clk(clk_50m_i),
        .rst_n(key_s0_n_i && startup_done),
        .enable_i(motor_active),
        .duty_i(16'sd500),
        .pwm_o(m1_pwm_o),
        .direction_o()
    );

    // LED2 心跳、LED3 就绪、LED4 正在运行、LED5 达到 10 秒上限。
    assign led_o = {expired, motor_active, startup_done, heartbeat};
endmodule
