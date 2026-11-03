`timescale 1ns/1ps
module tb_visual_primary_parser;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,bv=0;reg [7:0] b=0;reg [7:0] bytes[0:313];
    wire valid,legacy_valid,gvalid,beam;wire signed [15:0] yaw;
    wire [15:0] range_mm,uncertainty,age,seq;wire [31:0] frame,mission,lockid;
    integer n=0,oldn=0,i;
    vision_packet_parser #(.ENABLE_VISUAL_PRIMARY(1)) dut(.clk(clk),.rst_n(rst),.byte_i(b),.byte_valid_i(bv),
        .vision_valid_o(valid),.geometry_valid_o(gvalid),.geometry_beam_o(beam),.geometry_yaw_o(yaw),
        .geometry_range_o(range_mm),.geometry_uncertainty_o(uncertainty),.geometry_age_o(age),
        .sequence_o(seq),.frame_id_o(frame),.mission_id_o(mission),.lock_id_o(lockid),
        .mission_red_o(),.heartbeat_valid_o(),.selection_valid_o(),.follow_requested_o(),.nav_goal_valid_o(),.nav_goal_x_o(),.nav_goal_y_o(),.target_present_o(),.target_confirmed_o(),.target_centered_o(),.alignment_o(),.class_id_o(),.confidence_o(),.center_x_o(),.center_y_o(),.width_o(),.height_o(),.center_error_o(),.area_ratio_o(),.crc_error_count_o());
    vision_packet_parser legacy(.clk(clk),.rst_n(rst),.byte_i(b),.byte_valid_i(bv),.vision_valid_o(legacy_valid),
        .geometry_valid_o(),.geometry_beam_o(),.geometry_yaw_o(),.geometry_range_o(),.geometry_uncertainty_o(),.geometry_age_o(),.mission_id_o(),.mission_red_o(),.heartbeat_valid_o(),.selection_valid_o(),.follow_requested_o(),.lock_id_o(),.nav_goal_valid_o(),.nav_goal_x_o(),.nav_goal_y_o(),.target_present_o(),.target_confirmed_o(),.target_centered_o(),.alignment_o(),.class_id_o(),.confidence_o(),.center_x_o(),.center_y_o(),.width_o(),.height_o(),.center_error_o(),.area_ratio_o(),.frame_id_o(),.sequence_o(),.crc_error_count_o());
    always @(negedge clk)begin
        if(valid)begin
            n=n+1;
            if(n==1 && (!gvalid || !beam || yaw!=34 || range_mm!=500 || uncertainty!=200 || age!=10 || frame!=1 || seq!=10 || mission!=1 || lockid!=2))
                $fatal(1,"0x16 producer/parser mismatch");
            if(n==2 && gvalid)$fatal(1,"legacy mission reused geometry");
            if(n==3 && (!gvalid || beam || yaw!= -200 || frame!=3))$fatal(1,"new geometry wrong");
        end
        if(legacy_valid)oldn=oldn+1;
    end
    initial begin
        $readmemh("visual_primary_protocol.hex",bytes);
        repeat(3)@(negedge clk);rst=1;
        for(i=0;i<314;i=i+1)begin @(negedge clk);b=bytes[i];bv=1;@(negedge clk);bv=0;end
        repeat(3)@(negedge clk);
        if(n!=3 || oldn!=1)$fatal(1,"CRC/format/legacy isolation failed new%0d old%0d",n,oldn);
        $display("VISUAL_PRIMARY_PYTHON_CRC_PARSER_LEGACY_ISOLATION_PASS");$finish;
    end
endmodule

