// FPGA relative heading control. Q13 radians, +angle denotes physical CCW.
// Requires S -> neutral gap -> CRC request; G only renews an existing turn.
module imu_turn_guard #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer TIMEOUT_MS=10000,
    parameter integer LEASE_MS=300,
    parameter integer NEUTRAL_MS=150,
    parameter integer SETTLE_TICKS=20,
    parameter integer PIPELINED_TARGET=0,
    parameter integer DAMPED_APPROACH=0
) (
    input wire clk,rst_n,sample_tick_i,
    input wire request_i,
    input wire [15:0] sequence_i,
    input wire signed [15:0] angle_cdeg_i,
    input wire [7:0] speed_i,
    input wire inverted_i,
    input wire signed [15:0] yaw_i,
    input wire sensors_ok_i,hard_stop_i,motor_fault_i,other_active_i,cancel_i,
    input wire ascii_valid_i,error_i,
    input wire [7:0] ascii_i,
    output reg active_o=0,
    output reg fault_o=0,
    output reg [3:0] state_o=0,
    output reg [15:0] sequence_o=0,
    output reg signed [15:0] target_yaw_o=0,
    output wire signed [15:0] error_o,
    output wire [2:0] command_o,
    output wire [15:0] target_speed_o
);
    localparam integer PI=25736,TWO_PI=51472;
    localparam integer LEASE_CYCLES=(CLK_HZ/1000)*LEASE_MS;
    localparam integer TIMEOUT_CYCLES=(CLK_HZ/1000)*TIMEOUT_MS;
    localparam integer NEUTRAL_CYCLES=(CLK_HZ/1000)*NEUTRAL_MS;
    reg [31:0] lease_age=0,run_age=0,neutral_age=0;
    reg [7:0] settle_count=0,speed=8;
    reg armed=0,seen=0,inverted=0;
    reg [15:0] last_sequence=0;
    reg [2:0] applied_command=0;
    reg [31:0] direction_age=0;
    wire accept_request=request_i && !active_o && (!seen || sequence_i!=last_sequence) &&
        armed && neutral_age>=NEUTRAL_CYCLES && sensors_ok_i && !hard_stop_i &&
        !motor_fault_i && !other_active_i && !error_i && !cancel_i;
    wire signed [15:0] wrapped_target;
    wire converted_valid;
    reg target_pending=0;
    generate if(PIPELINED_TARGET)begin:g_target_pipeline
        // Capture the complete request together. Registered shift/add stages
        // avoid folding signed conversion and yaw addition into a shared DSP.
        sin12_turn_target_pipeline u_target(.clk(clk),.rst_n(rst_n),.valid_i(accept_request),
            .angle_cdeg_i(angle_cdeg_i),.yaw_i(yaw_i),.inverted_i(inverted_i),
            .valid_o(converted_valid),.target_o(wrapped_target));
    end else begin:g_target_legacy
        wire signed [31:0] delta_product=$signed(angle_cdeg_i)*32'sd1464;
        wire signed [31:0] delta=delta_product>>>10;
        wire signed [31:0] requested=$signed(yaw_i)+(inverted_i ? -delta : delta);
        wire signed [31:0] wrapped=requested>PI ? requested-TWO_PI : requested< -PI ? requested+TWO_PI : requested;
        assign wrapped_target=wrapped[15:0];
        assign converted_valid=1'b1;
    end endgenerate
    wire signed [16:0] difference=$signed(target_yaw_o)-$signed({yaw_i[15],yaw_i});
    wire signed [16:0] wrapped_error=difference>17'sd25736 ? difference-17'sd51472 :
        difference< -17'sd25736 ? difference+17'sd51472 : difference;
    wire [16:0] absolute_error=wrapped_error<0 ? -wrapped_error : wrapped_error;
    assign error_o=wrapped_error[15:0];
    // 286 Q13 units ~= 2 degrees; slow at <15 degrees. No reverse hunting:
    // stop inside tolerance, require continuous settling before DONE.
    wire [2:0] approach_command;
    wire [15:0] approach_speed;
    wire approach_stable;
    generate if(DAMPED_APPROACH)begin:g_approach
        heading_approach_control u_approach(.clk(clk),.rst_n(rst_n),.tick_i(sample_tick_i),
            .enable_i(active_o && !target_pending),.inverted_i(inverted),.yaw_i(yaw_i),
            .error_i(wrapped_error),.maximum_speed_i(speed),.command_o(approach_command),
            .speed_o(approach_speed),.stable_o(approach_stable));
    end else begin:g_legacy_approach
        assign approach_command=absolute_error<=286?0:((wrapped_error>0)^inverted)?3'd5:3'd6;
        assign approach_speed=absolute_error<2145?16'd8:{8'd0,speed};
        assign approach_stable=absolute_error<=286;
    end endgenerate
    wire [2:0] desired_command=target_pending?0:approach_command;
    assign command_o=active_o && sensors_ok_i && !hard_stop_i && !motor_fault_i && !cancel_i && !error_i ? applied_command : 3'd0;
    assign target_speed_o=command_o==0 ? 0 : approach_speed;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            active_o<=0;fault_o<=0;state_o<=0;sequence_o<=0;target_yaw_o<=0;
            lease_age<=0;run_age<=0;neutral_age<=0;settle_count<=0;
            speed<=8;armed<=0;seen<=0;inverted<=0;last_sequence<=0;
            applied_command<=0;direction_age<=0;
            target_pending<=0;
        end else begin
            if(applied_command==0)begin
                if(direction_age<NEUTRAL_CYCLES)direction_age<=direction_age+1'b1;
            end else direction_age<=0;
            if(!active_o)applied_command<=0;
            else if(applied_command!=0 && desired_command!=applied_command)begin
                applied_command<=0;direction_age<=0;
            end else if(applied_command==0 && direction_age>=NEUTRAL_CYCLES)
                applied_command<=desired_command;
            if(!active_o && neutral_age<NEUTRAL_CYCLES)neutral_age<=neutral_age+1'b1;
            if(active_o)begin
                neutral_age<=0;lease_age<=lease_age+1'b1;run_age<=run_age+1'b1;
                if(ascii_valid_i && ascii_i=="G")lease_age<=0;
                if(target_pending && converted_valid)begin
                    target_yaw_o<=wrapped_target;target_pending<=0;
                end
                if(sample_tick_i && !target_pending)begin
                    if(approach_stable && applied_command==0)begin
                        state_o<=2;
                        if(settle_count>=SETTLE_TICKS-1)begin active_o<=0;state_o<=3;end
                        else settle_count<=settle_count+1'b1;
                    end else begin settle_count<=0;state_o<=1;end
                end
                if(lease_age>=LEASE_CYCLES)begin active_o<=0;fault_o<=1;state_o<=4;end
                if(run_age>=TIMEOUT_CYCLES)begin active_o<=0;fault_o<=1;state_o<=5;end
                if(!sensors_ok_i || hard_stop_i || motor_fault_i || error_i)begin
                    active_o<=0;fault_o<=1;state_o<=6;
                end
            end
            if(request_i && !active_o && (!seen || sequence_i!=last_sequence))begin
                seen<=1;last_sequence<=sequence_i;sequence_o<=sequence_i;
                armed<=0;
                if(armed && neutral_age>=NEUTRAL_CYCLES && sensors_ok_i && !hard_stop_i &&
                   !motor_fault_i && !other_active_i && !error_i && !cancel_i)begin
                    active_o<=1;fault_o<=0;state_o<=1;lease_age<=0;run_age<=0;
                    settle_count<=0;target_pending<=PIPELINED_TARGET;
                    if(!PIPELINED_TARGET)target_yaw_o<=wrapped_target;
                    speed<=speed_i;inverted<=inverted_i;
                end else begin active_o<=0;fault_o<=1;state_o<=7;end
            end
            if(cancel_i || (ascii_valid_i && (ascii_i=="F" || ascii_i=="B" || ascii_i=="L" ||
               ascii_i=="R" || ascii_i=="V")))begin
                active_o<=0;armed<=0;if(active_o)state_o<=8;
            end
            // S wins over every request/lease on this clock, including S0 recovery.
            if(ascii_valid_i && (ascii_i=="S" || ascii_i=="s"))begin
                active_o<=0;armed<=1;fault_o<=0;state_o<=0;neutral_age<=0;settle_count<=0;
                target_pending<=0;
            end
        end
    end
