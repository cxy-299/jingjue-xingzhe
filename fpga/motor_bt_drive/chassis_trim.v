// R4 outer loop. Wheel order FL,FR,RL,RR; yaw is Q13 radians, +CCW.
// Only wheel speed references are trimmed. Independent hard stops remain upstream.
module chassis_trim #(parameter integer PHYSICAL_SPEEDS=0,
    parameter integer LATERAL_HEADING=0,parameter integer MISSION_PULSED=0) (
    input wire clk,rst_n,sample_tick_i,enable_i,yaw_valid_i,
    input wire [2:0] command_i,owner_i,
    input wire signed [15:0] yaw_i,
    input wire [15:0] base_i,
    input wire signed [15:0] speed0_i,speed1_i,speed2_i,speed3_i,
    output wire [63:0] targets_o,
    output reg heading_locked_o=0,
    output reg signed [15:0] reference_o=0,error_o=0,
    output reg signed [7:0] correction_o=0
);
    reg [2:0] previous_command=0,previous_owner=0;
    reg signed [17:0] x_integral=0,y_integral=0;
    reg signed [7:0] spin_x=0,spin_y=0;
    reg lateral_reference=0;
    reg straight_reference=0;
    wire straight=command_i==1 || command_i==2;
    wire lateral=LATERAL_HEADING && (command_i==3 || command_i==4);
    wire translation=straight || lateral;
    wire spin=command_i==5 || command_i==6;
    wire changed=previous_command!=command_i || previous_owner!=owner_i;
    // Mission alignment deliberately pauses between short moves. Keep its
    // original yaw through those pauses; re-locking each burst hides drift.
    wire keep_lateral_reference=LATERAL_HEADING && lateral_reference &&
        heading_locked_o && yaw_valid_i && owner_i==2 && previous_owner==2 &&
        (lateral || command_i==0);
    wire keep_straight_reference=MISSION_PULSED && straight_reference &&
        heading_locked_o && yaw_valid_i && owner_i==2 && previous_owner==2 &&
        (straight || command_i==0);
    wire signed [16:0] delta=$signed({reference_o[15],reference_o})-$signed({yaw_i[15],yaw_i});
    wire signed [16:0] wrapped=delta>25736 ? delta-17'sd51472 : delta< -25736 ? delta+17'sd51472 : delta;
    // During rotation directed speeds are magnitudes in the commanded direction.
    // Recover physical forward wheel speeds before inverse mecanum kinematics.
    wire signed [17:0] a=!PHYSICAL_SPEEDS && command_i==5 ? -$signed({{2{speed0_i[15]}},speed0_i}) : $signed({{2{speed0_i[15]}},speed0_i});
    wire signed [17:0] b=!PHYSICAL_SPEEDS && command_i==6 ? -$signed({{2{speed1_i[15]}},speed1_i}) : $signed({{2{speed1_i[15]}},speed1_i});
    wire signed [17:0] c=!PHYSICAL_SPEEDS && command_i==5 ? -$signed({{2{speed2_i[15]}},speed2_i}) : $signed({{2{speed2_i[15]}},speed2_i});
    wire signed [17:0] d=!PHYSICAL_SPEEDS && command_i==6 ? -$signed({{2{speed3_i[15]}},speed3_i}) : $signed({{2{speed3_i[15]}},speed3_i});
    wire signed [17:0] vx=(a+b+c+d)>>>2;
    wire signed [17:0] vy=(-a+b+c-d)>>>2;
    function signed [17:0] clamp_integral(input signed [18:0] v);
        begin clamp_integral=v>128 ? 128 : v< -128 ? -128 : v;end
    endfunction
    function signed [7:0] trim3(input signed [18:0] v);
        begin trim3=v>3 ? 3 : v< -3 ? -3 : v;end
    endfunction
    reg signed [9:0] h;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            previous_command<=0;previous_owner<=0;heading_locked_o<=0;
            reference_o<=0;error_o<=0;correction_o<=0;
            x_integral<=0;y_integral<=0;spin_x<=0;spin_y<=0;
            lateral_reference<=0;
            straight_reference<=0;
        end else begin
            previous_command<=command_i;previous_owner<=owner_i;
            if((!enable_i || changed || !yaw_valid_i) && !keep_lateral_reference && !keep_straight_reference)begin
                heading_locked_o<=0;error_o<=0;correction_o<=0;
                x_integral<=0;y_integral<=0;spin_x<=0;spin_y<=0;
                lateral_reference<=0;
                straight_reference<=0;
            end else if(translation && enable_i && !heading_locked_o)begin
                reference_o<=yaw_i;heading_locked_o<=1;error_o<=0;correction_o<=0;
                lateral_reference<=lateral;
                straight_reference<=straight;
            end else if(sample_tick_i)begin
                if(translation && heading_locked_o && enable_i)begin
                    error_o<=wrapped[15:0];
                    // Offset is ~1 degree; integer quantization makes the first nonzero
                    // correction at 399 Q13 units (~2.79 degrees), then ~1.79/count, max 4.
                    if(lateral)begin
                        h=wrapped>72 ? (wrapped-72)>>>7 : wrapped< -72 ? -((-wrapped-72)>>>7) : 0;
                        // Preserve equal/opposite yaw authority at low speed:
                        // target>=4 means base6 permits only +/-2, not +/-3
                        // followed by asymmetric output clipping.
                        if(base_i<=4)correction_o<=0;
                        else if(base_i==5)correction_o<=h>1?1:h< -1?-1:h;
                        else if(base_i==6)correction_o<=h>2?2:h< -2?-2:h;
                        else correction_o<=h>3?3:h< -3?-3:h;
                    end else begin
                        h=wrapped>143 ? (wrapped-143)>>>8 : wrapped< -143 ? -((-wrapped-143)>>>8) : 0;
                        if(MISSION_PULSED && owner_i==2 && base_i<=4)correction_o<=0;
                        else if(MISSION_PULSED && owner_i==2 && base_i==5)correction_o<=h>1?1:h< -1?-1:h;
                        else if(MISSION_PULSED && owner_i==2 && base_i==6)correction_o<=h>2?2:h< -2?-2:h;
                        else correction_o<=h>4 ? 4 : h< -4 ? -4 : h;
                    end
                end else begin error_o<=0;correction_o<=0;end
                if(spin)begin
                    x_integral<=clamp_integral($signed(x_integral)+$signed(vx));
                    y_integral<=clamp_integral($signed(y_integral)+$signed(vy));
                    spin_x<=trim3(($signed(vx)>>>1)+($signed(x_integral)>>>4));
                    spin_y<=trim3(($signed(vy)>>>1)+($signed(y_integral)>>>4));
                end else begin x_integral<=0;y_integral<=0;spin_x<=0;spin_y<=0;end
            end
        end
    end
    genvar i;
    generate for(i=0;i<4;i=i+1)begin:w
        localparam integer LEFT=(i==0 || i==2);
        localparam integer Y_SIGN=(i==1 || i==2) ? 1 : -1;
        wire signed [15:0] yaw_trim=LEFT ? -$signed(correction_o) : $signed(correction_o);
        wire signed [15:0] translation_trim=-$signed(spin_x)-Y_SIGN*$signed(spin_y);
        wire spin_forward=(command_i==5) ? !LEFT : LEFT;
        localparam integer FRONT=(i==0 || i==1);
        // Physical yaw vector [-,+,-,+] projected onto the commanded wheel
        // signs. LEFT [+,-,-,+] -> [-,-,+,+]; RIGHT is the opposite.
        wire signed [15:0] lateral_trim=(command_i==3 ? FRONT:!FRONT) ?
            -$signed(correction_o):$signed(correction_o);
        wire signed [16:0] adjusted=$signed({1'b0,base_i})+
            (straight ? (command_i==2 ? -yaw_trim : yaw_trim) :
             lateral ? lateral_trim :
             spin ? (spin_forward ? translation_trim : -translation_trim) : 16'sd0);
        // Never reverse a wheel to correct heading, and do not raise zero reference.
        reg [15:0] target_q=0;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)target_q<=0;
            else target_q<=(!enable_i || base_i==0) ? 16'd0 :
                adjusted<4 ? 16'd4 : adjusted>30 ? 16'd30 : adjusted[15:0];
        end
        // Keep this a register boundary. Immediate shutdown is enforced by
        // the physical PWM/IN gate, not a second combinational target mux.
        assign targets_o[i*16+:16]=target_q;
    end endgenerate
endmodule
