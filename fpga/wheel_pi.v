// 单轮整数速度环。保留 wheel_pi 模块名，避免旧 ModelSim 工程引用失效；KD>0 时为 PID。
// 目标和反馈的单位均为“每个 control_tick 周期的编码器计数”，不是转/分钟。
// duty_o 为有符号千分比，默认范围 -1000..+1000；符号决定方向，幅值决定 PWM 占空比。
module wheel_pi #(
    parameter integer KP = 4,
    parameter integer KI = 1,
    // 默认不启用微分：实际编码器的计数抖动与电机惯量未标定前，贸然加 D 可能更不稳。
    parameter integer KD = 0,
    parameter integer SHIFT = 3,
    parameter integer DUTY_MAX = 1000,
    parameter integer INTEGRAL_LIMIT = 20000
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   control_tick_i,
    input  wire                   enable_i,
    input  wire signed [15:0]     target_speed_i,
    input  wire signed [15:0]     feedback_speed_i,
    output reg  signed [15:0]     duty_o
);
    reg signed [31:0] integral_acc;
    reg signed [15:0] previous_feedback;
    reg derivative_valid;
    integer error_next;
    integer feedback_delta;
    integer integral_candidate;
    integer output_candidate;
    integer integral_next;
    integer output_next;

    // 微分作用于测速值而不是目标误差，避免目标阶跃时出现 D 项冲击。
    // 全部控制量仅在 control_tick_i 更新；PWM 载波频率由 motor_pwm_dir 独立产生。
    always @* begin
        error_next = target_speed_i - feedback_speed_i;
        feedback_delta = derivative_valid ? (feedback_speed_i - previous_feedback) : 0;
        integral_candidate = integral_acc + error_next;
        if (integral_candidate > INTEGRAL_LIMIT)
            integral_candidate = INTEGRAL_LIMIT;
        else if (integral_candidate < -INTEGRAL_LIMIT)
            integral_candidate = -INTEGRAL_LIMIT;

        // 若输出已饱和且误差还在推动同方向积分，则冻结积分，防止长期顶格后的积分饱和。
        output_candidate = (KP * error_next + KI * integral_candidate
                            - KD * feedback_delta) >>> SHIFT;
        if ((output_candidate > DUTY_MAX && error_next > 0) ||
            (output_candidate < -DUTY_MAX && error_next < 0))
            integral_next = integral_acc;
        else
            integral_next = integral_candidate;

        output_next = (KP * error_next + KI * integral_next
                       - KD * feedback_delta) >>> SHIFT;
        if (output_next > DUTY_MAX)
            output_next = DUTY_MAX;
        else if (output_next < -DUTY_MAX)
            output_next = -DUTY_MAX;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            duty_o <= 16'sd0;
            integral_acc <= 32'sd0;
            previous_feedback <= 16'sd0;
            derivative_valid <= 1'b0;
        end else if (!enable_i) begin
            // 故障停机：PWM 由 enable_i 组合关断，下一时钟清除内部历史量。
            duty_o <= 16'sd0;
            integral_acc <= 32'sd0;
            previous_feedback <= 16'sd0;
            derivative_valid <= 1'b0;
        end else if (control_tick_i) begin
            previous_feedback <= feedback_speed_i;
            derivative_valid <= 1'b1;
            if (target_speed_i == 0) begin
                // 零速指令不保留旧积分，避免车辆已到停车死区却仍有残余驱动力。
                duty_o <= 16'sd0;
                integral_acc <= 32'sd0;
                derivative_valid <= 1'b0;
            end else begin
                integral_acc <= integral_next;
                duty_o <= output_next;
            end
        end
    end
endmodule
