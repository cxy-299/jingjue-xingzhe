`timescale 1ns/1ps
`include "../nav/sin12_map.vh"
module tb_sin12_r20_full #(parameter CONTROL_REV=16);
    reg clk=0;always #5 clk=~clk;
    reg rst=0,rx=1;
    reg [7:0] frames[0:87];reg [7:0] sample_div=0;
    wire [3:0] pwm,in1,in2;wire [5:0] leds;
    always @(posedge clk)sample_div<=sample_div==99?0:sample_div+1'b1;
    acg720_motor_bt_drive #(.REV5_ENABLE(CONTROL_REV),.CLK_HZ(10000),.PWM_HZ(100),.BT_BAUD(1000),.DIAG_BAUD(1000),
        .SENSOR_IMU_BAUD(1000),.SENSOR_TOF_BAUD(1000),.STARTUP_MS(1),
        .STAGGER_MS(125),.KICK_MS(10),.LOSS_TICKS(255),.AUTO_NAV_ENABLE(1),.AUTO_MAP_ID(`SIN12_MAP_ID),.AUTO_MAP_BITS(`SIN12_MAP_BITS),
        .MISSION_ENABLE(1),.ROTATE_ENABLE(1),.SENSOR_ENABLE(1),.NAV_ENABLE(1),.VISION_ENABLE(1),
        .TOF_HARD_STOP_MM(100)) dut(
        .clk_50m_i(clk),.key_s0_n_i(rst),.bt_uart_rx_i(rx),.pi_uart_rx_i(1'b1),
        .imu_uart_rx_i(1'b1),.tof0_uart_rx_i(1'b1),.encoder_a_i(4'b0),.encoder_b_i(4'b0),
        .motor_pwm_o(pwm),.motor_in1_o(in1),.motor_in2_o(in2),.led_o(leds),
        .diag_uart_tx_o(),.bt_uart_tx_o());
    task send_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk);rx=0;repeat(10)@(negedge clk);
            for(i=0;i<8;i++)begin rx=b[i];repeat(10)@(negedge clk);end
            rx=1;repeat(12)@(negedge clk);
        end
    endtask
    task frame(input integer n);
        integer k;begin for(k=0;k<22;k++)send_byte(frames[n*22+k]);end
    endtask
    initial begin
        if(dut.g_autonav.u_guard.EARLY_STOP_MM!=200 || dut.g_autonav.u_guard.ADAPTIVE_DETOUR!=1 || dut.g_autonav.u_guard.CONSERVATIVE_CELLS!=1 || dut.TOF_HARD_STOP_MM!=100)
            $fatal(1,"R20 adaptive/200mm/supercover/100mm integration mismatch");
        if(dut.g_autonav.u_guard.FIXED_LEFT_DETOUR!=1) $fatal(1,"R20 detour disabled");
        if(dut.g_autonav.u_guard.DETOUR_FORWARD_CELLS!=3 || dut.g_autonav.u_guard.LATCH_NEAR_EVENT!=1)
            $fatal(1,"R20 extended detour/near latch not integrated");
        if(dut.g_navigation.u_nav_route.PROGRESS_PIPELINE!=1)
            $fatal(1,"R20 route progress pipeline was not enabled");
        if(dut.g_mission.u_guard.TWO_STAGE_APPROACH!=1 || dut.g_mission.u_guard.LEASE_MS!=600 || dut.BT_TIMEOUT_MS!=300)
            $fatal(1,"R20 mission-only lease contract mismatch");
        if(dut.g_mission.u_guard.OBSERVE_SETTLE_MS!=1000 ||
           dut.g_mission.u_guard.RECOVERY_RUN_MS!=100 ||
           dut.g_mission.u_guard.RECOVERY_REST_MS!=1000 ||
           dut.g_mission.u_guard.ALIGN_REST_MS!=1000 ||
           dut.g_mission.u_guard.APPROACH_REST_MS!=300)
            $fatal(1,"R20 production cadence parameters mismatch");
        if(dut.g_autonav.u_guard.CELL_COUNTS!=500 || dut.g_autonav.u_guard.ROUND_POSE_MM!=1 ||
           dut.g_navigation.u_nav_route.CELL_COUNTS!=1000)
            $fatal(1,"R20 forward calibration leaked into legacy lateral route");
        $readmemh("sin12_r20_packet_frames.mem",frames);
        force dut.imu_angle_valid=1'b1;force dut.imu_yaw_raw=32'h00000000;
        force dut.tof_valid=4'b0001;force dut.tof_hard_stop=1'b0;
        force dut.tof_sample=(sample_div==0);force dut.tof0_distance_mm=16'd1000;
        force dut.tof_speed_scale_permille=10'd1000;
        repeat(5)@(negedge clk);rst=1;repeat(2200)@(negedge clk);
        if(in1||in2)$fatal(1,"boot outputs active");
        send_byte("S");repeat(2200)@(negedge clk);frame(1);
        if(dut.auto_active || in1 || in2)$fatal(1,"bad CRC accepted or ASCII leaked");
        frame(2);
        if(dut.auto_active || in1 || in2)$fatal(1,"obsolete map accepted");
        frame(3);
        if(dut.auto_active || in1 || in2 || dut.auto_reason!=6)$fatal(1,"old 333-count packet accepted by R20");
        send_byte("S");repeat(2200)@(negedge clk);
        frame(0);
        repeat(15)begin send_byte("N");repeat(500)@(negedge clk);end
        if(!dut.auto_active || dut.auto_state!=7 || in1!=4'b1010 || in2!=4'b0101)
            $fatal(1,"goal motor integration failed state=%d reason=%d in1=%b in2=%b",dut.auto_state,dut.auto_reason,in1,in2);
        if(dut.command || dut.nav_active || dut.vision_active || dut.mission_active || dut.turn_active)
            $fatal(1,"multiple control owners");
        force dut.tof_hard_stop=1'b1;#1;
        if(in1||in2||pwm)$fatal(1,"live ToF stop waited for a control clock");
        repeat(1)@(negedge clk);
        if(in1||in2||pwm)$fatal(1,"near obstacle did not stop physical outputs");
        force dut.tof_hard_stop=1'b0;#1;
        if(CONTROL_REV>=3 && (in1||in2||pwm))$fatal(1,"one-cycle stop clearance rebounded before owner cancellation");
        repeat(4)@(negedge clk);
        if(dut.auto_active)$fatal(1,"ToF pulse not latched by owner");
        send_byte("N");repeat(100)@(negedge clk);
        if(dut.auto_active || in1 || in2)$fatal(1,"N resumed aborted task");
        send_byte("S");repeat(2200)@(negedge clk);frame(0);send_byte("N");
        if(dut.auto_active || in1 || in2)$fatal(1,"sequence replay accepted");
        // Stillness uses raw encoder feedback, independently of polarity.
        force dut.wheels[0].raw_speed=16'sd2;#1;
        if(dut.common_still)$fatal(1,"raw +2 incorrectly stationary");
        force dut.wheels[0].raw_speed=-16'sd2;#1;
        if(dut.common_still)$fatal(1,"raw -2 incorrectly stationary");
        force dut.wheels[0].raw_speed=-16'sd1;#1;
        if(!dut.common_still)$fatal(1,"raw -1 stationary equivalence");
        release dut.wheels[0].raw_speed;repeat(200)@(negedge clk);
        // Successful bridge releases the guard latch without ever driving it.
        force dut.avoid_enabled=1;
        force dut.avoid_capture=1;repeat(4)@(negedge clk);
        release dut.avoid_capture;force dut.avoid_resume=1;repeat(1)@(negedge clk);
        release dut.avoid_resume;
        send_byte("F");if(in1 || in2)$fatal(1,"resume bypassed 100ms neutral");
        repeat(1100)@(negedge clk);send_byte("F");repeat(20)@(negedge clk);
        if(dut.command!=1)$fatal(1,"fresh F did not resume successful detour state=%d inhibit=%b force=%b latch=%b ready=%b",dut.avoid_state,dut.avoid_inhibit,dut.u_bt_guard.force_stop_i,dut.u_bt_guard.require_stop,dut.u_bt_guard.neutral_ready);
        // A failed bridge must reject repeated F until an explicit S.
        force dut.g_manual_safety.u_avoid.state_o=5;repeat(5)@(negedge clk);
        send_byte("F");repeat(1100)@(negedge clk);send_byte("F");
        if(dut.command || in1 || in2 || pwm)$fatal(1,"F escaped failed-detour inhibit");
        release dut.g_manual_safety.u_avoid.state_o;
        send_byte("S");repeat(1200)@(negedge clk);send_byte("F");
        if(dut.command!=1)$fatal(1,"explicit S did not permit new instruction");
        send_byte("S");
        $display("SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS");$finish;
    end
    initial begin #3000000;$fatal(1,"integration timeout");end
endmodule
