`timescale 1ns/1ps
`include "../nav/sin12_map.vh"
module tb_sin12_r9_map_nav;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,tick=0,request=0,av=0,tf=0,ok=1,hard=0,mf=0,cancel=0;
    reg [7:0] ab=0,sx=17,sy=2,gx=9,gy=14,flags=1;
    reg [15:0] seq=1,distance=1000;
    reg signed [15:0] yaw=0;
    reg [31:0] p0=0,p1=0,p2=0,p3=0;
    wire active,fault;wire [7:0] state,reason,replans,x,y;wire [2:0] command;
    integer count,rotations,translates,spin_velocity=0;reg obstacle=0,renew=1,follow_yaw=1,fresh=1;
    autonomous_nav_guard #(.LOCAL_MAP_ENABLE(1),.CANCEL_PIPELINE(1),.PROGRESS_CONTROL(1),.MAP_BITS(`SIN12_MAP_BITS),.CELL_COUNTS(100),.NEUTRAL_TICKS(3),.SETTLE_TICKS(2),
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
            if(follow_yaw)begin
                spin_velocity=(spin_velocity*3+(command==5?128:command==6?-128:0))/4;
                yy=$signed(yaw)+spin_velocity;
                if(yy>25736)yy=yy-51472;if(yy< -25736)yy=yy+51472;
                yaw=yy;if(command==5 || command==6)rotations=rotations+1;
            end
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
        boot;flags=1;start_job;
        while(active && count<10000)begin
            step;count=count+1;
            if(dut.gx_o!=9 || dut.gy_o!=14)$fatal(1,"Map submitted goal changed");
            if(state==11 && (x!=9 || y!=14))$fatal(1,"Intermediate/estimated cell declared goal");
        end
        if(state!=11 || fault || x!=9 || y!=14 || rotations==0 || translates==0)
            $fatal(1,"Actual map route failed state=%d reason=%d xy=%d/%d",state,reason,x,y);
        repeat(50)step;if(active || command)$fatal(1,"Completed map navigation restarted");
        $display("R9_MAP2613_ORIGINAL_GOAL_CORNERS_INERTIAL_TURNS_PASS samples=%d",count);$finish;
    end
    initial begin #100000000;$fatal(1,"test timed out");end
endmodule
