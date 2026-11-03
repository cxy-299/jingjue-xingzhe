// ACG720 与新 L298P 驱动板的 M1 单轮试转顶层。
// 仅在按住 S1 时输出 20 kHz、10% 占空比；松手立即关断，单次最长 2 秒。
// 此工程用于离地接线验收，不包含编码器闭环、导航或自动启动。
module acg720_motor_m1_bringup #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer HOLD_MAX_MS = 2000,
    parameter integer DUTY_PERMILLE = 100
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
    localparam integer HOLD_MAX_CYCLES = ((CLK_HZ / 1000) * HOLD_MAX_MS < 1) ? 1 : (CLK_HZ / 1000) * HOLD_MAX_MS;
    localparam integer HEARTBEAT_CYCLES = (CLK_HZ / 2 < 1) ? 1 : CLK_HZ / 2;
    localparam signed [15:0] TEST_DUTY = DUTY_PERMILLE;

    // 配置完成后留出上电稳定时间。初值用于 SRAM 配置后的确定性停车。
    reg [31:0] startup_count = 32'd0;
    reg [31:0] debounce_count = 32'd0;
    reg [31:0] hold_count = 32'd0;
    reg [31:0] heartbeat_count = 32'd0;
    reg heartbeat = 1'b0;
    reg s1_meta = 1'b1;
    reg s1_sync = 1'b1;
    reg armed = 1'b0;
    reg expired = 1'b0;
    reg released_since_startup = 1'b0;

    wire startup_done = startup_count >= STARTUP_CYCLES;
    wire arm_reset_n = key_s0_n_i && !key_s1_n_i;
    // 原始按键电平也串在使能上：松手或按 S0 时不等待时钟边沿停车。
    wire motor_active = key_s0_n_i && !key_s1_n_i && !s1_sync &&
                        startup_done && released_since_startup && armed && !expired;

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            startup_count <= 32'd0;
            heartbeat_count <= 32'd0;
            heartbeat <= 1'b0;
            s1_meta <= 1'b1;
            s1_sync <= 1'b1;
        end else begin
            s1_meta <= key_s1_n_i;
            s1_sync <= s1_meta;
            if (!startup_done)
                startup_count <= startup_count + 1'b1;

            if (heartbeat_count >= HEARTBEAT_CYCLES - 1) begin
                heartbeat_count <= 32'd0;
                heartbeat <= ~heartbeat;
            end else begin
                heartbeat_count <= heartbeat_count + 1'b1;
            end

        end
    end

    // 只有上电等待结束后观察到 S1 松开，才能授权之后的一次按下。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i)
            released_since_startup <= 1'b0;
        else if (startup_done && key_s1_n_i)
            released_since_startup <= 1'b1;
    end

    // 松开 S1 时异步撤销内部授权；短暂重新按下也必须重新完成消抖。
    // 上电若 S1 已按住，须先松开一次才能获得试转授权。
    always @(posedge clk_50m_i or negedge arm_reset_n) begin
        if (!arm_reset_n) begin
            debounce_count <= 32'd0;
            hold_count <= 32'd0;
            armed <= 1'b0;
            expired <= 1'b0;
        end else begin
            if (!startup_done || !released_since_startup || s1_sync) begin
                debounce_count <= 32'd0;
                hold_count <= 32'd0;
                armed <= 1'b0;
            end else if (!armed) begin
                if (debounce_count >= DEBOUNCE_CYCLES - 1)
                    armed <= 1'b1;
                else
                    debounce_count <= debounce_count + 1'b1;
            end else if (!expired) begin
                if (hold_count >= HOLD_MAX_CYCLES - 1)
                    expired <= 1'b1;
                else
                    hold_count <= hold_count + 1'b1;
            end
        end
    end

    // M1 的 IN1/IN2 固定为一个方向；PWM 接 L298P 的使能端。
    // 若实际机械方向相反，断电后交换 M1 的两根电机线或修改板级方向映射。
    assign m1_in1_o = motor_active;
    assign m1_in2_o = 1'b0;

    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_m1_pwm (
        .clk(clk_50m_i),
        // PWM 计数器必须在上电等待阶段复位，否则 SRAM 配置后可能为未知态。
        .rst_n(key_s0_n_i && startup_done),
        .enable_i(motor_active),
        .duty_i(TEST_DUTY),
        .pwm_o(m1_pwm_o),
        .direction_o()
    );

    // LED2 心跳、LED3 上电就绪、LED4 电机允许、LED5 单次超时。
    assign led_o = {expired, motor_active, startup_done, heartbeat};
endmodule
