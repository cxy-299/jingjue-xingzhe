`timescale 1ns/1ps
module tb_sin9_target_follow;
    reg clk=0; always #5 clk=~clk;
    reg rst=0, rx=1;
    reg bt_valid=0; reg [7:0] bt_data=0;
    reg hard=0, sensors=1, motor_fault=0, nav=0;
    reg [15:0] distance=400;
    wire [7:0] data;
    wire byte_valid, rx_error, packet, selected, present, confirmed, follow;
    wire [15:0] class_id, seq;
    wire [31:0] lock_id;
    wire signed [15:0] center;
    wire active,fresh,sel,vis;
    wire [15:0] outclass,target;
    wire [31:0] outlock;
    wire [3:0] state;
    wire [2:0] command;
    reg [7:0] mem[0:199];
    uart_rx #(.CLK_HZ(10000),.BAUD(1000)) uart(.clk(clk),.rst_n(rst),
        .uart_rx_i(rx),.data_o(data),.data_valid_o(byte_valid),.framing_error_o(rx_error));
    vision_packet_parser #(.BYTE_TIMEOUT_CYCLES(300)) parser(
        .clk(clk),.rst_n(rst),.byte_i(data),.byte_valid_i(byte_valid),
        .vision_valid_o(packet),.selection_valid_o(selected),.follow_requested_o(follow),
        .lock_id_o(lock_id),.target_present_o(present),.target_confirmed_o(confirmed),
        .class_id_o(class_id),.center_error_o(center),.sequence_o(seq));
    vision_follow_guard #(.CLK_HZ(10000),.VISION_TIMEOUT_MS(2000),.LEASE_MS(1500),.NEUTRAL_MS(10)) guard(
        .clk(clk),.rst_n(rst),.packet_i(packet),.selected_i(selected),.visible_i(present),
        .confirmed_i(confirmed),.follow_i(follow),.sequence_i(seq),.class_i(class_id),
        .lock_i(lock_id),.center_i(center),.bt_valid_i(bt_valid),.bt_error_i(1'b0),
        .bt_byte_i(bt_data),.hard_stop_i(hard),.sensors_ok_i(sensors),
        .motor_fault_i(motor_fault),.nav_start_i(nav),.distance_i(distance),
        .active_o(active),.fresh_o(fresh),.selected_o(sel),.visible_o(vis),
        .class_o(outclass),.lock_o(outlock),.state_o(state),.command_o(command),.target_o(target));
    task send_byte(input [7:0] value);
        integer b;
        begin
            @(negedge clk); rx=0; repeat(10) @(negedge clk);
            for(b=0;b<8;b=b+1) begin rx=value[b]; repeat(10) @(negedge clk); end
            rx=1; repeat(12) @(negedge clk);
        end
    endtask
    task frame(input integer index, input integer corrupt);
        integer k;
        begin
            for(k=0;k<40;k=k+1) send_byte(mem[index*40+k] ^ ((corrupt && k==39)?8'h80:8'h00));
            repeat(8) @(negedge clk);
        end
    endtask
    task bt(input [7:0] value);
        begin @(negedge clk);bt_data=value;bt_valid=1;@(negedge clk);bt_valid=0;repeat(5)@(negedge clk);end
    endtask
    initial begin
        $readmemh("sin9_test_frames.mem",mem);
        repeat(5)@(negedge clk);rst=1;
        frame(0,0);
        if(outclass!=0 || outlock!=42 || !fresh || !vis || active || command!=0) $fatal(1,"lock must not drive");
        bt("V"); if(active) $fatal(1,"reset requires S");
        bt("S"); bt("V"); repeat(150)@(negedge clk);
        if(!active || command!=3) $fatal(1,"person alignment failed");
        frame(1,1); if(center!=-3000) $fatal(1,"corrupt CRC changed target");
        frame(1,0);repeat(150)@(negedge clk);
        if(command!=1 || target==0) $fatal(1,"centered approach failed");
        distance=200;repeat(150)@(negedge clk);
        if(command!=0 || target!=0) $fatal(1,"20cm hold failed");
        frame(2,0); if(active || command!=0) $fatal(1,"target loss not stopped");
        frame(3,0);bt("V");if(active) $fatal(1,"loss rearmed without S");
        bt("S");bt("V");distance=400;repeat(150)@(negedge clk);
        if(!active || outclass!=39 || command!=1) $fatal(1,"bottle selection failed");
        frame(4,0);if(active) $fatal(1,"new identity must cancel authority");
        bt("S");bt("V");repeat(150)@(negedge clk);
        hard=1;repeat(3)@(negedge clk); if(active || command!=0) $fatal(1,"hard stop failed");
        hard=0;bt("V");if(active) $fatal(1,"clearance auto rearmed");
        bt("S");bt("V");repeat(15100)@(negedge clk);
        if(active || command!=0) $fatal(1,"lease timeout failed");
        repeat(20000)@(negedge clk);if(fresh) $fatal(1,"stale target remains fresh");
        $display("SIN9_TARGET_UART_CRC_GUARD_PASS");$finish;
    end
    initial begin #3000000;$fatal(1,"timeout");end
endmodule
