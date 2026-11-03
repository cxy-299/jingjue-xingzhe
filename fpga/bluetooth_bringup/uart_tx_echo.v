// 8-N-1 串口发送器；发送请求只在空闲时采纳一次。
module uart_tx_echo #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start_i,
    input  wire [7:0] data_i,
    output reg        tx_o,
    output reg        busy_o,
    output reg        done_o
);
    localparam integer CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1,
                     S_DATA = 2'd2, S_STOP = 2'd3;

    reg [1:0] state;
    reg [31:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] data_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            baud_count <= 32'd0;
            bit_index <= 3'd0;
            data_hold <= 8'd0;
            tx_o <= 1'b1;  // UART 空闲为高。
            busy_o <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state)
                S_IDLE: begin
                    tx_o <= 1'b1;
                    busy_o <= 1'b0;
                    baud_count <= 32'd0;
                    if (start_i) begin
                        data_hold <= data_i;
                        tx_o <= 1'b0;
                        busy_o <= 1'b1;
                        state <= S_START;
                    end
                end
                S_START: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 32'd0;
                        bit_index <= 3'd0;
                        tx_o <= data_hold[0];
                        state <= S_DATA;
                    end else baud_count <= baud_count + 1'b1;
                end
                S_DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 32'd0;
                        if (bit_index == 3'd7) begin
                            tx_o <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx_o <= data_hold[bit_index + 1'b1];
                        end
                    end else baud_count <= baud_count + 1'b1;
                end
                S_STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= 32'd0;
                        busy_o <= 1'b0;
                        done_o <= 1'b1;
                        state <= S_IDLE;
                    end else baud_count <= baud_count + 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
