// SIN11: FPGA task lifecycle, bounded IMU search, alignment, approach, arrival.
// Pi sends perception only. M renews an existing mission; S always wins.
module vision_mission_guard #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer LEASE_MS=300, VISION_MS=1200,
    parameter integer TOTAL_MS=60000, LEG_MS=10000,
    parameter integer NEUTRAL_MS=150, DWELL_MS=1800,
    parameter integer ARRIVAL_TICKS=50,
    parameter integer VISUAL_PRIMARY=0,
    parameter integer CONTROLLED_ALIGN=0,
    parameter integer MISSION_REFINEMENT=0,
    parameter integer PERSISTENT_REACQUIRE=0,
    parameter integer RECOVERY_SEARCH=0,
    parameter integer RECOVERY_RUN_MS=500,RECOVERY_REST_MS=220,RECOVERY_WAIT_MS=300,
    parameter integer RECOVERY_SPEED=4,
    parameter integer ALIGN_RUN_MS=120,ALIGN_REST_MS=300,ALIGN_FRESH_MS=300,
    parameter integer APPROACH_REST_MS=ALIGN_REST_MS,OBSERVE_SETTLE_MS=0,
    parameter integer TWO_STAGE_APPROACH=0
)(
    input wire clk,rst_n,sample_tick_i,
    input wire [31:0] geometry_frame_i,
    input wire geometry_valid_i,geometry_beam_i,
    input wire signed [15:0] geometry_yaw_i,
    input wire [15:0] geometry_range_i,geometry_uncertainty_i,geometry_age_i,
    input wire request_i,input wire [31:0] request_id_i,
    input wire [15:0] request_class_i,request_distance_i,
    input wire request_red_i,request_inverted_i,
    input wire packet_i,input wire [15:0] packet_sequence_i,
    input wire [31:0] packet_mission_i,packet_lock_i,
    input wire [15:0] packet_class_i,input wire packet_red_i,
    input wire selected_i,visible_i,confirmed_i,
    input wire signed [15:0] center_i,yaw_i,
    input wire [15:0] distance_i,input wire distance_sample_i,
    input wire sensors_ok_i,hard_stop_i,motor_fault_i,other_active_i,cancel_i,
    input wire wheels_still_i,
    input wire ascii_valid_i,error_i,input wire [7:0] ascii_i,
    output reg active_o=0,output reg [31:0] id_o=0,lock_o=0,
    output reg [15:0] class_o=16'hffff,
    output reg [4:0] state_o=0,output reg [2:0] leg_o=0,
    output wire [2:0] command_o,output wire [15:0] speed_o
);
    localparam integer LEASE=(CLK_HZ/1000)*LEASE_MS,VISION=(CLK_HZ/1000)*VISION_MS;
    localparam integer TOTAL=(CLK_HZ/1000)*TOTAL_MS,LEG=(CLK_HZ/1000)*LEG_MS;
    localparam integer NEUTRAL=(CLK_HZ/1000)*NEUTRAL_MS,DWELL=(CLK_HZ/1000)*DWELL_MS;
    // 0 idle,1 searching,2 dwell/confirm,3 align,4 approach,5 arriving,
    // 6 success,7 exhausted,8 lease lost,9 perception lost,10 sensor/fault,
    // 11 total/leg timeout,12 cancelled,13 rejected,14 target lost/changed,
    // 15 heading budget fault,16 parked original-target recovery,
    // 17 bounded original-target yaw search.
    reg armed=0,seen_id=0,inverted=0,red=0;
    reg [31:0] last_id=0,perception_id=0,perception_lock=0;
    reg [15:0] perception_class=16'hffff,last_seq=0,arrival_mm=200;
    reg seen_packet=0,perception_red=0,present=0;
    reg signed [15:0] center=0,origin=0,heading=0;
    reg [31:0] lease_age=0,frame_age=VISION,total_age=0,leg_age=0,dwell_age=0;
    reg [31:0] neutral_age=0,direction_age=0;
    reg [7:0] arrival_ticks=0;
    reg [2:0] applied=0,desired;
    reg [15:0] desired_speed;
    reg [15:0] speed_reference=0;
    localparam integer ALIGN_RUN=(CLK_HZ/1000)*ALIGN_RUN_MS;
    localparam integer ALIGN_REST=(CLK_HZ/1000)*ALIGN_REST_MS;
    localparam integer APPROACH_REST=(CLK_HZ/1000)*APPROACH_REST_MS;
    localparam integer ALIGN_FRESH=(CLK_HZ/1000)*ALIGN_FRESH_MS;
    localparam integer ALIGN_MAX=ALIGN_RUN>ALIGN_REST?ALIGN_RUN:ALIGN_REST;
    localparam integer ALIGN_AGE_W=$clog2((ALIGN_MAX>APPROACH_REST?ALIGN_MAX:APPROACH_REST)+1);
    reg [1:0] align_phase=0; // 0 await new observation,1 bounded move,2 coast/observe
    reg [ALIGN_AGE_W-1:0] align_age=0;
    reg [2:0] align_direction=0;
    reg align_near=0;
    reg signed [15:0] alignment_yaw=0;
    // R11: one heading budget per uninterrupted alignment episode. A new
    // budget is acquired only after a completed alignment and a forward step,
    // never at every lateral pulse or centre-noise crossing.
    reg alignment_session=0;
    reg [1:0] centered_frames=0;
    reg [1:0] approach_phase=0;
    reg [ALIGN_AGE_W-1:0] approach_age=0;
    reg [15:0] range_anchor=0;
    reg [1:0] range_count=0,soft_near_count=0;
    reg [4:0] range_age=25;
    reg [3:0] approach_cap=8;
    // R14: retain the original task/token while fresh frames cannot confirm it.
    // R15 optionally adds bounded, low-speed yaw sweeps inside a small envelope;
    // it never changes the target identity and remains subordinate to all stops.
    // R16: a motion/encoder resettable quiet window, not merely elapsed time
    // since a missing frame. Two NEW confirmations must arrive after settling.
    // One extra sample excludes a partial first10ms interval from the minimum.
    localparam integer OBSERVE_TICKS=(OBSERVE_SETTLE_MS+9)/10+1;
    localparam integer OBSERVE_W=$clog2(OBSERVE_TICKS+1);
    reg [OBSERVE_W-1:0] observe_ticks=0;
    wire observation_ready=OBSERVE_SETTLE_MS==0 || observe_ticks>=OBSERVE_TICKS;
    reg [1:0] recovery_hits=0;
    localparam integer RECOVERY_RUN_TICKS=(RECOVERY_RUN_MS+9)/10;
    localparam integer RECOVERY_REST_TICKS=(RECOVERY_REST_MS+9)/10;
    localparam integer RECOVERY_WAIT_TICKS=(RECOVERY_WAIT_MS+9)/10;
    localparam integer RECOVERY_MAX_AGE=RECOVERY_RUN_TICKS>RECOVERY_REST_TICKS ?
        (RECOVERY_RUN_TICKS>RECOVERY_WAIT_TICKS?RECOVERY_RUN_TICKS:RECOVERY_WAIT_TICKS) :
        (RECOVERY_REST_TICKS>RECOVERY_WAIT_TICKS?RECOVERY_REST_TICKS:RECOVERY_WAIT_TICKS);
    localparam integer RECOVERY_AGE_W=$clog2(RECOVERY_MAX_AGE+1);
    reg [1:0] recovery_phase=0; // 0 parked, 1 short yaw nudge, 2 coast/observe
    reg [RECOVERY_AGE_W-1:0] recovery_age=0;
    reg recovery_direction=0; // alternate left/right about the captured heading
    reg signed [15:0] recovery_origin=0;
    reg recovery_blocked=0;
    reg recovery_candidate_seen=0;
    localparam integer RECOVERY_STEP=429;   // approximately +/-3 degrees
    localparam integer RECOVERY_LIMIT=572;  // approximately +/-4 degrees
    wire [16:0] range_delta=distance_i>=range_anchor ?
        {1'b0,distance_i}-{1'b0,range_anchor}:{1'b0,range_anchor}-{1'b0,distance_i};
    wire range_consistent=range_count==3 && range_age<25;
    wire refined_range_ok=!MISSION_REFINEMENT || range_consistent;
    function signed [15:0] wrap_heading(input signed [16:0] value);
        begin
            if(value>25736)wrap_heading=value-51472;
            else if(value< -25736)wrap_heading=value+51472;
            else wrap_heading=value;
        end
    endfunction
    wire signed [16:0] alignment_difference=$signed({alignment_yaw[15],alignment_yaw})-$signed({yaw_i[15],yaw_i});
    wire signed [16:0] alignment_error=alignment_difference>25736?alignment_difference-17'sd51472:
        alignment_difference< -25736?alignment_difference+17'sd51472:alignment_difference;
    wire alignment_heading_ok=alignment_error<=1144 && alignment_error>=-1144; // 8 degrees
    wire refined_heading_ok=!MISSION_REFINEMENT || !alignment_session || alignment_heading_ok;
    wire alignment_state=state_o==3 || state_o==4 || state_o==5;
    wire centered=center>=-1200 && center<=1200;
    // R12: departure and next-step authorization use the SAME outer bound.
    // Keep the inner1000/outer1200 hysteresis; no1200..1800 parked dead zone.
    wire approach_centered=MISSION_REFINEMENT ? centered_frames==3 && centered : centered;
    wire needs_alignment=MISSION_REFINEMENT ? !approach_centered : !centered;
    wire new_observation=packet_i && (!seen_packet || packet_sequence_i!=last_seq);
    wire matching_observation=packet_mission_i==id_o && packet_class_i==class_o &&
        packet_red_i==red && packet_lock_i==lock_o && selected_i && visible_i && confirmed_i;
    wire left_alignment=MISSION_REFINEMENT?center< -1000:center< -1200;
    wire right_alignment=MISSION_REFINEMENT?center>1000:center>1200;
    wire packet_needs_alignment=MISSION_REFINEMENT?(center_i< -1000 || center_i>1000):(center_i< -1200 || center_i>1200);
    wire [2:0] yaw_alignment_direction=((center_i<0)^inverted)?3'd5:3'd6;
    wire [2:0] packet_alignment_direction=TWO_STAGE_APPROACH ? yaw_alignment_direction : center_i<0?3'd3:3'd4;
    wire same_alignment_direction=TWO_STAGE_APPROACH ?
        align_direction==(((center<0)^inverted)?3'd5:3'd6) && (left_alignment || right_alignment) :
        (align_direction==3 && left_alignment)||(align_direction==4 && right_alignment);
    wire signed [16:0] difference=$signed(heading)-$signed({yaw_i[15],yaw_i});
    wire signed [16:0] err=difference>25736 ? difference-17'sd51472 :
                                 difference< -25736 ? difference+17'sd51472 : difference;
    wire [16:0] abs_err=err<0 ? -err : err;
    wire fresh=frame_age<VISION;
    wire identity_ok=fresh && perception_id==id_o && perception_class==class_o && perception_red==red;
    wire target_ok=identity_ok && present && perception_lock!=0;
    wire recovery_ascii_cancel=ascii_valid_i &&
        (ascii_i=="S" || ascii_i=="s" || ascii_i=="F" || ascii_i=="B" ||
         ascii_i=="L" || ascii_i=="R" || ascii_i=="V" || ascii_i=="G");
    wire recovery_safety_ok=sensors_ok_i && !hard_stop_i && !motor_fault_i &&
        !cancel_i && !error_i && !recovery_ascii_cancel;
    wire recoverable_miss=PERSISTENT_REACQUIRE && lock_o!=0 &&
        perception_id==id_o && perception_class==class_o && perception_red==red &&
        perception_lock==lock_o;
    wire recovery_same_packet=packet_i && packet_mission_i==id_o && packet_class_i==class_o &&
        packet_red_i==red && packet_lock_i==lock_o && selected_i;
    wire recovery_packet_abort=packet_i && (!new_observation || packet_mission_i!=id_o ||
        packet_class_i!=class_o || packet_red_i!=red || packet_lock_i!=lock_o || !selected_i);
    wire recovery_visible_packet=recovery_same_packet && visible_i;
    wire signed [15:0] recovery_goal_yaw=wrap_heading($signed({{16{recovery_origin[15]}},recovery_origin})+
        (recovery_direction ? RECOVERY_STEP : -RECOVERY_STEP));
    wire signed [15:0] recovery_error=wrap_heading($signed({{16{recovery_goal_yaw[15]}},recovery_goal_yaw})-
        $signed({{16{yaw_i[15]}},yaw_i}));
    wire [16:0] recovery_abs_error=recovery_error<0 ? -recovery_error : recovery_error;
    wire signed [15:0] recovery_offset=wrap_heading($signed({{16{yaw_i[15]}},yaw_i})-
        $signed({{16{recovery_origin[15]}},recovery_origin}));
    wire [16:0] recovery_abs_offset=recovery_offset<0 ? -recovery_offset : recovery_offset;
    // Search only with fresh/consistent ranging and while still outside the
    // requested arrival band; a lost image must never trigger rotation near it.
    wire recovery_range_safe=refined_range_ok && distance_i>125;
    wire recovery_search_range_safe=recovery_range_safe && distance_i>arrival_mm+25;
    wire recovery_envelope_ok=recovery_abs_offset<=RECOVERY_LIMIT ||
        (recovery_offset>RECOVERY_LIMIT && recovery_error<0) ||
        (recovery_offset< -RECOVERY_LIMIT && recovery_error>0);
    wire recovery_observation_safe=fresh && perception_id==id_o && perception_class==class_o &&
        perception_red==red && perception_lock==lock_o && !recovery_candidate_seen;
    wire recovery_motion_safe=active_o && recovery_safety_ok && recovery_observation_safe &&
        recovery_search_range_safe && recovery_envelope_ok && !recovery_blocked &&
        refined_heading_ok && fresh;
    wire recovery_search_active=PERSISTENT_REACQUIRE && RECOVERY_SEARCH && state_o==17 &&
        recovery_phase==1 && recovery_motion_safe && !recovery_visible_packet &&
        !matching_observation && !recovery_packet_abort;
    wire [2:0] recovery_search_command=recovery_abs_error<=143 ? 3'd0 :
        (((recovery_error>0)^inverted) ? 3'd5 : 3'd6);
    wire bounded_alignment=align_phase==1 && align_age<(TWO_STAGE_APPROACH?ALIGN_RUN/2:(align_near?ALIGN_RUN/2:ALIGN_RUN)) && frame_age<ALIGN_FRESH &&
        target_ok && same_alignment_direction && refined_heading_ok;
    wire bounded_approach=approach_phase==1 && approach_age<120*(CLK_HZ/1000) &&
        frame_age<ALIGN_FRESH && refined_range_ok && approach_centered;
    // Range clearance overrides *all* translation, including lateral alignment.
    // A non-centered target must not keep the robot moving at arrival distance.
    wire arrival_range=VISUAL_PRIMARY?1'b0:lock_o!=0 && distance_i<=arrival_mm+25;
    wire two_stage_forward,two_stage_final,two_stage_fine_ready;
    wire [15:0] two_stage_speed;
    generate if(TWO_STAGE_APPROACH)begin:g_two_stage
        mission_two_stage_approach #(.CLK_HZ(CLK_HZ)) u_approach(
            .clk(clk),.rst_n(rst_n),.active_i(active_o && lock_o!=0),.sample_tick_i(sample_tick_i),
            .target_ok_i(target_ok && perception_lock==lock_o && frame_age<ALIGN_FRESH),
            .range_ok_i(refined_range_ok),.centered_i(approach_centered),
            .eligible_i(alignment_state && (applied==1 || direction_age>=NEUTRAL)),
            .new_matching_i(new_observation && matching_observation),
            .distance_sample_i(distance_sample_i),.wheels_still_i(wheels_still_i),.motion_i(command_o!=0),
            .distance_i(distance_i),.arrival_i(arrival_mm),.speed_cap_i(approach_cap),
            .forward_o(two_stage_forward),.speed_o(two_stage_speed),
            .final_o(two_stage_final),.fine_ready_o(two_stage_fine_ready));
    end else begin:g_no_two_stage
        assign two_stage_forward=0;assign two_stage_speed=0;assign two_stage_final=0;assign two_stage_fine_ready=0;
    end endgenerate
    wire [2:0] visual_command;
    wire [15:0] visual_speed;
    wire visual_aligned,visual_near,visual_arrived,visual_heading_fault;
    generate if(VISUAL_PRIMARY)begin:g_visual_primary
        visual_primary_approach #(.ARRIVAL_TICKS(ARRIVAL_TICKS)) u_approach(
            .clk(clk),.rst_n(rst_n),.sample_tick_i(sample_tick_i),
            .active_i(active_o && alignment_state),.target_ok_i(target_ok && perception_lock==lock_o),
            .forward_applied_i(command_o==1),.inverted_i(inverted),.wheels_still_i(wheels_still_i),
            .sensors_ok_i(sensors_ok_i),.hard_stop_i(hard_stop_i),.motor_fault_i(motor_fault_i),
            .cancel_i(cancel_i || error_i || (ascii_valid_i && (ascii_i=="S" || ascii_i=="s"))),
            .packet_i(packet_i),.matching_i(matching_observation),.frame_i(geometry_frame_i),
            .geometry_valid_i(geometry_valid_i),.beam_inside_i(geometry_beam_i),
            .yaw_left_cdeg_i(geometry_yaw_i),.yaw_i(yaw_i),.coarse_mm_i(geometry_range_i),
            .uncertainty_mm_i(geometry_uncertainty_i),.observation_age_ms_i(geometry_age_i),
            .distance_sample_i(distance_sample_i),.distance_i(distance_i),.arrival_mm_i(arrival_mm),
            .command_o(visual_command),.speed_o(visual_speed),.aligned_o(visual_aligned),
            .near_o(visual_near),.arrived_o(visual_arrived),.heading_fault_o(visual_heading_fault),.phase_o());
    end else begin:g_legacy_visual
        assign visual_command=0;assign visual_speed=0;assign visual_aligned=0;
        assign visual_near=0;assign visual_arrived=0;assign visual_heading_fault=0;
    end endgenerate
    wire reacquire_stop=PERSISTENT_REACQUIRE && lock_o!=0 &&
        ((state_o==16 || state_o==17) && !recovery_search_active || !target_ok || perception_lock!=lock_o ||
         (packet_i && !matching_observation));
    assign command_o=recovery_search_active ? recovery_search_command :
        active_o && !arrival_range && !reacquire_stop &&
        (!MISSION_REFINEMENT || VISUAL_PRIMARY || (refined_range_ok &&
            (!(applied==1) || (TWO_STAGE_APPROACH?two_stage_forward:bounded_approach)))) &&
        (!CONTROLLED_ALIGN || (sensors_ok_i && !hard_stop_i && !motor_fault_i && !cancel_i && !error_i &&
            (!((applied==3 || applied==4) || (TWO_STAGE_APPROACH && alignment_state && (applied==5 || applied==6))) ||
             (bounded_alignment && (!two_stage_final || two_stage_fine_ready))))) &&
        (!VISUAL_PRIMARY || !alignment_state || applied==visual_command) ? applied : 0;
    assign speed_o=recovery_search_active ?
        (recovery_search_command==0 ? 16'd0 : RECOVERY_SPEED) :
        command_o==0 ? 0 : speed_reference;
    function signed [15:0] scan_heading(input signed [15:0] base,input [2:0] n,input inv);
        reg signed [31:0] delta,value;
        begin
            case(n) 0:delta=4289;1:delta=-4289;2:delta=8579;default:delta=-8579;endcase
            value=$signed(base)+(inv ? -delta : delta);
            scan_heading=value>25736 ? value-51472 : value< -25736 ? value+51472 : value;
        end
    endfunction
    always @* begin
        desired=0;desired_speed=0;
        if(state_o==1 && !target_ok)begin
            if(abs_err>286)begin desired=((err>0)^inverted)?5:6;desired_speed=abs_err<2145?8:12;end
        end else if(VISUAL_PRIMARY && alignment_state && target_ok)begin
            desired=visual_command;desired_speed=visual_speed;
        end else if((state_o==3 || state_o==4 || state_o==5) && target_ok && !arrival_range)begin
            if(TWO_STAGE_APPROACH)begin
                if(needs_alignment && (left_alignment || right_alignment))begin
                    desired=bounded_alignment && (!two_stage_final || two_stage_fine_ready)?align_direction:0;
                    desired_speed=4;
                end else if(two_stage_forward)begin desired=1;desired_speed=two_stage_speed;end
            end
            else if(needs_alignment && left_alignment)begin desired=CONTROLLED_ALIGN && !bounded_alignment?0:3;desired_speed=CONTROLLED_ALIGN?6:8;end
            else if(needs_alignment && right_alignment)begin desired=CONTROLLED_ALIGN && !bounded_alignment?0:4;desired_speed=CONTROLLED_ALIGN?6:8;end
            else if(approach_centered && distance_i>arrival_mm+25)begin
                desired=MISSION_REFINEMENT && !bounded_approach?0:1;
                desired_speed=MISSION_REFINEMENT?{12'd0,approach_cap}:distance_i>700?12:distance_i>450?10:8;
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active_o<=0;id_o<=0;lock_o<=0;class_o<=16'hffff;state_o<=0;leg_o<=0;
            armed<=0;seen_id<=0;last_id<=0;inverted<=0;red<=0;arrival_mm<=200;
            perception_id<=0;perception_lock<=0;perception_class<=16'hffff;perception_red<=0;
            present<=0;center<=0;last_seq<=0;seen_packet<=0;frame_age<=VISION;
            lease_age<=0;total_age<=0;leg_age<=0;dwell_age<=0;neutral_age<=0;
            direction_age<=0;applied<=0;arrival_ticks<=0;origin<=0;heading<=0;speed_reference<=0;
            align_phase<=0;align_age<=0;align_direction<=0;alignment_yaw<=0;align_near<=0;
            alignment_session<=0;centered_frames<=0;approach_phase<=0;approach_age<=0;
            range_anchor<=0;range_count<=0;range_age<=25;approach_cap<=8;soft_near_count<=0;
            observe_ticks<=0;
            recovery_hits<=0;recovery_phase<=0;recovery_age<=0;recovery_direction<=0;
            recovery_origin<=0;recovery_blocked<=0;recovery_candidate_seen<=0;
        end else begin
            // Break yaw-error/decision -> target scaling -> PI arithmetic path.
            // Motor enable/S/ToF gating stays independent and immediate.
            speed_reference<=desired_speed;
            if(!active_o || command_o!=0 || !wheels_still_i)observe_ticks<=0;
            else if(sample_tick_i && observe_ticks<OBSERVE_TICKS)observe_ticks<=observe_ticks+1'b1;
            if(MISSION_REFINEMENT)begin
                // Only real ToF commit strobes count as independent evidence.
                // A sudden far return stops motion; it cannot increase speed.
                // The live raw 100 mm hard stop remains completely upstream.
                if(sample_tick_i && range_age<25)range_age<=range_age+1'b1;
                if(distance_sample_i)begin
                    range_age<=0;range_anchor<=distance_i;
                    if(range_age>=25 || range_count==0 || range_delta>80)range_count<=1;
                    else if(range_count<3)range_count<=range_count+1'b1;
                    if(active_o && alignment_state)begin
                        if(distance_i<=450 && approach_cap>6)approach_cap<=6;
                        if(distance_i<=arrival_mm+150)approach_cap<=4;
                        if(distance_i+25<arrival_mm)begin
                            if(soft_near_count<3)soft_near_count<=soft_near_count+1'b1;
                        end else soft_near_count<=0;
                    end
                end
                if(new_observation && matching_observation && alignment_state)begin
                    if(center_i< -1200 || center_i>1200)centered_frames<=0;
                    else if(center_i>=-1000 && center_i<=1000 && wheels_still_i)begin
                        if(centered_frames<3)centered_frames<=centered_frames+1'b1;
                    end
                end
                if(TWO_STAGE_APPROACH)begin
                    approach_phase<=0;approach_age<=0;
                    if(command_o==1)alignment_session<=0;
                end else if(!active_o || !alignment_state || !target_ok || !approach_centered || arrival_range || !refined_range_ok)begin
                    approach_phase<=0;approach_age<=0;
                end else if(approach_phase==0)begin
                    if(new_observation && matching_observation && wheels_still_i &&
                       direction_age>=NEUTRAL && center_i>=-1200 && center_i<=1200)begin
                        approach_phase<=1;approach_age<=0;alignment_session<=0;
                    end
                end else if(approach_phase==1)begin
                    if(approach_age>=120*(CLK_HZ/1000))begin approach_phase<=2;approach_age<=0;end
                    else approach_age<=approach_age+1'b1;
                end else if(approach_phase==2)begin
                    if(approach_age<APPROACH_REST)approach_age<=approach_age+1'b1;
                    else if(wheels_still_i)begin approach_phase<=0;approach_age<=0;end
                end
            end
            if(CONTROLLED_ALIGN)begin
                if(!active_o || !alignment_state || !target_ok || arrival_range || !needs_alignment)begin
                    align_phase<=0;align_age<=0;align_direction<=0;
                end else if(align_phase==0)begin
                    // A packet captured while coasting cannot authorize a later
                    // move. Require a NEW same-identity observation after still.
                    if(new_observation && matching_observation && wheels_still_i &&
                       direction_age>=NEUTRAL && observation_ready && refined_heading_ok && packet_needs_alignment && refined_range_ok)begin
                        align_phase<=1;align_age<=0;align_direction<=packet_alignment_direction;
                        align_near<=center_i>=-2400 && center_i<=2400;
                        if(MISSION_REFINEMENT && !alignment_session)begin alignment_yaw<=yaw_i;alignment_session<=1;end
                    end
                end else if(align_phase==1)begin
                    if(align_age>=(TWO_STAGE_APPROACH?ALIGN_RUN/2:(align_near?ALIGN_RUN/2:ALIGN_RUN)) || !same_alignment_direction || frame_age>=ALIGN_FRESH)begin
                        align_phase<=2;align_age<=0;
                    end else align_age<=align_age+1'b1;
                end else if(align_phase==2)begin
                    if(align_age<ALIGN_REST)align_age<=align_age+1'b1;
                    else if(wheels_still_i)begin align_phase<=0;align_age<=0;end
                end
            end
            if(frame_age<VISION)frame_age<=frame_age+1'b1;
            if(packet_i && (!seen_packet || packet_sequence_i!=last_seq))begin
                seen_packet<=1;last_seq<=packet_sequence_i;frame_age<=0;
                perception_id<=packet_mission_i;perception_lock<=packet_lock_i;
                perception_class<=packet_class_i;perception_red<=packet_red_i;
                present<=selected_i && visible_i && confirmed_i;center<=center_i;
                if(recovery_same_packet)recovery_candidate_seen<=visible_i;
            end
            if(applied==0)begin if(direction_age<NEUTRAL)direction_age<=direction_age+1'b1;end
            else direction_age<=0;
            if(!active_o)begin
                applied<=0;if(neutral_age<NEUTRAL)neutral_age<=neutral_age+1'b1;
            end else begin
                neutral_age<=0;lease_age<=lease_age+1'b1;
                if(!(PERSISTENT_REACQUIRE && (state_o==16 || state_o==17)))total_age<=total_age+1'b1;
                if(ascii_valid_i && ascii_i=="M")lease_age<=0;
                if(applied!=0 && desired!=applied)begin applied<=0;direction_age<=0;end
                else if(applied==0 && direction_age>=NEUTRAL)applied<=desired;
                if(state_o==1 || state_o==2)begin
                    leg_age<=leg_age+1'b1;
                    if(target_ok)begin
                        lock_o<=perception_lock;state_o<=3;applied<=0;direction_age<=0;
                        alignment_yaw<=yaw_i;
                    end else if(state_o==1 && abs_err<=286)begin state_o<=2;dwell_age<=0;end
                    else if(state_o==2)begin
                        dwell_age<=dwell_age+1'b1;
                        if(abs_err>429)begin state_o<=1;dwell_age<=0;end
                        else if(dwell_age>=DWELL)begin
                            if(leg_o==3)begin active_o<=0;state_o<=7;end
                            else begin leg_o<=leg_o+1'b1;heading<=scan_heading(origin,leg_o+1'b1,inverted);
                                leg_age<=0;state_o<=1;end
                        end
                    end
                    if(leg_age>=LEG)begin active_o<=0;state_o<=11;end
                end else if(PERSISTENT_REACQUIRE && state_o==16)begin
                    applied<=0;arrival_ticks<=0;
                    if(new_observation && matching_observation)begin
                        // Two distinct confirmations of the retained token,
                        // stopped wheels, fresh range and the original heading
                        // budget are required before resuming the same task.
                        if(wheels_still_i && observation_ready && recovery_range_safe && direction_age>=NEUTRAL && refined_heading_ok)begin
                            if(recovery_hits<2)recovery_hits<=recovery_hits+1'b1;
                            if(recovery_hits>=1)begin
                                state_o<=3;recovery_hits<=0;recovery_phase<=0;recovery_age<=0;
                                recovery_candidate_seen<=0;centered_frames<=0;
                                range_count<=0;range_age<=25;applied<=0;direction_age<=0;
                            end
                        end else recovery_hits<=0;
                    end else begin
                        if(new_observation)recovery_hits<=0;
                        if(!RECOVERY_SEARCH || !recovery_safety_ok || !recovery_search_range_safe ||
                           !refined_heading_ok || recovery_candidate_seen || !recoverable_miss)begin
                            recovery_phase<=0;recovery_age<=0;
                        end else if(recovery_phase==2)begin
                            if(sample_tick_i && recovery_age<RECOVERY_REST_TICKS)
                                recovery_age<=recovery_age+1'b1;
                            else if(recovery_age>=RECOVERY_REST_TICKS && wheels_still_i)begin
                                recovery_phase<=0;recovery_age<=RECOVERY_WAIT_TICKS;
                            end
                        end else begin
                            if(sample_tick_i && recovery_age<RECOVERY_WAIT_TICKS)
                                recovery_age<=recovery_age+1'b1;
                            if(recovery_age>=RECOVERY_WAIT_TICKS && observation_ready && wheels_still_i && direction_age>=NEUTRAL)begin
                                recovery_phase<=1;state_o<=17;recovery_age<=0;
                            end
                        end
                    end
                end else if(PERSISTENT_REACQUIRE && state_o==17)begin
                    applied<=0;arrival_ticks<=0;
                    if(new_observation && matching_observation)begin
                        state_o<=16;recovery_phase<=2;recovery_age<=0;
                        if(wheels_still_i && observation_ready && recovery_range_safe && direction_age>=NEUTRAL && refined_heading_ok)begin
                            if(recovery_hits<2)recovery_hits<=recovery_hits+1'b1;
                            if(recovery_hits>=1)begin
                                state_o<=3;recovery_hits<=0;recovery_phase<=0;
                                recovery_candidate_seen<=0;centered_frames<=0;
                                range_count<=0;range_age<=25;direction_age<=0;
                            end
                        end else recovery_hits<=0;
                    end else if(recovery_visible_packet)begin
                        state_o<=16;recovery_phase<=2;recovery_age<=0;recovery_hits<=0;
                    end else if(!recovery_motion_safe)begin
                        state_o<=16;recovery_phase<=2;recovery_age<=0;
                    end else if(sample_tick_i)begin
                        if(recovery_abs_error<=143 || recovery_age>=RECOVERY_RUN_TICKS-1)begin
                            state_o<=16;recovery_phase<=2;recovery_age<=0;
                            recovery_direction<=~recovery_direction;
                        end else recovery_age<=recovery_age+1'b1;
                    end
                end else if(state_o==3 || state_o==4 || state_o==5)begin
                    if(!target_ok || perception_lock!=lock_o)begin
                        if(PERSISTENT_REACQUIRE && recoverable_miss)begin
                            state_o<=16;applied<=0;direction_age<=0;arrival_ticks<=0;
                            recovery_hits<=0;centered_frames<=0;range_count<=0;range_age<=25;
                            recovery_phase<=0;recovery_age<=0;recovery_direction<=0;
                            recovery_origin<=yaw_i;recovery_blocked<=0;recovery_candidate_seen<=visible_i;
                            if(!alignment_session)begin alignment_yaw<=yaw_i;alignment_session<=1;end
                        end else begin active_o<=0;state_o<=14;end
                    end
                    else if(VISUAL_PRIMARY)begin
                        if(visual_heading_fault)begin active_o<=0;state_o<=15;applied<=0;end
                        else if(visual_near)begin active_o<=0;state_o<=10;applied<=0;end
                        else if(visual_arrived)begin active_o<=0;state_o<=6;applied<=0;end
                        else if(!visual_aligned)state_o<=3;
                        else if(visual_command==1)state_o<=4;
                        else state_o<=5;
                    end
                    else if(distance_i+25<arrival_mm)begin
                        arrival_ticks<=0;
                        if(!MISSION_REFINEMENT || soft_near_count==3)begin active_o<=0;state_o<=10;end
                        else state_o<=5;
                    end
                    else if(needs_alignment)begin state_o<=3;arrival_ticks<=0;end
                    else if(distance_i>arrival_mm+25)begin state_o<=4;arrival_ticks<=0;end
                    else begin
                        state_o<=5;
                        if(MISSION_REFINEMENT && (!wheels_still_i || !range_consistent || !centered))arrival_ticks<=0;
                        else if(sample_tick_i)begin
                            if(arrival_ticks>=ARRIVAL_TICKS-1)begin active_o<=0;state_o<=6;end
                            else arrival_ticks<=arrival_ticks+1'b1;
                        end
                    end
                end
                if(packet_i && lock_o!=0 && alignment_state &&
                   (!selected_i || !visible_i || !confirmed_i || packet_lock_i!=lock_o))begin
                    if(PERSISTENT_REACQUIRE && selected_i && packet_lock_i==lock_o &&
                       packet_mission_i==id_o && packet_class_i==class_o && packet_red_i==red)begin
                        state_o<=16;applied<=0;arrival_ticks<=0;recovery_hits<=0;
                        if(state_o!=16 && state_o!=17)begin
                            direction_age<=0;centered_frames<=0;range_count<=0;range_age<=25;
                            recovery_phase<=0;recovery_age<=0;recovery_direction<=0;
                            recovery_origin<=yaw_i;recovery_blocked<=0;
                            recovery_candidate_seen<=visible_i;
                            if(!alignment_session)begin alignment_yaw<=yaw_i;alignment_session<=1;end
                        end
                    end else begin active_o<=0;state_o<=14;end
                end
                // Independent terminal conditions win over a recoverable miss.
                if(!fresh)begin active_o<=0;state_o<=9;end
                if(!identity_ok && fresh)begin active_o<=0;state_o<=12;end
                if(lease_age>=LEASE)begin active_o<=0;state_o<=8;end
                if(total_age>=TOTAL && !(PERSISTENT_REACQUIRE && (state_o==16 || state_o==17)))begin active_o<=0;state_o<=11;end
                if(!VISUAL_PRIMARY && CONTROLLED_ALIGN &&
                   ((alignment_state && needs_alignment) || (PERSISTENT_REACQUIRE && (state_o==16 || state_o==17) && alignment_session)) && !refined_heading_ok)begin
                    active_o<=0;state_o<=15;applied<=0;
                end
                if(!sensors_ok_i || hard_stop_i || motor_fault_i || error_i)begin active_o<=0;state_o<=10;end
                if(packet_i && (packet_mission_i!=id_o || packet_class_i!=class_o || packet_red_i!=red))begin
                    active_o<=0;state_o<=12;
                end
            end
            if(request_i && !active_o && (!seen_id || request_id_i!=last_id))begin
                seen_id<=1;last_id<=request_id_i;id_o<=request_id_i;class_o<=request_class_i;
                lock_o<=0;armed<=0;
                if(armed && neutral_age>=NEUTRAL && sensors_ok_i && !hard_stop_i && !motor_fault_i &&
                   !other_active_i && !error_i && fresh && perception_id==request_id_i &&
                   perception_class==request_class_i && perception_red==request_red_i)begin
                    active_o<=1;state_o<=1;leg_o<=0;origin<=yaw_i;
                    heading<=scan_heading(yaw_i,0,request_inverted_i);
                    arrival_mm<=request_distance_i;inverted<=request_inverted_i;red<=request_red_i;
                    lease_age<=0;total_age<=0;leg_age<=0;dwell_age<=0;arrival_ticks<=0;
                    applied<=0;direction_age<=0;
                    align_phase<=0;align_age<=0;align_direction<=0;
                    alignment_session<=0;centered_frames<=0;approach_phase<=0;approach_age<=0;
                    approach_cap<=8;soft_near_count<=0;range_count<=0;range_age<=25;
                    recovery_hits<=0;recovery_phase<=0;recovery_age<=0;recovery_direction<=0;
                    recovery_origin<=yaw_i;recovery_blocked<=0;recovery_candidate_seen<=0;
                end else begin active_o<=0;state_o<=13;end
            end
            if(cancel_i || (ascii_valid_i && (ascii_i=="F" || ascii_i=="B" || ascii_i=="L" ||
                   ascii_i=="R" || ascii_i=="V" || ascii_i=="G")))begin
                if(active_o)state_o<=12;active_o<=0;armed<=0;applied<=0;
            end
            if(ascii_valid_i && (ascii_i=="S" || ascii_i=="s"))begin
                if(active_o)state_o<=12;
                active_o<=0;armed<=1;applied<=0;neutral_age<=0;
            end
        end
    end
endmodule
