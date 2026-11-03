// 蓝牙运动命令门控：只接受 F/B/L/R/S，方向字节需持续刷新，否则自动停车。
// 转向必须先发送 S 并等待中性间隔；上电就绪前所有无线方向字节均被忽略。
module bt_motion_guard #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer TIMEOUT_MS = 300,
    parameter integer NEUTRAL_MS = 100,
    parameter integer RUN_LIMIT_MS = 3000,
    parameter integer DEFAULT_TARGET_COUNTS = 20,
    parameter integer CONTINUATION_ENABLE = 0
) (
    input wire clk,
    input wire rst_n,
    input wire armed_i,
    input wire force_stop_i,
    input wire resume_forward_i,
    input wire [7:0] rx_data_i,
    input wire rx_valid_i,
    input wire framing_error_i,
    output reg [2:0] command_o = 0,
    output reg [15:0] target_counts_o = DEFAULT_TARGET_COUNTS,
    output reg timeout_seen_o = 0,
    output reg framing_fault_o = 0
);
    localparam integer TIMEOUT_CYCLES = ((CLK_HZ / 1000) * TIMEOUT_MS < 1) ? 1 : (CLK_HZ / 1000) * TIMEOUT_MS;
    localparam integer NEUTRAL_CYCLES = ((CLK_HZ / 1000) * NEUTRAL_MS < 1) ? 1 : (CLK_HZ / 1000) * NEUTRAL_MS;
    localparam integer RUN_LIMIT_CYCLES = ((CLK_HZ / 1000) * RUN_LIMIT_MS < 1) ? 1 : (CLK_HZ / 1000) * RUN_LIMIT_MS;
    localparam [2:0] STOP = 0, FORWARD = 1, BACKWARD = 2, LEFT = 3, RIGHT = 4;
    reg [31:0] watchdog_count = 0;
    reg [31:0] run_count = 0;
    reg [31:0] neutral_count = 0;
    reg neutral_ready = 0;
    // 上电/复位后必须先收到显式 S。否则按住方向键时 S0 一松手就会重启。
    reg require_stop = 1;
    reg force_stop_prev = 0;
    reg [2:0] decoded;

    // 非命令字符（含回车、换行）不延长看门狗。
    always @* begin
        case (rx_data_i)
            "F", "f": decoded = FORWARD;
            "B", "b": decoded = BACKWARD;
            "L", "l": decoded = LEFT;
            "R", "r": decoded = RIGHT;
            "S", "s": decoded = STOP;
            default: decoded = 3'd7;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            command_o <= STOP;
            timeout_seen_o <= 0;
            framing_fault_o <= 0;
            watchdog_count <= 0;
            run_count <= 0;
            neutral_count <= 0;
            neutral_ready <= 0;
            require_stop <= 1;
            force_stop_prev <= 0;
            target_counts_o <= DEFAULT_TARGET_COUNTS;
        end else if (!armed_i) begin
            command_o <= STOP;
            watchdog_count <= 0;
            run_count <= 0;
            neutral_count <= 0;
            neutral_ready <= 0;
            require_stop <= 1;
            force_stop_prev <= 0;
            // 速度档位可在 S1 使能前选择；不能借此启动电机。
            if (rx_valid_i && !framing_error_i && !framing_fault_o) begin
                case (rx_data_i)
                    "1": target_counts_o <= 16'd12;
                    "2": target_counts_o <= 16'd16;
                    "3": target_counts_o <= 16'd20;
                    default: ;
                endcase
            end
        end else if (force_stop_i) begin
            // A ToF hard stop must discard the old direction in the FPGA,
            // independently of whether the PC is still reading COM6.  A
            // fresh S while stopped permits a new direction after clearance;
            // repeated stale F/B/L/R bytes cannot re-arm the motor.
            command_o <= STOP;
            watchdog_count <= 0;
            run_count <= 0;
            neutral_count <= 0;
            neutral_ready <= 0;
            if (!force_stop_prev) require_stop <= 1;
            if (rx_valid_i && !framing_error_i && !framing_fault_o && decoded == STOP) begin
                require_stop <= 0;
                timeout_seen_o <= 0;
            end
            if (framing_error_i) framing_fault_o <= 1;
            force_stop_prev <= 1;
        end else begin
            force_stop_prev <= 0;
            // Trusted successful detour handshake only. It clears the stop
            // latch, never sets a direction; wait a full neutral interval and
            // a later operator direction byte. Legacy guards ignore this pin.
            if (CONTINUATION_ENABLE && resume_forward_i && command_o==STOP && !framing_fault_o && !framing_error_i) begin
                require_stop <= 0;
                neutral_count <= 0;
                neutral_ready <= 0;
            end
            if (command_o == STOP) begin
                run_count <= 0;
                if (CONTINUATION_ENABLE && resume_forward_i) begin neutral_count<=0;neutral_ready<=0;end
                else if (neutral_count < NEUTRAL_CYCLES) neutral_count <= neutral_count + 1'b1;
                else neutral_ready <= 1;
            end else begin
                if (run_count < RUN_LIMIT_CYCLES) run_count <= run_count + 1'b1;
                neutral_count <= 0;
                neutral_ready <= 0;
                if (watchdog_count >= TIMEOUT_CYCLES - 1) begin
                    command_o <= STOP;
                    watchdog_count <= 0;
                    timeout_seen_o <= 1;
                    require_stop <= 1;
                end else watchdog_count <= watchdog_count + 1'b1;
            end
            if (framing_error_i) begin
                framing_fault_o <= 1;
                command_o <= STOP;
            end else if (rx_valid_i && !framing_fault_o) begin
                // 运动中忽略调速，须先发送 S 并停车。
                if (command_o == STOP) begin
                    case (rx_data_i)
                        "1": target_counts_o <= 16'd12;
                        "2": target_counts_o <= 16'd16;
                        "3": target_counts_o <= 16'd20;
                        default: ;
                    endcase
                end
                if (decoded == STOP) begin
                    command_o <= STOP;
                    watchdog_count <= 0;
                    neutral_count <= 0;
                    neutral_ready <= 0;
                    require_stop <= 0;
                    timeout_seen_o <= 0;
                end else if (decoded != 3'd7) begin
                    if (command_o == STOP) begin
                        if (neutral_ready && !require_stop) begin
                            command_o <= decoded;
                            watchdog_count <= 0;
                        end
                    end else if (decoded == command_o) begin
                        // 合法的同方向刷新同时续期运行租约。GUI 的“点击锁定”
                        // 仍会每 100 ms 发送一次方向字节；只要链路持续，
                        // 就不应被 3 s 的启动保护计时器误停。若链路断开，
                        // watchdog_count 仍会在 TIMEOUT_MS 后触发停车。
                        watchdog_count <= 0;
                        run_count <= 0;
                    end
                    else begin
                        // 不允许 F 直接跳 B/L/R：停车后还需明确的 S 解锁。
                        command_o <= STOP;
                        watchdog_count <= 0;
                        neutral_count <= 0;
                        neutral_ready <= 0;
                        require_stop <= 1;
                    end
                end
            end
            // 最后赋值，保证连续运行限时不能被同周期刷新字节覆盖。
            if (command_o != STOP && run_count >= RUN_LIMIT_CYCLES - 1) begin
                command_o <= STOP;
                timeout_seen_o <= 1;
                require_stop <= 1;
                watchdog_count <= 0;
            end
        end
    end
endmodule
