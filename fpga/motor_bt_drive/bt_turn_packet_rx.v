// Shared Bluetooth stream: hide framed payload/CRC bytes from ASCII controls.
// v3 type22: angle_cdeg int16 LE (+CCW), speed 8..12, flags bit0=yaw inverted.
module bt_turn_packet_rx #(
    parameter integer BYTE_TIMEOUT_CYCLES=1_000_000
) (
    input wire clk,rst_n,
    input wire [7:0] byte_i,
    input wire valid_i,error_i,
    output wire ascii_valid_o,
    output reg request_o=0,
    output reg [15:0] sequence_o=0,
    output reg signed [15:0] angle_o=0,
    output reg [7:0] speed_o=8,
    output reg inverted_o=0
);
    localparam IDLE=0,HEAD=1,BODY=2,PAYLOAD=3,CRC_LO=4,CRC_HI=5,DROP=6;
    reg [2:0] state=IDLE,index=0;
    reg [15:0] length=0,position=0,seq=0,crc=16'hffff;
    reg [7:0] version=0,kind=0,low_crc=0;
    reg [31:0] payload=0,age=0;
    assign ascii_valid_o=valid_i && !error_i && state==IDLE && byte_i!=8'haa;
    function [15:0] crc_next(input [15:0] c,input [7:0] b);
        integer k;reg [15:0] v;
        begin
            v=c^{b,8'h00};
            for(k=0;k<8;k=k+1)v=v[15] ? (v<<1)^16'h1021 : v<<1;
            crc_next=v;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;index<=0;length<=0;position<=0;seq<=0;crc<=16'hffff;
            version<=0;kind<=0;low_crc<=0;payload<=0;age<=0;
            request_o<=0;sequence_o<=0;angle_o<=0;speed_o<=8;inverted_o<=0;
        end else begin
            request_o<=0;
            if(error_i) begin state<=IDLE;age<=0;end
            else if(valid_i) begin
                age<=0;
                case(state)
                    IDLE: if(byte_i==8'haa) state<=HEAD;
                    HEAD: if(byte_i==8'h55) begin
                        state<=BODY;index<=0;crc<=16'hffff;payload<=0;
                    end else if(byte_i!=8'haa)state<=DROP;
                    BODY: begin
                        crc<=crc_next(crc,byte_i);
                        case(index)
                            0:version<=byte_i;
                            1:kind<=byte_i;
                            2:seq[7:0]<=byte_i;
                            3:seq[15:8]<=byte_i;
                            4:length[7:0]<=byte_i;
                            5:begin
                                length[15:8]<=byte_i;position<=0;
                                if({byte_i,length[7:0]}>80)state<=DROP;
                                else state<=({byte_i,length[7:0]}==0)?CRC_LO:PAYLOAD;
                            end
                        endcase
                        if(index!=5)index<=index+1'b1;
                    end
                    PAYLOAD:begin
                        crc<=crc_next(crc,byte_i);
                        if(position<4)payload[position*8+:8]<=byte_i;
                        if(position+1>=length)state<=CRC_LO;
                        else position<=position+1'b1;
                    end
                    CRC_LO:begin low_crc<=byte_i;state<=CRC_HI;end
                    CRC_HI:begin
                        if({byte_i,low_crc}==crc && version==3 && kind==8'h22 && length==4 &&
                           ($signed(payload[15:0])>=500 && $signed(payload[15:0])<=18000 ||
                            $signed(payload[15:0])<=-500 && $signed(payload[15:0])>=-18000) &&
                           payload[23:16]>=8 && payload[23:16]<=12 && payload[31:24]<=1) begin
                            request_o<=1;sequence_o<=seq;angle_o<=payload[15:0];
                            speed_o<=payload[23:16];inverted_o<=payload[24];
                        end
                        state<=IDLE;
                    end
                    DROP:begin end // malformed frame: quarantine until the byte-gap timeout
                    default:state<=IDLE;
                endcase
            end else if(state!=IDLE) begin
                if(age>=BYTE_TIMEOUT_CYCLES-1)begin state<=IDLE;age<=0;end
                else age<=age+1'b1;
            end
        end
    end
endmodule
