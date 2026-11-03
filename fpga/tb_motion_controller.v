`timescale 1ns/1ps

// Small self-checking smoke test for the policy layer.
// Run it with any Verilog-2001 simulator after adding
// vision_motion_controller.v to the simulation file list.
module tb_motion_controller;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg control_tick_i = 1'b0;
    reg link_alive_i = 1'b0;
    reg target_valid_i = 1'b0;
    reg target_confirmed_i = 1'b0;
    reg signed [15:0] center_error_i = 16'sd0;
    reg [15:0] tof_distance_mm_i = 16'd0;
    reg tof_valid_i = 1'b0;
    reg estop_i = 1'b0;

    wire signed [15:0] vx_cmd_o;
    wire signed [15:0] vy_cmd_o;
    wire signed [15:0] omega_cmd_o;
    wire [3:0] state_o;
    wire safe_stop_o;

    vision_motion_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .control_tick_i(control_tick_i),
        .link_alive_i(link_alive_i),
        .target_valid_i(target_valid_i),
        .target_confirmed_i(target_confirmed_i),
        .center_error_i(center_error_i),
        .tof_distance_mm_i(tof_distance_mm_i),
        .tof_valid_i(tof_valid_i),
        .estop_i(estop_i),
        .vx_cmd_o(vx_cmd_o),
        .vy_cmd_o(vy_cmd_o),
        .omega_cmd_o(omega_cmd_o),
        .state_o(state_o),
        .safe_stop_o(safe_stop_o)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(negedge clk);
            control_tick_i = 1'b1;
            @(negedge clk);
            control_tick_i = 1'b0;
        end
    endtask

    task check;
        input signed [15:0] expected_vx;
        input signed [15:0] expected_vy;
        input signed [15:0] expected_omega;
        input expected_stop;
        begin
            if (vx_cmd_o !== expected_vx || vy_cmd_o !== expected_vy ||
                omega_cmd_o !== expected_omega || safe_stop_o !== expected_stop) begin
                $display("FAIL vx=%0d vy=%0d omega=%0d stop=%b", vx_cmd_o,
                         vy_cmd_o, omega_cmd_o, safe_stop_o);
                $finish;
            end
        end
    endtask

    initial begin
        // Reset and sensor fault must be stopped.
        #12;
        rst_n = 1'b1;
        tick;
        check(16'sd0, 16'sd0, 16'sd0, 1'b1);

        // A confirmed target 4,000 pixels to the left and 1.5 m away:
        // approach forward and command negative lateral speed.
        link_alive_i = 1'b1;
        target_valid_i = 1'b1;
        target_confirmed_i = 1'b1;
        tof_valid_i = 1'b1;
        tof_distance_mm_i = 16'd1500;
        center_error_i = -16'sd4000;
        tick;
        if (vx_cmd_o <= 0 || vy_cmd_o >= 0 || safe_stop_o !== 1'b0) begin
            $display("FAIL confirmed follow policy");
            $finish;
        end

        // No target allows search rotation but no translation.
        target_valid_i = 1'b0;
        target_confirmed_i = 1'b0;
        tick;
        if (vx_cmd_o !== 0 || vy_cmd_o !== 0 || omega_cmd_o === 0 || safe_stop_o !== 1'b0) begin
            $display("FAIL search policy");
            $finish;
        end

        // Hard stop always clears all commands.
        target_valid_i = 1'b1;
        target_confirmed_i = 1'b1;
        tof_distance_mm_i = 16'd200;
        tick;
        check(16'sd0, 16'sd0, 16'sd0, 1'b1);

        $display("PASS tb_motion_controller");
        $finish;
    end
endmodule
