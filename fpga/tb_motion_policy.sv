`timescale 1ns/1ps

// 视觉+ToF 策略的自检平台。仿真顶层选本模块，不选真实机器人顶层。
// 每次 tick() 代表一个 100 Hz 控制周期；本测试只验证策略，不驱动实体电机。
module tb_motion_policy;
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
    integer test_step = 0;

    wire signed [15:0] vx_cmd_o;
    wire signed [15:0] vy_cmd_o;
    wire signed [15:0] omega_cmd_o;
    wire [3:0] state_o;
    wire safe_stop_o;

    // state_o 编码与 vision_motion_controller.v 一致，便于波形对照。
    localparam [3:0] STOP = 0, SEARCH = 1, APPROACH = 2, ALIGN = 3,
                     FOLLOW = 4, DISTANCE_OK = 5, TARGET_HOLD = 6,
                     HARD_STOP = 7, TOF_FAULT = 8, LINK_FAULT = 9,
                     ESTOP = 10;

    vision_motion_controller dut (
        .clk(clk), .rst_n(rst_n), .control_tick_i(control_tick_i),
        .link_alive_i(link_alive_i), .target_valid_i(target_valid_i),
        .target_confirmed_i(target_confirmed_i), .center_error_i(center_error_i),
        .tof_distance_mm_i(tof_distance_mm_i), .tof_valid_i(tof_valid_i),
        .estop_i(estop_i), .vx_cmd_o(vx_cmd_o), .vy_cmd_o(vy_cmd_o),
        .omega_cmd_o(omega_cmd_o), .state_o(state_o), .safe_stop_o(safe_stop_o)
    );

    always #5 clk = ~clk;

    // 在下降沿切换控制使能，避开 DUT 的上升沿采样竞争。
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
        input [3:0] expected_state;
        input expected_stop;
        begin
            if (vx_cmd_o !== expected_vx || vy_cmd_o !== expected_vy ||
                omega_cmd_o !== expected_omega || state_o !== expected_state ||
                safe_stop_o !== expected_stop) begin
                $display("FAIL step=%0d vx=%0d vy=%0d omega=%0d state=%0d stop=%b",
                         test_step, vx_cmd_o, vy_cmd_o, omega_cmd_o, state_o, safe_stop_o);
                $finish;
            end
        end
    endtask

    initial begin
        // 0. 复位时电机命令全零，且处于安全停车。
        #12;
        check(0, 0, 0, STOP, 1'b1);
        rst_n = 1'b1;
        test_step = 1;
        tick;
        check(0, 0, 0, TOF_FAULT, 1'b1);

        // 2. 急停优先级最高，即使 ToF 也无效仍显示 ESTOP。
        test_step = 2;
        estop_i = 1'b1;
        tick;
        check(0, 0, 0, ESTOP, 1'b1);

        // 3. 250 mm 是硬停车边界；不允许继续前进。
        test_step = 3;
        estop_i = 1'b0;
        tof_valid_i = 1'b1;
        tof_distance_mm_i = 16'd250;
        tick;
        check(0, 0, 0, HARD_STOP, 1'b1);

        // 4. 距离安全但通信失联，同样停车。
        test_step = 4;
        tof_distance_mm_i = 16'd1500;
        tick;
        check(0, 0, 0, LINK_FAULT, 1'b1);

        // 5. 无目标时仅原地旋转搜索，前进和横移必须为零。
        test_step = 5;
        link_alive_i = 1'b1;
        tick;
        check(0, 0, 200, SEARCH, 1'b0);

        // 6. 检测到目标但未连续确认：保持不动，避免误检启动。
        test_step = 6;
        target_valid_i = 1'b1;
        tick;
        check(0, 0, 0, TARGET_HOLD, 1'b0);

        // 7. 已确认且距离 1.5 m、目标偏左：向前并向左横移。
        // vx=(1500-500)/4=250；vy=-(4000-800)*220/9200=-76。
        test_step = 7;
        target_confirmed_i = 1'b1;
        center_error_i = -16'sd4000;
        tick;
        check(250, -76, 0, FOLLOW, 1'b0);

        // 控制周期之间输出保持原值，不随输入的瞬时变化乱跳。
        test_step = 8;
        center_error_i = 16'sd0;
        #1;
        check(250, -76, 0, FOLLOW, 1'b0);
        tick;
        check(250, 0, 0, APPROACH, 1'b0);

        // 9. 距离合适但目标偏右：只向右横移。
        test_step = 9;
        tof_distance_mm_i = 16'd500;
        center_error_i = 16'sd4000;
        tick;
        check(0, 76, 0, ALIGN, 1'b0);

        // 10. 距离和视觉中心都在死区：不运动，但仍保持可运行状态。
        test_step = 10;
        center_error_i = 16'sd0;
        tick;
        check(0, 0, 0, DISTANCE_OK, 1'b0);

        // 11. 死区边界 550 mm 和中心误差 800，不产生动作。
        test_step = 11;
        tof_distance_mm_i = 16'd550;
        center_error_i = 16'sd800;
        tick;
        check(0, 0, 0, DISTANCE_OK, 1'b0);

        $display("PASS tb_motion_policy: priority, search, confirm, follow, deadbands");
        $finish;
    end
endmodule
