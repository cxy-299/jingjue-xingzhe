// 10ms sampled outer loop. The wheel PID remains unchanged. Coast prediction
// uses measured yaw over 50ms, not command duration or a guessed reached angle.
module heading_approach_control #(
    parameter integer WINDOW_TICKS=5,
    parameter integer ANGLE_TOL=286,
    parameter integer QUIET_DELTA=72
)(
    input wire clk,rst_n,tick_i,enable_i,inverted_i,
    input wire signed [15:0] yaw_i,
    input wire signed [16:0] error_i,
    input wire [7:0] maximum_speed_i,
    output wire [2:0] command_o,
    output wire [15:0] speed_o,
    output wire stable_o
);
    reg initialized=0,rate_valid=0,braking=0;
    reg [2:0] window_age=0;
    reg signed [15:0] previous_yaw=0;
    reg signed [16:0] yaw_step=0;
    reg [2:0] command_q=0;
    reg [7:0] speed_q=0;
    wire signed [16:0] raw_delta=$signed({yaw_i[15],yaw_i})-$signed({previous_yaw[15],previous_yaw});
    wire signed [16:0] delta=raw_delta>25736?raw_delta-17'sd51472:
        raw_delta< -25736?raw_delta+17'sd51472:raw_delta;
    wire [16:0] distance=error_i<0?-error_i:error_i;
    wire [16:0] rate=yaw_step<0?-yaw_step:yaw_step;
    wire quiet=rate_valid && rate<=QUIET_DELTA;
    wire approaching=(error_i>0 && yaw_step>0)||(error_i<0 && yaw_step<0);
    // Three 50ms windows of lookahead, bounded by actual sampled angle change.
    wire [18:0] coast_distance={2'b0,rate}+({2'b0,rate}<<1)+ANGLE_TOL;
    assign command_o=enable_i?command_q:3'd0;
    assign speed_o=command_o==0?16'd0:{8'd0,speed_q};
    assign stable_o=enable_i && quiet && distance<=ANGLE_TOL && command_q==0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            initialized<=0;rate_valid<=0;braking<=0;window_age<=0;
            previous_yaw<=0;yaw_step<=0;command_q<=0;speed_q<=0;
        end else if(!enable_i)begin
            initialized<=0;rate_valid<=0;braking<=0;window_age<=0;
            previous_yaw<=yaw_i;yaw_step<=0;command_q<=0;speed_q<=0;
        end else if(tick_i)begin
            if(!initialized)begin initialized<=1;previous_yaw<=yaw_i;window_age<=0;end
            else if(window_age==WINDOW_TICKS-1)begin
                previous_yaw<=yaw_i;yaw_step<=delta;rate_valid<=1;window_age<=0;
            end else window_age<=window_age+1'b1;
            if(!rate_valid || distance<=ANGLE_TOL ||
               (approaching && !quiet && {2'b0,distance}<=coast_distance))begin
                command_q<=0;speed_q<=0;
                if(rate_valid)braking<=1;
            end else if(braking)begin
                // Never reverse a still-coasting chassis. Release only after a
                // complete quiet observation window; direction interlock remains.
                command_q<=0;speed_q<=0;
                if(quiet)braking<=0;
            end else begin
                command_q<=((error_i>0)^inverted_i)?3'd5:3'd6;
                // References stay within the existing trim/PID's supported range.
                speed_q<=distance<2145?8'd4:distance<4290?8'd6:maximum_speed_i;
            end
        end
    end
endmodule
