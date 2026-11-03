`timescale 1ns/1ps
// 导航接收/规划验收顶层：仍然只有 LED 输出，没有任何电机引脚。
// 收到 Pi 发来的 0x20 终点帧后，校验通过才启动片上固定地图 BFS。
// 注意：此阶段只验证通信和规划，不能据此认为车辆已经具备自主行驶能力。
module acg720_nav_preview #(
    parameter integer POR_BIT = 23 // 仅 testbench 缩短上电等待，实机保持 23
) (
    input  wire       clk_50m_i,
    input  wire       key_s0_n_i,
    input  wire       pi_uart_rx_i,
    output wire [5:0] led_o
);
    reg [23:0] power_on_count = 24'd0;
    reg [25:0] blink_count = 26'd0;
    reg goal_seen = 1'b0;
    reg framing_error_seen = 1'b0;
    wire rst_n = power_on_count[POR_BIT] && key_s0_n_i;
    wire link_alive;
    wire [15:0] crc_error_count;
    wire framing_error;
    wire goal_pulse;
    wire [7:0] goal_x, goal_y;
    wire planner_busy, route_ready, no_path, waypoint_valid;

    always @(posedge clk_50m_i) begin
        if (!power_on_count[POR_BIT]) power_on_count <= power_on_count + 1'b1;
        blink_count <= blink_count + 1'b1;
    end

    always @(posedge clk_50m_i or negedge rst_n) begin
        if (!rst_n) begin
            goal_seen <= 1'b0;
            framing_error_seen <= 1'b0;
        end else begin
            if (goal_pulse) goal_seen <= 1'b1;
            if (framing_error) framing_error_seen <= 1'b1;
        end
    end

    vision_uart_bridge #(
        .CLK_HZ(50_000_000), .BAUD(115200),
        .WATCHDOG_MS(1500), .VISION_TIMEOUT_MS(1500)
    ) u_bridge (
        .clk(clk_50m_i), .rst_n(rst_n), .pi_uart_rx_i(pi_uart_rx_i),
        .link_alive_o(link_alive), .vision_fresh_o(), .target_valid_o(),
        .target_confirmed_o(), .target_centered_o(), .alignment_o(),
        .class_id_o(), .confidence_o(), .center_x_o(), .center_y_o(),
        .width_o(), .height_o(), .center_error_o(), .area_ratio_o(),
        .frame_id_o(), .sequence_o(), .crc_error_count_o(crc_error_count),
        .uart_framing_error_o(framing_error), .vision_packet_pulse_o(),
        .nav_goal_pulse_o(goal_pulse), .nav_goal_x_o(goal_x),
        .nav_goal_y_o(goal_y)
    );

    fixed_grid_bfs #(.MAP_FILE("nav_map_20x20.mem")) u_planner (
        .clk(clk_50m_i), .rst_n(rst_n), .goal_valid_i(goal_pulse),
        .goal_x_i(goal_x), .goal_y_i(goal_y), .advance_i(1'b0),
        .busy_o(planner_busy), .route_ready_o(route_ready),
        .no_path_o(no_path), .waypoint_valid_o(waypoint_valid),
        .waypoint_x_o(), .waypoint_y_o(), .path_steps_o(),
        .accepted_goal_x_o(), .accepted_goal_y_o()
    );

    // 实体 LED2..LED7：运行、链路、收到合法终点、搜索中、找到路线、错误/不可达。
    // NAV3 板载版本标记：LED2 约每 0.17 秒翻转一次，明显快于旧版。
    assign led_o[0] = blink_count[23];
    assign led_o[1] = link_alive;
    assign led_o[2] = goal_seen;
    assign led_o[3] = planner_busy;
    assign led_o[4] = route_ready && waypoint_valid;
    assign led_o[5] = no_path || (crc_error_count != 16'd0) || framing_error_seen;
endmodule
