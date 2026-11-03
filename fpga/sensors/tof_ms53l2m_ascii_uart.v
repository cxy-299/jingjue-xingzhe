// ATK-MS53L2M normal-mode ASCII distance receiver.
// Accepts e.g. "800\r\n" and "800,1234\r\n"; only the first integer is used.
module tof_ms53l2m_ascii_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115200,
    parameter integer MIN_MM = 40,
    parameter integer MAX_MM = 8000
) (
    input wire clk,
    input wire rst_n,
    input wire uart_rx_i,
    output reg [15:0] distance_mm_o,
    output reg valid_pulse_o,
    output reg frame_error_o
);
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_error;
    // Check the range *before* multiplying: an arbitrarily long decimal token
    // must never wrap back into a plausible distance. Constants fold at synth.
    localparam [15:0] MAX_PREFIX = MAX_MM / 10;
    localparam [3:0] MAX_LAST_DIGIT = MAX_MM % 10;
    wire [3:0] decimal_digit = rx_data[3:0];
    reg [15:0] accumulator;
    reg digit_seen;
    reg suffix_seen;
    reg line_bad;
    wire exceeds_max = (accumulator > MAX_PREFIX) ||
                       ((accumulator == MAX_PREFIX) && (decimal_digit > MAX_LAST_DIGIT));

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx_i),
        .data_o(rx_data), .data_valid_o(rx_valid),
        .framing_error_o(rx_frame_error)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 0;
            digit_seen <= 1'b0;
            suffix_seen <= 1'b0;
            line_bad <= 1'b0;
            distance_mm_o <= 0;
            valid_pulse_o <= 1'b0;
            frame_error_o <= 1'b0;
        end else begin
            valid_pulse_o <= 1'b0;
            frame_error_o <= rx_frame_error;
            if (rx_frame_error) begin
                // The lost byte may be a digit or delimiter. Drop everything
                // through the next intact CR/LF, rather than joining its sides.
                accumulator <= 0;
                digit_seen <= 1'b0;
                suffix_seen <= 1'b0;
                line_bad <= 1'b1;
            end else if (rx_valid) begin
                if ((rx_data == 8'h0d) || (rx_data == 8'h0a)) begin
                    if (!line_bad && digit_seen && accumulator >= MIN_MM && accumulator <= MAX_MM) begin
                        distance_mm_o <= accumulator;
                        valid_pulse_o <= 1'b1;
                    end else if (digit_seen || line_bad) begin
                        frame_error_o <= 1'b1;
                    end
                    accumulator <= 0;
                    digit_seen <= 1'b0;
                    suffix_seen <= 1'b0;
                    line_bad <= 1'b0;
                end else if (!line_bad && !suffix_seen && rx_data >= "0" && rx_data <= "9") begin
                    if (exceeds_max) begin
                        line_bad <= 1'b1;
                        frame_error_o <= 1'b1;
                        accumulator <= 0;
                    end else begin
                        accumulator <= (accumulator << 3) + (accumulator << 1) + {12'd0, decimal_digit};
                    end
                    digit_seen <= 1'b1;
                end else if (!line_bad && digit_seen) begin
                    // comma, space, and signal-strength text are not part of
                    // the first distance token; terminate the normal parser.
                    suffix_seen <= 1'b1;
                end
            end
        end
    end
endmodule