endmodule

// Five-cycle, fully signed centidegrees -> Q13 radians -> wrapped heading.
// 1464 = 1024 + 512 - 64 - 8; all intermediate widths cover +/-18000 cdeg.
module sin12_turn_target_pipeline(
    input wire clk,rst_n,valid_i,
    input wire signed [15:0] angle_cdeg_i,yaw_i,
    input wire inverted_i,
    output wire valid_o,
    output reg signed [15:0] target_o=0
);
    wire signed [26:0] a={{11{angle_cdeg_i[15]}},angle_cdeg_i};
    reg [4:0] valid_q=0;
    (* syn_preserve=1 *) reg signed [26:0] hi_q=0,lo_q=0,product_q=0;
    (* syn_preserve=1 *) reg signed [17:0] delta_q=0,sum_q=0;
    reg signed [15:0] yaw0=0,yaw1=0,yaw2=0;
    reg inv0=0,inv1=0,inv2=0;
    assign valid_o=valid_q[4];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            valid_q<=0;hi_q<=0;lo_q<=0;product_q<=0;delta_q<=0;sum_q<=0;target_o<=0;
            yaw0<=0;yaw1<=0;yaw2<=0;inv0<=0;inv1<=0;inv2<=0;
        end else begin
            valid_q<={valid_q[3:0],valid_i};
            if(valid_i)begin
                hi_q<=(a<<<10)+(a<<<9);lo_q<=(a<<<6)+(a<<<3);
                yaw0<=yaw_i;inv0<=inverted_i;
            end
            if(valid_q[0])begin product_q<=hi_q-lo_q;yaw1<=yaw0;inv1<=inv0;end
            if(valid_q[1])begin delta_q<=product_q>>>10;yaw2<=yaw1;inv2<=inv1;end
            if(valid_q[2])sum_q<=$signed({{2{yaw2[15]}},yaw2})+(inv2 ? -delta_q : delta_q);
            if(valid_q[3])begin
                if(sum_q>18'sd25736)target_o<=sum_q-18'sd51472;
                else if(sum_q< -18'sd25736)target_o<=sum_q+18'sd51472;
                else target_o<=sum_q[15:0];
            end
        end
    end
endmodule
