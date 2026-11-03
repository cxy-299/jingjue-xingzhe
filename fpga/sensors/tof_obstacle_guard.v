// Four-channel ToF safety policy. Distances are millimetres.
// A missing/invalid set is deliberately fail-safe: zero speed and stop.
module tof_obstacle_guard #(
    parameter integer HARD_STOP_MM = 250,
    parameter integer DECEL_MM = 500,
    parameter integer CLEAR_MM = 800
) (
    input wire [15:0] d0_i,
    input wire [15:0] d1_i,
    input wire [15:0] d2_i,
    input wire [15:0] d3_i,
    input wire [3:0] valid_i,
    output reg valid_o,
    output reg obstacle_o,
    output reg hard_stop_o,
    output reg decel_o,
    output reg [9:0] speed_scale_permille_o,
    output reg [15:0] nearest_mm_o
);
    integer min_d;
    always @* begin
        min_d = 65535;
        if (valid_i[0] && d0_i < min_d) min_d = d0_i;
        if (valid_i[1] && d1_i < min_d) min_d = d1_i;
        if (valid_i[2] && d2_i < min_d) min_d = d2_i;
        if (valid_i[3] && d3_i < min_d) min_d = d3_i;
        valid_o = |valid_i;
        obstacle_o = 1'b0;
        hard_stop_o = 1'b0;
        decel_o = 1'b0;
        nearest_mm_o = (min_d > 65535) ? 16'hffff : min_d[15:0];
        speed_scale_permille_o = 10'd0;
        if (!valid_o) begin
            obstacle_o = 1'b1;
            hard_stop_o = 1'b1;
        end else if (min_d <= HARD_STOP_MM) begin
            obstacle_o = 1'b1;
            hard_stop_o = 1'b1;
        end else if (min_d < DECEL_MM) begin
            obstacle_o = 1'b1;
            decel_o = 1'b1;
            // Discrete limits avoid a long combinational divide into PWM.
            speed_scale_permille_o = 10'd500;
        end else if (min_d < CLEAR_MM) begin
            decel_o = 1'b1;
            speed_scale_permille_o = 10'd750;
        end else begin
            speed_scale_permille_o = 10'd1000;
        end
    end
endmodule
