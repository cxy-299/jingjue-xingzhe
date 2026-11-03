`timescale 1ns/1ps
module tb_sin12_r9_local_nav;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,tick=0,request=0,av=0,tf=0,ok=1,hard=0,mf=0,cancel=0;
    reg [7:0] ab=0,sx=5,sy=5,gx=5,gy=8,flags=5;
    reg [15:0] seq=1,distance=1000;
    reg signed [15:0] yaw=0;
    reg [31:0] p0=0,p1=0,p2=0,p3=0;
    wire active,fault;wire [7:0] state,reason,replans,x,y;wire [2:0] command;
    integer count,rotations,translates;reg obstacle=0,renew=1,follow_yaw=1,fresh=1;
    autonomous_nav_guard #(.LOCAL_MAP_ENABLE(1),.CANCEL_PIPELINE(1),.PROGRESS_CONTROL(1),.MAP_BITS({400{1'b1}}),.CELL_COUNTS(100),.NEUTRAL_TICKS(3),.SETTLE_TICKS(2),
        .MAX_TICKS(10000),.LEG_TICKS(2000)) dut(
        .clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(request),.sequence_i(seq),
        .sx_i(sx),.sy_i(sy),.gx_i(gx),.gy_i(gy),.flags_i(flags),.speed_i(8'd12),
        .counts_i(16'd100),.setback_i(16'sd0),.yaw_i(yaw),.sensors_ok_i(ok),.hard_stop_i(hard),
        .motor_fault_i(mf),.other_active_i(1'b0),.cancel_i(cancel),.ascii_valid_i(av),.ascii_i(ab),
        .error_i(1'b0),.tof_sample_i(tf),.distance_i(distance),
        .position0_i(p0),.position1_i(p1),.position2_i(p2),.position3_i(p3),
        .active_o(active),.fault_o(fault),.state_o(state),.reason_o(reason),.replans_o(replans),
        .sequence_o(),.x_o(x),.y_o(y),.gx_o(),.gy_o(),.obstacle_x_o(),.obstacle_y_o(),
        .command_o(command),.speed_o(),.local_mode_o());
    task step;
        integer yy;
        begin
            @(negedge clk);tick=0;tf=0;av=0;
            // Physical model: yaw moves only with rotation, encoders only forward.
            if(command==1)begin p0=p0+2;p1=p1-2;p2=p2+2;p3=p3-2;translates=translates+1;end
            if(follow_yaw && command==5)begin yy=$signed(yaw)+250;if(yy>25736)yy=yy-51472;yaw=yy;rotations=rotations+1;end
            if(follow_yaw && command==6)begin yy=$signed(yaw)-250;if(yy< -25736)yy=yy+51472;yaw=yy;rotations=rotations+1;end
            distance=1000;
            // A previously unknown small block centred on the original route.
            if(obstacle && dut.direction==0 && dut.px>=500 && dut.px<=600 && dut.py<800)
                distance=900-dut.py-100;
            repeat(18)@(negedge clk);
            tick=1;tf=fresh;av=renew;ab="N";
            @(negedge clk);tick=0;tf=0;av=0;
        end
    endtask
    task start_job;
        begin
            @(negedge clk);av=1;ab="S";@(negedge clk);av=0;
            repeat(5)step;
            @(negedge clk);request=1;@(negedge clk);request=0;
        end
    endtask
    task boot;
        begin rst=0;repeat(4)@(negedge clk);rst=1;yaw=0;p0=0;p1=0;p2=0;p3=0;
            count=0;rotations=0;translates=0;renew=1;ok=1;hard=0;mf=0;cancel=0;fresh=1;flags=5;
            repeat(5)step;
        end
    endtask
    initial begin
        boot;start_job;
        while(active && count<5000)begin step;count=count+1;end
        if(state!=11 || fault || x!=5 || y!=8 || translates==0)$fatal(1,"empty-field goal failed state=%d reason=%d xy=%d/%d",state,reason,x,y);
        repeat(50)step;if(active || command)$fatal(1,"completed task restarted");
        boot;obstacle=1;gy=12;seq=2;start_job;
        while(active && count<9000)begin step;count=count+1;end
        if(state!=11 || fault || replans==0 || rotations==0 || x!=5 || y!=12)
            $fatal(1,"measured obstacle detour failed state=%d reason=%d replans=%d xy=%d/%d",state,reason,replans,x,y);
        $display("SIN12_REAL_SENSOR_MODEL_BFS_DETOUR_PASS replans=%d",replans);
        boot;obstacle=0;seq=3;gy=8;start_job;
        repeat(100)step;renew=0;repeat(40)step;
        if(active || reason!=1 || command)$fatal(1,"lease timeout unsafe");
        renew=1;repeat(50)step;if(active || command)$fatal(1,"lease renewal resurrected task");
        boot;seq=4;start_job;repeat(100)step;hard=1;#1;
        if(command)$fatal(1,"hard stop not immediate");
        step;hard=0;repeat(50)step;
        if(active || command || reason!=4)$fatal(1,"hard stop resumed");
        boot;seq=5;start_job;repeat(100)step;ok=0;#1;
        if(command)$fatal(1,"stale sensors not gated");step;ok=1;repeat(50)step;
        if(active || reason!=2)$fatal(1,"stale sensor resume");
        boot;obstacle=0;seq=6;fresh=0;start_job;
        while(active && count<1000)begin step;count=count+1;end
        if(active || command || reason!=8)$fatal(1,"stale local ToF did not stop with reason8: %d",reason);
        boot;seq=7;start_job;
        while(active && command!=1 && count<1000)begin step;count=count+1;end
        if(command!=1)$fatal(1,"neutral interrupt test did not reach forward motion");
        step;@(negedge clk);tick=1;hard=1;#1;
        if(command)$fatal(1,"intent split delayed physical hard stop");
        @(negedge clk);tick=0;
        if(active || reason!=4 || dut.neutral!=0)
            $fatal(1,"interrupted movement incorrectly earned neutral credit");
        hard=0;repeat(5)step;
        if(command || active)$fatal(1,"neutral recovery restarted cancelled job");
        boot;seq=8;flags=0;start_job;
        if(active || reason!=6)$fatal(1,"unconfirmed geometry accepted");
        boot;seq=9;flags=5;start_job;
        while(active && command!=1 && count<1000)begin step;count=count+1;end
        if(command!=1)$fatal(1,"cancel test did not reach moving state");
        cancel=1;#1;if(command)$fatal(1,"live cancel physical gate delayed");
        @(negedge clk);cancel=0;#1;
        if(command)$fatal(1,"one-cycle cancel rebounded before fail bookkeeping");
        repeat(3)@(negedge clk);
        if(active || reason!=5 || command)$fatal(1,"cancel pipeline did not latch failure");
        repeat(30)step;if(active || command)$fatal(1,"cancelled job restarted");
        $display("R6_LOCAL_CANCEL_NO_DELAY_NO_REBOUND_PASS");
        $display("R5_LOCAL_MAP_FULL_DETOUR_RESTORE_STOP_LEASE_FRESH_FRAMES_PASS");$finish;
    end
    initial begin #100000000;$fatal(1,"test timed out");end
endmodule
