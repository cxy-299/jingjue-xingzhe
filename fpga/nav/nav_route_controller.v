`timescale 1ns/1ps
// 固定 20x20 地图的路点执行器。
//
// 规划器给出相邻路点，本模块把相邻格转换为 F/B/L/R，并用四路编码器的
// 平均绝对增量判断是否走完 10 cm 单元格。每个路点完成只产生一个
// advance_o 脉冲，不能把它当作电平确认。这样导航控制仍由 FPGA 闭环完成，
// PC/Pi 只负责发送终点帧，不发送 PWM 或电机速度。
module nav_route_controller #(
    parameter integer CELL_COUNTS = 1000,
    parameter integer SAMPLE_HZ = 100
) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_tick_i,
    input  wire new_goal_i,
    input  wire [7:0] goal_x_i,
    input  wire [7:0] goal_y_i,
    input  wire route_ready_i,
    input  wire no_path_i,
    input  wire waypoint_valid_i,
    input  wire [7:0] waypoint_x_i,
    input  wire [7:0] waypoint_y_i,
    input  wire [31:0] position0_i,
    input  wire [31:0] position1_i,
    input  wire [31:0] position2_i,
    input  wire [31:0] position3_i,
    output reg advance_o = 1'b0,
    output reg active_o = 1'b0,
    output reg done_o = 1'b0,
    output reg fault_o = 1'b0,
    output reg [2:0] command_o = 3'd0
);
    localparam [2:0] STOP=3'd0, FORWARD=3'd1, BACKWARD=3'd2,
                     LEFT=3'd3, RIGHT=3'd4;

    reg [7:0] goal_x, goal_y;
    reg [7:0] current_x, current_y;
    reg started;
    reg [31:0] base0, base1, base2, base3;
    reg [31:0] cell_counts;

    function [31:0] abs_diff;
        input [31:0] a;
        input [31:0] b;
        reg signed [32:0] d;
        begin
            d = $signed({1'b0, a}) - $signed({1'b0, b});
            abs_diff = d < 0 ? -d : d;
        end
    endfunction

    wire [31:0] d0 = abs_diff(position0_i, base0);
    wire [31:0] d1 = abs_diff(position1_i, base1);
    wire [31:0] d2 = abs_diff(position2_i, base2);
    wire [31:0] d3 = abs_diff(position3_i, base3);
    wire [33:0] delta_sum = d0 + d1 + d2 + d3;
    wire [31:0] average_delta = delta_sum[33:2];

    // 当前位置到下一路点只允许相邻格；若规划器输出异常，安全停机。
    always @* begin
        command_o = STOP;
        if (active_o && waypoint_valid_i) begin
            if (waypoint_x_i == current_x && waypoint_y_i == current_y + 1'b1)
                command_o = FORWARD;
            else if (waypoint_x_i == current_x && waypoint_y_i + 1'b1 == current_y)
                command_o = BACKWARD;
            else if (waypoint_x_i == current_x + 1'b1 && waypoint_y_i == current_y)
                command_o = RIGHT;
            else if (waypoint_x_i + 1'b1 == current_x && waypoint_y_i == current_y)
                command_o = LEFT;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            advance_o <= 1'b0;
            active_o <= 1'b0;
            done_o <= 1'b0;
            fault_o <= 1'b0;
            goal_x <= 0; goal_y <= 0;
            current_x <= 8'd18; current_y <= 8'd1;
            started <= 1'b0;
            base0 <= 0; base1 <= 0; base2 <= 0; base3 <= 0;
            cell_counts <= 0;
        end else begin
            advance_o <= 1'b0;
            done_o <= 1'b0;
            if (new_goal_i) begin
                goal_x <= goal_x_i;
                goal_y <= goal_y_i;
                current_x <= 8'd18;
                current_y <= 8'd1;
                started <= 1'b0;
                active_o <= 1'b0;
                fault_o <= 1'b0;
                cell_counts <= 0;
            end else if (no_path_i) begin
                active_o <= 1'b0;
                started <= 1'b0;
                fault_o <= 1'b1;
            end else if (route_ready_i && waypoint_valid_i && !started) begin
                // BFS 完成后锁存本段起始编码器位置。
                started <= 1'b1;
                active_o <= 1'b1;
                cell_counts <= 0;
                base0 <= position0_i; base1 <= position1_i;
                base2 <= position2_i; base3 <= position3_i;
            end else if (active_o && sample_tick_i) begin
                if (average_delta >= CELL_COUNTS) begin
                    current_x <= waypoint_x_i;
                    current_y <= waypoint_y_i;
                    advance_o <= 1'b1;
                    cell_counts <= 0;
                    base0 <= position0_i; base1 <= position1_i;
                    base2 <= position2_i; base3 <= position3_i;
                    if (waypoint_x_i == goal_x && waypoint_y_i == goal_y) begin
                        active_o <= 1'b0;
                        done_o <= 1'b1;
                    end
                end else if (cell_counts < 32'hFFFF_FFFF) begin
                    cell_counts <= cell_counts + 1'b1;
                end
            end
        end
    end
endmodule
