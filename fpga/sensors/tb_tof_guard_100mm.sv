`timescale 1ns/1ps
module tb_tof_guard_100mm;
    reg [15:0] distance = 0;
    reg [3:0] valid = 0;
    wire sensor_valid, obstacle, hard_stop, decel;
    wire [9:0] scale;
    wire [15:0] nearest;
    tof_obstacle_guard #(.HARD_STOP_MM(100)) dut (
        .d0_i(distance), .d1_i(16'd0), .d2_i(16'd0), .d3_i(16'd0),
        .valid_i(valid), .valid_o(sensor_valid), .obstacle_o(obstacle),
        .hard_stop_o(hard_stop), .decel_o(decel),
        .speed_scale_permille_o(scale), .nearest_mm_o(nearest)
    );
    task automatic expect_state(input [15:0] mm, input [3:0] v,
                                input h, input [9:0] s);
        begin
            distance = mm; valid = v; #1;
            if (hard_stop !== h || scale !== s)
                $fatal(1, "mm=%0d valid=%b hard=%b scale=%0d; expected %b/%0d",
                       mm, v, hard_stop, scale, h, s);
        end
    endtask
    initial begin
        expect_state(16'd0,   4'b0000, 1'b1, 10'd0); // unplug/stale
        expect_state(16'd99,  4'b0001, 1'b1, 10'd0);
        expect_state(16'd100, 4'b0001, 1'b1, 10'd0);
        expect_state(16'd101, 4'b0001, 1'b0, 10'd500);
        expect_state(16'd250, 4'b0001, 1'b0, 10'd500);
        expect_state(16'd499, 4'b0001, 1'b0, 10'd500);
        expect_state(16'd500, 4'b0001, 1'b0, 10'd750);
        expect_state(16'd799, 4'b0001, 1'b0, 10'd750);
        expect_state(16'd800, 4'b0001, 1'b0, 10'd1000);
        $display("TOF_GUARD_100MM_PASS");
        $finish;
    end
endmodule
