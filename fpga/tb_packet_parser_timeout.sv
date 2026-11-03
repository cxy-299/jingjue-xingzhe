`timescale 1ns/1ps
// 半帧超时恢复，以及 CRC 正确但版本/地图/坐标不合法时不发布导航命令。
module tb_packet_parser_timeout;
    reg clk=0,rst_n=0,byte_valid=0;
    reg [7:0] data=0;
    wire goal_valid;
    wire [7:0] gx,gy;
    integer pulses=0,i;
    reg [7:0] frame [0:13];
    reg [15:0] crc;
    always #5 clk=~clk;
    vision_packet_parser #(.BYTE_TIMEOUT_CYCLES(8)) dut(
        .clk(clk),.rst_n(rst_n),.byte_i(data),.byte_valid_i(byte_valid),
        .nav_goal_valid_o(goal_valid),.nav_goal_x_o(gx),.nav_goal_y_o(gy),
        .vision_valid_o(),.heartbeat_valid_o(),.target_present_o(),
        .target_confirmed_o(),.target_centered_o(),.alignment_o(),.class_id_o(),
        .confidence_o(),.center_x_o(),.center_y_o(),.width_o(),.height_o(),
        .center_error_o(),.area_ratio_o(),.frame_id_o(),.sequence_o(),.crc_error_count_o());
    always @(posedge clk) if(goal_valid) pulses=pulses+1;
    function [15:0] crc_next(input [15:0] c,input [7:0] b);
        reg [15:0] v; integer k;
        begin v=c^{b,8'h00}; for(k=0;k<8;k=k+1) v=v[15]?(v<<1)^16'h1021:v<<1; crc_next=v; end
    endfunction
    task put(input [7:0] b);
        begin @(negedge clk);data=b;byte_valid=1;@(negedge clk);byte_valid=0;end
    endtask
    task set_frame(input [7:0] version,input [15:0] map_id,input [7:0] x,input [7:0] y);
        begin
            frame[0]=8'haa;frame[1]=8'h55;frame[2]=version;frame[3]=8'h20;
            frame[4]=1;frame[5]=0;frame[6]=4;frame[7]=0;
            frame[8]=map_id[7:0];frame[9]=map_id[15:8];frame[10]=x;frame[11]=y;
            crc=16'hffff;for(i=2;i<12;i=i+1) crc=crc_next(crc,frame[i]);
            frame[12]=crc[7:0];frame[13]=crc[15:8];
        end
    endtask
    task send_frame;
        begin for(i=0;i<14;i=i+1) put(frame[i]); repeat(3) @(negedge clk); end
    endtask
    initial begin
        $dumpfile("packet_parser_timeout.vcd");
        $dumpvars(0,clk,rst_n,data,byte_valid,goal_valid,gx,gy,dut.state,dut.byte_idle_count);
        repeat(4) @(negedge clk);rst_n=1;
        set_frame(3,16'h2601,2,17);
        if(crc!==16'h90d8) $fatal(1,"FAIL 黄金 CRC 不一致");
        for(i=0;i<9;i=i+1) put(frame[i]);
        repeat(12) @(negedge clk);
        if(pulses!=0 || dut.state!=0) $fatal(1,"FAIL 半帧超时未清理");
        send_frame();
        if(pulses!=1 || gx!=2 || gy!=17) $fatal(1,"FAIL 超时后首帧丢失");
        set_frame(4,16'h2601,3,12);send_frame();
        set_frame(3,16'h0001,3,12);send_frame();
        set_frame(3,16'h2601,20,12);send_frame();
        set_frame(3,16'h2601,3,12);frame[13]=frame[13]^1;send_frame();
        if(pulses!=1 || gx!=2 || gy!=17) $fatal(1,"FAIL 非法帧发布/覆盖旧坐标");
        set_frame(3,16'h2601,3,12);send_frame();
        if(pulses!=2 || gx!=3 || gy!=12) $fatal(1,"FAIL 坏帧后不能恢复");
        $display("PASS tb_packet_parser_timeout: truncated recovery, golden CRC, version/map/range/CRC rejection");
        $finish;
    end
endmodule
