`timescale 1ns/1ps

// 串口验收 testbench：用真实的 50 MHz 时钟和 115200 波特率发送完整串口帧。
// 只把两个超时时间从实机的 1500 ms 缩为 5 ms，以免仿真等待过久。
// dut 是 vision_uart_bridge；板卡引脚/LED 不在本测试的范围内。
module tb_acg720_uart_bringup;
    localparam integer BIT_NS = 8680; // 1/115200 秒约等于 8680.56 ns
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    reg [7:0] payload [0:25];
    integer i;
    integer vision_pulses = 0; // 只统计 CRC 正确的视觉结果帧
    integer nav_pulses = 0;    // 只统计地图版本、坐标和 CRC 都正确的导航目标帧
    integer test_step = 0;     // 在 Wave 窗口中定位当前测试场景，见下方 initial

    wire link_alive;
    wire vision_fresh;
    wire target_valid;
    wire target_confirmed;
    wire [15:0] class_id;
    wire signed [15:0] center_error;
    wire [31:0] frame_id;
    wire [15:0] sequence_id;
    wire [15:0] crc_errors;
    wire framing_error;
    wire vision_pulse;
    wire nav_goal_pulse;
    wire [7:0] nav_goal_x, nav_goal_y;

    // 20 ns 周期 = 50 MHz。接收器应只在有效视觉帧时产生一个时钟脉冲。
    always #10 clk = ~clk;
    always @(posedge clk) if (vision_pulse) vision_pulses <= vision_pulses + 1;
    always @(posedge clk) if (nav_goal_pulse) nav_pulses <= nav_pulses + 1;

    vision_uart_bridge #(
        .CLK_HZ(50_000_000), .BAUD(115200),
        .WATCHDOG_MS(5), .VISION_TIMEOUT_MS(5)
    ) dut (
        .clk(clk), .rst_n(rst_n), .pi_uart_rx_i(uart_rx),
        .link_alive_o(link_alive), .vision_fresh_o(vision_fresh),
        .target_valid_o(target_valid), .target_confirmed_o(target_confirmed),
        .target_centered_o(), .alignment_o(), .class_id_o(class_id),
        .confidence_o(), .center_x_o(), .center_y_o(), .width_o(),
        .height_o(), .center_error_o(center_error), .area_ratio_o(),
        .frame_id_o(frame_id), .sequence_o(sequence_id),
        .crc_error_count_o(crc_errors), .uart_framing_error_o(framing_error),
        .vision_packet_pulse_o(vision_pulse),
        .nav_goal_pulse_o(nav_goal_pulse),
        .nav_goal_x_o(nav_goal_x), .nav_goal_y_o(nav_goal_y)
    );

    // 与树莓派/FPGA 一致：CRC16-CCITT，初值 FFFF，多项式 1021。
    function automatic [15:0] crc_step(input [15:0] prior, input [7:0] value);
        reg [15:0] tmp;
        integer n;
        begin
            tmp = prior ^ {value, 8'h00};
            for (n = 0; n < 8; n = n + 1)
                tmp = tmp[15] ? (tmp << 1) ^ 16'h1021 : tmp << 1;
            crc_step = tmp;
        end
    endfunction

    // UART 8-N-1：起始位 0、低位先发的 8 位数据、停止位 1。
    task automatic send_byte(input [7:0] value);
        integer bit_number;
        begin
            uart_rx = 1'b0;
            #(BIT_NS);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_rx = value[bit_number];
                #(BIT_NS);
            end
            uart_rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    // 帧头和末尾 CRC 不参与校验；只有 version 到 payload 进入 CRC。
    task automatic send_body_byte(input [7:0] value, inout [15:0] crc);
        begin
            send_byte(value);
            crc = crc_step(crc, value);
        end
    endtask

    // 发送完整协议帧：AA 55 | version/type/seq/len/payload | CRC低/高。
    // corrupt_crc=1 专门制造坏帧，验证 FPGA 必须拒绝它。
    task automatic send_packet(input [7:0] msg_type, input [15:0] seq,
                               input integer payload_len, input bit corrupt_crc);
        reg [15:0] crc;
        integer index;
        begin
            crc = 16'hFFFF;
            send_byte(8'hAA);
            send_byte(8'h55);
            send_body_byte(8'h03, crc);
            send_body_byte(msg_type, crc);
            send_body_byte(seq[7:0], crc);
            send_body_byte(seq[15:8], crc);
            send_body_byte(payload_len[7:0], crc);
            send_body_byte(payload_len[15:8], crc);
            for (index = 0; index < payload_len; index = index + 1)
                send_body_byte(payload[index], crc);
            if (corrupt_crc) crc = crc ^ 16'h0001;
            send_byte(crc[7:0]);
            send_byte(crc[15:8]);
            #(BIT_NS);
        end
    endtask

    // 构造固定的 26 字节视觉载荷，方便检查小端序和有符号偏差。
    // flags bit0=有目标，bit1=已确认；其余字段在此测试中置零。
    task automatic set_vision(input [7:0] flags);
        begin
            for (i = 0; i < 26; i = i + 1) payload[i] = 8'h00;
            payload[4] = 8'h78;
            payload[5] = 8'h56;
            payload[6] = 8'h34;
            payload[7] = 8'h12;
            payload[8] = flags;
            payload[9] = 8'h02;
            payload[10] = 8'h2A; // class 42
            payload[22] = 8'h2E; // -1234 = 0xFB2E
            payload[23] = 8'hFB;
        end
    endtask

    initial begin
        // 0：复位后，所有对外有效状态都必须为 0。
        #100;
        if (link_alive !== 1'b0 || vision_fresh !== 1'b0 ||
            target_valid !== 1'b0 || crc_errors !== 16'd0)
            $fatal(1, "FAIL reset state");
        rst_n = 1'b1;
        #(BIT_NS);

        // 1：心跳只证明串口链路活着，不能表示有新鲜视觉目标。
        test_step = 1;
        for (i = 0; i < 4; i = i + 1) payload[i] = 8'h00;
        send_packet(8'h01, 16'd1, 4, 1'b0);
        if (link_alive !== 1'b1 || vision_fresh !== 1'b0 ||
            target_valid !== 1'b0 || vision_pulses != 0)
            $fatal(1, "FAIL heartbeat semantics");

        // 2：正确视觉帧应更新目标状态、类别、帧号及有符号中心偏差。
        test_step = 2;
        set_vision(8'h03);
        send_packet(8'h13, 16'd2, 26, 1'b0);
        if (link_alive !== 1'b1 || vision_fresh !== 1'b1 ||
            target_valid !== 1'b1 || target_confirmed !== 1'b1 ||
            class_id !== 16'd42 || center_error !== -16'sd1234 ||
            frame_id !== 32'h12345678 || sequence_id !== 16'd2 || vision_pulses != 1)
            $fatal(1, "FAIL valid vision decoding");

        // 3：CRC 故意错误；错误计数 +1，不得发布新的视觉结果。
        test_step = 3;
        send_packet(8'h13, 16'd3, 26, 1'b1);
        if (crc_errors !== 16'd1 || vision_pulses != 1 || sequence_id !== 16'd2)
            $fatal(1, "FAIL CRC rejection");

        // 4：坏帧不能续命，两个超时到期后目标必须失效。
        test_step = 4;
        #5_200_000;
        if (link_alive !== 1'b0 || vision_fresh !== 1'b0 ||
            target_valid !== 1'b0 || target_confirmed !== 1'b0)
            $fatal(1, "FAIL stale-frame fail-safe");

        // 5：先有正确视觉帧，再有正确心跳。
        test_step = 5;
        set_vision(8'h03);
        send_packet(8'h13, 16'd4, 26, 1'b0);
        for (i = 0; i < 4; i = i + 1) payload[i] = 8'h00;
        send_packet(8'h01, 16'd5, 4, 1'b0);
        // 6：心跳仍新鲜，但旧视觉帧已超时；目标必须失效。
        test_step = 6;
        #4_200_000;
        if (link_alive !== 1'b1 || vision_fresh !== 1'b0 ||
            target_valid !== 1'b0 || target_confirmed !== 1'b0)
            $fatal(1, "FAIL heartbeat kept stale target alive");
        // 7：再等 1 ms，心跳本身也超时，链路状态应归零。
        test_step = 7;
        #1_000_000;
        if (link_alive !== 1'b0)
            $fatal(1, "FAIL link timeout");

        // 8：CRC 正确但 flags=0 的“无目标”帧不能产生目标有效信号。
        test_step = 8;
        set_vision(8'h00);
        send_packet(8'h13, 16'd6, 26, 1'b0);
        if (link_alive !== 1'b1 || vision_fresh !== 1'b1 ||
            target_valid !== 1'b0 || target_confirmed !== 1'b0 ||
            vision_pulses != 3 || framing_error !== 1'b0)
            $fatal(1, "FAIL no-target frame");

        // 9：新协议目标帧只能携带地图 ID 和格坐标，不能影响视觉状态。
        test_step = 9;
        payload[0]=8'h01; payload[1]=8'h26; payload[2]=8'd2; payload[3]=8'd17;
        send_packet(8'h20, 16'd7, 4, 1'b0);
        if(nav_pulses!=1 || nav_goal_x!=2 || nav_goal_y!=17 || vision_pulses!=3)
            $fatal(1,"FAIL nav goal decoding");

        // 10：错误 CRC、错误地图版本和越界坐标都不能触发 FPGA 规划。
        test_step = 10;
        send_packet(8'h20, 16'd8, 4, 1'b1);
        payload[0]=8'h02; send_packet(8'h20, 16'd9, 4, 1'b0);
        payload[0]=8'h01; payload[2]=8'd20; send_packet(8'h20, 16'd10, 4, 1'b0);
        if(nav_pulses!=1) $fatal(1,"FAIL invalid nav goal rejection");

        $display("PASS tb_acg720_uart_bringup: UART, CRC, vision, timeouts, nav goal validation");
        $finish;
    end
endmodule
