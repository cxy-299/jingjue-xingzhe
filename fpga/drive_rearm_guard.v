// 故障恢复门控：故障一出现立即禁止电机，解除后必须等控制周期重新确认。
// 这样不会在急停松开、ToF 瞬间恢复等时刻短暂重放上一次的 PWM 指令。
module drive_rearm_guard (
    input  wire clk,
    input  wire rst_n,
    input  wire control_tick_i,
    input  wire fault_i,
    output wire allow_o
);
    reg rearm_pending;
    wire safety_reset_n = rst_n && !fault_i;

    // 将故障作为异步置位条件：即使故障脉冲短于一个时钟周期也能锁存。
    // 故障解除只能在下一个 control_tick 同步清除锁存。
    always @(posedge clk or negedge safety_reset_n) begin
        if (!safety_reset_n)
            rearm_pending <= 1'b1;
        else if (control_tick_i)
            rearm_pending <= 1'b0;
    end

    // fault_i 组合关断；rearm_pending 保证故障解除后不会立即重启。
    assign allow_o = !fault_i && !rearm_pending;
endmodule
