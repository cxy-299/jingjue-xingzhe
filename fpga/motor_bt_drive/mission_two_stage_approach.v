// Smart mission only. Continuous qualified coarse approach, then a sticky
// arrival+100mm handoff and fresh-observation-authorized fine steps.
// No object identity inference, motor command ownership or hard-stop override.
module mission_two_stage_approach #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer HANDOFF_MM=100, QUIET_TICKS=101,
    parameter integer FINE_RUN_MS=60, FINE_REST_MS=300
)(
    input wire clk,rst_n,active_i,sample_tick_i,
    input wire target_ok_i,range_ok_i,centered_i,eligible_i,
    input wire new_matching_i,distance_sample_i,wheels_still_i,motion_i,
    input wire [15:0] distance_i,arrival_i,
    input wire [3:0] speed_cap_i,
    output wire forward_o,output wire [15:0] speed_o,
    output reg final_o=0,output reg fine_ready_o=0
);
    localparam integer RUN=(CLK_HZ/1000)*FINE_RUN_MS;
    localparam integer REST=(CLK_HZ/1000)*FINE_REST_MS;
    localparam integer AGE_W=$clog2((RUN>REST?RUN:REST)+1);
    localparam integer QUIET_W=$clog2(QUIET_TICKS+1);
    reg [QUIET_W-1:0] quiet=0;
    reg [1:0] hits=0,phase=0; // 0 await fresh stopped frame,1 step,2 coast
    reg [AGE_W-1:0] age=0;
    // Physical command_o includes the complete yaw/owner/safety cone. Do not
    // feed that combinational chain through the fine timer's24 register D muxes.
    // This register affects parked/coast bookkeeping only; current qualified,
    // live handoff, hard-stop and the quiet-window motion reset stay immediate.
    reg motion_q=0;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)motion_q<=0;else motion_q<=motion_i;
    wire [16:0] handoff={1'b0,arrival_i}+HANDOFF_MM;
    wire at_handoff={1'b0,distance_i}<=handoff;
    wire above_arrival={1'b0,distance_i}>{1'b0,arrival_i}+17'd25;
    wire qualified=active_i && eligible_i && target_ok_i && range_ok_i && centered_i;
    // The live handoff gate precedes the sticky flag, so a crossing cannot
    // leave one more coarse cycle on the physical forward output.
    assign forward_o=qualified && above_arrival &&
        ((!final_o && !at_handoff) || (final_o && fine_ready_o && phase==1 && age<RUN));
    wire [3:0] coarse_cap={1'b0,distance_i}<={1'b0,arrival_i}+17'd200 ? 4 : 8;
    assign speed_o=!forward_o ? 0 : final_o ? 16'd4 :
        (speed_cap_i<coarse_cap ? {12'd0,speed_cap_i}:{12'd0,coarse_cap});
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            final_o<=0;fine_ready_o<=0;quiet<=0;hits<=0;phase<=0;age<=0;
        end else if(!active_i)begin
            final_o<=0;fine_ready_o<=0;quiet<=0;hits<=0;phase<=0;age<=0;
        end else begin
            // Only committed fresh coherent ToF can latch the handoff. It
            // never unlatches on a farther background return or a visual miss.
            if(!final_o && distance_sample_i && range_ok_i && at_handoff)begin
                final_o<=1;fine_ready_o<=0;quiet<=0;hits<=0;phase<=0;age<=0;
            end
            if(final_o && !fine_ready_o)begin
                if(motion_i || !wheels_still_i || !target_ok_i || !range_ok_i)begin quiet<=0;hits<=0;end
                else begin
                    if(sample_tick_i && quiet<QUIET_TICKS)quiet<=quiet+1'b1;
                    if(new_matching_i && quiet>=QUIET_TICKS)begin
                        if(hits<2)hits<=hits+1'b1;
                        if(hits>=1)fine_ready_o<=1;
                    end
                end
            end
            if(!qualified || !above_arrival || !fine_ready_o)begin phase<=0;age<=0;end
            else if(phase==0)begin
                if(new_matching_i && wheels_still_i && !motion_q)begin phase<=1;age<=0;end
            end else if(phase==1)begin
                if(age>=RUN-1)begin phase<=2;age<=0;end
                else age<=age+1'b1;
            end else if(phase==2)begin
                if(age<REST)age<=age+1'b1;
                else if(wheels_still_i && !motion_q)begin phase<=0;age<=0;end
            end
        end
    end
endmodule
