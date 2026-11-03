`timescale 1ns/1ps

// 跨语言验收：用 Python pack_heartbeat/pack_vision_result 生成的原始字节，
// 按 115200 8-N-1 真实串行时序送进 FPGA RTL，检查全部关键字段。
module tb_python_protocol_vector;
    localparam integer BIT_NS = 8680;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    reg [7:0] stream [0:85];
    integer index;
    wire link_alive, vision_fresh, target_valid, target_confirmed;
    wire [15:0] class_id, confidence, center_x, area_ratio, sequence_id, crc_errors;
    wire signed [15:0] center_error;
    wire [31:0] frame_id;

    always #10 clk = ~clk;

    vision_uart_bridge #(.CLK_HZ(50_000_000), .BAUD(115200),
        .WATCHDOG_MS(5), .VISION_TIMEOUT_MS(5)) dut (
        .clk(clk), .rst_n(rst_n), .pi_uart_rx_i(uart_rx),
        .link_alive_o(link_alive), .vision_fresh_o(vision_fresh),
        .target_valid_o(target_valid), .target_confirmed_o(target_confirmed),
        .target_centered_o(), .alignment_o(), .class_id_o(class_id),
        .confidence_o(confidence), .center_x_o(center_x), .center_y_o(),
        .width_o(), .height_o(), .center_error_o(center_error),
        .area_ratio_o(area_ratio), .frame_id_o(frame_id),
        .sequence_o(sequence_id), .crc_error_count_o(crc_errors),
        .uart_framing_error_o(), .vision_packet_pulse_o()
    );

    task automatic send_byte(input [7:0] value);
        integer bit_index;
        begin
            uart_rx = 1'b0;
            #(BIT_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index];
                #(BIT_NS);
            end
            uart_rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    initial begin
        $readmemh("python_uart_frames.mem", stream);
        #100;
        rst_n = 1'b1;
        #(BIT_NS);
        // Python 心跳：seq=10, uptime=1234；只能令 link_alive=1。
        for (index = 0; index < 14; index = index + 1) send_byte(stream[index]);
        #100;
        if (link_alive !== 1'b1 || vision_fresh !== 1'b0)
            $fatal(1, "FAIL Python heartbeat");

        // Python 视觉包：瓶子 class=39、cx=3000、误差=-4000、面积=648。
        for (index = 14; index < 50; index = index + 1) send_byte(stream[index]);
        #100;
        if (target_valid !== 1'b1 || target_confirmed !== 1'b1 ||
            class_id !== 16'd39 || confidence !== 16'd9000 ||
            center_x !== 16'd3000 || center_error !== -16'sd4000 ||
            area_ratio !== 16'd648 || frame_id !== 32'd77 ||
            sequence_id !== 16'd11 || crc_errors !== 16'd0)
            $fatal(1, "FAIL Python vision field mapping");

        // Python 无目标包：明确撤销目标，保持视觉帧新鲜。
        for (index = 50; index < 86; index = index + 1) send_byte(stream[index]);
        #100;
        if (link_alive !== 1'b1 || vision_fresh !== 1'b1 ||
            target_valid !== 1'b0 || target_confirmed !== 1'b0 ||
            class_id !== 16'hFFFF || frame_id !== 32'd78 ||
            sequence_id !== 16'd12 || crc_errors !== 16'd0)
            $fatal(1, "FAIL Python no-target frame");

        $display("PASS tb_python_protocol_vector: Python bytes -> FPGA RTL");
        $finish;
    end
endmodule
