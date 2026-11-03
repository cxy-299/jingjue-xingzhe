`timescale 1ns/1ps
module tb_sin11_motor_integration;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,rx=1;
    reg [31:0] yaw_bits=0;
    reg [7:0] frames[0:39];
    wire [3:0] pwm,in1,in2;
    wire [5:0] leds;
    acg720_motor_bt_drive #(.CLK_HZ(10000),.PWM_HZ(100),.BT_BAUD(1000),
        .SENSOR_IMU_BAUD(1000),.SENSOR_TOF_BAUD(1000),.DIAG_BAUD(1000),
        .STARTUP_MS(1),.STAGGER_MS(2),.KICK_MS(10),.LOSS_TICKS(255),
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
        integer k;begin for(k=0;k<20;k++)send_byte(frames[n*20+k]);end
    endtask
    initial begin
        $readmemh("sin11_request_frames.mem",frames);
        force dut.imu_angle_valid=1'b1;force dut.imu_yaw_raw=yaw_bits;
        force dut.tof_valid=4'b0001;force dut.tof_hard_stop=1'b0;
        force dut.tof_speed_scale_permille=10'd1000;
        force dut.pi_packet=1'b1;force dut.pi_seq=16'd1;
        force dut.pi_mission=32'h47534642;force dut.pi_class=16'd39;force dut.pi_red=1'b1;
        force dut.pi_selected=1'b0;force dut.pi_present=1'b0;force dut.pi_confirmed=1'b0;
        force dut.pi_lock=0;force dut.pi_center=0;
        repeat(5)@(negedge clk);rst=1;repeat(1800)@(negedge clk);
        if(in1||in2)$fatal(1,"boot outputs active");
        send_byte("S");repeat(1600)@(negedge clk);frame(0);
        send_byte("M");repeat(1700)@(negedge clk);
        if(!dut.mission_active || in1!=4'b1111 || in2!=0 || dut.desired_forward!=4'b1010)
            $fatal(1,"mission physical CCW wheel integration state=%d active=%d in1=%b",dut.mission_state,dut.mission_active,in1);
        if(dut.command!=0 || dut.nav_active || dut.vision_active || dut.turn_active)
            $fatal(1,"competing mode active");
        force dut.tof_hard_stop=1'b1;repeat(2)@(negedge clk);
        if(in1||in2||pwm)$fatal(1,"near obstacle did not gate all mission pins");
        force dut.tof_hard_stop=1'b0;send_byte("M");repeat(50)@(negedge clk);
        if(dut.mission_active||in1||in2)$fatal(1,"clearance M resumed mission");
        send_byte("S");repeat(1600)@(negedge clk);frame(0);send_byte("M");
        repeat(100)@(negedge clk);
        if(dut.mission_active||in1||in2)$fatal(1,"mission ID replay after S");
        rst=0;repeat(3)@(negedge clk);rst=1;repeat(1800)@(negedge clk);send_byte("M");
        if(dut.mission_active||in1||in2)$fatal(1,"reset M resurrected mission");
        // End-to-end range priority with a still off-center perception target.
        force dut.pi_seq=16'd2;force dut.pi_selected=1'b1;
        force dut.pi_present=1'b1;force dut.pi_confirmed=1'b1;
        force dut.pi_lock=32'd99;force dut.pi_center=-16'sd2000;
        force dut.tof0_distance_mm=16'd500;
        send_byte("S");repeat(1600)@(negedge clk);frame(0);send_byte("M");
        repeat(1800)@(negedge clk);
        if(!dut.mission_active || dut.mission_command!=3 || !(in1||in2))
            $fatal(1,"range priority setup did not align");
        force dut.tof0_distance_mm=16'd205;repeat(2)@(negedge clk);
        if(in1||in2||pwm||dut.mission_command)$fatal(1,"off-center arrival did not close actual motor outputs");
        if(dut.mission_state!=3 || !dut.mission_active)$fatal(1,"off-center target falsely completed");
        force dut.pi_seq=16'd3;force dut.pi_center=16'sd0;
        repeat(8)begin send_byte("M");repeat(650)@(negedge clk);end
        if(dut.mission_active || dut.mission_state!=6 || in1||in2||pwm)
            $fatal(1,"centered stable range did not complete");
        force dut.tof0_distance_mm=16'd500;send_byte("M");repeat(200)@(negedge clk);
        if(dut.mission_active||in1||in2||pwm)$fatal(1,"moving target away restarted completed mission");
        $display("SIN11_MISSION_MOTOR_PINS_ARBITRATION_PASS");$finish;
    end
    initial begin #2000000;$fatal(1,"integration timeout");end
endmodule
