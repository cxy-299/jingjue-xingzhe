// Four-wheel mecanum mixer.
//
// Wheel order: front-left, front-right, rear-left, rear-right.
// Positive vx is forward, positive vy is right, and positive omega is
// counter-clockwise. Motor polarity can be inverted in the board wrapper.
module mecanum_kinematics #(
    parameter integer MAX_COMMAND = 1000
) (
    input  wire signed [15:0] vx_i,
    input  wire signed [15:0] vy_i,
    input  wire signed [15:0] omega_i,
    output reg signed [15:0] wheel_fl_o,
    output reg signed [15:0] wheel_fr_o,
    output reg signed [15:0] wheel_rl_o,
    output reg signed [15:0] wheel_rr_o
);
    integer fl_i;
    integer fr_i;
    integer rl_i;
    integer rr_i;
    integer max_abs_i;

    always @* begin
        fl_i = vx_i - vy_i - omega_i;
        fr_i = vx_i + vy_i + omega_i;
        rl_i = vx_i + vy_i - omega_i;
        rr_i = vx_i - vy_i + omega_i;

        max_abs_i = 0;
        if ((fl_i < 0 ? -fl_i : fl_i) > max_abs_i)
            max_abs_i = (fl_i < 0 ? -fl_i : fl_i);
        if ((fr_i < 0 ? -fr_i : fr_i) > max_abs_i)
            max_abs_i = (fr_i < 0 ? -fr_i : fr_i);
        if ((rl_i < 0 ? -rl_i : rl_i) > max_abs_i)
            max_abs_i = (rl_i < 0 ? -rl_i : rl_i);
        if ((rr_i < 0 ? -rr_i : rr_i) > max_abs_i)
            max_abs_i = (rr_i < 0 ? -rr_i : rr_i);

        if (max_abs_i > MAX_COMMAND) begin
            fl_i = (fl_i * MAX_COMMAND) / max_abs_i;
            fr_i = (fr_i * MAX_COMMAND) / max_abs_i;
            rl_i = (rl_i * MAX_COMMAND) / max_abs_i;
            rr_i = (rr_i * MAX_COMMAND) / max_abs_i;
        end

        wheel_fl_o = fl_i;
        wheel_fr_o = fr_i;
        wheel_rl_o = rl_i;
        wheel_rr_o = rr_i;
    end
endmodule
