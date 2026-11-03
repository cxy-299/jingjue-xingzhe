// 编码器接线验收专用：12 根电机控制输出始终为低，绝不运行电机。
// LED4～LED7 分别显示 M1～M4 的脉冲活动：稳定亮为正计数，闪烁为负计数。
// 编码器 5 V 信号必须先经过 5 V→3.3 V 电平转换，禁止直接接 FPGA。
module acg720_encoder_probe #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer HOLD_MS = 500,
    parameter integer BLINK_HZ = 5,
    parameter integer STARTUP_MS = 20
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire [3:0] encoder_a_i,
    input  wire [3:0] encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o
);
    localparam integer HOLD_CYCLES = ((CLK_HZ / 1000) * HOLD_MS < 1) ? 1 : (CLK_HZ / 1000) * HOLD_MS;
    localparam integer BLINK_HALF_CYCLES = ((CLK_HZ / (BLINK_HZ * 2)) < 1) ? 1 : CLK_HZ / (BLINK_HZ * 2);
    localparam integer HEARTBEAT_HALF_CYCLES = (CLK_HZ / 2 < 1) ? 1 : CLK_HZ / 2;
    localparam integer STARTUP_CYCLES = ((CLK_HZ / 1000) * STARTUP_MS < 1) ? 1 : (CLK_HZ / 1000) * STARTUP_MS;

    reg [31:0] startup_count = 32'd0;
    reg [31:0] blink_count = 32'd0;
    reg [31:0] heartbeat_count = 32'd0;
    reg blink = 1'b1;
    reg heartbeat = 1'b0;
    wire [3:0] activity_led;
    wire probe_rst_n = key_s0_n_i && (startup_count >= STARTUP_CYCLES);

    // 上电后先保持复位，使编码器同步器和计数器都有确定初值。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i)
            startup_count <= 32'd0;
        else if (startup_count < STARTUP_CYCLES)
            startup_count <= startup_count + 1'b1;
    end

    // 所有驱动输入为常低，编码器验收阶段不含 PWM 或闭环控制。
    assign motor_pwm_o = 4'b0000;
    assign motor_in1_o = 4'b0000;
    assign motor_in2_o = 4'b0000;
    assign led_o = {activity_led, probe_rst_n, heartbeat};

    always @(posedge clk_50m_i or negedge probe_rst_n) begin
        if (!probe_rst_n) begin
            blink_count <= 32'd0;
            heartbeat_count <= 32'd0;
            blink <= 1'b1;
            heartbeat <= 1'b0;
        end else begin
            if (blink_count >= BLINK_HALF_CYCLES - 1) begin
                blink_count <= 32'd0;
                blink <= ~blink;
            end else
                blink_count <= blink_count + 1'b1;
            if (heartbeat_count >= HEARTBEAT_HALF_CYCLES - 1) begin
                heartbeat_count <= 32'd0;
                heartbeat <= ~heartbeat;
            end else
                heartbeat_count <= heartbeat_count + 1'b1;
        end
    end

    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : channels
        wire signed [31:0] position;
        reg signed [31:0] previous_position = 32'sd0;
        reg [31:0] pulse_age = HOLD_CYCLES;
        reg last_forward = 1'b1;

        encoder_speed u_encoder (
            .clk(clk_50m_i), .rst_n(probe_rst_n),
            .encoder_a_i(encoder_a_i[i]), .encoder_b_i(encoder_b_i[i]),
            .sample_tick_i(1'b0), .position_o(position), .speed_o()
        );

        // 只检测已同步的合法正交状态变化；500 ms 无变化则灯灭。
        always @(posedge clk_50m_i or negedge probe_rst_n) begin
            if (!probe_rst_n) begin
                previous_position <= 32'sd0;
                pulse_age <= HOLD_CYCLES;
                last_forward <= 1'b1;
            end else begin
                previous_position <= position;
                if (position != previous_position) begin
                    pulse_age <= 32'd0;
                    last_forward <= position > previous_position;
                end else if (pulse_age < HOLD_CYCLES)
                    pulse_age <= pulse_age + 1'b1;
            end
        end
        assign activity_led[i] = probe_rst_n && (pulse_age < HOLD_CYCLES) &&
                                 (last_forward || blink);
    end endgenerate
endmodule
