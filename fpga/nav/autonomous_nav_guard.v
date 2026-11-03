// SIN12: bounded FPGA goal planning, fresh cardinal ToF scans, online occupancy,
// and forward-only waypoint driving. Base yaw is the field +Y heading at start.
// Geometry/odometry assume a level, known test field and a centred rotation pivot.
// A single ToF does NOT establish a complete collision-free swept volume.
module autonomous_nav_guard #(
    parameter integer CELL_COUNTS=1000,
    parameter integer LEASE_TICKS=30,
    parameter integer MAX_TICKS=30000,
    parameter integer LEG_TICKS=1500,
    parameter integer NEUTRAL_TICKS=20,
    parameter integer SETTLE_TICKS=20,
    parameter integer PROBE_FRAMES=3,
    parameter integer EARLY_STOP_MM=400,
    parameter integer INFLATE_MM=210,
    parameter [399:0] MAP_BITS=0,
    parameter integer LOCAL_MAP_ENABLE=0,
    parameter integer CANCEL_PIPELINE=0,
    parameter integer PROGRESS_CONTROL=0,
    parameter integer CONFIRMED_MAPPING=0,
    // Nearest-mm projection for odd counts/cell; old revisions keep truncation.
    parameter integer ROUND_POSE_MM=0,
    parameter integer RANGE_SPREAD_MM=50,
    parameter integer MAP_STILL_TICKS=5,
    // R18: explicit left/forward/right dogleg; older planner is unchanged.
    parameter integer FIXED_LEFT_DETOUR=0,
    // R19 extends the middle of the dogleg to three individually checked cells.
    // Defaults preserve the previously validated R18 and older behaviour.
    parameter integer DETOUR_FORWARD_CELLS=1,
    parameter integer LATCH_NEAR_EVENT=0,
    parameter integer ADAPTIVE_DETOUR=0,
    parameter integer CONSERVATIVE_CELLS=0
)(
    input wire clk,rst_n,sample_tick_i,request_i,
    input wire [15:0] sequence_i,
    input wire [7:0] sx_i,sy_i,gx_i,gy_i,flags_i,speed_i,
    input wire [15:0] counts_i,
    input wire signed [15:0] setback_i,yaw_i,
    input wire sensors_ok_i,hard_stop_i,motor_fault_i,other_active_i,cancel_i,
    input wire ascii_valid_i,error_i,input wire [7:0] ascii_i,
    input wire tof_sample_i,input wire [15:0] distance_i,
    input wire [31:0] position0_i,position1_i,position2_i,position3_i,
    output reg active_o=0,fault_o=0,
    output reg [7:0] state_o=0,reason_o=0,replans_o=0,
    output reg [15:0] sequence_o=0,
    output wire [7:0] x_o,y_o,
    output reg [7:0] gx_o=0,gy_o=0,
    output reg [7:0] obstacle_x_o=8'hff,obstacle_y_o=8'hff,
    output wire [2:0] command_o,output wire [15:0] speed_o,
    output reg local_mode_o=0
);
    // Only internal bookkeeping is pipelined. Physical command gating checks
    // BOTH live and registered cancel, so a one-cycle cancel can never rebound.
    reg cancel_q=0;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)cancel_q<=0;else cancel_q<=cancel_i;
    wire cancel_state=CANCEL_PIPELINE ? cancel_q:cancel_i;
    localparam IDLE=0,PLAN=1,PLAN_WAIT=2,WAYPOINT=3,TURN=4,
        PROBE=6,MOVE=7,BRAKE=8,MARK=9,SCAN_NEXT=10,DONE=11,FAILED=12,PROJECT=13,REOBSERVE=14,
        DETOUR=15;
    reg armed=0,seen=0,inverted=0,last_local=0;
    reg [15:0] last_seq=0;
    reg [15:0] lease=0,age=0,leg_age=0,neutral=0,settled=0,probe_age=0;
    reg [7:0] velocity=8;
    reg signed [15:0] reference_yaw=0,setback=0;
    reg signed [31:0] px=0,py=0,tx=0,ty=0,base_x=0,base_y=0,travel=0;
    reg [31:0] b0=0,b1=0,b2=0,b3=0;
    reg [1:0] direction=0,blocked_direction=0,scan_phase=0;
    reg blocked_leg=0;
    reg turn_running=0,finishing=0;
    reg waypoint_is_goal=0,completed_leg=0;
    reg [2:0] detour_leg=0;
    reg [1:0] detour_heading=0;
    reg signed [31:0] detour_x=0,detour_y=0;
    reg restore_detour_heading=0;
    reg safe_start_escape=0;
    function signed [31:0] step_x(input [1:0] d);
        begin step_x=d==3?CELL_COUNTS:d==1?-CELL_COUNTS:0;end
    endfunction
    function signed [31:0] step_y(input [1:0] d);
        begin step_y=d==0?CELL_COUNTS:d==2?-CELL_COUNTS:0;end
    endfunction
    wire [1:0] detour_left=detour_heading+2'd1;
    localparam integer DETOUR_LAST_LEG=DETOUR_FORWARD_CELLS+2;
    wire [2:0] detour_forward_steps=detour_leg<=1?0:
        DETOUR_FORWARD_CELLS==1?1:detour_leg==2?1:detour_leg==3?2:3;
    wire signed [31:0] detour_forward_counts=detour_forward_steps==3?3*CELL_COUNTS:
        detour_forward_steps==2?2*CELL_COUNTS:detour_forward_steps==1?CELL_COUNTS:0;
    // Select precomputed NEGATIVE constants too. Negating a variable mux result
    // adds a full-width carry chain before the target adder and increases routing
    // pressure. These are the exact same signed offsets, with no run-time negate.
    wire signed [31:0] detour_forward_negative=detour_forward_steps==3?-3*CELL_COUNTS:
        detour_forward_steps==2?-2*CELL_COUNTS:detour_forward_steps==1?-CELL_COUNTS:0;
    // Perpendicular offsets never add on the same axis. Select one constant
    // displacement before the single carry chain, then pipeline target, cell,
    // index and map lookup. DETOUR is parked and waits for this full pipeline.
    wire signed [31:0] detour_delta_x=detour_leg<DETOUR_LAST_LEG && detour_left[0] ? step_x(detour_left):
        detour_heading==3?detour_forward_counts:detour_heading==1?detour_forward_negative:0;
    wire signed [31:0] detour_delta_y=detour_leg<DETOUR_LAST_LEG && !detour_left[0] ? step_y(detour_left):
        detour_heading==0?detour_forward_counts:detour_heading==2?detour_forward_negative:0;
    reg signed [31:0] detour_target_x=0,detour_target_y=0;
    reg [7:0] detour_cell_x=0,detour_cell_y=0;
    reg [8:0] detour_cell=0;
    reg [10:0] detour_edge=0;
    reg detour_target_valid=0,detour_occupied=0,detour_denied=0;
    reg [2:0] detour_wait=0;
    wire [1:0] detour_direction=detour_leg==1?detour_left:
        detour_leg<DETOUR_LAST_LEG?detour_heading:detour_heading-2'd1;
    reg signed [31:0] last_advance=0;
    reg [31:0] brake_lead=0;
    localparam integer POSITION_TOL=CELL_COUNTS/10;
    reg [7:0] frames=0;
    reg [15:0] minimum=16'hffff,observation=0;
    reg [15:0] maximum=0;
    // Moving near rays stop motion immediately, but are not map points.
    // Freeze the origin with a coherent stopped observation window.
    reg signed [31:0] observation_px=0,observation_py=0;
    reg [31:0] still_p0=0,still_p1=0,still_p2=0,still_p3=0;
    reg [7:0] map_still=0;
    wire signed [31:0] still_d0=position0_i-still_p0,still_d1=position1_i-still_p1,
                       still_d2=position2_i-still_p2,still_d3=position3_i-still_p3;
    wire wheels_quiet=still_d0>=-1 && still_d0<=1 && still_d1>=-1 && still_d1<=1 &&
                      still_d2>=-1 && still_d2<=1 && still_d3>=-1 && still_d3<=1;
    reg [399:0] occupied=MAP_BITS;
    // A measured near ray also forbids APPROACH along that directed edge.
    // This is a motion keepout, not a claim that the next grid cell contains
    // the physical obstacle. Keep it until a fresh operator-started mission.
    reg [1599:0] denied_edges=0;
    // Register the bulk-map initialization enable. Previously the complete
    // live sensor/owner/request qualification drove 2000 reset muxes directly,
    // creating a nine-level, 1000-fanout path from ToF into denied_edges.
    // PLAN waits four clocks before using the maps, so this one-clock write
    // stage does not change planning or the immediate physical stop gates.
    reg clear_maps=0;
    reg [8:0] mark_index=0;
    reg signed [31:0] obstacle_x=0,obstacle_y=0;
    function [7:0] cell_index(input signed [31:0] position);
        integer k;
        begin
            cell_index=0;
            for(k=1;k<20;k=k+1)if(position>=k*CELL_COUNTS)cell_index=k;
            if(position<0 || position>=20*CELL_COUNTS)cell_index=255;
        end
    endfunction
    reg [7:0] cell_x=0,cell_y=0;
    reg [8:0] current_index=0;
    reg [2:0] plan_delay=0;
    reg [2:0] waypoint_delay=0;
    assign x_o=cell_x;assign y_o=cell_y;
    wire pose_ok=px>=0 && py>=0 && px<20*CELL_COUNTS && py<20*CELL_COUNTS;
    reg plan_request=0;
    wire plan_busy,plan_ready,plan_failed;
    wire [8:0] next_cell,path_length;
    wire [8:0] start_cell=current_index;
    wire [8:0] goal_cell=gy_o*20+gx_o;
    grid_bfs_dynamic #(.ALLOW_SAFE_START_ESCAPE(ADAPTIVE_DETOUR)) u_plan(.clk(clk),.rst_n(rst_n),.request_i(plan_request),
        .cancel_i(!active_o),.start_i(start_cell),.goal_i(goal_cell),.start_escape_i(ADAPTIVE_DETOUR && safe_start_escape),.occupied_i(occupied),.denied_edges_i(denied_edges),
        .busy_o(plan_busy),.ready_o(plan_ready),.no_path_o(plan_failed),.next_o(next_cell),.length_o(path_length));
    // Modular wheel subtraction is signed BEFORE widening. For forward physical
    // motion M1/M3 raw counts increase and M2/M4 decrease on this verified board.
    reg signed [31:0] dd0=0,dd1=0,dd2=0,dd3=0;
    reg signed [34:0] sum_delta=0;
    reg signed [32:0] pair0=0,pair1=0;
    reg [3:0] odometry_age=0;
    wire signed [31:0] advance=sum_delta>>>2;
    wire signed [31:0] measured_x=base_x+(direction==3 ? advance : direction==1 ? -advance : 0);
    wire signed [31:0] measured_y=base_y+(direction==0 ? advance : direction==2 ? -advance : 0);
    reg signed [31:0] dx=0,dy=0;
    reg [31:0] ax=0,ay=0;
    // Q13 radians. Positive physical heading is counterclockwise.
    wire signed [31:0] offset=direction==0 ? 0 : direction==1 ? 12868 : direction==2 ? 25736 : -12868;
    wire signed [31:0] target=$signed(reference_yaw)+(inverted ? -offset:offset);
    reg signed [31:0] target_wrapped=0;
    wire signed [31:0] difference=target_wrapped-$signed(yaw_i);
    reg signed [31:0] yaw_error=0;
    reg [31:0] abs_error=0;
    wire near_now=distance_i<=EARLY_STOP_MM;
    // Keep neutral accounting independent of the live safety/owner mux.
    // An interrupted moving state never earns neutral credit: fail() stops
    // the owner on this edge; only subsequent inactive samples earn it.
    // Physical command_o retains every immediate stop condition below.
    wire [2:0] approach_command;
    wire [15:0] approach_speed;
    wire approach_stable;
    generate if(PROGRESS_CONTROL)begin:g_approach
        heading_approach_control u_approach(.clk(clk),.rst_n(rst_n),.tick_i(sample_tick_i),
            .enable_i(active_o && state_o==TURN && turn_running),.inverted_i(inverted),
            .yaw_i(yaw_i),.error_i(yaw_error[16:0]),.maximum_speed_i(8'd8),
            .command_o(approach_command),.speed_o(approach_speed),.stable_o(approach_stable));
    end else begin:g_legacy_approach
        assign approach_command=abs_error>286?(((yaw_error>0)^inverted)?3'd5:3'd6):0;
        assign approach_speed=16'd8;
        assign approach_stable=abs_error<=286;
    end endgenerate
    wire [2:0] motion_intent=state_o==TURN && turn_running ? approach_command :
        state_o==MOVE && !near_now && abs_error<=715 ? 3'd1:3'd0;
    assign command_o=(!active_o || !sensors_ok_i || hard_stop_i || motor_fault_i || cancel_i || (CANCEL_PIPELINE && cancel_q) || error_i) ? 0 : motion_intent;
    assign speed_o=command_o==0 ? 0:state_o==TURN ? approach_speed:FIXED_LEFT_DETOUR ? 16'd4:
        PROGRESS_CONTROL && travel-advance<CELL_COUNTS/2 ? 16'd8:{8'd0,velocity};
    // Passing a non-final waypoint consumes it. Do not turn around to chase
    // its centre. Bound the acceptance to this adjacent cell and cross track.
    wire passed_waypoint=direction==0?py>=ty:direction==2?py<=ty:direction==3?px>=tx:px<=tx;
    wire bounded_pass=completed_leg && passed_waypoint &&
        (direction==0 || direction==2 ? ax<=POSITION_TOL && ay<=CELL_COUNTS/4:
                                        ay<=POSITION_TOL && ax<=CELL_COUNTS/4);
    wire at_waypoint=PROGRESS_CONTROL?
        ((ax<=POSITION_TOL && ay<=POSITION_TOL)||(!waypoint_is_goal && bounded_pass)):
        (ax<=CELL_COUNTS/100 && ay<=CELL_COUNTS/100);
    wire signed [31:0] sample_advance=advance-last_advance;
    wire [15:0] fresh_min=distance_i<minimum ? distance_i:minimum;
    wire [15:0] fresh_max=distance_i>maximum ? distance_i:maximum;
    wire coherent_window=frames==0 || fresh_max-fresh_min<=RANGE_SPREAD_MM;
    wire signed [31:0] center_to_face=100-$signed(setback);
    wire signed [31:0] ray_length=$signed({1'b0,observation})+center_to_face;
    reg projection_start=0,projection_sent=0;
    wire projection_done_x,projection_done_y;
    wire [23:0] pose_mm_x_unsigned,pose_mm_y_unsigned;
    wire signed [31:0] pose_mm_x={8'b0,pose_mm_x_unsigned},pose_mm_y={8'b0,pose_mm_y_unsigned};
    wire [23:0] numerator_x=(CONFIRMED_MAPPING?observation_px:px)*100+(ROUND_POSE_MM?CELL_COUNTS/2:0),
                numerator_y=(CONFIRMED_MAPPING?observation_py:py)*100+(ROUND_POSE_MM?CELL_COUNTS/2:0);
    localparam [23:0] DIVISOR=CELL_COUNTS;
    nav_unsigned_divider u_project_x(.clk(clk),.rst_n(rst_n),.start_i(projection_start),
        .numerator_i(numerator_x),.denominator_i(DIVISOR),
        .busy_o(),.done_o(projection_done_x),.quotient_o(pose_mm_x_unsigned));
    nav_unsigned_divider u_project_y(.clk(clk),.rst_n(rst_n),.start_i(projection_start),
        .numerator_i(numerator_y),.denominator_i(DIVISOR),
        .busy_o(),.done_o(projection_done_y),.quotient_o(pose_mm_y_unsigned));
    reg [4:0] mark_col=0,mark_row=0;
    wire signed [31:0] mark_x=mark_col*100+50,mark_y=mark_row*100+50;
    reg signed [15:0] mx=0,my=0;
    reg [31:0] square_x=0,square_y=0;
    reg [32:0] square=0;
    reg [1:0] mark_phase=0;
    // R20: block every cell intersecting the 210mm safety disk, not just
    // cells whose centres lie in it. Millimetre rays are never grid-snapped.
    function signed [15:0] cell_axis_distance(input signed [31:0] center,point);
        reg signed [15:0] delta;
        reg [15:0] magnitude;
        begin
            // Field centres0..1950, valid ray40..8000+setback: subtraction
            // stays inside signed16. The clipped distance feeds the same DSP.
            delta=$signed(center[15:0])-$signed(point[15:0]);
            magnitude=delta<0?-delta:delta;
            cell_axis_distance=CONSERVATIVE_CELLS ? (magnitude>50?magnitude-50:0):delta;
        end
    endfunction
    function [7:0] mm_cell(input signed [31:0] position);
        integer k;
        begin
            mm_cell=0;
            for(k=1;k<20;k=k+1)if(position>=k*100)mm_cell=k;
            if(position<0 || position>=2000)mm_cell=255;
        end
    endfunction
    task fail(input [7:0] reason);
        begin active_o<=0;fault_o<=1;state_o<=FAILED;reason_o<=reason;armed<=0;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin occupied<=MAP_BITS;denied_edges<=0;end
        else if(clear_maps)begin occupied<=local_mode_o ? 400'd0:MAP_BITS;denied_edges<=0;end
        // Keep a near edge forbidden even when stopped rays disagree.
        // This is a motion keepout, not a guessed physical obstacle cell.
        else if(CONFIRMED_MAPPING && active_o && state_o==BRAKE && blocked_leg &&
                neutral>=NEUTRAL_TICKS && pose_ok)
            denied_edges[start_cell*4+direction]<=1;
        else if(active_o && state_o==MARK)begin
            if(mark_index==0 && pose_ok && observation<=EARLY_STOP_MM)
                denied_edges[start_cell*4+direction]<=1;
            if(mark_phase==3 && obstacle_x>=0 && obstacle_x<2000 &&
               obstacle_y>=0 && obstacle_y<2000 && square<=INFLATE_MM*INFLATE_MM)
                occupied[mark_index]<=1;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active_o<=0;fault_o<=0;state_o<=IDLE;reason_o<=0;replans_o<=0;sequence_o<=0;
            armed<=0;seen<=0;last_seq<=0;inverted<=0;lease<=0;age<=0;leg_age<=0;local_mode_o<=0;last_local<=0;
            neutral<=0;settled<=0;probe_age<=0;velocity<=8;reference_yaw<=0;setback<=0;
            px<=0;py<=0;tx<=0;ty<=0;base_x<=0;base_y<=0;travel<=0;
            b0<=0;b1<=0;b2<=0;b3<=0;direction<=0;blocked_direction<=0;scan_phase<=0;blocked_leg<=0;
            frames<=0;minimum<=16'hffff;observation<=0;clear_maps<=0;mark_index<=0;turn_running<=0;finishing<=0;
            maximum<=0;observation_px<=0;observation_py<=0;
            still_p0<=0;still_p1<=0;still_p2<=0;still_p3<=0;map_still<=0;
            waypoint_is_goal<=0;completed_leg<=0;last_advance<=0;brake_lead<=0;
            detour_leg<=0;detour_heading<=0;detour_x<=0;detour_y<=0;restore_detour_heading<=0;safe_start_escape<=0;
            detour_target_x<=0;detour_target_y<=0;detour_cell_x<=0;detour_cell_y<=0;
            detour_cell<=0;detour_edge<=0;detour_target_valid<=0;detour_occupied<=0;detour_denied<=0;detour_wait<=0;
            obstacle_x_o<=8'hff;obstacle_y_o<=8'hff;
            obstacle_x<=0;obstacle_y<=0;plan_request<=0;gx_o<=0;gy_o<=0;
            cell_x<=0;cell_y<=0;current_index<=0;plan_delay<=0;waypoint_delay<=0;
            dd0<=0;dd1<=0;dd2<=0;dd3<=0;sum_delta<=0;pair0<=0;pair1<=0;odometry_age<=0;
            dx<=0;dy<=0;ax<=0;ay<=0;target_wrapped<=0;yaw_error<=0;abs_error<=0;mark_col<=0;mark_row<=0;
            projection_start<=0;projection_sent<=0;mx<=0;my<=0;square_x<=0;square_y<=0;square<=0;mark_phase<=0;
        end else begin
            clear_maps<=0;
            plan_request<=0;
            if(FIXED_LEFT_DETOUR)begin
                detour_target_x<=detour_x+detour_delta_x;detour_target_y<=detour_y+detour_delta_y;
                detour_cell_x<=cell_index(detour_target_x);detour_cell_y<=cell_index(detour_target_y);
                detour_target_valid<=detour_target_x>=0 && detour_target_y>=0 &&
                    detour_target_x<20*CELL_COUNTS && detour_target_y<20*CELL_COUNTS;
                detour_cell<=detour_cell_y*20+detour_cell_x;
                detour_edge<={start_cell,detour_direction};
                detour_occupied<=occupied[detour_cell];detour_denied<=denied_edges[detour_edge];
                if(state_o!=DETOUR)detour_wait<=0;
                else if(detour_wait<5)detour_wait<=detour_wait+1'b1;
            end
            cell_x<=cell_index(px);cell_y<=cell_index(py);current_index<=cell_y*20+cell_x;
            if(state_o!=PLAN)plan_delay<=0;else if(plan_delay<4)plan_delay<=plan_delay+1'b1;
            if(state_o!=WAYPOINT)waypoint_delay<=0;else if(waypoint_delay<4)waypoint_delay<=waypoint_delay+1'b1;
            dx<=tx-px;dy<=ty-py;ax<=dx<0?-dx:dx;ay<=dy<0?-dy:dy;
            target_wrapped<=target>25736 ? target-51472:target< -25736 ? target+51472:target;
            yaw_error<=difference>25736?difference-51472:difference< -25736?difference+51472:difference;
            abs_error<=yaw_error<0?-yaw_error:yaw_error;
            dd0<=position0_i-b0;dd1<=position1_i-b1;dd2<=position2_i-b2;dd3<=position3_i-b3;
            pair0<={dd0[31],dd0}-{dd1[31],dd1};pair1<={dd2[31],dd2}-{dd3[31],dd3};
            sum_delta<={{2{pair0[32]}},pair0}+{{2{pair1[32]}},pair1};
            if(state_o==MOVE || state_o==BRAKE)begin if(odometry_age<7)odometry_age<=odometry_age+1'b1;end
            else odometry_age<=0;
            projection_start<=0;
            if(state_o!=PROJECT)projection_sent<=0;
            if(!active_o || state_o!=TURN)turn_running<=0;
            else if(neutral>=NEUTRAL_TICKS)turn_running<=1;
            if(sample_tick_i)begin
                still_p0<=position0_i;still_p1<=position1_i;still_p2<=position2_i;still_p3<=position3_i;
                if(!wheels_quiet || motion_intent!=0)map_still<=0;
                else if(map_still<MAP_STILL_TICKS)map_still<=map_still+1'b1;
                if(state_o==MOVE)begin
                    last_advance<=advance;
                    // 80ms coast allowance, capped at the documented 10mm
                    // endpoint tolerance. No division/multiplier in this path.
                    if(sample_advance<=0)brake_lead<=0;
                    else if(sample_advance>CELL_COUNTS/80)brake_lead<=POSITION_TOL;
                    else brake_lead<=sample_advance<<3;
                end
                if(!active_o)begin if(neutral<NEUTRAL_TICKS)neutral<=neutral+1'b1;end
                else begin
                    lease<=lease+1'b1;age<=age+1'b1;leg_age<=leg_age+1'b1;
                    if(motion_intent==0 && neutral<NEUTRAL_TICKS)neutral<=neutral+1'b1;
                    else if(motion_intent!=0)neutral<=0;
                    case(state_o)
                        WAYPOINT:if(waypoint_delay>=4)begin
                            if(at_waypoint)begin
                                if(FIXED_LEFT_DETOUR && detour_leg!=0)begin
                                    if(detour_leg<DETOUR_LAST_LEG)begin detour_leg<=detour_leg+1'b1;state_o<=DETOUR;end
                                    else begin
                                        detour_leg<=0;direction<=detour_heading;restore_detour_heading<=1;
                                        settled<=0;neutral<=0;state_o<=TURN;leg_age<=0;
                                    end
                                end else if(start_cell==goal_cell && (!PROGRESS_CONTROL || waypoint_is_goal))begin direction<=0;finishing<=1;settled<=0;state_o<=TURN;leg_age<=0;end
                                else state_o<=PLAN;
                            end else if(PROGRESS_CONTROL && completed_leg && passed_waypoint)begin
                                // A final overshoot outside tolerance is not
                                // arrival, nor permission to oscillate/reverse.
                                fail(13);
                            end else begin
                                direction<=ax>(PROGRESS_CONTROL?POSITION_TOL:CELL_COUNTS/100) ? (dx>0?3:1):(dy>0?0:2);
                                travel<=ax>(PROGRESS_CONTROL?POSITION_TOL:CELL_COUNTS/100) ? ax:ay;
                                scan_phase<=0;settled<=0;leg_age<=0;state_o<=TURN;
                            end
                        end
                        TURN:begin
                            // Do not pulse rotation while waiting for neutral:
                            // after rotation starts, its own continuous state
                            // carries neutral permission until heading settles.
                            if(approach_stable)begin
                                settled<=settled+1'b1;
                                if(settled>=SETTLE_TICKS-1)begin
                                    if(restore_detour_heading)begin restore_detour_heading<=0;state_o<=PLAN;end
                                    else if(finishing)begin active_o<=0;state_o<=DONE;end
                                    else begin state_o<=PROBE;frames<=0;minimum<=16'hffff;maximum<=0;probe_age<=0;end
                                end
                            end else settled<=0;
                        end
                        PROBE:begin
                            probe_age<=probe_age+1'b1;
                            if(probe_age>=100)fail(8);
                            if(abs_error>286)begin state_o<=TURN;settled<=0;frames<=0;end
                        end
                        REOBSERVE:begin
                            px<=measured_x;py<=measured_y;
                            probe_age<=probe_age+1'b1;
                            if(probe_age>=100)fail(8);
                            if(abs_error>286 || !wheels_quiet)begin
                                frames<=0;minimum<=16'hffff;maximum<=0;
                            end
                        end
                        MOVE:if(odometry_age>=5)begin
                            px<=measured_x;py<=measured_y;
                            if(near_now || advance>=travel-(PROGRESS_CONTROL?$signed(brake_lead):0) || abs_error>715)begin
                                state_o<=BRAKE;neutral<=0;blocked_leg<=near_now;
                                completed_leg<=1;
                                if(near_now)begin observation<=distance_i;blocked_direction<=direction;end
                            end
                            if(advance< -CELL_COUNTS/10 || advance>3*CELL_COUNTS)fail(9);
                        end
                        BRAKE:begin
                            px<=measured_x;py<=measured_y;
                            if(neutral>=NEUTRAL_TICKS && (!FIXED_LEFT_DETOUR ||
                               (wheels_quiet && map_still>=MAP_STILL_TICKS)))begin
                                if(blocked_leg)begin
                                    if(replans_o>=8)fail(11);
                                    else begin
                                        replans_o<=replans_o+1'b1;scan_phase<=0;
                                        if(CONFIRMED_MAPPING)begin
                                            state_o<=REOBSERVE;frames<=0;minimum<=16'hffff;maximum<=0;probe_age<=0;
                                        end else state_o<=PROJECT;
                                    end
                                end else begin state_o<=WAYPOINT;leg_age<=0;end
                            end
                        end
                    endcase
                end
            end
            // TURN permission is latched after its initial stopped interval;
            // see turn_running below for continuous rotation, never a pulse train.
            if(active_o)begin
                // Capture a valid near ray even BETWEEN 10ms control ticks.
                // The combinational gate already stops immediately. Latching
                // BRAKE prevents a short near echo from disappearing before the
                // next tick and silently allowing forward motion to rebound.
                // Mapping still requires three coherent fresh STOPPED rays.
                if(LATCH_NEAR_EVENT && state_o==MOVE && near_now && sensors_ok_i)begin
                    state_o<=BRAKE;neutral<=0;blocked_leg<=1;completed_leg<=1;
                    observation<=distance_i;blocked_direction<=direction;
                    obstacle_x_o<=8'hff;obstacle_y_o<=8'hff;
                end
                case(state_o)
                    DETOUR:if(detour_wait>=5)begin
                        // A fixed manoeuvre is a preference, never permission
                        // to leave the field or enter a known occupied cell.
                        if(!detour_target_valid)fail(14);
                        else if(detour_occupied || detour_denied)fail(14);
                        else begin
                            tx<=detour_target_x;ty<=detour_target_y;
                            waypoint_is_goal<=0;completed_leg<=0;waypoint_delay<=0;
                            state_o<=WAYPOINT;leg_age<=0;
                        end
                    end
                    PLAN:if(plan_delay>=4 && !plan_busy)begin plan_request<=1;state_o<=PLAN_WAIT;end
                    PLAN_WAIT:if(plan_ready)begin
                        if(plan_failed)fail(7);
                        else begin
                            // First exit after a new stopped ray is strictly
                            // one axis. Preserve the actual other coordinate;
                            // do not centre the partly blocked start tile first.
                            tx<=ADAPTIVE_DETOUR && safe_start_escape && next_cell%20==cell_x ? px:(next_cell%20)*CELL_COUNTS+CELL_COUNTS/2;
                            ty<=ADAPTIVE_DETOUR && safe_start_escape && next_cell/20==cell_y ? py:(next_cell/20)*CELL_COUNTS+CELL_COUNTS/2;
                            waypoint_is_goal<=!safe_start_escape && next_cell==goal_cell;completed_leg<=0;
                            safe_start_escape<=0;
                            state_o<=WAYPOINT;leg_age<=0;
                        end
                    end
                    PROBE,REOBSERVE:if(tof_sample_i && abs_error<=286 &&
                        (!CONFIRMED_MAPPING || (map_still>=MAP_STILL_TICKS && wheels_quiet)))begin
                        minimum<=fresh_min;frames<=frames+1'b1;
                        maximum<=fresh_max;
                        if(CONFIRMED_MAPPING && (frames==0 || !coherent_window))begin
                            minimum<=distance_i;maximum<=distance_i;frames<=1;
                            observation_px<=px;observation_py<=py;
                        end
                        if(frames>=PROBE_FRAMES-1 && (!CONFIRMED_MAPPING || coherent_window))begin
                            observation<=fresh_min;
                            if(CONFIRMED_MAPPING && fresh_min>EARLY_STOP_MM &&
                               (scan_phase!=0 || state_o==REOBSERVE))begin
                                // A long background echo must not create a new
                                // occupied cell or erase a previously denied edge.
                                state_o<=SCAN_NEXT;
                            end else if(scan_phase!=0 || fresh_min<=EARLY_STOP_MM)begin
                                // MARK visits each cell; endpoints outside the field
                                // are ignored rather than clamped to a false edge.
                                if(scan_phase==0 && state_o!=REOBSERVE && replans_o>=8)fail(11);
                                else begin
                                    if(scan_phase==0 && state_o!=REOBSERVE)begin replans_o<=replans_o+1'b1;blocked_direction<=direction;end
                                    state_o<=PROJECT;
                                end
                            end else begin
                                b0<=position0_i;b1<=position1_i;b2<=position2_i;b3<=position3_i;
                                last_advance<=0;brake_lead<=0;completed_leg<=0;
                                base_x<=px;base_y<=py;state_o<=MOVE;leg_age<=0;
                            end
                        end
                    end
                    PROJECT:begin
                        // A previous point is not evidence for this observation.
                        // Out-of-field rays must export invalid, never the last
                        // obstacle cell. Keep legacy revisions unchanged.
                        if(LATCH_NEAR_EVENT)begin obstacle_x_o<=8'hff;obstacle_y_o<=8'hff;end
                        if(!projection_sent)begin projection_start<=1;projection_sent<=1;end
                        if(projection_done_x && projection_done_y)begin
                            obstacle_x<=pose_mm_x+(direction==3?ray_length:direction==1?-ray_length:0);
                            obstacle_y<=pose_mm_y+(direction==0?ray_length:direction==2?-ray_length:0);
                            state_o<=MARK;mark_index<=0;mark_phase<=0;mark_col<=0;mark_row<=0;
                        end
                    end
                    MARK:begin
                        if(mark_index==0 && obstacle_x>=0 && obstacle_x<2000 && obstacle_y>=0 && obstacle_y<2000)begin
                            obstacle_x_o<=mm_cell(obstacle_x);obstacle_y_o<=mm_cell(obstacle_y);
                        end
                        case(mark_phase)
                            0:begin mx<=cell_axis_distance(mark_x,obstacle_x);my<=cell_axis_distance(mark_y,obstacle_y);mark_phase<=1;end
                            1:begin square_x<=mx*mx;square_y<=my*my;mark_phase<=2;end
                            2:begin square<={1'b0,square_x}+{1'b0,square_y};mark_phase<=3;end
                            3:begin
                                mark_phase<=0;
                                if(mark_index==399)state_o<=SCAN_NEXT;
                                else begin
                                    mark_index<=mark_index+1'b1;
                                    if(mark_col==19)begin mark_col<=0;mark_row<=mark_row+1'b1;end
                                    else mark_col<=mark_col+1'b1;
                                end
                            end
                        endcase
                    end
                    SCAN_NEXT:begin
                        leg_age<=0;settled<=0;neutral<=0;
                        if(ADAPTIVE_DETOUR)begin
                            // Review only: re-use the real occupied/denied-edge
                            // BFS so every next cell respects the same210mm mask.
                            // No blind left1/forward3/right1 motion through it.
                            // No occupancy bit is cleared. A current tile may
                            // overlap the safety disk while the stopped actual
                            // pose is outside it. Seed BFS only in that case;
                            // the measured forward edge remains denied and every
                            // destination cell must be wholly clear.
                            detour_leg<=0;restore_detour_heading<=0;scan_phase<=0;
                            if(ray_length<=INFLATE_MM)fail(14);
                            else begin safe_start_escape<=1;state_o<=PLAN;end
                        end else if(FIXED_LEFT_DETOUR)begin
                            // Left one cell, N individually checked forward
                            // cells, right one, restore the original heading.
                            // A subsequent near ray begins another bounded
                            // dogleg from its stopped pose, preserving gx/gy.
                            detour_x<=px;detour_y<=py;detour_heading<=blocked_direction;
                            detour_leg<=1;restore_detour_heading<=0;scan_phase<=0;state_o<=DETOUR;
                        end else if(scan_phase==0)begin scan_phase<=1;direction<=blocked_direction+1'b1;state_o<=TURN;end
                        else if(scan_phase==1)begin scan_phase<=2;direction<=blocked_direction-1'b1;state_o<=TURN;end
                        else begin scan_phase<=0;state_o<=PLAN;end
                    end
                endcase
                if(ascii_valid_i && ascii_i=="N")lease<=0;
                if(age>=MAX_TICKS || leg_age>=LEG_TICKS)fail(10);
                if(!pose_ok)fail(9);
                if(lease>=LEASE_TICKS)fail(1);
                if(!sensors_ok_i)fail(2);
                if(motor_fault_i)fail(3);
                if(hard_stop_i)fail(4);
                if(cancel_state || error_i)fail(5);
            end
            if(request_i && !active_o && (!seen || sequence_i!=last_seq || (LOCAL_MAP_ENABLE && flags_i[2]!=last_local)))begin
                seen<=1;last_seq<=sequence_i;sequence_o<=sequence_i;armed<=0;last_local<=LOCAL_MAP_ENABLE && flags_i[2];
                if(armed && neutral>=NEUTRAL_TICKS && sensors_ok_i && !hard_stop_i && !motor_fault_i &&
                   !other_active_i && !cancel_state && !error_i && sx_i<20 && sy_i<20 && gx_i<20 && gy_i<20 &&
                   flags_i[0] && flags_i<=(LOCAL_MAP_ENABLE?7:3) && counts_i==CELL_COUNTS && setback_i>=-30 && setback_i<=50 &&
                   speed_i>=8 && speed_i<=12)begin
                    active_o<=1;fault_o<=0;reason_o<=0;state_o<=PLAN;replans_o<=0;
                    gx_o<=gx_i;gy_o<=gy_i;px<=sx_i*CELL_COUNTS+CELL_COUNTS/2;
                    py<=sy_i*CELL_COUNTS+CELL_COUNTS/2;reference_yaw<=yaw_i;setback<=setback_i;
                    inverted<=flags_i[1];velocity<=speed_i;clear_maps<=1;local_mode_o<=LOCAL_MAP_ENABLE && flags_i[2];
                    age<=0;lease<=0;leg_age<=0;scan_phase<=0;finishing<=0;
                    detour_leg<=0;restore_detour_heading<=0;safe_start_escape<=0;
                    obstacle_x_o<=8'hff;obstacle_y_o<=8'hff;
                end else fail(6);
            end
            if(ascii_valid_i && ascii_i=="S")begin
                active_o<=0;armed<=1;neutral<=0;fault_o<=0;
                if(active_o)begin state_o<=FAILED;reason_o<=12;end
            end
        end
    end
endmodule
