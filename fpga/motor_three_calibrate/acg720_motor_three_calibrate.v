// M2～M4 逐轮离地标定：每次按 S1 仅运行一轮 700 ms，自动切换下一个轮号。
// 本位流只用于确定机械前进方向与编码器极性，禁止四轮落地运行。
module acg720_motor_three_calibrate #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer BAUD = 115_200,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer KICK_MS = 100,
    parameter integer RUN_MAX_MS = 700,
    parameter integer LOSS_TICKS = 20,
    parameter [3:0] REVERSE_MASK = 4'b0000
) (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire key_s1_n_i,
    input wire [3:0] encoder_a_i,
    input wire [3:0] encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o,
    output wire uart_tx_o
);
    localparam integer SAMPLE_CYCLES = ((CLK_HZ / 100) < 1) ? 1 : (CLK_HZ / 100);
    localparam integer KICK_CYCLES = (((CLK_HZ / 1000) * KICK_MS) < 1) ? 1 : ((CLK_HZ / 1000) * KICK_MS);
    wire [3:0] button_led;
    wire run_request;
    wire unused_pwm;
    wire unused_in2;
    reg [1:0] wheel_index = 2'd1;
    reg run_previous = 0;
    reg [31:0] kick_count = 0;
    reg [31:0] sample_count = 0;
    reg sample_tick = 0;
    reg sample_tick_d = 0;
    reg [3:0] telemetry_tick = 0;
    reg [5:0] loss_count = 0;
    reg feedback_seen = 0;
    reg fault_latched = 0;
    wire motor_enable = key_s0_n_i && run_request && !fault_latched;
    wire signed [15:0] duty_permille = kick_count < KICK_CYCLES ? 16'sd1000 : 16'sd800;
    wire [3:0] channel_enable;
    wire signed [15:0] raw_speed [0:3];
    wire signed [15:0] selected_speed = raw_speed[wheel_index];
    wire signed [16:0] speed_abs = selected_speed < 0 ? -$signed(selected_speed) : $signed(selected_speed);

    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ),
        .STARTUP_MS(STARTUP_MS), .DEBOUNCE_MS(DEBOUNCE_MS),
        .RUN_MAX_MS(RUN_MAX_MS)
    ) u_button (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i), .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(unused_pwm), .m1_in1_o(run_request),
        .m1_in2_o(unused_in2), .led_o(button_led)
    );

    // 一次试转结束后顺序改选下一轮；故障期间禁止再次起动，需 S0 复位。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            wheel_index <= 2'd1;
            run_previous <= 0;
            kick_count <= 0;
        end else begin
            run_previous <= run_request;
            if (run_previous && !run_request) begin
                if (wheel_index == 2'd3) wheel_index <= 2'd1;
                else wheel_index <= wheel_index + 1'b1;
            end
            if (!run_request) kick_count <= 0;
            else if (kick_count < KICK_CYCLES) kick_count <= kick_count + 1'b1;
        end
    end

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

    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : wheels
        wire [31:0] unused_position;
        encoder_speed u_encoder (
            .clk(clk_50m_i), .rst_n(key_s0_n_i),
            .encoder_a_i(encoder_a_i[i]), .encoder_b_i(encoder_b_i[i]),
            .sample_tick_i(sample_tick), .position_o(unused_position), .speed_o(raw_speed[i])
        );
        assign channel_enable[i] = motor_enable && wheel_index == i;
        // 原标定版本方向掩码为零；前进核验版本仅反置 M2～M4。
        assign motor_in1_o[i] = channel_enable[i] && !REVERSE_MASK[i];
        assign motor_in2_o[i] = channel_enable[i] && REVERSE_MASK[i];
        motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && button_led[1]),
            .enable_i(channel_enable[i]), .duty_i(duty_permille),
            .pwm_o(motor_pwm_o[i]), .direction_o()
        );
    end endgenerate

    // 起动 100 ms 后无计数持续约 200 ms，或计数异常过快，立即锁存故障。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            loss_count <= 0;
            feedback_seen <= 0;
            fault_latched <= 0;
        end else if (!run_request) begin
            loss_count <= 0;
        end else if (sample_tick_d && kick_count >= KICK_CYCLES && !fault_latched) begin
            if (speed_abs > 80) fault_latched <= 1;
            if (speed_abs < 2) begin
                if (loss_count >= LOSS_TICKS - 1) fault_latched <= 1;
                else loss_count <= loss_count + 1'b1;
            end else begin
                loss_count <= 0;
                feedback_seen <= 1;
            end
        end
    end
    // LED2 心跳、LED3 就绪、LED4 运行、LED5 超时、LED6 有反馈、LED7 故障。
    assign led_o = {fault_latched, feedback_seen, button_led[3], motor_enable, button_led[1:0]};

    // 每 100 ms 发送当前轮号及原始有符号计数，例如 M2:+027\r\n。
    reg [7:0] tx_byte = 0;
    reg tx_start = 0;
    wire tx_busy;
    wire tx_done;
    reg [3:0] byte_index = 0;
    reg [1:0] send_state = 0;
    reg frame_pending = 0;
    reg [1:0] wheel_hold = 1;
    reg negative_hold = 0;
    reg [9:0] speed_hold = 0;
    wire [9:0] speed_hundreds = speed_hold / 10'd100;

    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .start_i(tx_start),
        .data_i(tx_byte), .tx_o(uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            telemetry_tick <= 0;
            byte_index <= 0;
            send_state <= 0;
            frame_pending <= 0;
            wheel_hold <= 1;
            negative_hold <= 0;
            speed_hold <= 0;
            tx_byte <= 0;
            tx_start <= 0;
        end else begin
            tx_start <= 0;
            if (sample_tick_d && motor_enable) begin
                if (telemetry_tick == 9) begin
                    telemetry_tick <= 0;
                    if (send_state == 0) frame_pending <= 1;
                end else telemetry_tick <= telemetry_tick + 1'b1;
            end else if (!run_request) telemetry_tick <= 0;
            case (send_state)
                0: if (frame_pending) begin
                    frame_pending <= 0;
                    wheel_hold <= wheel_index;
                    negative_hold <= selected_speed < 0;
                    speed_hold <= speed_abs > 999 ? 10'd999 : speed_abs[9:0];
                    byte_index <= 0;
                    send_state <= 1;
                end
                1: if (!tx_busy) begin
                    case (byte_index)
                        0: tx_byte <= "M";
                        1: tx_byte <= 8'h31 + {6'd0, wheel_hold};
                        2: tx_byte <= ":";
                        3: tx_byte <= negative_hold ? "-" : "+";
                        4: tx_byte <= 8'h30 + {4'd0, speed_hundreds[3:0]};
                        5: tx_byte <= 8'h30 + (speed_hold / 10) % 10;
                        6: tx_byte <= 8'h30 + speed_hold % 10;
                        7: tx_byte <= 8'h0d;
                        default: tx_byte <= 8'h0a;
                    endcase
                    send_state <= 2;
                end
                2: begin tx_start <= 1; send_state <= 3; end
                3: if (tx_done) begin
                    if (byte_index == 8) send_state <= 0;
                    else begin byte_index <= byte_index + 1'b1; send_state <= 1; end
                end
            endcase
        end
    end
endmodule
