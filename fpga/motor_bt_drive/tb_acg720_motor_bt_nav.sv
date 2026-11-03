`timescale 1ns/1ps
// BTD6 第一阶段回归：9600 baud 蓝牙路径帧 -> CRC/地图校验 -> 路点方向，
// 再用合成编码器增量确认执行器消费一个 10 cm 路点。
module tb_acg720_motor_bt_nav;
    reg clk = 0, key_n = 0, bt_rx = 1;
    reg [3:0] enc_a = 0, enc_b = 0;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    wire diag_tx, bt_tx;
    integer i, timeout;

    always #500 clk = ~clk; // 1 MHz，匹配本测试实例的参数
    acg720_motor_bt_drive #(
        .CLK_HZ(1_000_000), .PWM_HZ(2_000), .BT_BAUD(10_000),
        .DIAG_BAUD(20_000), .STARTUP_MS(1), .STAGGER_MS(1),
        .KICK_MS(1), .TARGET_COUNTS(4), .BT_TIMEOUT_MS(300),
        .RUN_LIMIT_MS(3000), .NAV_ENABLE(1), .NAV_CELL_COUNTS(4)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(key_n), .bt_uart_rx_i(bt_rx),
        .imu_uart_rx_i(1'b1), .tof0_uart_rx_i(1'b1),
        .encoder_a_i(enc_a), .encoder_b_i(enc_b), .motor_pwm_o(pwm),
        .motor_in1_o(in1), .motor_in2_o(in2), .led_o(led),
        .diag_uart_tx_o(diag_tx), .bt_uart_tx_o(bt_tx)
    );

    task automatic send_byte(input [7:0] value);
        integer bit_number;
        begin
            bt_rx = 0; #100000;
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                bt_rx = value[bit_number]; #100000;
            end
            bt_rx = 1; #100000;
        end
    endtask

    task automatic send_route;
        begin
            // map 0x2601, goal (2,17), route [LEFT, FORWARD], CRC16=0xC284.
            send_byte(8'hAA); send_byte(8'h55); send_byte(8'h03); send_byte(8'h21);
            send_byte(8'h01); send_byte(8'h00); send_byte(8'h07); send_byte(8'h00);
            send_byte(8'h01); send_byte(8'h26); send_byte(8'h02); send_byte(8'h11);
            send_byte(8'h02); send_byte(8'h02); send_byte(8'h00);
            send_byte(8'h84); send_byte(8'hC2);
        end
    endtask

    task automatic quad_step(input [1:0] state);
        begin
            enc_a = {4{state[1]}};
            enc_b = {4{state[0]}};
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        key_n = 1;
        repeat (1500) @(posedge clk);
        if (!dut.ready) $fatal(1, "BTD6 ready timeout");

        send_route();
        timeout = 0;
        while (!dut.nav_active && timeout < 200000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (4) @(posedge clk);
        if (timeout >= 200000 || dut.nav_no_path || !dut.nav_active ||
            dut.g_navigation.u_nav_parser.step_count_o != 2 ||
            dut.nav_command != 3 ||
            dut.g_navigation.u_nav_parser.goal_x_o != 2 ||
            dut.g_navigation.u_nav_parser.goal_y_o != 17)
            $fatal(1, "path did not create expected route: t=%0d no_path=%b active=%b ready=%b state=%0d crc=%0d calc=%04h work=%04h low=%02h len=%0d msg=%02h map=%04h bad=%b steps=%0d cmd=%0d goal=(%0d,%0d)",
                   timeout, dut.nav_no_path, dut.nav_active, dut.nav_route_ready,
                   dut.g_navigation.u_nav_parser.state,
                   dut.g_navigation.u_nav_parser.crc_error_count_o,
                   dut.g_navigation.u_nav_parser.last_crc_calc_o,
                   dut.g_navigation.u_nav_parser.crc_work,
                   {dut.g_navigation.u_nav_parser.crc_low},
                   dut.g_navigation.u_nav_parser.payload_length,
                   dut.g_navigation.u_nav_parser.message_type,
                   dut.g_navigation.u_nav_parser.stage_map_id,
                   dut.g_navigation.u_nav_parser.stage_bad_direction,
                   dut.g_navigation.u_nav_parser.step_count_o, dut.nav_command,
                   dut.g_navigation.u_nav_parser.goal_x_o,
                   dut.g_navigation.u_nav_parser.goal_y_o);

        // An explicit S must cancel the route; it must not resume merely
        // because the old path remains in the parser state.
        send_byte("S");
        repeat (20) @(posedge clk);
        if (dut.nav_active)
            $fatal(1, "explicit S did not cancel active route");
        send_route();
        timeout = 0;
        while (!dut.nav_active && timeout < 200000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        if (timeout >= 200000)
            $fatal(1, "route did not re-arm after explicit S and new frame");

        // 00->01->11->10->00 is four valid quadrature transitions.
        quad_step(2'b00); quad_step(2'b01); quad_step(2'b11);
        quad_step(2'b10); quad_step(2'b00);
        timeout = 0;
        while (dut.g_navigation.u_nav_route.index != 1 && timeout < 50000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        timeout = 0;
        while (dut.nav_command != 1 && timeout < 200000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        if (timeout >= 200000 || !dut.nav_active || dut.g_navigation.u_nav_route.fault_o || dut.nav_command != 1)
            $fatal(1, "encoder distance did not advance the first waypoint safely: t=%0d active=%b fault=%b current=(%0d,%0d)", timeout,
                     dut.nav_active, dut.g_navigation.u_nav_route.fault_o,
                   dut.g_navigation.u_nav_route.index, dut.g_navigation.u_nav_route.steps);

        quad_step(2'b00); quad_step(2'b01); quad_step(2'b11);
        quad_step(2'b10); quad_step(2'b00);
        timeout = 0;
        while (dut.nav_active && timeout < 50000) begin @(posedge clk); timeout = timeout + 1; end
        if (timeout >= 50000 || dut.g_navigation.u_nav_route.fault_o)
            $fatal(1, "encoder distance did not finish the route safely");

        $display("PASS tb_acg720_motor_bt_nav: Bluetooth route -> FPGA encoder waypoint");
        $finish;
    end
endmodule
