// ACG720-GW5AT60 串口验收顶层：只接板载 LED，不连接任何电机输出。
// 板载 CH340E 的 TXD -> FPGA 串口 RX(J21)；50 MHz 晶振 -> Y18。
module acg720_uart_bringup (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       pi_uart_rx_i,
    output wire [5:0] led_o
);
    reg [23:0] power_on_count = 24'd0;
    reg [25:0] blink_count = 26'd0;
    reg framing_error_seen = 1'b0;
    wire rst_n;
    wire link_alive;
    wire vision_fresh;
    wire target_valid;
    wire target_confirmed;
    wire target_centered_unused;
    wire [15:0] crc_error_count;
    wire uart_framing_error;

    always @(posedge clk_50m_i) begin
        if (!power_on_count[23])
            power_on_count <= power_on_count + 1'b1;
        blink_count <= blink_count + 1'b1;
    end

    // S0 按下为低；上电计数完成且 S0 松开后，才释放接收器复位。
    assign rst_n = power_on_count[23] && key_s0_n_i;

    always @(posedge clk_50m_i or negedge rst_n) begin
        if (!rst_n)
            framing_error_seen <= 1'b0;
        else if (uart_framing_error)
            framing_error_seen <= 1'b1;
    end

    vision_uart_bridge #(
        .CLK_HZ(50_000_000),
        .BAUD(115200),
        .WATCHDOG_MS(1500),
        .VISION_TIMEOUT_MS(1500)
    ) u_bridge (
        .clk(clk_50m_i),
        .rst_n(rst_n),
        .pi_uart_rx_i(pi_uart_rx_i),
        .link_alive_o(link_alive),
        .vision_fresh_o(vision_fresh),
        .target_valid_o(target_valid),
        .target_confirmed_o(target_confirmed),
        .target_centered_o(target_centered_unused),
        .alignment_o(),
        .class_id_o(),
        .confidence_o(),
        .center_x_o(),
        .center_y_o(),
        .width_o(),
        .height_o(),
        .center_error_o(),
        .area_ratio_o(),
        .frame_id_o(),
        .sequence_o(),
        .crc_error_count_o(crc_error_count),
        .uart_framing_error_o(uart_framing_error),
        .vision_packet_pulse_o()
    );

    // 实体 LED2..LED7 依次显示：运行、链路、视觉新鲜、目标、已确认、错误。
    // LED 高电平点亮；LED0/1 对应本器件专用配置引脚，不作为普通 IO 使用。
    assign led_o[0] = blink_count[25];
    assign led_o[1] = link_alive;
    assign led_o[2] = vision_fresh;
    assign led_o[3] = target_valid;
    assign led_o[4] = target_confirmed;
    assign led_o[5] = (crc_error_count != 16'd0) || framing_error_seen;
endmodule
