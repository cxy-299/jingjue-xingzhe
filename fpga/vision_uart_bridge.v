// 串口桥分三步：接收字节 -> 校验协议帧 -> 计算安全超时。
// 本模块不直接输出电机指令；下游必须依据 target_valid_o 决定是否使用目标。
module vision_uart_bridge #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115200,
    parameter integer WATCHDOG_MS = 1500,
    parameter integer VISION_TIMEOUT_MS = 1500
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pi_uart_rx_i,

    output wire        link_alive_o,
    output wire        vision_fresh_o,
    output wire        target_valid_o,
    output wire        target_confirmed_o,
    output wire        target_centered_o,
    output wire [7:0]  alignment_o,
    output wire [15:0] class_id_o,
    output wire [15:0] confidence_o,
    output wire [15:0] center_x_o,
    output wire [15:0] center_y_o,
    output wire [15:0] width_o,
    output wire [15:0] height_o,
    output wire signed [15:0] center_error_o,
    output wire [15:0] area_ratio_o,
    output wire [31:0] frame_id_o,
    output wire [15:0] sequence_o,
    output wire [15:0] crc_error_count_o,
    output wire        uart_framing_error_o,
    output wire        vision_packet_pulse_o,
    output wire        nav_goal_pulse_o,
    output wire [7:0]  nav_goal_x_o,
    output wire [7:0]  nav_goal_y_o
);
    localparam integer WATCHDOG_CYCLES = (CLK_HZ / 1000) * WATCHDOG_MS;
    localparam integer VISION_TIMEOUT_CYCLES = (CLK_HZ / 1000) * VISION_TIMEOUT_MS;

    wire [7:0] rx_byte;
    wire rx_byte_valid;
    wire vision_valid;
    wire heartbeat_valid;
    wire target_present;
    wire target_confirmed;
    reg [31:0] watchdog_count;
    reg [31:0] vision_age_count;
    reg link_alive;
    reg vision_fresh;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_i(pi_uart_rx_i),
        .data_o(rx_byte),
        .data_valid_o(rx_byte_valid),
        .framing_error_o(uart_framing_error_o)
    );

    vision_packet_parser #(.BYTE_TIMEOUT_CYCLES((CLK_HZ / 1000) * 20)) u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .byte_i(rx_byte),
        .byte_valid_i(rx_byte_valid),
        .vision_valid_o(vision_valid),
        .heartbeat_valid_o(heartbeat_valid),
        .nav_goal_valid_o(nav_goal_pulse_o),
        .nav_goal_x_o(nav_goal_x_o),
        .nav_goal_y_o(nav_goal_y_o),
        .target_present_o(target_present),
        .target_confirmed_o(target_confirmed),
        .target_centered_o(target_centered_o),
        .alignment_o(alignment_o),
        .class_id_o(class_id_o),
        .confidence_o(confidence_o),
        .center_x_o(center_x_o),
        .center_y_o(center_y_o),
        .width_o(width_o),
        .height_o(height_o),
        .center_error_o(center_error_o),
        .area_ratio_o(area_ratio_o),
        .frame_id_o(frame_id_o),
        .sequence_o(sequence_o),
        .crc_error_count_o(crc_error_count_o)
    );

    // 心跳、视觉或导航终点任一合法帧，都可证明最近串口链路可用。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_count <= 32'd0;
            link_alive <= 1'b0;
        end else if (vision_valid || heartbeat_valid || nav_goal_pulse_o) begin
            watchdog_count <= 32'd0;
            link_alive <= 1'b1;
        end else if (watchdog_count >= WATCHDOG_CYCLES - 1) begin
            watchdog_count <= watchdog_count;
            link_alive <= 1'b0;
        end else begin
            watchdog_count <= watchdog_count + 1'b1;
        end
    end

    // 视觉结果单独计时：仅收到心跳不能延长旧目标的有效期。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vision_age_count <= 32'd0;
            vision_fresh <= 1'b0;
        end else if (vision_valid) begin
            vision_age_count <= 32'd0;
            vision_fresh <= 1'b1;
        end else if (vision_age_count >= VISION_TIMEOUT_CYCLES - 1) begin
            vision_age_count <= vision_age_count;
            vision_fresh <= 1'b0;
        end else begin
            vision_age_count <= vision_age_count + 1'b1;
        end
    end

    assign link_alive_o = link_alive;
    assign vision_fresh_o = vision_fresh;
    // 链路和视觉结果都新鲜，且当前帧明确“有目标”，才允许下游使用。
    assign target_valid_o = link_alive && vision_fresh && target_present;
    assign target_confirmed_o = link_alive && vision_fresh && target_confirmed;
    assign vision_packet_pulse_o = vision_valid;
endmodule

