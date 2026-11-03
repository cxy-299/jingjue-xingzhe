// 四轮离地闭环试验：S1 单击起停，S0 急停，最长两秒；禁止以此位流直接落地。
// 实物车头为 M1/M2 端；4CL2 修正 M1，与 M3 一样使用 IN2 且前进计数为正。
module acg720_motor_four_closed_loop #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer BAUD = 115_200,
    parameter integer STARTUP_MS = 20,
    parameter integer DEBOUNCE_MS = 10,
    parameter integer RUN_MAX_MS = 2_000,
    parameter integer STAGGER_MS = 125,
    parameter integer KICK_MS = 100,
    parameter integer TARGET_COUNTS = 20,
    parameter integer LOSS_TICKS = 20
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
    localparam integer SAMPLE_CYCLES = CLK_HZ / 100 < 1 ? 1 : CLK_HZ / 100;
    localparam integer STAGGER_CYCLES = (CLK_HZ / 1000) * STAGGER_MS;
    localparam integer KICK_CYCLES = (CLK_HZ / 1000) * KICK_MS < 1 ? 1 : (CLK_HZ / 1000) * KICK_MS;
    wire [3:0] button_led;
    wire run_request;
    wire unused_pwm, unused_in2;
    wire [3:0] channel_enable;
    wire [3:0] channel_fault;
    wire [3:0] feedback_seen;
    wire signed [15:0] speed [0:3];
    wire [15:0] duty [0:3];
    wire motor_enable = key_s0_n_i && run_request && !(|channel_fault);
    reg [31:0] run_age = 0;
    reg [31:0] sample_count = 0;
    reg sample_tick = 0;
    reg sample_tick_d = 0;

    // 复用已实测的按键上电互锁、消抖与两秒硬超时。
    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ), .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS), .RUN_MAX_MS(RUN_MAX_MS)
    ) u_button (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i), .key_s1_n_i(key_s1_n_i),
        .m1_pwm_o(unused_pwm), .m1_in1_o(run_request),
        .m1_in2_o(unused_in2), .led_o(button_led)
    );

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            run_age <= 0;
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
            if (!motor_enable) run_age <= 0;
            else if (run_age < 3 * STAGGER_CYCLES) run_age <= run_age + 1'b1;
        end
    end

    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : wheels
        wire signed [15:0] raw_speed;
        wire [31:0] unused_position;
        wire signed [16:0] normalized_speed = (i == 0 || i == 2) ? $signed(raw_speed) : -$signed(raw_speed);
        wire signed [15:0] pwm_duty;
        assign channel_enable[i] = motor_enable && run_age >= i * STAGGER_CYCLES;
        assign motor_in1_o[i] = channel_enable[i] && i != 0 && i != 2;
        assign motor_in2_o[i] = channel_enable[i] && (i == 0 || i == 2);
        assign speed[i] = normalized_speed[15:0];
        assign duty[i] = pwm_duty;
        encoder_speed u_encoder (
            .clk(clk_50m_i), .rst_n(key_s0_n_i),
            .encoder_a_i(encoder_a_i[i]), .encoder_b_i(encoder_b_i[i]),
            .sample_tick_i(sample_tick), .position_o(unused_position), .speed_o(raw_speed)
        );
        motor_four_pi_channel #(
            .KICK_CYCLES(KICK_CYCLES), .TARGET_COUNTS(TARGET_COUNTS),
            .LOSS_TICKS(LOSS_TICKS)
        ) u_control (
            .clk(clk_50m_i), .rst_n(key_s0_n_i), .enable_i(channel_enable[i]),
            .sample_tick_i(sample_tick_d), .forward_speed_i(normalized_speed),
            .target_counts_i(TARGET_COUNTS[15:0]),
            .duty_o(pwm_duty), .fault_o(channel_fault[i]),
            .feedback_seen_o(feedback_seen[i])
        );
        motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && button_led[1]),
            .enable_i(channel_enable[i]), .duty_i(pwm_duty),
            .pwm_o(motor_pwm_o[i]), .direction_o()
        );
    end endgenerate

    // LED2 心跳、LED3 就绪、LED4 任一路运行、LED5 超时、LED6 四路均有反馈、LED7 任一路故障。
    assign led_o = {|channel_fault, &feedback_seen, button_led[3], |channel_enable, button_led[1:0]};

    // 串口每 100 ms 轮询一轮，格式如 M2 T020 A+028 D0600 F0\r\n；仅输出诊断，不接收控制。
    reg [3:0] telemetry_tick = 0;
    reg frame_pending = 0;
    reg [1:0] next_wheel = 0;
    reg [1:0] wheel_hold = 0;
    reg [9:0] actual_hold = 0;
    reg actual_negative_hold = 0;
    reg [9:0] duty_hold = 0;
    reg fault_hold = 0;
    reg [4:0] byte_index = 0;
    reg [1:0] send_state = 0;
    reg [7:0] tx_byte = 0;
    reg tx_start = 0;
    wire tx_busy, tx_done;
    wire signed [15:0] selected_speed = speed[next_wheel];
    wire signed [16:0] selected_abs = selected_speed < 0 ? -$signed(selected_speed) : $signed(selected_speed);
    wire [9:0] actual_hundreds = actual_hold / 100;
    wire [9:0] duty_thousands = duty_hold / 1000;
    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .start_i(tx_start),
        .data_i(tx_byte), .tx_o(uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            telemetry_tick <= 0;
            frame_pending <= 0;
            next_wheel <= 0;
            wheel_hold <= 0;
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
                    wheel_hold <= next_wheel;
                    next_wheel <= next_wheel + 1'b1;
                    actual_hold <= selected_abs > 999 ? 10'd999 : selected_abs[9:0];
                    actual_negative_hold <= selected_speed < 0;
                    duty_hold <= channel_enable[next_wheel] ? duty[next_wheel][9:0] : 10'd0;
                    fault_hold <= |channel_fault;
                    byte_index <= 0;
                    send_state <= 1;
                end
                1: if (!tx_busy) begin
                    case (byte_index)
                        0: tx_byte <= "M"; 1: tx_byte <= 8'h31 + {6'd0, wheel_hold};
                        2: tx_byte <= " "; 3: tx_byte <= "T";
                        4: tx_byte <= 8'h30 + (TARGET_COUNTS / 100) % 10;
                        5: tx_byte <= 8'h30 + (TARGET_COUNTS / 10) % 10;
                        6: tx_byte <= 8'h30 + TARGET_COUNTS % 10;
                        7: tx_byte <= " "; 8: tx_byte <= "A";
                        9: tx_byte <= actual_negative_hold ? "-" : "+";
                        10: tx_byte <= 8'h30 + {4'd0, actual_hundreds[3:0]};
                        11: tx_byte <= 8'h30 + (actual_hold / 10) % 10;
                        12: tx_byte <= 8'h30 + actual_hold % 10;
                        13: tx_byte <= " "; 14: tx_byte <= "D";
                        15: tx_byte <= 8'h30 + {4'd0, duty_thousands[3:0]};
                        16: tx_byte <= 8'h30 + (duty_hold / 100) % 10;
                        17: tx_byte <= 8'h30 + (duty_hold / 10) % 10;
                        18: tx_byte <= 8'h30 + duty_hold % 10;
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

