`timescale 1ns/1ps
// FPGA 端路径执行器：路径已由 GUI/Pi 在同一固定地图上计算并经过 CRC 传输。
// 每个方向占一个 10 cm 单元格，编码器平均绝对增量达到 CELL_COUNTS 才前进。
module nav_route_executor #(
    parameter integer CELL_COUNTS = 1000,
    // 100 Hz 路点采样下，方向改变后给电机约 100 ms 中性时间，
    // 避免麦克纳姆对角轮换向瞬态被 PI 反向反馈保护误判。
    parameter integer TURN_NEUTRAL_SAMPLES = 10,
    // R15 only: break the four-wheel 32-bit progress path into clock stages.
    // Legacy builds retain their original same-sample arithmetic.
    parameter integer PROGRESS_PIPELINE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire sample_tick_i,
    input wire route_valid_i,
    input wire [7:0] step_count_i,
    input wire [127:0] route_bits_i,
    input wire [31:0] position0_i,
    input wire [31:0] position1_i,
    input wire [31:0] position2_i,
    input wire [31:0] position3_i,
    input wire cancel_i,
    output reg active_o = 0,
    output reg advance_o = 0,
    output reg done_o = 0,
    output reg fault_o = 0,
    output reg [2:0] command_o = 0
);
    localparam [2:0] STOP=0, FORWARD=1, BACKWARD=2, LEFT=3, RIGHT=4;
    reg [7:0] steps, index;
    reg [127:0] bits;
    reg [31:0] base0,base1,base2,base3;
    reg [15:0] neutral_count;
    function [31:0] abs_diff;
        input [31:0] a; input [31:0] b;
        reg [31:0] delta;
        begin
            // Encoder positions are signed two's-complement counters.  Use a
            // modular subtraction, then take its signed magnitude.  An
            // unsigned comparison would turn a small negative displacement
            // from zero into ~2^32 counts and finish a cell immediately.
            // A physical 10 cm cell cannot accumulate 2^31 transitions.
            delta = a - b;
            abs_diff = delta[31] ? (~delta + 32'd1) : delta;
        end
    endfunction
    wire [31:0] d0=abs_diff(position0_i,base0), d1=abs_diff(position1_i,base1),
                d2=abs_diff(position2_i,base2), d3=abs_diff(position3_i,base3);
    wire [33:0] sum={2'b0,d0}+{2'b0,d1}+{2'b0,d2}+{2'b0,d3};
    wire [31:0] average_delta=sum[33:2];
    wire progress_ready, cell_reached;
    wire retire_cell = active_o && sample_tick_i && neutral_count == 0 &&
                       progress_ready && cell_reached;
    generate if (PROGRESS_PIPELINE) begin : g_progress
        reg [31:0] delta0,delta1,delta2,delta3;
        reg [31:0] mag0,mag1,mag2,mag3;
        reg [32:0] pair01,pair23;
        reg [33:0] total;
        reg reached;
        reg [4:0] valid;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                delta0<=0;delta1<=0;delta2<=0;delta3<=0;
                mag0<=0;mag1<=0;mag2<=0;mag3<=0;
                pair01<=0;pair23<=0;total<=0;reached<=0;valid<=0;
            end else begin
                delta0<=position0_i-base0;delta1<=position1_i-base1;
                delta2<=position2_i-base2;delta3<=position3_i-base3;
                mag0<=delta0[31] ? (~delta0+32'd1) : delta0;
                mag1<=delta1[31] ? (~delta1+32'd1) : delta1;
                mag2<=delta2[31] ? (~delta2+32'd1) : delta2;
                mag3<=delta3[31] ? (~delta3+32'd1) : delta3;
                pair01<={1'b0,mag0}+{1'b0,mag1};
                pair23<={1'b0,mag2}+{1'b0,mag3};
                total<={1'b0,pair01}+{1'b0,pair23};
                reached<=total[33:2]>=CELL_COUNTS;
                // Route replacement and every new base invalidate ALL older
                // progress. A sample during refill waits; never double-advance.
                if (cancel_i || route_valid_i || !active_o || retire_cell)
                    valid<=0;
                else valid<={valid[3:0],1'b1};
            end
        end
        assign progress_ready=valid[4];
        assign cell_reached=reached;
    end else begin : g_direct_progress
        assign progress_ready=1'b1;
        assign cell_reached=average_delta>=CELL_COUNTS;
    end endgenerate
    always @* begin
        command_o=STOP;
        if (active_o && index < steps && neutral_count == 0) begin
            case (bits[index*2 +: 2])
                2'd0: command_o=FORWARD;
                2'd1: command_o=BACKWARD;
                2'd2: command_o=LEFT;
                2'd3: command_o=RIGHT;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_o<=0; advance_o<=0; done_o<=0; fault_o<=0;
            steps<=0; index<=0; bits<=0;
            base0<=0;base1<=0;base2<=0;base3<=0;
            neutral_count<=0;
        end else begin
            advance_o<=0; done_o<=0;
            if (cancel_i) begin
                // ToF hard stop or explicit S cancels the stale route.  The
                // route must be sent again after the obstacle is cleared;
                // merely removing the obstacle must never restart motion.
                active_o<=0;
                neutral_count<=0;
            end else if (route_valid_i) begin
                if (step_count_i==0 || step_count_i>64) begin
                    active_o<=0; fault_o<=1;
                end else begin
                    steps<=step_count_i; index<=0; bits<=route_bits_i; active_o<=1; fault_o<=0;
                    base0<=position0_i;base1<=position1_i;base2<=position2_i;base3<=position3_i;
                    neutral_count<=0;
                end
            end else if (active_o && sample_tick_i) begin
                if (neutral_count != 0) begin
                    neutral_count <= neutral_count - 1'b1;
                end else if (progress_ready && cell_reached) begin
                    advance_o<=1;
                    base0<=position0_i;base1<=position1_i;base2<=position2_i;base3<=position3_i;
                    if (index + 1'b1 >= steps) begin active_o<=0; done_o<=1; end
                    else begin
                        if (TURN_NEUTRAL_SAMPLES > 0 &&
                            bits[index*2 +: 2] != bits[(index+1'b1)*2 +: 2])
                            neutral_count <= TURN_NEUTRAL_SAMPLES;
                        index<=index+1'b1;
                    end
                end
            end
        end
    end
endmodule
