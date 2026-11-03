`timescale 1ns/1ps

module tb_nav_route_executor_signed;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, tick = 0, route_valid = 0, cancel = 0;
    reg [31:0] pos = 0;
    wire active, advance, done, fault;
    wire [2:0] command;

    nav_route_executor #(.CELL_COUNTS(10), .TURN_NEUTRAL_SAMPLES(0)) dut (
        .clk(clk), .rst_n(rst_n), .sample_tick_i(tick),
        .route_valid_i(route_valid), .step_count_i(8'd1),
        .route_bits_i(128'd0),
        .position0_i(pos), .position1_i(pos),
        .position2_i(pos), .position3_i(pos),
        .cancel_i(cancel), .active_o(active), .advance_o(advance),
        .done_o(done), .fault_o(fault), .command_o(command)
    );

    task automatic sample_at(input signed [31:0] value);
        begin
            @(negedge clk); pos = value; tick = 1;
            @(negedge clk); tick = 0;
        end
    endtask

    task automatic load_route;
        begin
            @(negedge clk); route_valid = 1;
            @(negedge clk); route_valid = 0;
            if (!active || command != 1) $fatal(1, "route was not armed");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        load_route();
        sample_at(-1);
        sample_at(-4);
        if (!active || done || fault || dut.average_delta != 4)
            $fatal(1, "negative encoder count prematurely completed cell: delta=%0d", dut.average_delta);
        sample_at(-9);
        if (!active) $fatal(1, "cell completed below threshold");
        sample_at(-10);
        if (active || fault) $fatal(1, "negative ten-count cell did not complete");

        // Reload from a negative base and cross zero in the next cell.
        load_route();
        sample_at(-1);
        if (!active || dut.average_delta != 9)
            $fatal(1, "cross-zero displacement miscounted: delta=%0d", dut.average_delta);
        sample_at(0);
        if (active || fault) $fatal(1, "cross-zero ten-count cell did not complete");
        $display("PASS tb_nav_route_executor_signed");
        $finish;
    end
endmodule
