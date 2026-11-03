// 四轮串口诊断发送器：每 100 ms 输出一轮数据，供电脑独立观察手机遥控下的闭环状态。
module motor_four_diag_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer TARGET_COUNTS = 20,
    parameter integer TELEMETRY_DIV = 10
) (
    input wire clk,
    input wire rst_n,
    input wire sample_tick_i,
    input wire [15:0] target_counts_i,
    input wire signed [15:0] speed0_i,
    input wire signed [15:0] speed1_i,
    input wire signed [15:0] speed2_i,
    input wire signed [15:0] speed3_i,
    input wire signed [15:0] duty0_i,
    input wire signed [15:0] duty1_i,
    input wire signed [15:0] duty2_i,
    input wire signed [15:0] duty3_i,
    input wire fault_i,
    output wire uart_tx_o
);
    reg [7:0] telemetry_tick = 0;
    reg frame_pending = 0;
    reg [1:0] next_wheel = 0;
    reg [1:0] wheel_hold = 0;
    reg [9:0] actual_hold = 0;
    reg negative_hold = 0;
    reg [9:0] duty_hold = 0;
    reg fault_hold = 0;
    reg [9:0] target_hold = TARGET_COUNTS;
    reg [4:0] byte_index = 0;
    reg [1:0] send_state = 0;
    reg [7:0] tx_byte = 0;
    reg tx_start = 0;
    wire tx_busy, tx_done;
    reg signed [15:0] selected_speed;
    reg signed [15:0] selected_duty;
    wire signed [16:0] selected_abs = selected_speed < 0 ? -$signed(selected_speed) : $signed(selected_speed);
    wire [9:0] actual_hundreds = actual_hold / 100;
    wire [9:0] duty_thousands = duty_hold / 1000;

    always @* begin
        case (next_wheel)
            0: begin selected_speed = speed0_i; selected_duty = duty0_i; end
            1: begin selected_speed = speed1_i; selected_duty = duty1_i; end
            2: begin selected_speed = speed2_i; selected_duty = duty2_i; end
            default: begin selected_speed = speed3_i; selected_duty = duty3_i; end
        endcase
    end

    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst_n(rst_n), .start_i(tx_start),
        .data_i(tx_byte), .tx_o(uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            telemetry_tick <= 0; frame_pending <= 0; next_wheel <= 0;
            wheel_hold <= 0; actual_hold <= 0; negative_hold <= 0;
            duty_hold <= 0; fault_hold <= 0; byte_index <= 0;
            target_hold <= TARGET_COUNTS;
            send_state <= 0; tx_byte <= 0; tx_start <= 0;
        end else begin
            tx_start <= 0;
            if (sample_tick_i) begin
                if (telemetry_tick >= TELEMETRY_DIV - 1) begin
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
                    negative_hold <= selected_speed < 0;
                    duty_hold <= selected_duty > 1000 ? 10'd1000 : selected_duty[9:0];
                    fault_hold <= fault_i;
                    target_hold <= target_counts_i > 999 ? 10'd999 : target_counts_i[9:0];
                    byte_index <= 0;
                    send_state <= 1;
                end
                1: if (!tx_busy) begin
                    case (byte_index)
                        0: tx_byte <= "M"; 1: tx_byte <= 8'h31 + {6'd0, wheel_hold};
                        2: tx_byte <= " "; 3: tx_byte <= "T";
                        4: tx_byte <= 8'h30 + (target_hold / 100) % 10;
                        5: tx_byte <= 8'h30 + (target_hold / 10) % 10;
                        6: tx_byte <= 8'h30 + target_hold % 10;
                        7: tx_byte <= " "; 8: tx_byte <= "A";
                        9: tx_byte <= negative_hold ? "-" : "+";
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
