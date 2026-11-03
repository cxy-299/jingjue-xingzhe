`timescale 1ns/1ps
module tb_sin11_mission;
    reg clk=0;always #5 clk=~clk;
    reg manual_stop=0;
    reg rst=0,request=0,pkt=0,ascii_valid=0,hard=0,sensors=1,cancel=0,renew=1,feed=1;
    reg [7:0] ascii=0;
    reg [31:0] req_id=1,pid=1,plock=0;
    reg [15:0] seq=0,pclass=39;
    reg pred=1,selected=0,visible=0,confirmed=0,inverted=0;
    reg signed [15:0] center=0,yaw=0;
    reg [15:0] distance=900;
    reg [7:0] clock_count=0;
    wire active;wire [31:0] id,lockid;wire [15:0] cls,speed;
    wire [3:0] state;wire [2:0] leg,command;
    vision_mission_guard #(.CLK_HZ(1000),.NEUTRAL_MS(20),.DWELL_MS(40),
        .LEG_MS(1000),.TOTAL_MS(6000),.ARRIVAL_TICKS(3)) dut(
        .clk(clk),.rst_n(rst),.sample_tick_i(clock_count%10==0),
        .request_i(request),.request_id_i(req_id),.request_class_i(16'd39),.request_distance_i(16'd200),
        .request_red_i(1'b1),.request_inverted_i(inverted),.packet_i(pkt),.packet_sequence_i(seq),
        .packet_mission_i(pid),.packet_lock_i(plock),.packet_class_i(pclass),.packet_red_i(pred),
        .selected_i(selected),.visible_i(visible),.confirmed_i(confirmed),.center_i(center),
        .yaw_i(yaw),.distance_i(distance),.distance_sample_i(1'b0),.sensors_ok_i(sensors),.hard_stop_i(hard),
        .wheels_still_i(1'b1),.motor_fault_i(1'b0),.other_active_i(1'b0),.cancel_i(cancel),.ascii_valid_i(ascii_valid),
        .ascii_i(ascii),.error_i(1'b0),.active_o(active),.id_o(id),.lock_o(lockid),.class_o(cls),
        .state_o(state),.leg_o(leg),.command_o(command),.speed_o(speed));
    always @(negedge clk)begin
        clock_count<=clock_count+1;
        pkt<=feed && clock_count%20==0;
        if(feed && clock_count%20==0)seq<=seq+1;
        if(manual_stop)begin ascii_valid<=1;ascii<="S";end
        else if(renew && active && clock_count%50==0)begin ascii_valid<=1;ascii<="M";end
        else begin ascii_valid<=0;ascii<=0;end
    end
    task waitcycles(input integer n);repeat(n)@(posedge clk);endtask
    task stop_arm;
        begin renew=0;manual_stop=1;waitcycles(3);#1;manual_stop=0;waitcycles(30);renew=1;end
    endtask
    task start(input integer n);
        begin req_id=n;pid=n;waitcycles(25);stop_arm();
            @(posedge clk);#1;request=1;@(posedge clk);#1;request=0;waitcycles(35);end
    endtask
    initial begin
        waitcycles(4);rst=1;waitcycles(40);
        if(active || command)$fatal(1,"boot must stop");
        start(1);
        if(!active || command!=5 || state!=1)$fatal(1,"initial CCW search active=%d cmd=%d state=%d armed=%d neutral=%d",active,command,state,dut.armed,dut.neutral_age);
        yaw=4289;waitcycles(20);
        if(command!=0 || state!=2)$fatal(1,"scan dwell");
        waitcycles(65);yaw=-4289;waitcycles(65);yaw=8579;waitcycles(65);yaw=-8579;waitcycles(90);
        if(active || state!=7 || command)$fatal(1,"bounded search exhausted");
        // Same mission cannot be restarted with S/M/replayed request.
        start(1);if(active)$fatal(1,"replayed mission restarted");
        yaw=0;start(2);
        selected=1;visible=1;confirmed=1;plock=99;center=-2000;waitcycles(70);
        if(state!=3 || command!=3 || lockid!=99)$fatal(1,"semantic lock alignment");
        center=0;distance=500;waitcycles(80);
        if(state!=4 || command!=1)$fatal(1,"approach");
        // Regression: distance takes precedence over an off-center target.
        center=-2000;waitcycles(50);
        if(command!=3)$fatal(1,"far alignment setup");
        distance=205;#1;
        if(command!=0 || speed!=0)$fatal(1,"arrival range must immediately stop lateral alignment");
        waitcycles(100);
        if(!active || state!=3 || command!=0)$fatal(1,"off-center range stop falsely completed or moved");
        center=2000;waitcycles(50);
        if(command!=0 || !active)$fatal(1,"right alignment overrode arrival stop");
        center=0;waitcycles(30);
        distance=205;waitcycles(100);
        if(state!=6 || active || command)$fatal(1,"stable arrival complete");
        distance=900;waitcycles(80);if(active)$fatal(1,"arrival auto resumed");
        selected=0;visible=0;confirmed=0;plock=0;start(3);hard=1;waitcycles(2);
        if(active || state!=10 || command)$fatal(1,"hard stop");
        hard=0;waitcycles(80);if(active)$fatal(1,"obstacle removal resumed");
        start(4);renew=0;waitcycles(350);
        if(active || state!=8)$fatal(1,"lease timeout");
        renew=1;start(5);feed=0;waitcycles(1250);
        if(active)$fatal(1,"perception timeout");feed=1;
        start(6);selected=1;visible=1;confirmed=1;plock=100;center=0;waitcycles(60);
        visible=0;waitcycles(30);
        if(active || state!=14)$fatal(1,"target disappearance");
        visible=1;waitcycles(80);if(active)$fatal(1,"target return resumed");
        selected=0;visible=0;confirmed=0;plock=0;yaw=25700;inverted=1;start(7);
        if(command!=5)$fatal(1,"inverted yaw physical CCW");
        cancel=1;waitcycles(2);cancel=0;
        if(active || command)$fatal(1,"mode cancellation");
        pred=0;start(8);if(active || state!=13)$fatal(1,"wrong semantic color accepted");
        $display("SIN11_MISSION_SEARCH_ARRIVAL_CANCEL_PASS");$finish;
    end
    initial begin #300000;$fatal(1,"test timeout");end
endmodule
