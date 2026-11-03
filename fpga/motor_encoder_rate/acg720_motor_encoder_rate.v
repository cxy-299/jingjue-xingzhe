// M1 编码器速度标定：限时开环试转，结束后用 LED2～LED7 显示平均计数。
// 仅用于测量反馈量级；不是 PID 闭环，M2～M4 始终保持关闭。
module acg720_motor_encoder_rate #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer KICK_MS = 100,
    parameter integer RUN_MAX_MS = 700,
    parameter integer SAMPLE_START_MS = 200
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
    localparam integer SAMPLE_START_CYCLES = (CLK_HZ / 1000) * SAMPLE_START_MS;
    // 显示码每加 1，代表约 2 个四倍频计数 / 10 ms。
    // 比如试转 700 ms、从 200 ms 开始统计，则 500 ms 内每 100 个计数显示加 1。
    localparam integer DISPLAY_DIVISOR = ((RUN_MAX_MS - SAMPLE_START_MS) / 10) * 2;
    localparam [15:0] DISPLAY_DIVISOR_16 = DISPLAY_DIVISOR;

    wire m1_pwm;
    wire m1_in1;
    wire m1_in2;
    wire [3:0] motor_led;
    wire signed [31:0] position;
    wire encoder_rst_n = key_s0_n_i && motor_led[1];
    reg [31:0] elapsed = 32'd0;
    reg signed [15:0] start_position = 16'sd0;
    reg sample_ready = 1'b0;
    reg previous_active = 1'b0;
    reg [5:0] measured_code = 6'd0;
    reg signed [15:0] count_delta = 16'sd0;
    reg [15:0] remaining = 16'd0;
    localparam [1:0] METER_IDLE = 2'd0, METER_ABS = 2'd1,
                     METER_DIVIDE = 2'd2, METER_DONE = 2'd3;
    reg [1:0] meter_state = METER_IDLE;

    // 与已通过上板试转的 EMD1 保持同样的电机电气行为和 700 ms 硬超时。
    acg720_motor_m1_kick_80 #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ), .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS), .KICK_MS(KICK_MS), .RUN_MAX_MS(RUN_MAX_MS)
    ) u_m1_drive (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i), .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(m1_pwm), .m1_in1_o(m1_in1), .m1_in2_o(m1_in2), .led_o(motor_led)
    );

    encoder_speed u_m1_encoder (
        .clk(clk_50m_i), .rst_n(encoder_rst_n),
        .encoder_a_i(m1_encoder_a_i), .encoder_b_i(m1_encoder_b_i),
        .sample_tick_i(1'b0), .position_o(position), .speed_o()
    );

    always @(posedge clk_50m_i or negedge encoder_rst_n) begin
        if (!encoder_rst_n) begin
            elapsed <= 32'd0;
            start_position <= 16'sd0;
            sample_ready <= 1'b0;
            previous_active <= 1'b0;
            measured_code <= 6'd0;
            count_delta <= 16'sd0;
            remaining <= 16'd0;
            meter_state <= METER_IDLE;
        end else begin
            previous_active <= m1_in1;
            if (!m1_in1) begin
                elapsed <= 32'd0;
                if (previous_active && sample_ready) begin
                    // 先锁存差值，再逐拍计算绝对值和除数，避免组合除法破坏 50 MHz 时序。
                    count_delta <= position[15:0] - start_position;
                    meter_state <= METER_ABS;
                end else begin
                    case (meter_state)
                        METER_ABS: begin
                            remaining <= count_delta < 0 ? -count_delta : count_delta;
                            meter_state <= METER_DIVIDE;
                        end
                        METER_DIVIDE: begin
                            if (remaining >= DISPLAY_DIVISOR_16 && measured_code < 6'd63) begin
                                remaining <= remaining - DISPLAY_DIVISOR_16;
                                measured_code <= measured_code + 1'b1;
                            end else begin
                                // 63 为量程上限，不能当作精确速度；正常换算至多约 1.3 微秒。
                                meter_state <= METER_DONE;
                            end
                        end
                        default: meter_state <= meter_state;
                    endcase
                end
            end else if (!previous_active) begin
                elapsed <= 32'd0;
                sample_ready <= 1'b0;
                measured_code <= 6'd0;
                meter_state <= METER_IDLE;
            end else if (elapsed < SAMPLE_START_CYCLES) begin
                elapsed <= elapsed + 1'b1;
                if (elapsed == SAMPLE_START_CYCLES - 1) begin
                    start_position <= position[15:0];
                    sample_ready <= 1'b1;
                end
            end
        end
    end

    // FPGA 引脚和 EMD1 完全一致；另外三路所有控制线恒低。
    assign motor_pwm_o = {3'b000, m1_pwm};
    assign motor_in1_o = {3'b000, m1_in1};
    assign motor_in2_o = {3'b000, m1_in2};
    // 运行前/运行中沿用心跳、就绪、运行灯；超时后改为 6 位静态二进制读数。
    assign led_o = (motor_led[3] && meter_state == METER_DONE)
                   ? measured_code : {2'b00, motor_led};
endmodule
