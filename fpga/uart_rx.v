// 8-N-1 串口接收器：默认 50 MHz 时钟、115200 波特率。
// 只负责“串行电平 -> 字节”，不处理帧头或 CRC。
module uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx_i,
    output reg  [7:0] data_o,
    output reg        data_valid_o,
    output reg        framing_error_o
);
    localparam integer CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_START = 2'd1;
    localparam [1:0] S_DATA  = 2'd2;
    localparam [1:0] S_STOP  = 2'd3;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [31:0] clock_count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    // 输入来自异步串口，先用两级寄存器同步，降低亚稳态风险。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= uart_rx_i;
            rx_sync <= rx_meta;
        end
    end

    // 起始位在中点确认，后续每隔一个位时间采样数据/停止位。
    // 停止位正确时 data_valid_o 只拉高一个 FPGA 时钟周期。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            clock_count <= 32'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
            data_o <= 8'd0;
            data_valid_o <= 1'b0;
            framing_error_o <= 1'b0;
        end else begin
            data_valid_o <= 1'b0;
            framing_error_o <= 1'b0;
            case (state)
                S_IDLE: begin
                    clock_count <= 32'd0;
                    bit_index <= 3'd0;
                    if (!rx_sync)
                        state <= S_START;
                end

                S_START: begin
                    if (clock_count == HALF_BIT - 1) begin
                        clock_count <= 32'd0;
                        state <= rx_sync ? S_IDLE : S_DATA;
                    end else begin
                        clock_count <= clock_count + 1'b1;
                    end
                end

                S_DATA: begin
                    if (clock_count == CLKS_PER_BIT - 1) begin
                        clock_count <= 32'd0;
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clock_count <= clock_count + 1'b1;
                    end
                end

                S_STOP: begin
                    if (clock_count == CLKS_PER_BIT - 1) begin
                        clock_count <= 32'd0;
                        state <= S_IDLE;
                        if (rx_sync) begin
                            data_o <= shift_reg;
                            data_valid_o <= 1'b1;
                        end else begin
                            framing_error_o <= 1'b1;
                        end
                    end else begin
                        clock_count <= clock_count + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

