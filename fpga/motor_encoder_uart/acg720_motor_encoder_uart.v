// M1 编码器十进制串口遥测：电机仍由 700 ms 硬超时限制，串口只在停机后发送一次。
// 发送格式为 M1:-026\r\n；单位是四倍频计数/10 ms，溢出时符号位改成 !。
module acg720_motor_encoder_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200,
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
    output wire       uart_tx_o
);
    wire [3:0] hundreds;
    wire [3:0] tens;
    wire [3:0] ones;
    wire negative;
    wire overflow;
    wire meter_done;
    wire tx_busy;
    wire tx_done;
    reg tx_start = 1'b0;
    reg [7:0] tx_byte = 8'h00;
    reg last_meter_done = 1'b0;
    reg [3:0] byte_index = 4'd0;
    localparam [1:0] SEND_IDLE = 2'd0, SEND_START = 2'd1,
                     SEND_WAIT = 2'd2, SEND_ADVANCE = 2'd3;
    reg [1:0] send_state = SEND_IDLE;

    // 数码管的三个输出不接到顶层引脚；综合时会移除未使用的数码管扫描器。
    // 电机方向、占空比、超时与已验证版本完全相同。
    acg720_motor_encoder_decimal #(
        .CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ), .STARTUP_MS(STARTUP_MS),
        .DEBOUNCE_MS(DEBOUNCE_MS), .KICK_MS(KICK_MS),
        .RUN_MAX_MS(RUN_MAX_MS), .SAMPLE_START_MS(SAMPLE_START_MS)
    ) u_meter (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i),
        .key_s1_n_i(key_s1_n_i), .m1_encoder_a_i(m1_encoder_a_i),
        .m1_encoder_b_i(m1_encoder_b_i), .motor_pwm_o(motor_pwm_o),
        .motor_in1_o(motor_in1_o), .motor_in2_o(motor_in2_o),
        .led_o(led_o), .seg_ds_o(), .seg_sh_cp_o(), .seg_st_cp_o(),
        .decimal_hundreds_o(hundreds), .decimal_tens_o(tens),
        .decimal_ones_o(ones), .decimal_negative_o(negative),
        .decimal_overflow_o(overflow), .decimal_done_o(meter_done)
    );

    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart_tx (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .start_i(tx_start),
        .data_i(tx_byte), .tx_o(uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );

    // 仅在一次测量完成的上升沿装帧，不连续重复发送。
    // 若 S0 复位，正在发送的字节立即中止，UART 回到空闲高电平。
    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            last_meter_done <= 1'b0;
            tx_start <= 1'b0;
            tx_byte <= 8'h00;
            byte_index <= 4'd0;
            send_state <= SEND_IDLE;
        end else begin
            last_meter_done <= meter_done;
            tx_start <= 1'b0;
            case (send_state)
                SEND_IDLE: begin
                    if (meter_done && !last_meter_done) begin
                        byte_index <= 4'd0;
                        send_state <= SEND_START;
                    end
                end
                SEND_START: begin
                    if (!tx_busy) begin
                        case (byte_index)
                            4'd0: tx_byte <= "M";
                            4'd1: tx_byte <= "1";
                            4'd2: tx_byte <= ":";
                            4'd3: tx_byte <= overflow ? "!" : (negative ? "-" : "+");
                            4'd4: tx_byte <= 8'h30 + {4'd0, hundreds};
                            4'd5: tx_byte <= 8'h30 + {4'd0, tens};
                            4'd6: tx_byte <= 8'h30 + {4'd0, ones};
                            4'd7: tx_byte <= 8'h0d;
                            default: tx_byte <= 8'h0a;
                        endcase
                        // 数据在本拍末更新，下一拍再启动发送器。
                        send_state <= SEND_WAIT;
                    end
                end
                SEND_WAIT: begin
                    tx_start <= 1'b1;
                    send_state <= SEND_ADVANCE;
                end
                SEND_ADVANCE: begin
                    if (tx_done) begin
                        if (byte_index == 4'd8)
                            send_state <= SEND_IDLE;
                        else begin
                            byte_index <= byte_index + 1'b1;
                            send_state <= SEND_START;
                        end
                    end
                end
                default: send_state <= SEND_IDLE;
            endcase
        end
    end
endmodule
