// SIN9: Pi perception on USB UART, explicit Bluetooth V lease, S always wins.
// No image-area range estimate. Front ToF is used only with a centered target.
module vision_follow_guard #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer VISION_TIMEOUT_MS=1200,
    parameter integer LEASE_MS=300,
    parameter integer NEUTRAL_MS=100
) (
    input wire clk, rst_n,
    input wire packet_i, selected_i, visible_i, confirmed_i, follow_i,
    input wire [15:0] sequence_i, class_i,
    input wire [31:0] lock_i,
    input wire signed [15:0] center_i,
    input wire bt_valid_i, bt_error_i,
    input wire [7:0] bt_byte_i,
    input wire hard_stop_i, sensors_ok_i, motor_fault_i, nav_start_i,
    input wire [15:0] distance_i,
    output reg active_o=0,
    output wire fresh_o, selected_o, visible_o,
    output reg [15:0] class_o=16'hffff,
    output reg [31:0] lock_o=0,
    output reg [3:0] state_o=0,
    output reg [2:0] command_o=0,
    output reg [15:0] target_o=0
);
    localparam integer VISION_CYCLES=(CLK_HZ/1000)*VISION_TIMEOUT_MS;
    localparam integer LEASE_CYCLES=(CLK_HZ/1000)*LEASE_MS;
    localparam integer NEUTRAL_CYCLES=(CLK_HZ/1000)*NEUTRAL_MS;
    reg [31:0] age=VISION_CYCLES, lease_age=LEASE_CYCLES, neutral_age=0;
    reg selected=0, visible=0, confirmed=0, follow=0;
    reg signed [15:0] center=0;
    reg require_stop=1;
    reg [15:0] last_seq=0;
    reg seen=0;
    reg [2:0] desired;
    reg [15:0] speed;
    assign fresh_o=age<VISION_CYCLES;
    assign selected_o=fresh_o && selected;
    assign visible_o=fresh_o && visible && confirmed;
    always @* begin
        desired=0; speed=0;
        if (center < -1200) begin desired=3; speed=6; end
        else if (center > 1200) begin desired=4; speed=6; end
        else if (distance_i > 225) begin
            desired=1;
            speed=distance_i>700 ? 12 : distance_i>450 ? 10 : distance_i>300 ? 8 : 6;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active_o<=0; age<=VISION_CYCLES; lease_age<=LEASE_CYCLES;
            neutral_age<=0; require_stop<=1; seen<=0; last_seq<=0;
            selected<=0; visible<=0; confirmed<=0; follow<=0; center<=0;
            class_o<=16'hffff; lock_o<=0; state_o<=0; command_o<=0; target_o<=0;
        end else begin
            if(age<VISION_CYCLES) age<=age+1'b1;
            if(lease_age<LEASE_CYCLES) lease_age<=lease_age+1'b1;
            if(packet_i && (!seen || sequence_i!=last_seq)) begin
                age<=0; seen<=1; last_seq<=sequence_i;
                selected<=selected_i && lock_i!=0; visible<=visible_i;
                confirmed<=confirmed_i; follow<=follow_i; center<=center_i;
                class_o<=class_i; lock_o<=lock_i;
                // A different clicked object cancels the previous motion authority.
                if(active_o && lock_i!=lock_o) begin
                    active_o<=0; require_stop<=1; command_o<=0; target_o<=0;
                end
            end
            if(command_o==0) begin
                if(neutral_age<NEUTRAL_CYCLES) neutral_age<=neutral_age+1'b1;
            end else neutral_age<=0;
            if(!active_o) begin
                command_o<=0; target_o<=0;
                state_o<=!fresh_o ? 9 : !selected ? 1 : !visible || !confirmed ? 3 : 2;
            end else if(!fresh_o || !selected || !visible || !confirmed || !follow ||
                        hard_stop_i || !sensors_ok_i || motor_fault_i || lease_age>=LEASE_CYCLES) begin
                command_o<=0; target_o<=0; active_o<=0; require_stop<=1;
                state_o<=hard_stop_i ? 8 : motor_fault_i ? 10 : !fresh_o ? 9 : 3;
            end else if(command_o!=0 && desired!=command_o) begin
                command_o<=0; target_o<=0; neutral_age<=0; state_o<=11;
            end else if(command_o==0 && neutral_age<NEUTRAL_CYCLES) begin
                target_o<=0; state_o<=11;
            end else begin
                command_o<=desired; target_o<=speed;
                state_o<=desired==3 ? 4 : desired==4 ? 5 : desired==1 ? 6 : 7;
            end
            // New bad/missing target cancels immediately, before the next frame age tick.
            if(packet_i && (!selected_i || !visible_i || !confirmed_i || !follow_i) && active_o) begin
                active_o<=0; command_o<=0; target_o<=0; require_stop<=1; state_o<=3;
            end
            if(bt_valid_i && !bt_error_i && bt_byte_i=="V" && !require_stop &&
               fresh_o && selected && visible && confirmed && follow &&
               sensors_ok_i && !hard_stop_i && !motor_fault_i) begin
                active_o<=1; lease_age<=0;
            end
            if(nav_start_i || bt_error_i || (bt_valid_i &&
               (bt_byte_i=="S" || bt_byte_i=="s" || bt_byte_i=="F" || bt_byte_i=="B" ||
                bt_byte_i=="L" || bt_byte_i=="R"))) begin
                active_o<=0; command_o<=0; target_o<=0; lease_age<=LEASE_CYCLES;
                require_stop<=!(bt_valid_i && (bt_byte_i=="S" || bt_byte_i=="s"));
            end
            // Cancellation wins even if a V refresh arrives with the same packet.
            if(packet_i && active_o && (lock_i!=lock_o || !selected_i ||
               !visible_i || !confirmed_i || !follow_i)) begin
                active_o<=0; command_o<=0; target_o<=0; require_stop<=1; state_o<=3;
            end
        end
    end
endmodule
