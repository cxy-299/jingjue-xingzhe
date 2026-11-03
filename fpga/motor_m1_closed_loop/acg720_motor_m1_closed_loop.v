// M1 离地闭环标定：S1 单击起动，S0 急停，最长两秒；其余三路始终关闭。
// 速度单位为编码器四倍频计数/10 ms，M1 前进时原始计数为负，控制前先反号。
module acg720_motor_m1_closed_loop #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer BAUD = 115_200,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer RUN_MAX_MS = 2_000,
    parameter integer KICK_MS = 100,
    parameter integer TARGET_COUNTS = 20,
    parameter integer BASE_DUTY = 600,
    parameter integer KP = 8,
    parameter integer KI = 1,
    parameter integer LOSS_TICKS = 20,
    parameter integer MAX_COUNTS = 50
) (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire key_s1_n_i,
    input wire m1_encoder_a_i,
    input wire m1_encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o,
    output wire uart_tx_o
);
    localparam integer SAMPLE_CYCLES = ((CLK_HZ / 100) < 1) ? 1 : (CLK_HZ / 100);
    localparam integer KICK_CYCLES = (((CLK_HZ / 1000) * KICK_MS) < 1) ? 1 : ((CLK_HZ / 1000) * KICK_MS);
    localparam signed [17:0] TARGET_18 = TARGET_COUNTS;
    reg [31:0] sample_count = 0;
    reg [31:0] kick_count = 0;
    reg sample_tick = 0;
    reg sample_tick_d = 0;
    reg [3:0] telemetry_tick = 0;
    reg signed [15:0] duty_permille = BASE_DUTY;
    reg signed [31:0] integral = 0;
    reg [5:0] loss_count = 0;
    reg [1:0] reverse_count = 0;
    reg fault_latched = 0;
    reg feedback_seen = 0;
    reg run_previous = 0;
    reg signed [17:0] error_stage = 0;
    reg error_pending = 0;
    wire [3:0] control_led;
    wire run_request;
    wire unused_pwm;
    wire unused_in2;
    wire signed [15:0] raw_speed;
    wire signed [16:0] forward_speed = -$signed(raw_speed);
    wire signed [17:0] forward_18 = {forward_speed[16], forward_speed};
    wire [31:0] unused_position;
    wire motor_enable = key_s0_n_i && run_request && !fault_latched;
    wire kick_active = motor_enable && kick_count < KICK_CYCLES;
    wire signed [15:0] motor_duty = kick_active ? 16'sd1000 : duty_permille;
    integer integral_calc;
    integer output_calc;

    // 复用已上板验证的按键消抖、上电松键互锁和硬超时。
    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ),
        .STARTUP_MS(STARTUP_MS), .DEBOUNCE_MS(DEBOUNCE_MS),
        .RUN_MAX_MS(RUN_MAX_MS)
    ) u_button (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i), .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(unused_pwm), .m1_in1_o(run_request),
        .m1_in2_o(unused_in2), .led_o(control_led)
    );

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            sample_count <= 0;
            sample_tick <= 0;
            sample_tick_d <= 0;
        end else begin
            sample_tick_d <= sample_tick;
            sample_tick <= 0;
            if (sample_count >= SAMPLE_CYCLES - 1) begin
                sample_count <= 0;
                sample_tick <= 1;
            end else sample_count <= sample_count + 1'b1;
        end
    end

    encoder_speed u_encoder (
        .clk(clk_50m_i), .rst_n(key_s0_n_i),
        .encoder_a_i(m1_encoder_a_i), .encoder_b_i(m1_encoder_b_i),
        .sample_tick_i(sample_tick), .position_o(unused_position), .speed_o(raw_speed)
    );

    // 起动全占空比窗口结束后才检查反馈，防止静止时误判编码器丢失。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) kick_count <= 0;
        else if (!run_request) kick_count <= 0;
        else if (kick_count < KICK_CYCLES) kick_count <= kick_count + 1'b1;
    end

    // 积分只在目标附近逐步修正，且上下限同时约束积分和实际 PWM。
    // 故障锁存只能用 S0 复位清除，避免编码器线间歇接触导致自动再起动。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            duty_permille <= BASE_DUTY;
            integral <= 0;
            loss_count <= 0;
            reverse_count <= 0;
            fault_latched <= 0;
            feedback_seen <= 0;
            run_previous <= 0;
            error_stage <= 0;
            error_pending <= 0;
        end else begin
            run_previous <= run_request;
            if (!run_request || !run_previous) begin
                duty_permille <= BASE_DUTY;
                integral <= 0;
                loss_count <= 0;
                reverse_count <= 0;
                error_pending <= 0;
            end else begin
                // 将速度误差先打一拍，避免编码器到 PWM 的长组合路径。
                if (error_pending) begin
                    error_pending <= 0;
                    if (!fault_latched) begin
                        integral_calc = integral + KI * error_stage;
                        if (integral_calc > 200) integral_calc = 200;
                        if (integral_calc < -200) integral_calc = -200;
                        output_calc = BASE_DUTY + KP * error_stage + integral_calc;
                        if (output_calc > 850) output_calc = 850;
                        if (output_calc < 300) output_calc = 300;
                        integral <= integral_calc;
                        duty_permille <= output_calc[15:0];
                    end
                end
                if (sample_tick_d && !fault_latched && !kick_active) begin
                    if (forward_speed > MAX_COUNTS) fault_latched <= 1;
                    if (forward_speed < -2) begin
                        if (reverse_count >= 2) fault_latched <= 1;
                        else reverse_count <= reverse_count + 1'b1;
                    end else reverse_count <= 0;
                    if (forward_speed < 2) begin
                        if (loss_count >= LOSS_TICKS - 1) fault_latched <= 1;
                        else loss_count <= loss_count + 1'b1;
                    end else begin
                        loss_count <= 0;
                        feedback_seen <= 1;
                    end
                    error_stage <= TARGET_18 - forward_18;
                    error_pending <= 1;
                end
            end
        end
    end

    assign motor_in1_o = {3'b000, motor_enable};
    assign motor_in2_o = 4'b0000;
    assign motor_pwm_o[3:1] = 3'b000;
    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm (
        .clk(clk_50m_i), .rst_n(key_s0_n_i && control_led[1]),
        .enable_i(motor_enable), .duty_i(motor_duty),
        .pwm_o(motor_pwm_o[0]), .direction_o()
    );
    // LED2 心跳、LED3 就绪、LED4 运行、LED5 硬超时、LED6 有反馈、LED7 故障。
    assign led_o = {fault_latched, feedback_seen, control_led[3], motor_enable,
                    control_led[1:0]};

    // 每 100 ms 发送一帧目标、实际速度、占空比及故障状态，供电脑串口标定。
    // 例如 M1 T020 A+026 D0600 F0\r\n；串口不是控制入口。
    reg [7:0] tx_byte = 0;
    reg tx_start = 0;
    wire tx_busy;
    wire tx_done;
    reg [4:0] byte_index = 0;
    reg [1:0] send_state = 0;
    reg [9:0] actual_hold = 0;
    reg actual_negative_hold = 0;
    reg [9:0] duty_hold = 0;
    reg fault_hold = 0;
    reg frame_pending = 0;
    wire [16:0] actual_abs = forward_speed < 0 ? -forward_speed : forward_speed;
    wire [9:0] actual_hundreds = actual_hold / 10'd100;
    wire [9:0] duty_thousands = duty_hold / 10'd1000;

    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .start_i(tx_start),
        .data_i(tx_byte), .tx_o(uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            telemetry_tick <= 0;
            frame_pending <= 0;
            actual_hold <= 0;
            actual_negative_hold <= 0;
            duty_hold <= 0;
            fault_hold <= 0;
            byte_index <= 0;
            send_state <= 0;
            tx_byte <= 0;
            tx_start <= 0;
        end else begin
            tx_start <= 0;
            if (sample_tick_d) begin
                if (telemetry_tick == 9) begin
                    telemetry_tick <= 0;
                    if (send_state == 0) frame_pending <= 1;
                end else telemetry_tick <= telemetry_tick + 1'b1;
            end
            case (send_state)
                0: if (frame_pending) begin
                    frame_pending <= 0;
                    actual_hold <= actual_abs > 999 ? 10'd999 : actual_abs[9:0];
                    actual_negative_hold <= forward_speed < 0;
                    duty_hold <= motor_enable ? motor_duty[9:0] : 10'd0;
                    fault_hold <= fault_latched;
                    byte_index <= 0;
                    send_state <= 1;
                end
                1: if (!tx_busy) begin
                    case (byte_index)
                        0: tx_byte <= "M"; 1: tx_byte <= "1"; 2: tx_byte <= " ";
                        3: tx_byte <= "T";
                        4: tx_byte <= "0" + (TARGET_COUNTS / 100) % 10;
                        5: tx_byte <= "0" + (TARGET_COUNTS / 10) % 10;
                        6: tx_byte <= "0" + TARGET_COUNTS % 10;
                        7: tx_byte <= " "; 8: tx_byte <= "A";
                        9: tx_byte <= actual_negative_hold ? "-" : "+";
                        10: tx_byte <= 8'h30 + {4'd0, actual_hundreds[3:0]};
                        11: tx_byte <= 8'h30 + ((actual_hold / 10) % 10);
                        12: tx_byte <= 8'h30 + (actual_hold % 10);
                        13: tx_byte <= " "; 14: tx_byte <= "D";
                        15: tx_byte <= 8'h30 + {4'd0, duty_thousands[3:0]};
                        16: tx_byte <= 8'h30 + ((duty_hold / 100) % 10);
                        17: tx_byte <= 8'h30 + ((duty_hold / 10) % 10);
                        18: tx_byte <= 8'h30 + (duty_hold % 10);
                        19: tx_byte <= " "; 20: tx_byte <= "F";
                        21: tx_byte <= fault_hold ? "1" : "0";
                        22: tx_byte <= 8'h0d;
                        default: tx_byte <= 8'h0a;
                    endcase
                    send_state <= 2;
                end
                2: begin tx_start <= 1; send_state <= 3; end
                3: if (tx_done) begin
                    if (byte_index == 23) send_state <= 0;
                    else begin byte_index <= byte_index + 1'b1; send_state <= 1; end
                end
            endcase
        end
    end
endmodule
