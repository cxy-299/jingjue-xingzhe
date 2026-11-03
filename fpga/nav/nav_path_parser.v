`timescale 1ns/1ps
// v3 路径帧解析器（9600 baud 字节流由上游 uart_rx 提供）。
// AA55 | 03 | 21 | seq(u16 LE) | len(5+n) | map_id(2601 LE) | goal_x | goal_y |
// step_count=n | n 个方向(0=F,1=B,2=L,3=R) | CRC16-CCITT LE。
// 只有整帧 CRC、地图 ID、长度和方向码均合法，才发布 route_valid_o。
module nav_path_parser #(
    parameter integer MAX_STEPS = 64,
    parameter integer BYTE_TIMEOUT_CYCLES = 1_000_000
) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] byte_i,
    input wire byte_valid_i,
    output reg route_valid_o = 1'b0,
    output reg [7:0] goal_x_o = 0,
    output reg [7:0] goal_y_o = 0,
    output reg map_ok_o = 1'b0,
    output reg [7:0] step_count_o = 0,
    output reg [127:0] route_bits_o = 0,
    output reg [15:0] crc_error_count_o = 0,
    output reg [15:0] last_crc_calc_o = 0
);
    localparam [7:0] VERSION=8'h03, MSG_PATH=8'h21;
    localparam [2:0] WAIT_AA=0, WAIT_55=1, BODY=2, PAYLOAD=3, CRC_LO=4, CRC_HI=5;
    reg [2:0] state;
    reg [2:0] body_index;
    reg [15:0] payload_index;
    reg [15:0] payload_length;
    reg [15:0] seq;
    reg [7:0] version, message_type;
    reg [15:0] crc_work;
    reg [7:0] crc_low;
    reg [31:0] idle_count;
    reg [15:0] stage_map_id;
    reg [7:0] stage_goal_x, stage_goal_y, stage_steps;
    reg [127:0] stage_route_bits;
    reg stage_bad_direction;

    function [15:0] crc16_next;
        input [15:0] crc_in;
        input [7:0] data_in;
        integer i;
        reg [15:0] value;
        begin
            value = crc_in ^ {data_in, 8'h00};
            for (i=0; i<8; i=i+1)
                value = value[15] ? ((value << 1) ^ 16'h1021) : (value << 1);
            crc16_next = value;
        end
    endfunction

    task reset_frame;
        begin
            state <= WAIT_AA; body_index <= 0; payload_index <= 0; crc_work <= 16'hFFFF;
            stage_bad_direction <= 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_AA; body_index <= 0; payload_index <= 0;
            payload_length <= 0; seq <= 0; version <= 0; message_type <= 0;
            crc_work <= 16'hFFFF; crc_low <= 0; idle_count <= 0;
            stage_map_id <= 0; stage_goal_x <= 0; stage_goal_y <= 0;
            stage_steps <= 0; stage_route_bits <= 0; stage_bad_direction <= 0;
            route_valid_o <= 0; goal_x_o <= 0; goal_y_o <= 0; map_ok_o <= 0;
            step_count_o <= 0; route_bits_o <= 0; crc_error_count_o <= 0;
            last_crc_calc_o <= 0;
        end else begin
            route_valid_o <= 1'b0;
            if (byte_valid_i) begin
                idle_count <= 0;
                case (state)
                    WAIT_AA: if (byte_i == 8'hAA) state <= WAIT_55;
                    WAIT_55: begin
                        if (byte_i == 8'h55) begin state <= BODY; body_index <= 0; crc_work <= 16'hFFFF; end
                        else if (byte_i != 8'hAA) state <= WAIT_AA;
                    end
                    BODY: begin
                        crc_work <= crc16_next(crc_work, byte_i);
                        case (body_index)
                            0: version <= byte_i;
                            1: message_type <= byte_i;
                            2: seq[7:0] <= byte_i;
                            3: seq[15:8] <= byte_i;
                            4: payload_length[7:0] <= byte_i;
                            5: begin
                                payload_length[15:8] <= byte_i;
                                payload_index <= 0;
                                if ({byte_i,payload_length[7:0]} < 16'd5 ||
                                    {byte_i,payload_length[7:0]} > (MAX_STEPS+5)) reset_frame();
                                else state <= PAYLOAD;
                            end
                        endcase
                        if (body_index != 5) body_index <= body_index + 1'b1;
                    end
                    PAYLOAD: begin
                        crc_work <= crc16_next(crc_work, byte_i);
                        case (payload_index)
                            0: stage_map_id[7:0] <= byte_i;
                            1: stage_map_id[15:8] <= byte_i;
                            2: stage_goal_x <= byte_i;
                            3: stage_goal_y <= byte_i;
                            4: begin
                                stage_steps <= byte_i;
                                if (byte_i > MAX_STEPS || byte_i != payload_length - 5)
                                    stage_bad_direction <= 1'b1;
                            end
                            default: begin
                                if (payload_index < (MAX_STEPS+5)) begin
                                    stage_route_bits[(payload_index-5)*2 +: 2] <= byte_i[1:0];
                                    if (byte_i > 3) stage_bad_direction <= 1'b1;
                                end
                            end
                        endcase
                        if (payload_index + 1'b1 >= payload_length) state <= CRC_LO;
                        else payload_index <= payload_index + 1'b1;
                    end
                    CRC_LO: begin crc_low <= byte_i; state <= CRC_HI; end
                    CRC_HI: begin
                        last_crc_calc_o <= crc_work;
                        if ({byte_i,crc_low} == crc_work) begin
                            if (version == VERSION && message_type == MSG_PATH &&
                                stage_map_id == 16'h2601 && stage_goal_x < 20 && stage_goal_y < 20 &&
                                !stage_bad_direction) begin
                                route_valid_o <= 1'b1;
                                goal_x_o <= stage_goal_x; goal_y_o <= stage_goal_y;
                                map_ok_o <= 1'b1; step_count_o <= stage_steps;
                                route_bits_o <= stage_route_bits;
                            end
                        end else crc_error_count_o <= crc_error_count_o + 1'b1;
                        reset_frame();
                    end
                    default: reset_frame();
                endcase
            end else if (state != WAIT_AA) begin
                if (idle_count >= BYTE_TIMEOUT_CYCLES-1) begin idle_count <= 0; reset_frame(); end
                else idle_count <= idle_count + 1'b1;
            end
        end
    end
endmodule
