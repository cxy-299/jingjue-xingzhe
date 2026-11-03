`timescale 1ns/1ps
module tb_sin11_packets;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0;reg [7:0] byteval;
    reg [7:0] requests[0:39],observation[0:44];
    wire request,ascii_ok,vvalid,selected,visible,confirmed,red,follow;
    wire [31:0] rid,vid,lockid;
    wire [15:0] category,distance;
    integer requests_seen=0,observations_seen=0,k;
    bt_mission_packet_rx packet(.clk(clk),.rst_n(rst),.byte_i(byteval),.valid_i(valid),.error_i(1'b0),
        .request_o(request),.mission_o(rid),.class_o(category),.distance_o(distance),.red_o(),
        .inverted_o(),.ascii_valid_o(),.sequence_o(),.angle_o(),.speed_o());
    bt_turn_packet_rx gate(.clk(clk),.rst_n(rst),.byte_i(byteval),.valid_i(valid),.error_i(1'b0),
        .ascii_valid_o(ascii_ok),.request_o(),.sequence_o(),.angle_o(),.speed_o(),.inverted_o());
    vision_packet_parser vp(.clk(clk),.rst_n(rst),.byte_i(byteval),.byte_valid_i(valid),
        .vision_valid_o(vvalid),.mission_id_o(vid),.mission_red_o(red),.selection_valid_o(selected),
        .follow_requested_o(follow),.lock_id_o(lockid),.target_present_o(visible),.target_confirmed_o(confirmed),
        .heartbeat_valid_o(),.nav_goal_valid_o(),.nav_goal_x_o(),.nav_goal_y_o(),
        .target_centered_o(),.alignment_o(),.class_id_o(),.confidence_o(),.center_x_o(),.center_y_o(),
        .width_o(),.height_o(),.center_error_o(),.area_ratio_o(),.frame_id_o(),.sequence_o(),.crc_error_count_o());
    always @(posedge clk)begin
        if(request)begin
            requests_seen++;
            if(rid!=32'h47534642 || category!=39 || distance!=200)$fatal(1,"request fields");
        end
        if(vvalid)begin
            observations_seen++;
            if(vid!=32'h47534642 || lockid!=42 || !red || !selected || !visible || !confirmed || follow)
                $fatal(1,"mission observation fields/legacy-follow isolation");
        end
        if(valid && ascii_ok)$fatal(1,"binary byte leaked into ASCII command");
    end
    task send(input [7:0] b);
        begin @(negedge clk);byteval=b;valid=1;@(negedge clk);valid=0;end
    endtask
    initial begin
        $readmemh("sin11_request_frames.mem",requests);$readmemh("sin11_observation_frame.mem",observation);
        repeat(4)@(negedge clk);rst=1;
        for(k=0;k<40;k++)send(requests[k]);
        repeat(5)@(negedge clk);
        if(requests_seen!=1)$fatal(1,"CRC acceptance count %d",requests_seen);
        for(k=0;k<45;k++)send(observation[k]);
        repeat(5)@(negedge clk);
        if(observations_seen!=1)$fatal(1,"observation acceptance count");
        $display("SIN11_CRC_MISSION_ID_ASCII_ISOLATION_PASS");$finish;
    end
endmodule
