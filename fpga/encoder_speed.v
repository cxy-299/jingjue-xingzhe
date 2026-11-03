// Synchronized quadrature encoder counter with sampled speed output.
// speed_o is the signed count delta since the previous sample_tick_i.
module encoder_speed #(
    parameter integer SPEED_WIDTH = 16,
    // 1 preserves the legacy decoder. SIN12 uses 50 clocks = 1 us at 50 MHz.
    parameter integer FILTER_CYCLES = 1
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         encoder_a_i,
    input  wire                         encoder_b_i,
    input  wire                         sample_tick_i,
    output wire signed [31:0]            position_o,
    output reg  signed [SPEED_WIDTH-1:0] speed_o
);
    reg a_meta;
    reg a_sync;
    reg b_meta;
    reg b_sync;
    reg [1:0] previous_state;
    reg signed [31:0] position;
    reg signed [31:0] sampled_position;
    reg signed [31:0] delta_i;
    wire [1:0] encoder_state;
    generate if (FILTER_CYCLES <= 1) begin : g_unfiltered
        assign encoder_state = {a_sync, b_sync};
    end else begin : g_stable_pair
        localparam integer FILTER_WIDTH = $clog2(FILTER_CYCLES + 1);
        reg [1:0] candidate = 0, stable = 0;
        reg [FILTER_WIDTH-1:0] stable_cycles = 0;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin candidate<=0;stable<=0;stable_cycles<=0;end
            else if ({a_sync,b_sync} != candidate) begin
                candidate<={a_sync,b_sync};stable_cycles<=1;
            end else if (stable_cycles < FILTER_CYCLES) begin
                stable_cycles<=stable_cycles+1'b1;
                if (stable_cycles==FILTER_CYCLES-1) stable<=candidate;
            end
        end
        assign encoder_state = stable;
    end endgenerate

    assign position_o = position;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_meta <= 1'b0;
            a_sync <= 1'b0;
            b_meta <= 1'b0;
            b_sync <= 1'b0;
            previous_state <= 2'b00;
            position <= 32'sd0;
            sampled_position <= 32'sd0;
            speed_o <= {SPEED_WIDTH{1'b0}};
            delta_i <= 32'sd0;
        end else begin
            a_meta <= encoder_a_i;
            a_sync <= a_meta;
            b_meta <= encoder_b_i;
            b_sync <= b_meta;

            // 正向 00->01->11->10->00；反向按相反次序。
            // 不能写 1'sd1：有符号 1 位的二进制 1 表示 -1，会颠倒计数方向。
            case ({previous_state, encoder_state})
                4'b0001, 4'b0111, 4'b1110, 4'b1000: position <= position + 32'sd1;
                4'b0010, 4'b1011, 4'b1101, 4'b0100: position <= position - 32'sd1;
                default: position <= position;
            endcase
            previous_state <= encoder_state;

            if (sample_tick_i) begin
                delta_i = position - sampled_position;
                speed_o <= delta_i[SPEED_WIDTH-1:0];
                sampled_position <= position;
            end
        end
    end
endmodule
