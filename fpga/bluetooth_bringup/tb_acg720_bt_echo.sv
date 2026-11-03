`timescale 1ns/1ps

// 使用较小的时钟/波特率比例加速仿真；每位仍精确占 10 个时钟。
module tb_acg720_bt_echo #(
    parameter integer TB_CLK_HZ = 1_000_000,
    parameter integer TB_BAUD = 100_000
);
    localparam integer CPB = (TB_CLK_HZ + TB_BAUD / 2) / TB_BAUD;
    reg clk = 1'b0;
    reg key_s0_n = 1'b0;
    reg bt_rx = 1'b1;
    wire bt_tx;
    wire [3:0] motor_pwm, motor_in1, motor_in2;
    wire [5:0] led;

    always #(500_000_000 / TB_CLK_HZ) clk = ~clk;

    acg720_bt_echo #(
        .CLK_HZ(TB_CLK_HZ), .BAUD(TB_BAUD),
        .STARTUP_MS(1), .STATUS_HOLD_MS(50)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(key_s0_n),
        .bt_uart_rx_i(bt_rx), .bt_uart_tx_o(bt_tx),
        .motor_pwm_o(motor_pwm), .motor_in1_o(motor_in1),
        .motor_in2_o(motor_in2), .led_o(led)
    );

    // 任一时刻都不允许测试位流产生电机驱动高电平。
    always @(posedge clk) begin
        if ({motor_pwm, motor_in1, motor_in2} !== 12'b0)
            $fatal(1, "蓝牙验收位流意外使能电机");
    end

    task automatic send_byte(input [7:0] value, input bit good_stop);
        integer i;
        begin
            @(negedge clk);
            bt_rx = 1'b0;
            repeat (CPB) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                bt_rx = value[i];
                repeat (CPB) @(negedge clk);
            end
            bt_rx = good_stop;
            repeat (CPB) @(negedge clk);
            bt_rx = 1'b1;
        end
    endtask

    task automatic expect_echo(input [7:0] expected);
        integer i;
        begin
            @(negedge bt_tx);
            repeat (CPB + CPB/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                if (bt_tx !== expected[i])
                    $fatal(1, "回显第 %0d 位错误：期望=%b 实际=%b", i, expected[i], bt_tx);
                repeat (CPB) @(posedge clk);
            end
            if (bt_tx !== 1'b1)
                $fatal(1, "回显停止位错误");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        key_s0_n = 1'b1;
        wait (led[1] === 1'b1);
        repeat (4) @(posedge clk);
        if (bt_tx !== 1'b1 || led[5:2] !== 4'b0000)
            $fatal(1, "初态错误，TX=%b LED=%b", bt_tx, led);

        // 手机/电脑发送 A，FPGA 必须原样回传，LED4/5/6 给出可见状态。
        fork
            send_byte(8'h41, 1'b1);
            expect_echo(8'h41);
        join
        repeat (CPB) @(posedge clk);
        if (led[4:2] !== 3'b111 || led[5] !== 1'b0)
            $fatal(1, "字符 A 的 LED 状态错误：%b", led);

        // 再发 B，最近字节判定应从 A 改为非 A，不应锁死。
        fork
            send_byte(8'h42, 1'b1);
            expect_echo(8'h42);
        join
        repeat (4) @(posedge clk);
        if (led[4] !== 1'b0 || led[5] !== 1'b0)
            $fatal(1, "字符 B 的 LED 状态错误：%b", led);

        // 错误停止位必须锁存 LED7，且不得产生新回显。
        send_byte(8'h5a, 1'b0);
        repeat (30) @(posedge clk);
        if (led[5] !== 1'b1 || bt_tx !== 1'b1)
            $fatal(1, "错误帧处理失败：LED=%b TX=%b", led, bt_tx);

        // S0 清除状态；释放后串口恢复空闲高电平。
        @(negedge clk);
        key_s0_n = 1'b0;
        repeat (4) @(posedge clk);
        #1;
        if (led[5:1] !== 5'b00000 || bt_tx !== 1'b1)
            $fatal(1, "S0 复位失败：LED=%b TX=%b", led, bt_tx);
        @(negedge clk);
        key_s0_n = 1'b1;
        repeat (4) @(posedge clk);
        #1;
        if (led[1] !== 1'b1 || led[5] !== 1'b0)
            $fatal(1, "S0 松开后未正常就绪：LED=%b", led);

        $display("PASS tb_acg720_bt_echo CLK=%0d BAUD=%0d: RX, echo TX, framing, reset, motors low",
                 TB_CLK_HZ, TB_BAUD);
        $finish;
    end
endmodule
