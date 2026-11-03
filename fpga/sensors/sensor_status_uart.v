// 统一传感器状态诊断：115200 8N1。
// I1 T1 D0455 H0 F00 R3F800000 P00000000 Y00000000 W0\r\n
// R/P/Y are little-endian IMU float32 values represented in normal hex bit
// order; the PC converts radians to degrees. F bits: 0 ToF, 1 Bluetooth
// timeout, 2 UART framing, 3 navigation, 4 motor PI. W bits identify the
// latched PI fault per wheel: bit0 M1 through bit3 M4.
module sensor_status_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer REPORT_MS = 250
) (
    input wire clk,
    input wire rst_n,
    input wire imu_valid_i,
    input wire tof_valid_i,
    input wire [15:0] distance_i,
    input wire hard_stop_i,
    input wire [31:0] roll_bits_i,
    input wire [31:0] pitch_bits_i,
    input wire [31:0] yaw_bits_i,
    input wire [7:0] fault_flags_i,
    input wire [3:0] wheel_fault_i,
    output wire tx_o
);
    localparam integer REPORT_CYCLES = (CLK_HZ / 1000) * REPORT_MS;
    reg [31:0] report_count;
    reg startup_pending;
    reg pending = 0;
    reg [5:0] byte_index = 0;
    reg [7:0] tx_byte = 0;
    reg tx_start = 0;
    wire tx_busy, tx_done;
    reg imu_hold, tof_hold, hard_hold;
    reg [15:0] distance_hold;
    reg [31:0] roll_hold, pitch_hold, yaw_hold;
    reg [7:0] fault_hold;
    reg [3:0] wheel_fault_hold;

    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin
            hex_ascii = nibble < 10 ? 8'h30 + nibble : 8'h41 + nibble - 4'd10;
        end
    endfunction

    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n), .start_i(tx_start), .data_i(tx_byte),
        .tx_o(tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Start with a report immediately after reset.  This makes a
            // cold-start UART check deterministic instead of requiring the
            // operator to wait for the first 250 ms interval.
            report_count <= 0; startup_pending <= 1;
            pending <= 0; byte_index <= 0; tx_byte <= 0;
            tx_start <= 0; imu_hold <= 0; tof_hold <= 0; hard_hold <= 1;
            distance_hold <= 0;
            roll_hold <= 0; pitch_hold <= 0; yaw_hold <= 0; fault_hold <= 0;
            wheel_fault_hold <= 0;
        end else begin
            tx_start <= 0;
            if (!pending && byte_index == 0) begin
                if (startup_pending || report_count >= REPORT_CYCLES - 1) begin
                    report_count <= 0;
                    startup_pending <= 0;
                    pending <= 1;
                    imu_hold <= imu_valid_i;
                    tof_hold <= tof_valid_i;
                    hard_hold <= hard_stop_i;
                    distance_hold <= distance_i;
                    roll_hold <= roll_bits_i; pitch_hold <= pitch_bits_i;
                    yaw_hold <= yaw_bits_i; fault_hold <= fault_flags_i;
                    wheel_fault_hold <= wheel_fault_i;
                end else report_count <= report_count + 1'b1;
            end
            if (pending) begin
                // uart_tx_echo asserts tx_done while it is completing the
                // stop bit.  Do not start a new byte on that same cycle,
                // otherwise the previous byte is emitted once more.
                if (!tx_busy && !tx_done) begin
                    case (byte_index)
                        0: tx_byte <= "I";
                        1: tx_byte <= imu_hold ? "1" : "0";
                        2: tx_byte <= " ";
                        3: tx_byte <= "T";
                        4: tx_byte <= tof_hold ? "1" : "0";
                        5: tx_byte <= " ";
                        6: tx_byte <= "D";
                        7: tx_byte <= 8'h30 + ((distance_hold / 1000) % 10);
                        8: tx_byte <= 8'h30 + ((distance_hold / 100) % 10);
                        9: tx_byte <= 8'h30 + ((distance_hold / 10) % 10);
                        10: tx_byte <= 8'h30 + (distance_hold % 10);
                        11: tx_byte <= " ";
                        12: tx_byte <= "H";
                        13: tx_byte <= hard_hold ? "1" : "0";
                        14: tx_byte <= " ";
                        15: tx_byte <= "F";
                        16: tx_byte <= hex_ascii(fault_hold[7:4]);
                        17: tx_byte <= hex_ascii(fault_hold[3:0]);
                        18: tx_byte <= " ";
                        19: tx_byte <= "R";
                        20: tx_byte <= hex_ascii(roll_hold[31:28]);
                        21: tx_byte <= hex_ascii(roll_hold[27:24]);
                        22: tx_byte <= hex_ascii(roll_hold[23:20]);
                        23: tx_byte <= hex_ascii(roll_hold[19:16]);
                        24: tx_byte <= hex_ascii(roll_hold[15:12]);
                        25: tx_byte <= hex_ascii(roll_hold[11:8]);
                        26: tx_byte <= hex_ascii(roll_hold[7:4]);
                        27: tx_byte <= hex_ascii(roll_hold[3:0]);
                        28: tx_byte <= " ";
                        29: tx_byte <= "P";
                        30: tx_byte <= hex_ascii(pitch_hold[31:28]);
                        31: tx_byte <= hex_ascii(pitch_hold[27:24]);
                        32: tx_byte <= hex_ascii(pitch_hold[23:20]);
                        33: tx_byte <= hex_ascii(pitch_hold[19:16]);
                        34: tx_byte <= hex_ascii(pitch_hold[15:12]);
                        35: tx_byte <= hex_ascii(pitch_hold[11:8]);
                        36: tx_byte <= hex_ascii(pitch_hold[7:4]);
                        37: tx_byte <= hex_ascii(pitch_hold[3:0]);
                        38: tx_byte <= " ";
                        39: tx_byte <= "Y";
                        40: tx_byte <= hex_ascii(yaw_hold[31:28]);
                        41: tx_byte <= hex_ascii(yaw_hold[27:24]);
                        42: tx_byte <= hex_ascii(yaw_hold[23:20]);
                        43: tx_byte <= hex_ascii(yaw_hold[19:16]);
                        44: tx_byte <= hex_ascii(yaw_hold[15:12]);
                        45: tx_byte <= hex_ascii(yaw_hold[11:8]);
                        46: tx_byte <= hex_ascii(yaw_hold[7:4]);
                        47: tx_byte <= hex_ascii(yaw_hold[3:0]);
                        48: tx_byte <= " ";
                        49: tx_byte <= "W";
                        50: tx_byte <= hex_ascii(wheel_fault_hold);
                        51: tx_byte <= 8'h0d;
                        default: tx_byte <= 8'h0a;
                    endcase
                    tx_start <= 1;
                end
                if (tx_done) begin
                    if (byte_index == 52) begin
                        byte_index <= 0;
                        pending <= 0;
                    end else byte_index <= byte_index + 1'b1;
                end
            end
        end
    end
endmodule