// 每轮独立 PI：输入已归一化为机械前进正计数，输出占空比千分数。
module motor_four_pi_channel #(
    parameter integer KICK_CYCLES = 5_000_000,
    parameter integer TARGET_COUNTS = 20,
    parameter integer LOSS_TICKS = 20,
    parameter integer BASE_DUTY = 600,
    parameter integer KP = 4,
    parameter integer KI = 1,
    parameter integer MAX_COUNTS = 50,
    parameter integer DUTY_STEP = 50,
    parameter integer MIN_DUTY = 300,
    parameter integer MAX_DUTY = 850,
    // Append for compatibility with existing positional instantiations.
    // SIN12 opts into a sample-synchronous ramp bounded by MAX_DUTY.
    parameter integer KICK_RAMP_ENABLE = 0,
    parameter integer RUNTIME_PID_ENABLE = 0,
    parameter integer RECOVERABLE_BLOCK_ENABLE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire enable_i,
    input wire sample_tick_i,
    input wire signed [16:0] forward_speed_i,
    input wire signed [15:0] target_counts_i,
    output wire signed [15:0] duty_o,
    output reg fault_o = 0,
    output reg feedback_seen_o = 0,
    // Latched first-trip evidence. R5 may explicitly acknowledge pure E1
    // while stopped; reverse/overspeed evidence still requires reset.
    // Bits: 0=no feedback, 1=reverse feedback, 2=overspeed.
    output reg [2:0] fault_reason_o = 0,
    output reg signed [15:0] fault_speed_o = 0,
    output reg [15:0] fault_duty_o = 0,
    input wire [5:0] kp_i,ki_i,kd_i,
    input wire feedback_start_i,
    input wire clear_block_i
);
    localparam integer LOSS_WIDTH = LOSS_TICKS < 2 ? 1 : $clog2(LOSS_TICKS + 1);
    reg [31:0] kick_count = 0;
    reg signed [15:0] kick_duty = BASE_DUTY;
    reg [LOSS_WIDTH-1:0] loss_count = 0;
    reg [1:0] reverse_count = 0;
    reg signed [7:0] integral = 0;
    reg signed [15:0] duty_permille = BASE_DUTY;
    reg signed [15:0] duty_target = BASE_DUTY;
    reg signed [17:0] error_stage = 0;
    reg error_pending = 0;
    reg duty_pending = 0;
    reg active_previous = 0;
    // Separate saturation and arithmetic stages; every stage finishes long
    // before the next 10ms sample. Do not synthesize a 32-bit clamp/add chain.
    reg sum_pending=0,clamp_pending=0;
    reg signed [26:0] pd_sum=0,raw_output=0;
    reg signed [11:0] bias_stage=BASE_DUTY;
    wire signed [6:0] gain_p=RUNTIME_PID_ENABLE ? $signed({1'b0,kp_i}) : KP;
    wire signed [6:0] gain_i=RUNTIME_PID_ENABLE ? $signed({1'b0,ki_i}) : KI;
    wire signed [6:0] gain_d=RUNTIME_PID_ENABLE ? $signed({1'b0,kd_i}) : 0;
    reg signed [17:0] previous_error=0;
    reg signed [18:0] delta_error=0;
    reg derivative_valid=0,product_pending=0;
    reg signed [24:0] p_product=0,i_product=0;
    reg signed [25:0] d_product=0;
    wire signed [25:0] integral_sum=$signed(integral)+$signed(i_product);
    wire signed [7:0] clipped_integral=integral_sum>26'sd120 ? 8'sd120 :
        integral_sum< -26'sd120 ? -8'sd120 : integral_sum[7:0];
    wire kick_active = kick_count < KICK_CYCLES;
    wire running = enable_i && target_counts_i > 0;
    wire [2:0] trip_reason =
        ((forward_speed_i < 2 && loss_count >= LOSS_TICKS - 1) ? 3'b001 : 3'b000) |
        ((forward_speed_i < -2 && reverse_count >= 2) ? 3'b010 : 3'b000) |
        ((forward_speed_i > MAX_COUNTS) ? 3'b100 : 3'b000);
    assign duty_o = !running || fault_o ? 16'sd0 :
        (kick_active && !(RUNTIME_PID_ENABLE && feedback_start_i)) ? (KICK_RAMP_ENABLE ? kick_duty : 16'sd1000) : duty_permille;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) kick_duty <= BASE_DUTY;
        else if (!running) kick_duty <= BASE_DUTY;
        else if (kick_active && sample_tick_i) begin
            if (kick_duty + DUTY_STEP < MAX_DUTY)
                kick_duty <= kick_duty + DUTY_STEP;
            else kick_duty <= MAX_DUTY;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) kick_count <= 0;
        else if (!running) kick_count <= 0;
        else if (kick_active) kick_count <= kick_count + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            loss_count <= 0; reverse_count <= 0; integral <= 0;
            duty_permille <= BASE_DUTY; duty_target <= BASE_DUTY;
            error_stage <= 0; error_pending <= 0; duty_pending <= 0;
            active_previous <= 0;
            previous_error<=0;delta_error<=0;derivative_valid<=0;product_pending<=0;
            p_product<=0;i_product<=0;d_product<=0;
            sum_pending<=0;clamp_pending<=0;pd_sum<=0;raw_output<=0;bias_stage<=BASE_DUTY;
            fault_o <= 0; feedback_seen_o <= 0;
            fault_reason_o <= 0; fault_speed_o <= 0; fault_duty_o <= 0;
        end else begin
            active_previous <= running;
            if (RECOVERABLE_BLOCK_ENABLE && clear_block_i && !running &&
                fault_o && fault_reason_o == 3'b001) begin
                fault_o <= 0; fault_reason_o <= 0;
                fault_speed_o <= 0; fault_duty_o <= 0;
            end
            if (!running || !active_previous) begin
                loss_count <= 0; reverse_count <= 0; integral <= 0;
                duty_permille <= BASE_DUTY; duty_target <= BASE_DUTY;
                error_pending <= 0; duty_pending <= 0;
                previous_error<=0;delta_error<=0;derivative_valid<=0;product_pending<=0;
                sum_pending<=0;clamp_pending<=0;pd_sum<=0;raw_output<=0;bias_stage<=BASE_DUTY;
            end else begin
                if (error_pending) begin
                    error_pending <= 0;
                    p_product<=gain_p*error_stage;
                    i_product<=gain_i*error_stage;
                    d_product<=gain_d*delta_error;
                    product_pending<=1;
                end
                if (product_pending) begin
                    product_pending<=0;
                    if(!fault_o)begin
                        integral<=clipped_integral;
                        bias_stage<=BASE_DUTY+$signed(clipped_integral);
                        pd_sum<=$signed(p_product)+$signed(d_product);
                        sum_pending<=1;
                    end
                end
                if(sum_pending)begin
                    sum_pending<=0;
                    if(!fault_o)begin
                        raw_output<=$signed(pd_sum)+$signed(bias_stage);
                        clamp_pending<=1;
                    end
                end
                if(clamp_pending)begin
                    clamp_pending<=0;
                    if(!fault_o)begin
                        duty_target<=raw_output>MAX_DUTY ? MAX_DUTY :
                            raw_output<MIN_DUTY ? MIN_DUTY : raw_output[15:0];
                        duty_pending<=1;
                    end
                end
                if (duty_pending) begin
                    duty_pending <= 0;
                    if (!fault_o) begin
                        if (duty_target > duty_permille + DUTY_STEP)
                            duty_permille <= duty_permille + DUTY_STEP;
                        else if (duty_target < duty_permille - DUTY_STEP)
                            duty_permille <= duty_permille - DUTY_STEP;
                        else
                            duty_permille <= duty_target;
                    end
                end
                if (sample_tick_i && !fault_o && (!kick_active || (RUNTIME_PID_ENABLE && feedback_start_i))) begin
                    if (!kick_active && trip_reason != 0) begin
                        fault_o <= 1;
                        fault_reason_o <= trip_reason;
                        fault_speed_o <= forward_speed_i[15:0];
                        fault_duty_o <= duty_o;
                    end
                    if (!kick_active) begin
                    if (forward_speed_i < -2) begin
                        if (reverse_count < 2) reverse_count <= reverse_count + 1'b1;
                    end else reverse_count <= 0;
                    if (forward_speed_i < 2) begin
                        if (loss_count < LOSS_TICKS - 1) loss_count <= loss_count + 1'b1;
                    end else begin
                        loss_count <= 0;
                        feedback_seen_o <= 1;
                    end
                    end
                    delta_error<=derivative_valid ?
                        ($signed({{2{target_counts_i[15]}},target_counts_i})-$signed({forward_speed_i[16],forward_speed_i}))-$signed(previous_error) : 19'sd0;
                    previous_error<=$signed({{2{target_counts_i[15]}},target_counts_i})-$signed({forward_speed_i[16],forward_speed_i});
                    derivative_valid<=1;
                    error_stage <= $signed({{2{target_counts_i[15]}}, target_counts_i})
                                   - $signed({forward_speed_i[16], forward_speed_i});
                    error_pending <= 1;
                end
            end
        end
    end
endmodule
