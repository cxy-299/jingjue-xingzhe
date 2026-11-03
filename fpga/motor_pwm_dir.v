// 单轮有符号占空比转 PWM/方向。duty_i 默认 -1000..+1000，绝对值对应 0..100%。
// 本模块只产生载波与方向；转速闭环由上游 wheel_pi 负责，不能直接把 PWM 波形送入 PID。
module motor_pwm_dir #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer DUTY_MAX = 1000
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable_i,
    input  wire signed [15:0] duty_i,
    output reg                pwm_o,
    output reg                direction_o
);
    localparam integer PWM_PERIOD = (CLK_HZ / PWM_HZ < 1) ? 1 : (CLK_HZ / PWM_HZ);
    reg [31:0] pwm_count;
    integer duty_abs_i;
    integer on_ticks_i;

    always @* begin
        duty_abs_i = duty_i;
        if (duty_abs_i < 0)
            duty_abs_i = -duty_abs_i;
        if (duty_abs_i > DUTY_MAX)
            duty_abs_i = DUTY_MAX;
        on_ticks_i = (duty_abs_i * PWM_PERIOD) / DUTY_MAX;
        direction_o = (duty_i < 0);
        // 故障关断不等待 PWM 周期边界，enable_i 拉低就立即输出低电平。
        pwm_o = enable_i && (pwm_count < on_ticks_i);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pwm_count <= 32'd0;
        else if (pwm_count >= PWM_PERIOD - 1)
            pwm_count <= 32'd0;
        else
            pwm_count <= pwm_count + 1'b1;
    end
endmodule
