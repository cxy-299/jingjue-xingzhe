`timescale 1ns/1ps
module tb_sensor_frontend;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg imu_rx = 1'b1;
    reg tof_rx = 1'b1;
    wire [31:0] roll_raw, pitch_raw, yaw_raw;
    wire imu_valid, imu_error;
    wire [15:0] distance_mm;
    wire tof_valid, tof_error;
    reg [15:0] d0, d1, d2, d3;
    reg [3:0] dvalid;
    wire guard_valid, obstacle, hard_stop, decel;
    wire [9:0] speed_scale;
    wire [15:0] nearest;
    reg seen_imu = 1'b0;
    reg [31:0] seen_roll, seen_pitch, seen_yaw;
    reg seen_tof = 1'b0;

    imu_yahboom_uart #(.CLK_HZ(100_000_000), .BAUD(115_200)) u_imu (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(imu_rx),
        .roll_raw_o(roll_raw), .pitch_raw_o(pitch_raw), .yaw_raw_o(yaw_raw),
        .angle_valid_o(imu_valid), .frame_error_o(imu_error)
    );
    tof_ms53l2m_ascii_uart #(.CLK_HZ(100_000_000), .BAUD(9_600)) u_tof (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(tof_rx),
        .distance_mm_o(distance_mm), .valid_pulse_o(tof_valid),
        .frame_error_o(tof_error)
    );
    tof_obstacle_guard u_guard (
        .d0_i(d0), .d1_i(d1), .d2_i(d2), .d3_i(d3), .valid_i(dvalid),
        .valid_o(guard_valid), .obstacle_o(obstacle), .hard_stop_o(hard_stop),
        .decel_o(decel), .speed_scale_permille_o(speed_scale),
        .nearest_mm_o(nearest)
    );

    task automatic send_imu_byte(input reg [7:0] value);
        integer i;
        begin
            imu_rx = 1'b0; #(8_681);
            for (i = 0; i < 8; i = i + 1) begin
                imu_rx = value[i]; #(8_681);
            end
            imu_rx = 1'b1; #(8_681);
        end
    endtask
    task automatic send_tof_byte(input reg [7:0] value);
        integer i;
        begin
            tof_rx = 1'b0; #(104_167);
            for (i = 0; i < 8; i = i + 1) begin
                tof_rx = value[i]; #(104_167);
            end
            tof_rx = 1'b1; #(104_167);
        end
    endtask

    always @(posedge clk) begin
        if (imu_valid) begin
            seen_imu <= 1'b1;
            seen_roll <= roll_raw;
            seen_pitch <= pitch_raw;
            seen_yaw <= yaw_raw;
        end
        if (tof_valid) seen_tof <= 1'b1;
    end

    task automatic send_imu_angle;
        begin
            // Vendor frame: Euler float32 radians = 1.0, -0.5, 0.25.
            send_imu_byte(8'h7e); send_imu_byte(8'h23);
            send_imu_byte(8'd17); send_imu_byte(8'h26);
            send_imu_byte(8'h00); send_imu_byte(8'h00);
            send_imu_byte(8'h80); send_imu_byte(8'h3f);
            send_imu_byte(8'h00); send_imu_byte(8'h00);
            send_imu_byte(8'h00); send_imu_byte(8'hbf);
            send_imu_byte(8'h00); send_imu_byte(8'h00);
            send_imu_byte(8'h80); send_imu_byte(8'h3e);
            send_imu_byte(8'h14);
        end
    endtask

    task automatic send_tof(input integer value);
        integer i;
        reg [7:0] digits [0:7];
        integer n, v;
        begin
            n = 0; v = value;
            if (v == 0) begin digits[0] = "0"; n = 1; end
            else begin
                while (v > 0) begin digits[n] = "0" + (v % 10); v = v / 10; n = n + 1; end
                for (i = 0; i < n/2; i = i + 1) begin
                    digits[7] = digits[i]; digits[i] = digits[n-1-i]; digits[n-1-i] = digits[7];
                end
            end
            for (i = 0; i < n; i = i + 1) send_tof_byte(digits[i]);
            send_tof_byte(8'h0d); send_tof_byte(8'h0a);
        end
    endtask

    initial begin
        d0 = 0; d1 = 0; d2 = 0; d3 = 0; dvalid = 0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        send_imu_angle();
        repeat (20) @(posedge clk);
        if (!seen_imu || seen_roll !== 32'h3f800000 || seen_pitch !== 32'hbf000000 || seen_yaw !== 32'h3e800000)
            $fatal(1, "IMU angle frame decode failed");
        send_tof(1200);
        repeat (20) @(posedge clk);
        if (!seen_tof || distance_mm !== 16'd1200) $fatal(1, "ToF parse failed");
        dvalid = 4'b0000; #1;
        if (!hard_stop || speed_scale !== 0) $fatal(1, "invalid ToF must stop");
        d0 = 1000; d1 = 900; dvalid = 4'b0011; #1;
        if (hard_stop || speed_scale !== 1000) $fatal(1, "clear policy failed");
        d0 = 450; #1;
        if (!decel || hard_stop || speed_scale !== 500) $fatal(1, "near decel policy failed");
        d0 = 650; #1;
        if (!decel || hard_stop || speed_scale !== 750) $fatal(1, "far decel policy failed");
        d0 = 200; #1;
        if (!hard_stop || speed_scale !== 0) $fatal(1, "hard stop policy failed");
        $display("SENSOR_FRONTEND_PASS");
        $finish;
    end
endmodule
