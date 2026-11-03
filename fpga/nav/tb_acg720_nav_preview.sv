`timescale 1ns/1ps
// 集成回归：以真实 UART 8N1 时序喂入 Python 协议产生的黄金字节序列。
// 检查合法终点触发片上规划、坏 CRC 不触发、障碍内终点被拒绝。
module tb_acg720_nav_preview;
    localparam integer BIT_NS = 8680;
    reg clk=0, key_n=1, uart_rx=1;
    wire [5:0] led;
    reg [7:0] packet [0:13];
    integer i, timeout;
    integer goal_pulses=0;

    always #10 clk=~clk;
    acg720_nav_preview #(.POR_BIT(4)) dut (
        .clk_50m_i(clk), .key_s0_n_i(key_n),
        .pi_uart_rx_i(uart_rx), .led_o(led)
    );
    always @(posedge clk) if(dut.goal_pulse) goal_pulses <= goal_pulses+1;

    task automatic send_byte(input [7:0] value);
        integer bit_number;
        begin
            uart_rx=0; #(BIT_NS);
            for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
                uart_rx=value[bit_number]; #(BIT_NS);
            end
            uart_rx=1; #(BIT_NS);
        end
    endtask
    task automatic send_packet;
        begin
            for(i=0;i<14;i=i+1) send_byte(packet[i]);
            #(BIT_NS);
        end
    endtask
    task automatic set_example;
        begin
            // pack_nav_goal(seq=1, x=2, y=17) 的 CRC 为 90D8（线上低字节先发）。
            packet[0]=8'haa; packet[1]=8'h55; packet[2]=8'h03; packet[3]=8'h20;
            packet[4]=8'h01; packet[5]=8'h00; packet[6]=8'h04; packet[7]=8'h00;
            packet[8]=8'h01; packet[9]=8'h26; packet[10]=8'h02; packet[11]=8'h11;
            packet[12]=8'hd8; packet[13]=8'h90;
        end
    endtask
    task automatic set_blocked;
        begin
            // pack_nav_goal(seq=2, x=11, y=4)：此格位于实体障碍 A 内。
            packet[0]=8'haa; packet[1]=8'h55; packet[2]=8'h03; packet[3]=8'h20;
            packet[4]=8'h02; packet[5]=8'h00; packet[6]=8'h04; packet[7]=8'h00;
            packet[8]=8'h01; packet[9]=8'h26; packet[10]=8'h0b; packet[11]=8'h04;
            packet[12]=8'ha1; packet[13]=8'ha0;
        end
    endtask

    initial begin
        repeat(24) @(negedge clk);
        if(dut.rst_n!==1) $fatal(1,"上电复位未释放");

        set_example(); send_packet();
        timeout=0;
        while(!dut.route_ready && timeout<10000) begin
            @(negedge clk); timeout=timeout+1;
        end
        if(timeout>=10000 || goal_pulses!=1 || dut.no_path ||
           dut.u_planner.path_steps_o!=34 ||
           dut.u_planner.waypoint_x_o!=17 || dut.u_planner.waypoint_y_o!=1 ||
           led[1]!==1 || led[2]!==1 || led[4]!==1 || led[5]!==0)
            $fatal(1,"合法终点没有生成预期 34 步路径");

        // 故意翻转 CRC 高字节。应增加错误数，却不能产生第二次终点脉冲。
        set_example(); packet[13]=8'h91; send_packet();
        if(goal_pulses!=1 || dut.crc_error_count!=1 || dut.route_ready!==1)
            $fatal(1,"坏 CRC 影响了已规划路线");

        set_blocked(); send_packet();
        timeout=0;
        while(!dut.no_path && timeout<10000) begin
            @(negedge clk); timeout=timeout+1;
        end
        if(timeout>=10000 || goal_pulses!=2 || dut.route_ready!==0 || led[5]!==1)
            $fatal(1,"障碍目标未被安全拒绝");

        $display("PASS tb_acg720_nav_preview: UART -> CRC/map ID -> FPGA BFS -> LED, no motor outputs");
        $finish;
    end
endmodule
