// 灵枢协议 v3 解析器：AA 55 | 版本/类型/序号/长度/载荷 | CRC16。
// 先把载荷存入 stage_* 暂存寄存器；只有整帧 CRC 和格式正确才发布结果。
// 因此半帧或坏帧不会改动上一帧的公开识别字段。
module vision_packet_parser #(
    parameter integer ENABLE_VISUAL_PRIMARY = 0,
    parameter integer MAX_PAYLOAD = 64,
    // 默认对应 50 MHz 下 20 ms；桥接层按实际时钟覆盖，截断帧超时后允许重新同步。
    parameter integer BYTE_TIMEOUT_CYCLES = 1_000_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  byte_i,
    input  wire        byte_valid_i,

    output reg         vision_valid_o,
    output reg geometry_valid_o,geometry_beam_o,
    output reg signed [15:0] geometry_yaw_o,
    output reg [15:0] geometry_range_o,geometry_uncertainty_o,geometry_age_o,
    output reg [31:0] mission_id_o,
    output reg mission_red_o,
    output reg         heartbeat_valid_o,
    output reg         selection_valid_o,
    output reg         follow_requested_o,
    output reg [31:0]  lock_id_o,
    output reg         nav_goal_valid_o,
    output reg  [7:0]  nav_goal_x_o,
    output reg  [7:0]  nav_goal_y_o,
    output reg         target_present_o,
    output reg         target_confirmed_o,
    output reg         target_centered_o,
    output reg  [7:0]  alignment_o,
    output reg  [15:0] class_id_o,
    output reg  [15:0] confidence_o,
    output reg  [15:0] center_x_o,
    output reg  [15:0] center_y_o,
    output reg  [15:0] width_o,
    output reg  [15:0] height_o,
    output reg signed [15:0] center_error_o,
    output reg  [15:0] area_ratio_o,
    output reg  [31:0] frame_id_o,
    output reg  [15:0] sequence_o,
    output reg  [15:0] crc_error_count_o
);
    localparam [7:0] PROTOCOL_VERSION = 8'd3;
    localparam [7:0] MSG_HEARTBEAT = 8'h01;
    localparam [7:0] MSG_VISION_RESULT = 8'h13;
    localparam [7:0] MSG_NAV_GOAL = 8'h20;
    localparam [15:0] VISION_PAYLOAD_LENGTH = 16'd26;
    localparam [15:0] NAV_GOAL_PAYLOAD_LENGTH = 16'd4;
    localparam [15:0] NAV_MAP_ID = 16'h2601;

    localparam [2:0] S_WAIT_AA = 3'd0;
    localparam [2:0] S_WAIT_55 = 3'd1;
    localparam [2:0] S_BODY = 3'd2;
    localparam [2:0] S_PAYLOAD = 3'd3;
    localparam [2:0] S_CRC_LO = 3'd4;
    localparam [2:0] S_CRC_HI = 3'd5;

    reg [2:0] state;
    reg [2:0] body_index;
    reg [15:0] payload_index;
    reg [7:0] version;
    reg [7:0] message_type;
    reg [15:0] sequence;
    reg [15:0] payload_length;
    reg [15:0] crc_work;
    reg [7:0] crc_low;
    reg [31:0] byte_idle_count;

    reg [31:0] stage_mission_id;reg [7:0] stage_color;
    reg [7:0] stage_geometry_flags;
    reg [15:0] stage_geometry_yaw,stage_geometry_range,stage_geometry_uncertainty,stage_geometry_age;
    reg [31:0] stage_lock_id;
    reg [7:0] stage_flags;
    reg [7:0] stage_alignment;
    reg [15:0] stage_class_id;
    reg [15:0] stage_confidence;
    reg [15:0] stage_center_x;
    reg [15:0] stage_center_y;
    reg [15:0] stage_width;
    reg [15:0] stage_height;
    reg [15:0] stage_center_error;
    reg [15:0] stage_area_ratio;
    reg [31:0] stage_frame_id;
    reg [15:0] stage_map_id;
    reg [7:0] stage_goal_x;
    reg [7:0] stage_goal_y;

    // CRC16-CCITT 从版本字节算到载荷末尾，不包括 AA 55 和末尾 CRC 两字节。
    function [15:0] crc16_next;
        input [15:0] crc_in;
        input [7:0] data_in;
        integer i;
        reg [15:0] value;
        begin
            value = crc_in ^ {data_in, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (value[15])
                    value = (value << 1) ^ 16'h1021;
                else
                    value = value << 1;
            end
            crc16_next = value;
        end
    endfunction

    task reset_frame_state;
        begin
            state <= S_WAIT_AA;
            body_index <= 3'd0;
            payload_index <= 16'd0;
            crc_work <= 16'hFFFF;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT_AA;
            body_index <= 3'd0;
            payload_index <= 16'd0;
            version <= 8'd0;
            message_type <= 8'd0;
            sequence <= 16'd0;
            payload_length <= 16'd0;
            crc_work <= 16'hFFFF;
            crc_low <= 8'd0;
            byte_idle_count <= 32'd0;
            stage_lock_id <= 0;stage_mission_id<=0;stage_color<=0;mission_id_o<=0;mission_red_o<=0;
            geometry_valid_o<=0;geometry_beam_o<=0;geometry_yaw_o<=0;
            geometry_range_o<=0;geometry_uncertainty_o<=0;geometry_age_o<=16'hffff;
            stage_geometry_flags<=0;stage_geometry_yaw<=0;stage_geometry_range<=0;
            stage_geometry_uncertainty<=0;stage_geometry_age<=16'hffff;
            selection_valid_o <= 0; follow_requested_o <= 0; lock_id_o <= 0;
            stage_flags <= 8'd0;
            stage_alignment <= 8'd0;
            stage_class_id <= 16'hFFFF;
            stage_confidence <= 16'd0;
            stage_center_x <= 16'd0;
            stage_center_y <= 16'd0;
            stage_width <= 16'd0;
            stage_height <= 16'd0;
            stage_center_error <= 16'd0;
            stage_area_ratio <= 16'd0;
            stage_frame_id <= 32'd0;
            stage_map_id <= 16'd0;
            stage_goal_x <= 8'd0;
            stage_goal_y <= 8'd0;
            vision_valid_o <= 1'b0;
            heartbeat_valid_o <= 1'b0;
            nav_goal_valid_o <= 1'b0;
            nav_goal_x_o <= 8'd0;
            nav_goal_y_o <= 8'd0;
            target_present_o <= 1'b0;
            target_confirmed_o <= 1'b0;
            target_centered_o <= 1'b0;
            alignment_o <= 8'd0;
            class_id_o <= 16'hFFFF;
            confidence_o <= 16'd0;
            center_x_o <= 16'd0;
            center_y_o <= 16'd0;
            width_o <= 16'd0;
            height_o <= 16'd0;
            center_error_o <= 16'sd0;
            area_ratio_o <= 16'd0;
            frame_id_o <= 32'd0;
            sequence_o <= 16'd0;
            crc_error_count_o <= 16'd0;
        end else begin
            vision_valid_o <= 1'b0;
            heartbeat_valid_o <= 1'b0;
            nav_goal_valid_o <= 1'b0;

            if (byte_valid_i) begin
                byte_idle_count <= 32'd0;
                case (state)
                    S_WAIT_AA: begin
                        if (byte_i == 8'hAA)
                            state <= S_WAIT_55;
                    end

                    S_WAIT_55: begin
                        if (byte_i == 8'h55) begin
                            state <= S_BODY;
                            body_index <= 3'd0;
                            crc_work <= 16'hFFFF;
                        end else if (byte_i != 8'hAA) begin
                            state <= S_WAIT_AA;
                        end
                    end

                    S_BODY: begin
                        crc_work <= crc16_next(crc_work, byte_i);
                        case (body_index)
                            3'd0: version <= byte_i;
                            3'd1: message_type <= byte_i;
                            3'd2: sequence[7:0] <= byte_i;
                            3'd3: sequence[15:8] <= byte_i;
                            3'd4: payload_length[7:0] <= byte_i;
                            3'd5: begin
                                payload_length[15:8] <= byte_i;
                                payload_index <= 16'd0;
                                if ({byte_i, payload_length[7:0]} == 16'd0)
                                    state <= S_CRC_LO;
                                else if ({byte_i, payload_length[7:0]} > MAX_PAYLOAD)
                                    reset_frame_state();
                                else
                                    state <= S_PAYLOAD;
                            end
                        endcase
                        if (body_index != 3'd5)
                            body_index <= body_index + 1'b1;
                    end

                    // 逐字节接收载荷，只写暂存区；此时下游还看不到未验证的数据。
                    S_PAYLOAD: begin
                        crc_work <= crc16_next(crc_work, byte_i);
                        if (message_type == MSG_VISION_RESULT || message_type == 8'h14 || message_type == 8'h15 || (ENABLE_VISUAL_PRIMARY && message_type==8'h16)) begin
                            case (payload_index)
                                16'd4:  stage_frame_id[7:0] <= byte_i;
                                16'd5:  stage_frame_id[15:8] <= byte_i;
                                16'd6:  stage_frame_id[23:16] <= byte_i;
                                16'd7:  stage_frame_id[31:24] <= byte_i;
                                16'd8:  stage_flags <= byte_i;
                                16'd9:  stage_alignment <= byte_i;
                                16'd10: stage_class_id[7:0] <= byte_i;
                                16'd11: stage_class_id[15:8] <= byte_i;
                                16'd12: stage_confidence[7:0] <= byte_i;
                                16'd13: stage_confidence[15:8] <= byte_i;
                                16'd14: stage_center_x[7:0] <= byte_i;
                                16'd15: stage_center_x[15:8] <= byte_i;
                                16'd16: stage_center_y[7:0] <= byte_i;
                                16'd17: stage_center_y[15:8] <= byte_i;
                                16'd18: stage_width[7:0] <= byte_i;
                                16'd19: stage_width[15:8] <= byte_i;
                                16'd20: stage_height[7:0] <= byte_i;
                                16'd21: stage_height[15:8] <= byte_i;
                                16'd22: stage_center_error[7:0] <= byte_i;
                                16'd23: stage_center_error[15:8] <= byte_i;
                                16'd24: stage_area_ratio[7:0] <= byte_i;
                                16'd25: stage_area_ratio[15:8] <= byte_i;
                                16'd26: stage_lock_id[7:0] <= byte_i;
                                16'd27: stage_lock_id[15:8] <= byte_i;
                                16'd28: stage_lock_id[23:16] <= byte_i;
                                16'd29: stage_lock_id[31:24] <= byte_i;
                                16'd30:stage_mission_id[7:0]<=byte_i;
                                16'd31:stage_mission_id[15:8]<=byte_i;
                                16'd32:stage_mission_id[23:16]<=byte_i;
                                16'd33:stage_mission_id[31:24]<=byte_i;
                                16'd34:stage_color<=byte_i;
                                16'd35:stage_geometry_flags<=byte_i;
                                16'd36:stage_geometry_yaw[7:0]<=byte_i;
                                16'd37:stage_geometry_yaw[15:8]<=byte_i;
                                16'd38:stage_geometry_range[7:0]<=byte_i;
                                16'd39:stage_geometry_range[15:8]<=byte_i;
                                16'd40:stage_geometry_uncertainty[7:0]<=byte_i;
                                16'd41:stage_geometry_uncertainty[15:8]<=byte_i;
                                16'd42:stage_geometry_age[7:0]<=byte_i;
                                16'd43:stage_geometry_age[15:8]<=byte_i;
                            endcase
                        end else if (message_type == MSG_NAV_GOAL) begin
                            // 地图版本和终点格先暂存；CRC 通过之前绝不触发规划。
                            case (payload_index)
                                16'd0: stage_map_id[7:0] <= byte_i;
                                16'd1: stage_map_id[15:8] <= byte_i;
                                16'd2: stage_goal_x <= byte_i;
                                16'd3: stage_goal_y <= byte_i;
                            endcase
                        end

                        if (payload_index + 1'b1 >= payload_length)
                            state <= S_CRC_LO;
                        else
                            payload_index <= payload_index + 1'b1;
                    end

                    S_CRC_LO: begin
                        crc_low <= byte_i;
                        state <= S_CRC_HI;
                    end

                    // 收到 CRC 高字节后，统一检查 CRC、版本、消息类型和长度；
                    // 只有全部正确才更新输出并给出一拍的有效脉冲。
                    S_CRC_HI: begin
                        if ({byte_i, crc_low} == crc_work) begin
                            if (
                                version == PROTOCOL_VERSION &&
                                ((message_type == MSG_VISION_RESULT && payload_length == VISION_PAYLOAD_LENGTH) ||
                                 (message_type == 8'h14 && payload_length == 30) ||
                                 (message_type == 8'h15 && payload_length == 35 && stage_color<=1 && stage_mission_id!=0) ||
                                 (ENABLE_VISUAL_PRIMARY && message_type==8'h16 && payload_length==44 &&
                                  stage_color<=1 && stage_mission_id!=0 && stage_geometry_flags<=3))
                            ) begin
                                vision_valid_o <= 1'b1;
                                selection_valid_o <= (message_type == 8'h14 || message_type == 8'h15 || (ENABLE_VISUAL_PRIMARY && message_type==8'h16)) && stage_flags[3];
                                follow_requested_o <= message_type == 8'h14 && stage_flags[4];
                                lock_id_o <= (message_type == 8'h14 || message_type == 8'h15 || (ENABLE_VISUAL_PRIMARY && message_type==8'h16)) ? stage_lock_id : 0;
                                mission_id_o<=(message_type==8'h15 || (ENABLE_VISUAL_PRIMARY && message_type==8'h16)) ? stage_mission_id : 0;
                                mission_red_o<=(message_type==8'h15 || (ENABLE_VISUAL_PRIMARY && message_type==8'h16)) && stage_color==1;
                                geometry_valid_o<=ENABLE_VISUAL_PRIMARY && message_type==8'h16 && stage_geometry_flags[0];
                                geometry_beam_o<=ENABLE_VISUAL_PRIMARY && message_type==8'h16 && stage_geometry_flags[1];
                                geometry_yaw_o<=stage_geometry_yaw;geometry_range_o<=stage_geometry_range;
                                geometry_uncertainty_o<=stage_geometry_uncertainty;geometry_age_o<=stage_geometry_age;
                                target_present_o <= stage_flags[0];
                                target_confirmed_o <= stage_flags[1];
                                target_centered_o <= stage_flags[2];
                                alignment_o <= stage_alignment;
                                class_id_o <= stage_class_id;
                                confidence_o <= stage_confidence;
                                center_x_o <= stage_center_x;
                                center_y_o <= stage_center_y;
                                width_o <= stage_width;
                                height_o <= stage_height;
                                center_error_o <= stage_center_error;
                                area_ratio_o <= stage_area_ratio;
                                frame_id_o <= stage_frame_id;
                                sequence_o <= sequence;
                            end else if (
                                version == PROTOCOL_VERSION &&
                                message_type == MSG_HEARTBEAT &&
                                payload_length == 16'd4
                            ) begin
                                heartbeat_valid_o <= 1'b1;
                            end else if (
                                version == PROTOCOL_VERSION &&
                                message_type == MSG_NAV_GOAL &&
                                payload_length == NAV_GOAL_PAYLOAD_LENGTH &&
                                stage_map_id == NAV_MAP_ID &&
                                stage_goal_x < 8'd20 && stage_goal_y < 8'd20
                            ) begin
                                nav_goal_valid_o <= 1'b1;
                                nav_goal_x_o <= stage_goal_x;
                                nav_goal_y_o <= stage_goal_y;
                            end
                        end else begin
                            crc_error_count_o <= crc_error_count_o + 1'b1;
                        end
                        reset_frame_state();
                    end

                    default: reset_frame_state();
                endcase
            end else if (state == S_WAIT_AA) begin
                byte_idle_count <= 32'd0;
            end else if (byte_idle_count >= BYTE_TIMEOUT_CYCLES - 1) begin
                // 丢弃半帧而不发布 stage_*，后续完整帧可以从 AA 55 重新开始。
                byte_idle_count <= 32'd0;
                reset_frame_state();
            end else begin
                byte_idle_count <= byte_idle_count + 1'b1;
            end
        end
    end
endmodule

