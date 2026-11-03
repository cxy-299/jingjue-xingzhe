// EXPERIMENTAL smart-mission-only controller. No direct PWM/IN outputs.
// Camera geometry is advisory; only fresh, independently committed ToF returns
// inside the calibrated visual envelope authorize forward motion or arrival.
// sample_tick_i MUST be the existing 10 ms epoch. No change to upstream safety.
module visual_primary_approach #(
    parameter integer ARRIVAL_TICKS=50
)(
    input wire clk,rst_n,sample_tick_i,active_i,target_ok_i,wheels_still_i,
    input wire forward_applied_i,inverted_i,
    input wire sensors_ok_i,hard_stop_i,motor_fault_i,cancel_i,
    input wire packet_i,matching_i,
    input wire [31:0] frame_i,
    input wire geometry_valid_i,beam_inside_i,
    input wire signed [15:0] yaw_left_cdeg_i,yaw_i,
    input wire [15:0] coarse_mm_i,uncertainty_mm_i,observation_age_ms_i,
    input wire distance_sample_i,input wire [15:0] distance_i,arrival_mm_i,
    output wire [2:0] command_o,output wire [15:0] speed_o,
    output wire aligned_o,near_o,arrived_o,heading_fault_o,
    output reg [2:0] phase_o=0
);
    // phase0 await qualified observation,1 yaw pulse,2 neutral/new observation,
    // 3 fresh-return cross-check,4 continuous fresh approach,5 arrival confirm.
    reg seen=0,valid=0,beam=0,budget=0;
    reg [31:0] last_frame=0;
    reg [8:0] visual_age=300;
    reg [4:0] range_age=25,turn_ticks=0,neutral_ticks=0;
    reg [1:0] hits=0;
    reg [7:0] arrival_ticks=0;
    reg [15:0] coarse=0,uncertainty=0,anchor=0;
    reg signed [15:0] bearing=0,origin=0,turn_origin=0;
    reg [15:0] turn_goal=0;
    reg [2:0] turn=0;
    reg [3:0] cap=8;
    reg done=0;
    wire new_frame=packet_i && (!seen || frame_i!=last_frame);
    wire new_good=new_frame && matching_i && geometry_valid_i &&
        observation_age_ms_i<280 && coarse_mm_i>=150 && coarse_mm_i<=10000 &&
        uncertainty_mm_i>=20 && uncertainty_mm_i<=coarse_mm_i/2 &&
        yaw_left_cdeg_i>=-4500 && yaw_left_cdeg_i<=4500;
    wire fresh=valid && visual_age<300 && target_ok_i;
    wire centered=bearing>=-100 && bearing<=100 && beam;
    wire packet_centered=yaw_left_cdeg_i>=-100 && yaw_left_cdeg_i<=100 && beam_inside_i;
    wire [16:0] low_range=coarse>uncertainty?{1'b0,coarse}-{1'b0,uncertainty}:0;
    wire [16:0] high_range={1'b0,coarse}+{1'b0,uncertainty};
    wire [16:0] delta=distance_i>=anchor?{1'b0,distance_i}-{1'b0,anchor}:{1'b0,anchor}-{1'b0,distance_i};
    wire in_envelope={1'b0,distance_i}>=low_range && {1'b0,distance_i}<=high_range;
    wire consistent=hits==3 && range_age<25 && in_envelope &&
        (!distance_sample_i || delta<=80);
    wire signed [16:0] raw_yaw=$signed({yaw_i[15],yaw_i})-$signed({origin[15],origin});
    wire signed [16:0] yaw_error=raw_yaw>25736?raw_yaw-17'sd51472:
        raw_yaw< -25736?raw_yaw+17'sd51472:raw_yaw;
    assign heading_fault_o=budget && (yaw_error>1144 || yaw_error< -1144); // original 8deg
    // Snapshot a <=6deg camera correction, then use FAST IMU feedback to stop
    // and taper rotation before waiting for another expensive detector frame.
    // 183/128 Q13 per centidegree: shift/add only, no DSP or divider.
    wire [15:0] abs_bearing=yaw_left_cdeg_i[15]?-yaw_left_cdeg_i:yaw_left_cdeg_i;
    wire [9:0] clipped_bearing=abs_bearing>600?10'd600:abs_bearing[9:0];
    wire [19:0] scaled_bearing=({10'd0,clipped_bearing}<<7)+({10'd0,clipped_bearing}<<5)+
        ({10'd0,clipped_bearing}<<4)+({10'd0,clipped_bearing}<<2)+
        ({10'd0,clipped_bearing}<<1)+{10'd0,clipped_bearing};
    wire signed [16:0] turn_raw=$signed({yaw_i[15],yaw_i})-$signed({turn_origin[15],turn_origin});
    wire signed [16:0] turn_wrapped=turn_raw>25736?turn_raw-17'sd51472:
        turn_raw< -25736?turn_raw+17'sd51472:turn_raw;
    wire signed [16:0] turn_progress=inverted_i?-turn_wrapped:turn_wrapped;
    wire signed [17:0] turn_remaining=turn==5?$signed({2'b0,turn_goal})-turn_progress:
        $signed({2'b0,turn_goal})+turn_progress;
    wire safe=active_i && fresh && sensors_ok_i && !hard_stop_i &&
        !motor_fault_i && !cancel_i && !heading_fault_o;
    // Live close-range safety is upstream too. Never reverse to manufacture arrival.
    assign near_o=consistent && distance_i+25<arrival_mm_i;
    assign aligned_o=fresh && centered;
    assign command_o=!safe || done || near_o ? 0 :
        phase_o==1 && turn_ticks<12 && turn_remaining>72 && ((turn==5 && bearing>100)||(turn==6 && bearing< -100)) ? turn :
        phase_o==4 && centered && consistent && distance_i>arrival_mm_i+25 ? 3'd1 : 3'd0;
    assign speed_o=command_o==0?16'd0:command_o==1?{12'd0,cap}:turn_remaining<=286?16'd4:16'd6;
    assign arrived_o=done && safe;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            phase_o<=0;seen<=0;valid<=0;beam<=0;budget<=0;last_frame<=0;
            visual_age<=300;range_age<=25;turn_ticks<=0;neutral_ticks<=0;hits<=0;
            arrival_ticks<=0;coarse<=0;uncertainty<=0;anchor<=0;bearing<=0;origin<=0;
            turn<=0;cap<=8;done<=0;turn_origin<=0;turn_goal<=0;
        end else if(!active_i)begin
            phase_o<=0;valid<=0;beam<=0;budget<=0;visual_age<=300;range_age<=25;
            turn_ticks<=0;neutral_ticks<=0;hits<=0;arrival_ticks<=0;turn<=0;cap<=8;done<=0;
            // Keep frame dedup across inactive/start: a replay is not new evidence.
            if(packet_i)begin seen<=1;last_frame<=frame_i;end
        end else begin
            if(sample_tick_i)begin
                if(visual_age<300)visual_age<=visual_age>289?300:visual_age+10;
                if(range_age<25)range_age<=range_age+1'b1;
                if(phase_o==1 && turn_ticks<12)turn_ticks<=turn_ticks+1'b1;
                if((phase_o==0 || phase_o==2) && wheels_still_i && neutral_ticks<15)
                    neutral_ticks<=neutral_ticks+1'b1;
                else if(!wheels_still_i)neutral_ticks<=0;
            end
            if(new_frame)begin
                seen<=1;last_frame<=frame_i;
                valid<=new_good;visual_age<=new_good?observation_age_ms_i[8:0]+20:300;
                beam<=beam_inside_i;bearing<=yaw_left_cdeg_i;
                coarse<=coarse_mm_i;uncertainty<=uncertainty_mm_i;
                if(!new_good || !packet_centered)begin hits<=0;range_age<=25;arrival_ticks<=0;end
            end
            // No observation -> no prediction-based cruising. After a gap, stop
            // and reacquire THREE independent ToF commits; never reuse old hits.
            if(!safe)begin phase_o<=0;hits<=0;range_age<=25;arrival_ticks<=0;turn<=0;neutral_ticks<=0;end
            else begin
                if(phase_o==0 || phase_o==2)begin
                    if(new_good && wheels_still_i && neutral_ticks>=15)begin
                        if(packet_centered)begin phase_o<=3;hits<=0;range_age<=25;end
                        else begin
                            phase_o<=1;turn<=yaw_left_cdeg_i>0?5:6;turn_ticks<=0;
                            turn_origin<=yaw_i;turn_goal<=scaled_bearing[19:7];
                            if(!budget)begin origin<=yaw_i;budget<=1;end
                        end
                    end
                end else if(phase_o==1)begin
                    if(turn_ticks>=12 || turn_remaining<=72 || centered ||
                       (turn==5 && bearing< -100)||(turn==6 && bearing>100))begin
                        phase_o<=2;neutral_ticks<=0;turn<=0;
                    end
                end else if(phase_o==3 || phase_o==4 || phase_o==5)begin
                    if(!centered)begin phase_o<=2;neutral_ticks<=0;hits<=0;arrival_ticks<=0;end
                    else begin
                        if(distance_sample_i)begin
                            anchor<=distance_i;range_age<=0;
                            if(!in_envelope)begin hits<=0;arrival_ticks<=0;phase_o<=3;end
                            else if(hits==0 || range_age>=25 || delta>80)begin hits<=1;arrival_ticks<=0;phase_o<=3;end
                            else if(hits<3)hits<=hits+1'b1;
                            if(distance_i<=450 && cap>6)cap<=6;
                            if(distance_i<=arrival_mm_i+150)cap<=4;
                        end
                        if(!consistent)begin phase_o<=3;arrival_ticks<=0;end
                        else if(distance_i<=arrival_mm_i+25)begin
                            phase_o<=5;
                            if(sample_tick_i && wheels_still_i && !near_o)begin
                                if(arrival_ticks>=ARRIVAL_TICKS-1)done<=1;
                                else arrival_ticks<=arrival_ticks+1'b1;
                            end else if(!wheels_still_i)arrival_ticks<=0;
                        end else begin phase_o<=4;arrival_ticks<=0;end
                    end
                end
            end
            if(forward_applied_i)budget<=0; // only actual parent-applied forward motion
        end
    end
endmodule

