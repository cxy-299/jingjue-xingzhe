// M1 转速标定 EMR2：只允许单轮限时开环试转，数码管显示稳态窗口的十进制计数。
// 此工程仍不是 PID；不能用于车辆落地行驶。
module acg720_motor_encoder_decimal #(
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
    output wire [5:0] led_o,
    output wire       seg_ds_o,
    output wire       seg_sh_cp_o,
    output wire       seg_st_cp_o,
    // 将完成后的十进制读数同时提供给串口遥测顶层，避免重复实现测速逻辑。
    output wire [3:0] decimal_hundreds_o,
    output wire [3:0] decimal_tens_o,
    output wire [3:0] decimal_ones_o,
    output wire       decimal_negative_o,
    output wire       decimal_overflow_o,
    output wire       decimal_done_o
);
    localparam integer SAMPLE_START_CYCLES = (CLK_HZ / 1000) * SAMPLE_START_MS;
    // 500 ms 采样窗口有 50 个 10 ms 周期，重复减 50 求整数平均值。
    localparam [15:0] DISPLAY_DIVISOR = (RUN_MAX_MS - SAMPLE_START_MS) / 10;
    localparam [2:0] METER_IDLE = 3'd0, METER_ABS = 3'd1,
                     METER_DIVIDE = 3'd2, METER_DONE = 3'd3;

    wire m1_pwm;
    wire m1_in1;
    wire m1_in2;
    wire [3:0] motor_led;
    wire signed [31:0] position;
    wire encoder_rst_n = key_s0_n_i && motor_led[1];
    reg [31:0] elapsed = 32'd0;
    reg signed [15:0] start_position = 16'sd0;
    reg signed [15:0] count_delta = 16'sd0;
    reg [15:0] remaining = 16'd0;
    reg previous_active = 1'b0;
    reg sample_ready = 1'b0;
    reg [2:0] meter_state = METER_IDLE;
    reg [3:0] ones = 4'd0;
    reg [3:0] tens = 4'd0;
    reg [3:0] hundreds = 4'd0;
    reg meter_overflow = 1'b0;

    // 复用 EMD1 已上板验证的 M1 电机驱动，避免改动方向、载波和硬超时。
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

    // 从起动后 200 ms 才开始计数，避开全占空比起动和加速段。
    // 电机停稳后用逐拍减法计算平均计数，整个换算只影响显示而不影响电机控制。
    always @(posedge clk_50m_i or negedge encoder_rst_n) begin
        if (!encoder_rst_n) begin
            elapsed <= 32'd0;
            start_position <= 16'sd0;
            count_delta <= 16'sd0;
            remaining <= 16'd0;
            previous_active <= 1'b0;
            sample_ready <= 1'b0;
            meter_state <= METER_IDLE;
            ones <= 4'd0;
            tens <= 4'd0;
            hundreds <= 4'd0;
            meter_overflow <= 1'b0;
        end else begin
            previous_active <= m1_in1;
            if (!m1_in1) begin
                elapsed <= 32'd0;
                if (previous_active && sample_ready) begin
                    count_delta <= position[15:0] - start_position;
                    meter_state <= METER_ABS;
                end else begin
                    case (meter_state)
                        METER_ABS: begin
                            remaining <= count_delta < 0 ? -count_delta : count_delta;
                            meter_state <= METER_DIVIDE;
                        end
                        METER_DIVIDE: begin
                            if (remaining >= DISPLAY_DIVISOR && !meter_overflow) begin
                                remaining <= remaining - DISPLAY_DIVISOR;
                                if (ones == 4'd9) begin
                                    ones <= 4'd0;
                                    if (tens == 4'd9) begin
                                        tens <= 4'd0;
                                        if (hundreds == 4'd9) begin
                                            hundreds <= 4'd9;
                                            tens <= 4'd9;
                                            ones <= 4'd9;
                                            meter_overflow <= 1'b1;
                                        end else
                                            hundreds <= hundreds + 1'b1;
                                    end else
                                        tens <= tens + 1'b1;
                                end else
                                    ones <= ones + 1'b1;
                            end else
                                meter_state <= METER_DONE;
                        end
                        default: meter_state <= meter_state;
                    endcase
                end
            end else if (!previous_active) begin
                elapsed <= 32'd0;
                sample_ready <= 1'b0;
                meter_state <= METER_IDLE;
                ones <= 4'd0;
                tens <= 4'd0;
                hundreds <= 4'd0;
                meter_overflow <= 1'b0;
            end else if (elapsed < SAMPLE_START_CYCLES) begin
                elapsed <= elapsed + 1'b1;
                if (elapsed == SAMPLE_START_CYCLES - 1) begin
                    start_position <= position[15:0];
                    sample_ready <= 1'b1;
                end
            end
        end
    end

    seg7_hc595_scan #(
        .SCAN_CYCLES(CLK_HZ / 2000), .SHIFT_CYCLES(CLK_HZ / 2000000)
    ) u_display (
        .clk(clk_50m_i), .rst_n(key_s0_n_i),
        .ones_i(ones), .tens_i(tens), .hundreds_i(hundreds),
        .ds_o(seg_ds_o), .sh_cp_o(seg_sh_cp_o), .st_cp_o(seg_st_cp_o)
    );

    assign motor_pwm_o = {3'b000, m1_pwm};
    assign motor_in1_o = {3'b000, m1_in1};
    assign motor_in2_o = {3'b000, m1_in2};
    assign decimal_hundreds_o = hundreds;
    assign decimal_tens_o = tens;
    assign decimal_ones_o = ones;
    assign decimal_negative_o = count_delta < 0;
    assign decimal_overflow_o = meter_overflow;
    assign decimal_done_o = meter_state == METER_DONE;
    // LED2 心跳、LED3 就绪、LED4 运行、LED5 硬超时、LED6 读数完成、LED7 溢出。
    assign led_o = {meter_overflow, (meter_state == METER_DONE), motor_led};
endmodule
