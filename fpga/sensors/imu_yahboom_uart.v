// Yahboom YB-MRA02 UART Euler receiver. The vendor's YbImuSerialLib and
// STM32 driver use 115200 8N1 and the frame:
//   7E 23 LEN FUNC PAYLOAD CHECKSUM
// LEN includes all five overhead bytes. CHECKSUM is the low eight bits of
// the sum of all preceding bytes. FUNC=26 contains three little-endian
// IEEE-754 float32 values in radians: roll, pitch, yaw.
module imu_yahboom_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200
) (
    input wire clk,
    input wire rst_n,
    input wire uart_rx_i,
    output reg [31:0] roll_raw_o,
    output reg [31:0] pitch_raw_o,
    output reg [31:0] yaw_raw_o,
    output reg angle_valid_o,
    output reg frame_error_o
);
    wire [7:0] rx_data;
    wire rx_valid, rx_frame_error;
    reg [2:0] state;
    reg [7:0] frame_len, frame_func, payload_count, checksum;
    reg [95:0] payload;
    localparam S_HEAD1=3'd0, S_HEAD2=3'd1, S_LENGTH=3'd2,
               S_FUNCTION=3'd3, S_PAYLOAD=3'd4, S_CHECK=3'd5;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx_i),
        .data_o(rx_data), .data_valid_o(rx_valid),
        .framing_error_o(rx_frame_error)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_HEAD1;
            frame_len <= 0; frame_func <= 0; payload_count <= 0;
            checksum <= 0; payload <= 0;
            roll_raw_o <= 0; pitch_raw_o <= 0; yaw_raw_o <= 0;
            angle_valid_o <= 0; frame_error_o <= 0;
        end else begin
            angle_valid_o <= 0;
            frame_error_o <= rx_frame_error;
            if (rx_frame_error) state <= S_HEAD1;
            else if (rx_valid) begin
                case (state)
                    S_HEAD1: if (rx_data == 8'h7e) begin
                        checksum <= 8'h7e;
                        state <= S_HEAD2;
                    end
                    S_HEAD2: begin
                        if (rx_data == 8'h23) begin
                            checksum <= checksum + rx_data;
                            state <= S_LENGTH;
                        end else state <= S_HEAD1;
                    end
                    S_LENGTH: begin
                        if (rx_data >= 8'd5 && rx_data <= 8'd64) begin
                            frame_len <= rx_data;
                            checksum <= checksum + rx_data;
                            state <= S_FUNCTION;
                        end else begin
                            frame_error_o <= 1;
                            state <= S_HEAD1;
                        end
                    end
                    S_FUNCTION: begin
                        frame_func <= rx_data;
                        checksum <= checksum + rx_data;
                        payload_count <= 0;
                        payload <= 0;
                        state <= (frame_len == 8'd5) ? S_CHECK : S_PAYLOAD;
                    end
                    S_PAYLOAD: begin
                        checksum <= checksum + rx_data;
                        payload <= {rx_data, payload[95:8]};
                        payload_count <= payload_count + 1'b1;
                        if (payload_count == frame_len - 8'd6) state <= S_CHECK;
                    end
                    S_CHECK: begin
                        if (rx_data == checksum) begin
                            if (frame_func == 8'h26 && frame_len == 8'd17) begin
                                roll_raw_o <= payload[31:0];
                                pitch_raw_o <= payload[63:32];
                                yaw_raw_o <= payload[95:64];
                                angle_valid_o <= 1;
                            end
                        end else frame_error_o <= 1;
                        state <= S_HEAD1;
                    end
                    default: state <= S_HEAD1;
                endcase
            end
        end
    end
endmodule
