// v3 type 0x27, payload P/I/D uint16 LE. CRC-protected, atomic stopped-only apply.
// status: 0 boot/default; 1 applied; 2 busy; 3 range. Invalid CRC has no ACK.
module bt_pid_config #(parameter integer BYTE_TIMEOUT_CYCLES=1_000_000)(
    input wire clk,rst_n,input wire [7:0] byte_i,input wire valid_i,error_i,stopped_i,
    output reg [5:0] p_o=4,i_o=1,d_o=0,
    output reg [15:0] sequence_o=0,output reg [1:0] status_o=0,
    output reg changed_o=0
);
    localparam IDLE=0,HEAD=1,BODY=2,PAYLOAD=3,CRC_LO=4,CRC_HI=5,DROP=6;
    reg [2:0] state=0,index=0;
    reg [15:0] length=0,position=0,seq=0,crc=16'hffff;
    reg [7:0] version=0,kind=0,low_crc=0;
    reg [47:0] payload=0;
    reg [31:0] age=0;
    function [15:0] crc_next(input [15:0] c,input [7:0] b);
        integer k;reg [15:0] v;
        begin v=c^{b,8'h00};for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc_next=v;end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=0;index<=0;length<=0;position<=0;seq<=0;crc<=16'hffff;
            version<=0;kind<=0;low_crc<=0;payload<=0;age<=0;
            p_o<=4;i_o<=1;d_o<=0;sequence_o<=0;status_o<=0;changed_o<=0;
        end else begin
            changed_o<=0;
            if(error_i)begin state<=DROP;age<=0;end
            else if(valid_i)begin
                age<=0;
                case(state)
                IDLE:if(byte_i==8'haa)state<=HEAD;
                HEAD:if(byte_i==8'h55)begin state<=BODY;index<=0;crc<=16'hffff;payload<=0;end else if(byte_i!=8'haa)state<=DROP;
                BODY:begin
                    crc<=crc_next(crc,byte_i);
                    case(index)
                    0:version<=byte_i;1:kind<=byte_i;2:seq[7:0]<=byte_i;3:seq[15:8]<=byte_i;
                    4:length[7:0]<=byte_i;
                    5:begin length[15:8]<=byte_i;position<=0;state<=({byte_i,length[7:0]}>80)?DROP:({byte_i,length[7:0]}==0)?CRC_LO:PAYLOAD;end
                    endcase
                    if(index!=5)index<=index+1'b1;
                end
                PAYLOAD:begin
                    crc<=crc_next(crc,byte_i);if(position<6)payload[position*8+:8]<=byte_i;
                    if(position+1>=length)state<=CRC_LO;else position<=position+1'b1;
                end
                CRC_LO:begin low_crc<=byte_i;state<=CRC_HI;end
                CRC_HI:begin
                    if({byte_i,low_crc}==crc && version==3 && kind==8'h27 && length==6)begin
                        sequence_o<=seq;
                        if(payload[15:0]>32 || payload[31:16]>8 || payload[47:32]>32)status_o<=3;
                        else if(!stopped_i)status_o<=2;
                        else begin p_o<=payload[5:0];i_o<=payload[21:16];d_o<=payload[37:32];status_o<=1;changed_o<=1;end
                    end
                    state<=IDLE;
                end
                default:state<=DROP;
                endcase
            end else if(state!=IDLE)begin
                if(age>=BYTE_TIMEOUT_CYCLES-1)begin state<=IDLE;age<=0;end else age<=age+1'b1;
            end
        end
    end
endmodule
