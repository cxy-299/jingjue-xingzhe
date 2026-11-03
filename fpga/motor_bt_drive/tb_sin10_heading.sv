`timescale 1ns/1ps
module tb_sin10_heading #(parameter PIPELINED_TARGET=0);
    reg clk=0;always #5 clk=~clk;
    reg rst=0;
    reg [7:0] data=0;reg valid=0,uart_error=0;
    wire ascii_valid,request;wire [15:0] seq;wire signed [15:0] angle;
    wire [7:0] speed;wire inverted;
    reg [31:0] yaw_bits=0;reg imu_recent=1;
    wire signed [15:0] yaw;wire yaw_valid;
    reg sensors=1,hard=0,motor_fault=0,other_active=0,cancel=0;
    wire active,fault;wire [3:0] state;wire [15:0] accepted_seq,target_speed;
    wire signed [15:0] target_yaw,error;wire [2:0] command;
    integer ticks=0,ascii_count=0,requests=0;
    reg tick=0;
    reg [7:0] frames[0:83];reg [31:0] angles[0:9];
    always @(negedge clk)begin
        tick=0;
        if(ticks==99)begin tick=1;ticks=0;end else ticks=ticks+1;
    end
    always @(posedge clk)begin
        if(ascii_valid)ascii_count=ascii_count+1;
        if(request)requests=requests+1;
    end
    bt_turn_packet_rx #(.BYTE_TIMEOUT_CYCLES(250)) parser(
        .clk(clk),.rst_n(rst),.byte_i(data),.valid_i(valid),.error_i(uart_error),
        .ascii_valid_o(ascii_valid),.request_o(request),.sequence_o(seq),
        .angle_o(angle),.speed_o(speed),.inverted_o(inverted));
    yaw_float_to_q13 convert(.clk(clk),.rst_n(rst),.bits_i(yaw_bits),
        .recent_i(imu_recent),.yaw_o(yaw),.valid_o(yaw_valid));
    imu_turn_guard #(.CLK_HZ(10000),.TIMEOUT_MS(1000),.NEUTRAL_MS(10),.PIPELINED_TARGET(PIPELINED_TARGET)) guard(
        .clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(request),
        .sequence_i(seq),.angle_cdeg_i(angle),.speed_i(speed),.inverted_i(inverted),
        .yaw_i(yaw),.sensors_ok_i(sensors&&yaw_valid),.hard_stop_i(hard),
        .motor_fault_i(motor_fault),.other_active_i(other_active),.cancel_i(cancel),
        .ascii_valid_i(ascii_valid),.error_i(uart_error),.ascii_i(data),
        .active_o(active),.fault_o(fault),.state_o(state),.sequence_o(accepted_seq),
        .target_yaw_o(target_yaw),.error_o(error),.command_o(command),.target_speed_o(target_speed));
    task byte_send(input [7:0] b);
        begin @(negedge clk);data=b;valid=1;@(negedge clk);valid=0;repeat(2)@(negedge clk);end
    endtask
    task frame(input integer n,input bit corrupt);
        integer i,before_ascii;
        begin
            before_ascii=ascii_count;
            for(i=0;i<14;i++)byte_send(frames[n*14+i]^((corrupt&&i==13)?8'h80:0));
            repeat(3)@(negedge clk);
            if(PIPELINED_TARGET)begin
                if(guard.target_pending && command!=0)$fatal(1,"motion before target conversion");
                repeat(8)@(negedge clk);
            end
            if(ascii_count!=before_ascii)$fatal(1,"binary payload escaped into ASCII controls");
        end
    endtask
    task stop_arm;
        begin byte_send("S");repeat(120)@(negedge clk);end
    endtask
    task wait_lease(input integer cycles);
        integer n;
        begin
            for(n=0;n<cycles;n++)begin
                @(negedge clk);
                if(n%500==499)byte_send("G");
            end
        end
    endtask
    task reset_all;
        begin rst=0;repeat(4)@(negedge clk);rst=1;repeat(4)@(negedge clk);end
    endtask
    initial begin
        $readmemh("sin10_turn_frames.mem",frames);$readmemh("sin10_yaw_bits.mem",angles);
        reset_all();
        if(!yaw_valid||yaw!=0||active||command!=0)$fatal(1,"initial state");
        yaw_bits=angles[6];repeat(3)@(negedge clk);
        if(yaw<12865||yaw>12870)$fatal(1,"radians to Q13 conversion");
        yaw_bits=32'h7fc00000;repeat(3)@(negedge clk);if(yaw_valid)$fatal(1,"NaN accepted");
        yaw_bits=32'h7f800000;repeat(3)@(negedge clk);if(yaw_valid)$fatal(1,"infinity accepted");
        yaw_bits=angles[0];repeat(3)@(negedge clk);
        // Oversized/truncated binary data cannot leak ASCII motor/lease bytes.
        begin:bad_length
            integer before_count;
            before_count=ascii_count;
            byte_send(8'haa);byte_send(8'h55);byte_send(3);byte_send(8'h22);
            byte_send(0);byte_send(0);byte_send(8'hff);byte_send(0);
            byte_send("F");byte_send("S");byte_send("G");
            if(ascii_count!=before_count)$fatal(1,"bad-length payload escaped quarantine");
            repeat(300)@(negedge clk);
        end
        frame(0,0);if(active||state!=7)$fatal(1,"reset rearmed without S");
        stop_arm();frame(1,1);if(active)$fatal(1,"CRC error started turn");
        frame(1,0);repeat(150)@(negedge clk);
        if(!active||command!=6||accepted_seq!=2)$fatal(1,"CW command");
        byte_send("S");if(active||command!=0)$fatal(1,"S did not cancel");
        stop_arm();frame(0,0);repeat(150)@(negedge clk);
        if(!active||command!=5)$fatal(1,"CCW command");
        yaw_bits=angles[2];repeat(5)@(negedge clk);
        if(command!=0)$fatal(1,"overshoot must enter neutral");
        repeat(50)@(negedge clk);if(command!=0)$fatal(1,"reversal skipped neutral");
        repeat(100)@(negedge clk);if(command!=6)$fatal(1,"overshoot recovery direction");
        yaw_bits=angles[1];wait_lease(2200);
        if(active||state!=3||command!=0)$fatal(1,"settling completion");
        byte_send("G");frame(0,0);if(active)$fatal(1,"duplicate or G restarted completed turn");
        stop_arm();yaw_bits=angles[7];repeat(3)@(negedge clk);frame(2,0);
        if(target_yaw>=0||error<700||error>730)$fatal(1,"179+5 wrap around");
        yaw_bits=angles[9];wait_lease(2200);if(active||state!=3)$fatal(1,"wrapped turn completion");
        stop_arm();yaw_bits=angles[0];repeat(3)@(negedge clk);frame(3,0);repeat(150)@(negedge clk);
        if(command!=5||target_yaw>=0)$fatal(1,"inverted mounting polarity");
        hard=1;repeat(3)@(negedge clk);if(active||command!=0||state!=6)$fatal(1,"ToF stop");
        hard=0;byte_send("G");if(active)$fatal(1,"hard stop rearmed automatically");
        stop_arm();frame(4,0);repeat(3100)@(negedge clk);
        if(active||state!=4)$fatal(1,"lease expiry");
        stop_arm();frame(5,0);wait_lease(11000);
        if(active||state!=5)$fatal(1,"heading timeout");
        stop_arm();frame(0,0);imu_recent=0;repeat(5)@(negedge clk);
        if(active||state!=6)$fatal(1,"stale IMU continued");
        imu_recent=1;stop_arm();frame(1,0);motor_fault=1;repeat(3)@(negedge clk);
        if(active||state!=6)$fatal(1,"motor fault continued");
        motor_fault=0;stop_arm();frame(3,0);cancel=1;repeat(3)@(negedge clk);
        if(active||state!=8)$fatal(1,"navigation preemption");
        cancel=0;reset_all();frame(0,0);if(active)$fatal(1,"reset resumed previous turn");
        $display("SIN10_HEADING_CRC_WRAP_SETTLE_INTERLOCK_PASS");$finish;
    end
    initial begin #3000000;$fatal(1,"test timeout");end
endmodule
