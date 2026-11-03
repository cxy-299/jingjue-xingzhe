// ACG720 板载两片 74HC595 的八位数码管扫描驱动。
// 串入顺序为：先段码（U25），后位选（U24）；段码低有效、位选高有效。
module seg7_hc595_scan #(
    parameter integer SCAN_CYCLES = 25_000,
    parameter integer SHIFT_CYCLES = 25
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] ones_i,
    input  wire [3:0] tens_i,
    input  wire [3:0] hundreds_i,
    output reg        ds_o,
    output reg        sh_cp_o,
    output reg        st_cp_o
);
    localparam integer SCAN_PERIOD = SCAN_CYCLES < 1 ? 1 : SCAN_CYCLES;
    localparam integer SHIFT_PERIOD = SHIFT_CYCLES < 1 ? 1 : SHIFT_CYCLES;
    localparam [2:0] LOAD = 3'd0, DATA = 3'd1, CLOCK_HIGH = 3'd2,
                     CLOCK_LOW = 3'd3, LATCH_HIGH = 3'd4, LATCH_LOW = 3'd5;
    reg [31:0] scan_count;
    reg [31:0] shift_count;
    reg [2:0] digit_index;
    reg [2:0] state;
    reg [15:0] shift_data;
    reg [3:0] bit_index;
    reg [3:0] digit_value;
    reg [6:0] segment;
    reg [7:0] select_digit;

    // 低三位显示百、十、个位；其余五位消隐，便于直接读取计数。
    always @* begin
        select_digit = 8'b0000_0001 << digit_index;
        case (digit_index)
            3'd0: digit_value = ones_i;
            3'd1: digit_value = tens_i;
            3'd2: digit_value = hundreds_i;
            default: digit_value = 4'hf;
        endcase
        case (digit_value)
            4'd0: segment = 7'b1000000;
            4'd1: segment = 7'b1111001;
            4'd2: segment = 7'b0100100;
            4'd3: segment = 7'b0110000;
            4'd4: segment = 7'b0011001;
            4'd5: segment = 7'b0010010;
            4'd6: segment = 7'b0000010;
            4'd7: segment = 7'b1111000;
            4'd8: segment = 7'b0000000;
            4'd9: segment = 7'b0010000;
            default: segment = 7'b1111111;
        endcase
    end

    // 所有时序使用 50 MHz 主时钟及使能脉冲，不产生额外时钟域。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_count <= 32'd0;
            digit_index <= 3'd0;
            shift_count <= 32'd0;
            state <= LOAD;
            shift_data <= 16'd0;
            bit_index <= 4'd0;
            ds_o <= 1'b0;
            sh_cp_o <= 1'b0;
            st_cp_o <= 1'b0;
        end else begin
            if (scan_count >= SCAN_PERIOD - 1) begin
                scan_count <= 32'd0;
                digit_index <= digit_index + 1'b1;
            end else
                scan_count <= scan_count + 1'b1;

            if (shift_count >= SHIFT_PERIOD - 1) begin
                shift_count <= 32'd0;
                case (state)
                    LOAD: begin
                        shift_data <= {1'b0, segment, select_digit};
                        bit_index <= 4'd15;
                        st_cp_o <= 1'b0;
                        state <= DATA;
                    end
                    DATA: begin
                        sh_cp_o <= 1'b0;
                        ds_o <= shift_data[15];
                        state <= CLOCK_HIGH;
                    end
                    CLOCK_HIGH: begin
                        sh_cp_o <= 1'b1;
                        state <= CLOCK_LOW;
                    end
                    CLOCK_LOW: begin
                        sh_cp_o <= 1'b0;
                        shift_data <= shift_data << 1;
                        if (bit_index == 0)
                            state <= LATCH_HIGH;
                        else begin
                            bit_index <= bit_index - 1'b1;
                            state <= DATA;
                        end
                    end
                    LATCH_HIGH: begin
                        st_cp_o <= 1'b1;
                        state <= LATCH_LOW;
                    end
                    default: begin
                        st_cp_o <= 1'b0;
                        state <= LOAD;
                    end
                endcase
            end else
                shift_count <= shift_count + 1'b1;
        end
    end
endmodule
