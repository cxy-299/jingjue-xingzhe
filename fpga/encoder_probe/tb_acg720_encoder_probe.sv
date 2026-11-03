`timescale 1ns/1ps

// 仅验证编码器方向、活动指示、复位和电机输出恒低；不接实物电机。
module tb_acg720_encoder_probe;
    reg clk = 1'b0;
    reg key_s0_n = 1'b0;
    reg [3:0] encoder_a = 4'b0000;
    reg [3:0] encoder_b = 4'b0000;
    wire [3:0] motor_pwm;
    wire [3:0] motor_in1;
    wire [3:0] motor_in2;
    wire [5:0] led;

    always #5 clk = ~clk;

    acg720_encoder_probe #(
        .CLK_HZ(1000), .HOLD_MS(100), .BLINK_HZ(5), .STARTUP_MS(3)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(key_s0_n),
        .encoder_a_i(encoder_a), .encoder_b_i(encoder_b),
        .motor_pwm_o(motor_pwm), .motor_in1_o(motor_in1),
        .motor_in2_o(motor_in2), .led_o(led)
    );

    task automatic step(input integer wheel, input bit a, input bit b);
        begin
            @(negedge clk);
            encoder_a[wheel] = a;
            encoder_b[wheel] = b;
            repeat (6) @(posedge clk);
            #1;
            if ({motor_pwm, motor_in1, motor_in2} !== 12'b0)
                $fatal(1, "电机输出不得在编码器测试中使能");
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        key_s0_n = 1'b1;
        repeat (6) @(posedge clk);
        #1;
        if (led[1] !== 1'b1 || led[5:2] !== 4'b0)
            $fatal(1, "上电复位或初始 LED 状态错误: %b", led);

        // M1 正向：00→01→11→10→00，应得到 +4 计数。
        step(0, 0, 1);
        step(0, 1, 1);
        step(0, 1, 0);
        step(0, 0, 0);
        if (dut.channels[0].position !== 32'sd4 || led[2] !== 1'b1)
            $fatal(1, "M1 正向译码错误，位置=%0d，LED=%b", dut.channels[0].position, led[2]);

        // M2 反向：00→10→11→01→00，应得到 -4 计数。
        step(1, 1, 0);
        step(1, 1, 1);
        step(1, 0, 1);
        step(1, 0, 0);
        if (dut.channels[1].position !== -32'sd4 ||
            dut.channels[1].last_forward !== 1'b0)
            $fatal(1, "M2 反向译码错误，位置=%0d", dut.channels[1].position);
        if (led[5:4] !== 2'b00)
            $fatal(1, "未活动的 M3/M4 指示灯不应亮");

        // 超过保持时间后，四路活动灯都应熄灭。
        repeat (110) @(posedge clk);
        #1;
        if (led[5:2] !== 4'b0)
            $fatal(1, "活动超时后 LED 未熄灭: %b", led[5:2]);

        // S0 必须立即清零计数并使电机输出继续保持全低。
        @(negedge clk);
        key_s0_n = 1'b0;
        #1;
        if (led[5:1] !== 5'b0 ||
            dut.channels[0].position !== 32'sd0 ||
            dut.channels[1].position !== 32'sd0 ||
            {motor_pwm, motor_in1, motor_in2} !== 12'b0)
            $fatal(1, "S0 复位后仍有活动状态");
        $display("PASS tb_acg720_encoder_probe: direction, timeout, reset, motor outputs low");
        $finish;
    end
endmodule
