// Single ATK-MS53L2M hardware bring-up.
// Temporary wiring: use the verified ACG720 Bluetooth RX pin E16/P7-23 as
// tof_uart_rx_i, disconnecting Bluetooth. Distance is printed on the board's
// USB-UART at 115200 as D=xxxx\r\n; LEDs show valid/decel/stop/error.
module tof_single_bringup #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer TOF_BAUD = 115200,
    parameter integer DIAG_BAUD = 115200
) (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire tof_uart_rx_i,
    output wire diag_uart_tx_o,
    output wire [5:0] led_o
);
    wire [15:0] distance_mm;
    wire distance_valid, tof_error;
    reg [15:0] last_distance;
    reg [31:0] report_timer;
    reg [3:0] msg_index;
    reg [15:0] report_value;
    reg reporting;
    reg tx_start;
    wire tx_busy, tx_done;
    wire [7:0] tx_char;
    reg heartbeat;
    // 50 MHz / 2 = 25,000,000: 24 bits would wrap before the LED toggles.
    reg [31:0] heartbeat_count;
    reg valid_recent;
    reg error_recent;
    reg [31:0] valid_age;
    reg [31:0] error_age;
    // The parser outputs one-clock pulses. Keep the last sample visible until
    // it is stale; a pulse must not be used directly as an LED/safety state.
    wire hard_stop = valid_recent && (last_distance <= 16'd250);
    wire decel = valid_recent && (last_distance < 16'd800) && !hard_stop;

    tof_ms53l2m_ascii_uart #(.CLK_HZ(CLK_HZ), .BAUD(TOF_BAUD)) u_tof (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .uart_rx_i(tof_uart_rx_i),
        .distance_mm_o(distance_mm), .valid_pulse_o(distance_valid),
        .frame_error_o(tof_error)
    );
    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(DIAG_BAUD)) u_tx (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .start_i(tx_start), .data_i(tx_char),
        .tx_o(diag_uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );

    function [7:0] dec_ascii;
        input [3:0] value;
        begin dec_ascii = 8'd48 + value; end
    endfunction
    reg [7:0] char_value;
    integer tmp_value;
    always @* begin
        tmp_value = report_value;
        case (msg_index)
            0: char_value = "D";
            1: char_value = "=";
            2: char_value = dec_ascii((tmp_value / 1000) % 10);
            3: char_value = dec_ascii((tmp_value / 100) % 10);
            4: char_value = dec_ascii((tmp_value / 10) % 10);
            5: char_value = dec_ascii(tmp_value % 10);
            6: char_value = 8'h0d;
            default: char_value = 8'h0a;
        endcase
    end
    assign tx_char = char_value;

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            last_distance <= 0;
            report_timer <= 0;
            msg_index <= 0;
            report_value <= 0;
            reporting <= 1'b0;
            tx_start <= 1'b0;
            heartbeat <= 1'b0;
            heartbeat_count <= 0;
            valid_recent <= 1'b0;
            error_recent <= 1'b0;
            valid_age <= 0;
            error_age <= 0;
        end else begin
        heartbeat_count <= heartbeat_count + 1'b1;
        if (heartbeat_count == CLK_HZ/2) begin heartbeat_count <= 0; heartbeat <= ~heartbeat; end
        tx_start <= 1'b0;
        if (distance_valid) begin
            last_distance <= distance_mm;
            valid_recent <= 1'b1;
            valid_age <= 0;
        end else if (valid_recent) begin
            if (valid_age >= CLK_HZ/2 - 1) valid_recent <= 1'b0;
            else valid_age <= valid_age + 1'b1;
        end
        if (tof_error) begin
            error_recent <= 1'b1;
            error_age <= 0;
        end else if (error_recent) begin
            if (error_age >= CLK_HZ/2 - 1) error_recent <= 1'b0;
            else error_age <= error_age + 1'b1;
        end
        if (!reporting) begin
            if (report_timer >= CLK_HZ/10) begin
                report_timer <= 0;
                report_value <= valid_recent ? last_distance : 16'd0;
                msg_index <= 0;
                reporting <= 1'b1;
            end else report_timer <= report_timer + 1'b1;
        end else begin
            if (tx_done) begin
                if (msg_index == 7) reporting <= 1'b0;
                else msg_index <= msg_index + 1'b1;
            end else if (!tx_busy && !tx_start) tx_start <= 1'b1;
        end
        end
    end
    assign led_o[0] = heartbeat;
    assign led_o[1] = valid_recent;
    assign led_o[2] = hard_stop;
    assign led_o[3] = decel;
    assign led_o[4] = ~valid_recent;
    assign led_o[5] = error_recent;
endmodule
