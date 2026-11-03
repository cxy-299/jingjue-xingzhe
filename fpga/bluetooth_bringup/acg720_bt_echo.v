// 蓝牙隔离联调顶层：仅串口回显和 LED，不接受任何运动指令。
// 即使驱动板控制线仍接着，全部 12 个电机输出也被固定为低。
module acg720_bt_echo #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600,
    parameter integer STARTUP_MS = 10,
    parameter integer STATUS_HOLD_MS = 500
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       bt_uart_rx_i,
    output wire       bt_uart_tx_o,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o
);
    localparam integer STARTUP_CYCLES = (CLK_HZ / 1000) * STARTUP_MS;
    localparam integer HOLD_CYCLES = (CLK_HZ / 1000) * STATUS_HOLD_MS;
    reg [31:0] startup_count = 32'd0;
    reg [25:0] heartbeat_count = 26'd0;
    reg [31:0] rx_hold_count;
    reg [31:0] tx_hold_count;
    reg last_byte_is_a;
    reg error_seen;
    reg [7:0] pending_byte;
    reg pending_valid;
    wire rst_n;
    wire [7:0] rx_data;
    wire rx_valid;
    wire framing_error;
    wire tx_busy;
    wire tx_done;
    wire tx_start;

    always @(posedge clk_50m_i) begin
        if (startup_count < STARTUP_CYCLES)
            startup_count <= startup_count + 1'b1;
        heartbeat_count <= heartbeat_count + 1'b1;
    end
    assign rst_n = (startup_count >= STARTUP_CYCLES) && key_s0_n_i;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk_50m_i), .rst_n(rst_n), .uart_rx_i(bt_uart_rx_i),
        .data_o(rx_data), .data_valid_o(rx_valid),
        .framing_error_o(framing_error)
    );

    // 一个字节的缓冲区用于回显；过快输入造成覆盖时点亮错误灯。
    assign tx_start = pending_valid && !tx_busy;
    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk_50m_i), .rst_n(rst_n), .start_i(tx_start),
        .data_i(pending_byte), .tx_o(bt_uart_tx_o),
        .busy_o(tx_busy), .done_o(tx_done)
    );

    always @(posedge clk_50m_i or negedge rst_n) begin
        if (!rst_n) begin
            pending_byte <= 8'd0;
            pending_valid <= 1'b0;
            rx_hold_count <= 32'd0;
            tx_hold_count <= 32'd0;
            last_byte_is_a <= 1'b0;
            error_seen <= 1'b0;
        end else begin
            if (rx_hold_count != 0) rx_hold_count <= rx_hold_count - 1'b1;
            if (tx_hold_count != 0) tx_hold_count <= tx_hold_count - 1'b1;
            if (tx_start) pending_valid <= 1'b0;
            if (rx_valid) begin
                rx_hold_count <= HOLD_CYCLES;
                last_byte_is_a <= (rx_data == 8'h41);
                if (pending_valid && !tx_start)
                    error_seen <= 1'b1;
                else begin
                    pending_byte <= rx_data;
                    pending_valid <= 1'b1;
                end
            end
            if (tx_done) tx_hold_count <= HOLD_CYCLES;
            if (framing_error) error_seen <= 1'b1;
        end
    end

    assign motor_pwm_o = 4'b0000;
    assign motor_in1_o = 4'b0000;
    assign motor_in2_o = 4'b0000;

    // 实体 LED2..LED7：心跳、就绪、收到字节、回显完成、最近字节为 A、错误锁存。
    assign led_o[0] = heartbeat_count[25];
    assign led_o[1] = rst_n;
    assign led_o[2] = (rx_hold_count != 0);
    assign led_o[3] = (tx_hold_count != 0);
    assign led_o[4] = last_byte_is_a;
    assign led_o[5] = error_seen;
endmodule
