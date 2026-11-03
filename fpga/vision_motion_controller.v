// Fixed-point motion policy for the FPGA side of the robot.
//
// Command units are milli-units: 1000 means 1.000 normalized speed.
// Vision controls lateral alignment, while ToF controls forward approach.
// The controller intentionally never commands reverse motion from ToF data;
// a hard-stop, invalid ToF value, lost UART link, or emergency stop clears all
// translational and rotational commands.
module vision_motion_controller #(
    parameter integer TARGET_DISTANCE_MM = 500,
    parameter integer DISTANCE_DEADBAND_MM = 50,
    parameter integer HARD_STOP_MM = 250,
    parameter integer MAX_VX = 300,
    parameter integer MAX_VY = 220,
    parameter integer SEARCH_OMEGA = 200,
    parameter integer CENTER_DEADBAND = 800,
    parameter integer LATERAL_DENOM = 10000 - CENTER_DEADBAND,
    parameter integer DISTANCE_DIVISOR = 4
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   control_tick_i,
    input  wire                   link_alive_i,
    input  wire                   target_valid_i,
    input  wire                   target_confirmed_i,
    input  wire signed [15:0]     center_error_i,
    input  wire [15:0]            tof_distance_mm_i,
    input  wire                   tof_valid_i,
    input  wire                   estop_i,

    output reg signed [15:0]      vx_cmd_o,
    output reg signed [15:0]      vy_cmd_o,
    output reg signed [15:0]      omega_cmd_o,
    output reg [3:0]              state_o,
    output reg                    safe_stop_o
);
    localparam [3:0] STATE_STOP       = 4'd0;
    localparam [3:0] STATE_SEARCH     = 4'd1;
    localparam [3:0] STATE_APPROACH   = 4'd2;
    localparam [3:0] STATE_ALIGN      = 4'd3;
    localparam [3:0] STATE_FOLLOW     = 4'd4;
    localparam [3:0] STATE_DISTANCE_OK= 4'd5;
    localparam [3:0] STATE_TARGET_HOLD= 4'd6;
    localparam [3:0] STATE_HARD_STOP  = 4'd7;
    localparam [3:0] STATE_TOF_FAULT  = 4'd8;
    localparam [3:0] STATE_LINK_FAULT = 4'd9;
    localparam [3:0] STATE_ESTOP      = 4'd10;

    reg signed [15:0] next_vx;
    reg signed [15:0] next_vy;
    reg signed [15:0] next_omega;
    reg [3:0] next_state;
    reg next_safe_stop;

    integer distance_error_i;
    integer vx_calc_i;
    integer lateral_abs_i;
    integer vy_calc_i;

    always @* begin
        next_vx = 16'sd0;
        next_vy = 16'sd0;
        next_omega = 16'sd0;
        next_state = STATE_STOP;
        next_safe_stop = 1'b0;

        distance_error_i = 0;
        vx_calc_i = 0;
        lateral_abs_i = 0;
        vy_calc_i = 0;

        if (estop_i) begin
            next_state = STATE_ESTOP;
            next_safe_stop = 1'b1;
        end else if (!tof_valid_i) begin
            next_state = STATE_TOF_FAULT;
            next_safe_stop = 1'b1;
        end else if (tof_distance_mm_i <= HARD_STOP_MM) begin
            next_state = STATE_HARD_STOP;
            next_safe_stop = 1'b1;
        end else if (!link_alive_i) begin
            next_state = STATE_LINK_FAULT;
            next_safe_stop = 1'b1;
        end else if (!target_valid_i) begin
            // Searching is allowed to rotate in place, but never to drive
            // forward or sideways without a current target.
            next_state = STATE_SEARCH;
            next_omega = SEARCH_OMEGA;
        end else if (!target_confirmed_i) begin
            next_state = STATE_TARGET_HOLD;
        end else begin
            distance_error_i = tof_distance_mm_i - TARGET_DISTANCE_MM;
            if (tof_distance_mm_i > TARGET_DISTANCE_MM + DISTANCE_DEADBAND_MM) begin
                vx_calc_i = distance_error_i / DISTANCE_DIVISOR;
                if (vx_calc_i > MAX_VX)
                    vx_calc_i = MAX_VX;
                if (vx_calc_i < 0)
                    vx_calc_i = 0;
                next_vx = vx_calc_i;
            end

            if (center_error_i > CENTER_DEADBAND) begin
                lateral_abs_i = center_error_i - CENTER_DEADBAND;
                vy_calc_i = (lateral_abs_i * MAX_VY) / LATERAL_DENOM;
                if (vy_calc_i > MAX_VY)
                    vy_calc_i = MAX_VY;
                next_vy = vy_calc_i;
            end else if (center_error_i < -CENTER_DEADBAND) begin
                lateral_abs_i = (-center_error_i) - CENTER_DEADBAND;
                vy_calc_i = (lateral_abs_i * MAX_VY) / LATERAL_DENOM;
                if (vy_calc_i > MAX_VY)
                    vy_calc_i = MAX_VY;
                next_vy = -vy_calc_i;
            end

            if ((next_vx != 0) && (next_vy != 0))
                next_state = STATE_FOLLOW;
            else if (next_vx != 0)
                next_state = STATE_APPROACH;
            else if (next_vy != 0)
                next_state = STATE_ALIGN;
            else
                next_state = STATE_DISTANCE_OK;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vx_cmd_o <= 16'sd0;
            vy_cmd_o <= 16'sd0;
            omega_cmd_o <= 16'sd0;
            state_o <= STATE_STOP;
            safe_stop_o <= 1'b1;
        end else if (control_tick_i) begin
            vx_cmd_o <= next_vx;
            vy_cmd_o <= next_vy;
            omega_cmd_o <= next_omega;
            state_o <= next_state;
            safe_stop_o <= next_safe_stop;
        end
    end
endmodule
