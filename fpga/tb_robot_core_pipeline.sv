`timescale 1ns/1ps
// 真 UART 进入完整控制核心；编码器同步后采样，下一拍 PID 消费本周期测速。
// 只模拟数字反馈，不模拟电机惯量，因此不用于证明实际 PID 调参稳定性。
module tb_robot_core_pipeline;
    reg clk=0,rst_n=0,uart_rx=1,tof_valid=1,estop=0;
    reg [15:0] distance=1000;
    reg [3:0] enc_a=0,enc_b=0;
    wire [3:0] pwm,dir,locked_pwm;
    wire enabled,link_alive,vision_fresh,locked_enable;
    wire signed [15:0] fl_speed;
    reg [7:0] bytes [0:35];
    reg [15:0] crc;
    integer i,k,timeout;
    always #500 clk=~clk; // 1 MHz 仿真时钟，与核心 CLK_HZ 参数一致。
    fpga_robot_core #(.CLK_HZ(1_000_000),.BAUD(100_000),.CONTROL_HZ(1000),
        .PWM_HZ(10_000),.WATCHDOG_MS(20),.VISION_TIMEOUT_MS(8),
        .WHEEL_KP(8),.WHEEL_KI(0),.WHEEL_PID_SHIFT(3),
        .WHEEL_COUNTS_AT_FULL_SCALE(100)) dut(
        .clk(clk),.rst_n(rst_n),.pi_uart_rx_i(uart_rx),
        .tof_distance_mm_i(distance),.tof_valid_i(tof_valid),.estop_i(estop),
        .encoder_a_i(enc_a),.encoder_b_i(enc_b),.motor_pwm_o(pwm),
        .motor_dir_o(dir),.motor_enable_o(enabled),.link_alive_o(link_alive),
        .vision_fresh_o(vision_fresh),.wheel_fl_speed_o(fl_speed),
        .target_valid_o(),.target_confirmed_o(),.safe_stop_o(),.vx_cmd_o(),
        .vy_cmd_o(),.omega_cmd_o(),.motion_state_o(),.wheel_fl_ref_o(),
        .wheel_fr_ref_o(),.wheel_rl_ref_o(),.wheel_rr_ref_o(),.wheel_fr_speed_o(),
        .wheel_rl_speed_o(),.wheel_rr_speed_o(),.crc_error_count_o(),.uart_framing_error_o());
    // 未标定核心保持默认 counts=0，任何视觉结果均不能放行电机输出。
    fpga_robot_core #(.CLK_HZ(1_000_000),.BAUD(100_000),.CONTROL_HZ(1000),
        .PWM_HZ(10_000),.WATCHDOG_MS(20),.VISION_TIMEOUT_MS(8)) uncalibrated(
        .clk(clk),.rst_n(rst_n),.pi_uart_rx_i(uart_rx),
        .tof_distance_mm_i(distance),.tof_valid_i(tof_valid),.estop_i(estop),
        .encoder_a_i(enc_a),.encoder_b_i(enc_b),.motor_pwm_o(locked_pwm),
        .motor_enable_o(locked_enable),.motor_dir_o(),.link_alive_o(),.vision_fresh_o(),
        .target_valid_o(),.target_confirmed_o(),.safe_stop_o(),.vx_cmd_o(),
        .vy_cmd_o(),.omega_cmd_o(),.motion_state_o(),.wheel_fl_ref_o(),
        .wheel_fr_ref_o(),.wheel_rl_ref_o(),.wheel_rr_ref_o(),.wheel_fl_speed_o(),
        .wheel_fr_speed_o(),.wheel_rl_speed_o(),.wheel_rr_speed_o(),
        .crc_error_count_o(),.uart_framing_error_o());
    always @(negedge clk) if(rst_n && (locked_enable!==0 || locked_pwm!==0))
        $fatal(1,"FAIL 未标定核心产生驱动");
    function [15:0] crc_next(input [15:0] c,input [7:0] b);
        reg [15:0] v;integer j;
        begin v=c^{b,8'h00};for(j=0;j<8;j=j+1) v=v[15]?(v<<1)^16'h1021:v<<1;crc_next=v;end
    endfunction
    task send_byte(input [7:0] b);
        integer j;
        begin
            @(negedge clk);uart_rx=0;repeat(10) @(negedge clk);
            for(j=0;j<8;j=j+1) begin uart_rx=b[j];repeat(10) @(negedge clk);end
            uart_rx=1;repeat(10) @(negedge clk);
        end
    endtask
    task send_message(input [7:0] kind,input integer length);
        begin
            for(i=0;i<36;i=i+1)bytes[i]=0;
            bytes[0]=8'haa;bytes[1]=8'h55;bytes[2]=3;bytes[3]=kind;bytes[4]=1;
            bytes[6]=length;
            if(kind==8'h13) bytes[16]=3; // 载荷 flags：有目标且已确认；居中误差默认为零。
            crc=16'hffff;
            for(i=2;i<8+length;i=i+1)crc=crc_next(crc,bytes[i]);
            bytes[8+length]=crc[7:0];bytes[9+length]=crc[15:8];
            for(i=0;i<10+length;i=i+1)send_byte(bytes[i]);
            repeat(5) @(negedge clk);
        end
    endtask
    task encoder_state(input [1:0] ab);
        begin enc_a[0]=ab[1];enc_b[0]=ab[0];repeat(5) @(negedge clk);end
    endtask
    task wait_sample_edge;
        begin
            timeout=0;
            while(dut.control_tick!==1 && timeout<1100) begin @(negedge clk);timeout=timeout+1;end
            if(timeout>=1100)$fatal(1,"FAIL 控制 tick 超时");
            @(posedge clk);#1; // 此拍编码器与策略完成非阻塞更新，PID 仍保持上一输出。
        end
    endtask
    initial begin
        $dumpfile("robot_core_pipeline.vcd");
        $dumpvars(0,clk,rst_n,uart_rx,tof_valid,estop,enabled,link_alive,vision_fresh,
            pwm,dir,enc_a,enc_b,fl_speed,dut.control_tick,dut.pid_tick,
            dut.wheel_fl_target_counts,dut.wheel_fl_duty,dut.wheel_fr_duty);
        repeat(4) @(negedge clk);rst_n=1;
        send_message(8'h13,26);
        // 初次从安全停车恢复，先让策略和恢复门控各完成所需控制拍。
        timeout=0;
        while((enabled!==1 || dut.wheel_fl_duty!=12) && timeout<2200) begin
            @(negedge clk);timeout=timeout+1;
        end
        if(!enabled || dut.wheel_fl_target_counts!=12 || dut.wheel_fl_duty!=12)
            $fatal(1,"FAIL 合法视觉帧未使完整核心进入预期状态");
        // 等采样脉冲落下，再在一个完整采样窗内送入 8 个正向四相边沿。
        @(negedge clk);
        for(k=0;k<2;k=k+1) begin encoder_state(1);encoder_state(3);encoder_state(2);encoder_state(0);end
        wait_sample_edge();
        if(fl_speed!=8 || dut.wheel_fl_duty!=12 || dut.pid_tick!==1)
            $fatal(1,"FAIL 采样阶段不正确 speed=%0d duty=%0d",fl_speed,dut.wheel_fl_duty);
        @(posedge clk);#1;
        if(dut.wheel_fl_duty!=4 || dut.wheel_fr_duty!=12)
            $fatal(1,"FAIL PID 未消费本周期测速/轮间串扰 duty=%0d",dut.wheel_fl_duty);
        @(negedge clk);tof_valid=0;#1;
        if(enabled!==0 || pwm!==0)$fatal(1,"FAIL ToF 失效未立即关断");
        repeat(3) @(negedge clk);
        if(dut.wheel_fl_duty!=0)$fatal(1,"FAIL 故障未清除 PID");
        tof_valid=1;#1;if(enabled!==0)$fatal(1,"FAIL ToF 恢复立即重放旧输出");
        wait_sample_edge();@(posedge clk);#1;
        if(enabled!==1)$fatal(1,"FAIL 控制周期后未恢复");
        // 短于时钟的急停脉冲也要锁存，松开后等待控制周期再恢复。
        @(negedge clk);estop=1;#100;
        if(enabled!==0 || pwm!==0)$fatal(1,"FAIL 急停未关断");
        estop=0;#100;if(enabled!==0)$fatal(1,"FAIL 短急停未锁存");
        wait_sample_edge();@(posedge clk);#1;
        // 心跳保持链路存活，但不得给旧的视觉目标续期。
        repeat(6) send_message(8'h01,4);
        if(link_alive!==1 || vision_fresh!==0 || enabled!==0 || pwm!==0)
            $fatal(1,"FAIL 心跳为旧视觉续期/停车失效");
        repeat(21000) @(negedge clk);
        if(link_alive!==0 || enabled!==0)$fatal(1,"FAIL 链路超时失效");
        rst_n=0;repeat(3) @(negedge clk);
        if(pwm!==0 || enabled!==0)$fatal(1,"FAIL 复位输出不安全");
        $display("PASS tb_robot_core_pipeline: UART, current feedback PID, independent lanes, ToF/estop, stale vision, link timeout, calibration lock");
        $finish;
    end
endmodule
