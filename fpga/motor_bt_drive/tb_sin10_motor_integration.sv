`timescale 1ns/1ps
module tb_sin10_motor_integration #(parameter CONTROL_REV=0);
    reg clk=0;always #5 clk=~clk;
    reg rst=0,rx=1;
    reg [31:0] yaw_bits=0;
    reg [7:0] frames[0:83];
    wire [3:0] pwm,in1,in2;
    wire [5:0] leds;
    acg720_motor_bt_drive #(.CLK_HZ(10000),.PWM_HZ(100),.BT_BAUD(1000),
        .SENSOR_IMU_BAUD(1000),.SENSOR_TOF_BAUD(1000),.DIAG_BAUD(1000),
        .STARTUP_MS(1),.STAGGER_MS(2),.KICK_MS(10),.LOSS_TICKS(255),
        .ROTATE_ENABLE(1),.SENSOR_ENABLE(1),.NAV_ENABLE(1),.VISION_ENABLE(1),
        .TOF_HARD_STOP_MM(100),.REV5_ENABLE(CONTROL_REV)) dut(
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
        integer k;begin for(k=0;k<14;k++)send_byte(frames[n*14+k]);end
    endtask
    initial begin
        $readmemh("sin10_turn_frames.mem",frames);
        force dut.imu_angle_valid=1'b1;
        force dut.imu_yaw_raw=yaw_bits;
        force dut.tof_valid=4'b0001;
        force dut.tof_hard_stop=1'b0;
        force dut.tof_speed_scale_permille=10'd1000;
        repeat(5)@(negedge clk);rst=1;repeat(1800)@(negedge clk);
        if(in1||in2)$fatal(1,"boot outputs active");
        send_byte("S");repeat(1600)@(negedge clk);frame(0);
        repeat(1700)@(negedge clk);
        if(!dut.turn_active || in1!=4'b1111 || in2!=0 || dut.desired_forward!=4'b1010)
            $fatal(1,"CCW physical wheel polarity integration");
        if(dut.command!=0 || dut.nav_active || dut.vision_active)$fatal(1,"competing mode active");
        send_byte("S");repeat(5)@(negedge clk);
        if(in1||in2||pwm)$fatal(1,"S failed to gate all pins");
        repeat(1600)@(negedge clk);frame(1);repeat(1700)@(negedge clk);
        if(in1!=0||in2!=4'b1111||dut.desired_forward!=4'b0101)$fatal(1,"CW wheel polarity integration");
        force dut.tof_hard_stop=1'b1;repeat(2)@(negedge clk);
        if(in1||in2||pwm)$fatal(1,"near obstacle did not gate all pins");
        force dut.tof_hard_stop=1'b0;send_byte("G");repeat(50)@(negedge clk);
        if(dut.turn_active||in1||in2)$fatal(1,"clearance G rearmed canceled turn");
        rst=0;repeat(3)@(negedge clk);rst=1;repeat(1800)@(negedge clk);send_byte("G");
        if(dut.turn_active||in1||in2)$fatal(1,"reset resurrected turn");
        $display("SIN10_MOTOR_PIN_ARBITRATION_UART_PASS");$finish;
    end
    initial begin #2000000;$fatal(1,"integration timeout");end
endmodule
