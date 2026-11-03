// Board-independent sensor front-end for competition tasks 1 and 3.
// Connect the four ToF RX pins and one Yahboom IMU RX pin at the board top.
// ToF values are held for TIMEOUT_MS; a stale/absent set is fail-safe stop.
module sensor_task1_3_core #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer IMU_BAUD = 115200,
    parameter integer TOF_BAUD = 115200,
    parameter integer TIMEOUT_MS = 250,
    parameter integer IMU_TIMEOUT_MS = 500,
    parameter integer TOF_COUNT = 4,
    parameter integer HARD_STOP_MM = 250
) (
    input wire clk,
    input wire rst_n,
    input wire imu_uart_rx_i,
    input wire tof0_uart_rx_i,
    input wire tof1_uart_rx_i,
    input wire tof2_uart_rx_i,
    input wire tof3_uart_rx_i,
    output wire [31:0] roll_raw_o,
    output wire [31:0] pitch_raw_o,
    output wire [31:0] yaw_raw_o,
    output wire imu_angle_valid_o,
    output wire [15:0] tof0_distance_mm_o,
    output wire [15:0] tof1_distance_mm_o,
    output wire [15:0] tof2_distance_mm_o,
    output wire [15:0] tof3_distance_mm_o,
    output wire [3:0] tof_valid_o,
    output wire tof_obstacle_o,
    output wire tof_hard_stop_o,
    output wire tof_decel_o,
    output wire [9:0] tof_speed_scale_permille_o,
    output wire [15:0] tof_nearest_mm_o,
    output reg tof0_sample_o=0
);
    localparam integer TIMEOUT_CYCLES = (CLK_HZ / 1000) * TIMEOUT_MS;
    localparam integer IMU_TIMEOUT_CYCLES = (CLK_HZ / 1000) * IMU_TIMEOUT_MS;
    wire [15:0] d0_p, d1_p, d2_p, d3_p;
    wire v0_p, v1_p, v2_p, v3_p;
    wire e0, e1, e2, e3;
    reg [15:0] d0_r, d1_r, d2_r, d3_r;
    reg [31:0] age0, age1, age2, age3;
    reg [3:0] valid_r;
    wire imu_valid_pulse;
    reg imu_valid_r;
    reg [31:0] imu_age;

    imu_yahboom_uart #(.CLK_HZ(CLK_HZ), .BAUD(IMU_BAUD)) u_imu (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(imu_uart_rx_i),
        .roll_raw_o(roll_raw_o), .pitch_raw_o(pitch_raw_o), .yaw_raw_o(yaw_raw_o),
        .angle_valid_o(imu_valid_pulse), .frame_error_o()
    );
    assign imu_angle_valid_o = imu_valid_r;
    tof_ms53l2m_ascii_uart #(.CLK_HZ(CLK_HZ), .BAUD(TOF_BAUD)) u_tof0 (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(tof0_uart_rx_i),
        .distance_mm_o(d0_p), .valid_pulse_o(v0_p), .frame_error_o(e0)
    );
    generate if (TOF_COUNT > 1) begin : g_tof1
        tof_ms53l2m_ascii_uart #(.CLK_HZ(CLK_HZ), .BAUD(TOF_BAUD)) u_tof1 (
            .clk(clk), .rst_n(rst_n), .uart_rx_i(tof1_uart_rx_i),
            .distance_mm_o(d1_p), .valid_pulse_o(v1_p), .frame_error_o(e1)
        );
    end else begin : g_no_tof1
        assign d1_p = 0; assign v1_p = 1'b0; assign e1 = 1'b0;
    end endgenerate
    generate if (TOF_COUNT > 2) begin : g_tof2
        tof_ms53l2m_ascii_uart #(.CLK_HZ(CLK_HZ), .BAUD(TOF_BAUD)) u_tof2 (
            .clk(clk), .rst_n(rst_n), .uart_rx_i(tof2_uart_rx_i),
            .distance_mm_o(d2_p), .valid_pulse_o(v2_p), .frame_error_o(e2)
        );
    end else begin : g_no_tof2
        assign d2_p = 0; assign v2_p = 1'b0; assign e2 = 1'b0;
    end endgenerate
    generate if (TOF_COUNT > 3) begin : g_tof3
        tof_ms53l2m_ascii_uart #(.CLK_HZ(CLK_HZ), .BAUD(TOF_BAUD)) u_tof3 (
            .clk(clk), .rst_n(rst_n), .uart_rx_i(tof3_uart_rx_i),
            .distance_mm_o(d3_p), .valid_pulse_o(v3_p), .frame_error_o(e3)
        );
    end else begin : g_no_tof3
        assign d3_p = 0; assign v3_p = 1'b0; assign e3 = 1'b0;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tof0_sample_o <= 0;
            d0_r <= 0; d1_r <= 0; d2_r <= 0; d3_r <= 0;
            age0 <= 0; age1 <= 0; age2 <= 0; age3 <= 0;
            valid_r <= 0;
            imu_valid_r <= 0; imu_age <= 0;
        end else begin
            // Delayed pulse refers to the committed distance register.
            tof0_sample_o <= v0_p;
            if (imu_valid_pulse) begin imu_valid_r <= 1; imu_age <= 0; end
            else if (imu_age < IMU_TIMEOUT_CYCLES) imu_age <= imu_age + 1'b1;
            else imu_valid_r <= 0;
            if (v0_p) begin d0_r <= d0_p; age0 <= 0; valid_r[0] <= 1'b1; end
            else if (age0 < TIMEOUT_CYCLES) age0 <= age0 + 1'b1;
            else valid_r[0] <= 1'b0;
            if (v1_p) begin d1_r <= d1_p; age1 <= 0; valid_r[1] <= 1'b1; end
            else if (age1 < TIMEOUT_CYCLES) age1 <= age1 + 1'b1;
            else valid_r[1] <= 1'b0;
            if (v2_p) begin d2_r <= d2_p; age2 <= 0; valid_r[2] <= 1'b1; end
            else if (age2 < TIMEOUT_CYCLES) age2 <= age2 + 1'b1;
            else valid_r[2] <= 1'b0;
            if (v3_p) begin d3_r <= d3_p; age3 <= 0; valid_r[3] <= 1'b1; end
            else if (age3 < TIMEOUT_CYCLES) age3 <= age3 + 1'b1;
            else valid_r[3] <= 1'b0;
        end
    end
    assign tof0_distance_mm_o = d0_r;
    assign tof1_distance_mm_o = d1_r;
    assign tof2_distance_mm_o = d2_r;
    assign tof3_distance_mm_o = d3_r;
    assign tof_valid_o = valid_r;
    tof_obstacle_guard #(.HARD_STOP_MM(HARD_STOP_MM)) u_guard (
        .d0_i(d0_r), .d1_i(d1_r), .d2_i(d2_r), .d3_i(d3_r), .valid_i(valid_r),
        .valid_o(), .obstacle_o(tof_obstacle_o), .hard_stop_o(tof_hard_stop_o),
        .decel_o(tof_decel_o), .speed_scale_permille_o(tof_speed_scale_permille_o),
        .nearest_mm_o(tof_nearest_mm_o)
    );
endmodule
