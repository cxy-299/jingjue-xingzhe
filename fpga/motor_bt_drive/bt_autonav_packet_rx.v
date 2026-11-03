// v3/type26, payload <HBBBBHhBB>: map, startXY, goalXY, counts/cell,
// ToF face setback mm, flags(bit0 geometry confirmed, bit1 yaw inverted), speed.
// Shared parser quarantines binary bytes from legacy ASCII controls upstream.
module bt_autonav_packet_rx #(parameter BYTE_TIMEOUT_CYCLES=1_000_000,
    parameter [15:0] MAP_ID=16'h2612)(
    input wire clk,rst_n,valid_i,error_i,input wire [7:0] byte_i,
    output reg request_o=0,output reg [15:0] sequence_o=0,
    output reg [7:0] sx_o=0,sy_o=0,gx_o=0,gy_o=0,
    output reg [15:0] counts_o=0,
    output reg signed [15:0] setback_o=0,
    output reg [7:0] flags_o=0,speed_o=0
);
    reg [2:0] state=0,index=0;
    reg [15:0] len=0,pos=0,seq=0,crc=16'hffff;
    reg [7:0] ver=0,kind=0,lo=0;
    reg [95:0] data=0;reg [31:0] age=0;
    function [15:0] crc_next(input [15:0] c,input [7:0] b);
        integer k;reg [15:0] v;
        begin v=c^{b,8'h00};for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc_next=v;end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=0;index<=0;len<=0;pos<=0;seq<=0;crc<=16'hffff;
            ver<=0;kind<=0;lo<=0;data<=0;age<=0;request_o<=0;sequence_o<=0;
            sx_o<=0;sy_o<=0;gx_o<=0;gy_o<=0;counts_o<=0;setback_o<=0;flags_o<=0;speed_o<=0;
        end else begin
            request_o<=0;
            if(error_i)begin state<=0;age<=0;end
            else if(valid_i)begin
                age<=0;
                case(state)
                    0:if(byte_i==8'haa)state<=1;
                    1:if(byte_i==8'h55)begin state<=2;index<=0;crc<=16'hffff;data<=0;end
                      else if(byte_i!=8'haa)state<=6;
                    2:begin
                        crc<=crc_next(crc,byte_i);
                        case(index)
                            0:ver<=byte_i;1:kind<=byte_i;2:seq[7:0]<=byte_i;3:seq[15:8]<=byte_i;
                            4:len[7:0]<=byte_i;
                            5:begin len[15:8]<=byte_i;pos<=0;
                                state<=({byte_i,len[7:0]}>80)?6:({byte_i,len[7:0]}==0)?4:3;end
                        endcase
                        if(index!=5)index<=index+1'b1;
                    end
                    3:begin
                        crc<=crc_next(crc,byte_i);
                        if(pos<12)data[pos*8+:8]<=byte_i;
                        if(pos+1>=len)state<=4;else pos<=pos+1'b1;
                    end
                    4:begin lo<=byte_i;state<=5;end
                    5:begin
                        if({byte_i,lo}==crc && ver==3 && kind==8'h26 && len==12 && data[15:0]==MAP_ID)begin
                            request_o<=1;sequence_o<=seq;
                            sx_o<=data[23:16];sy_o<=data[31:24];gx_o<=data[39:32];gy_o<=data[47:40];
                            counts_o<=data[63:48];setback_o<=data[79:64];
                            flags_o<=data[87:80];speed_o<=data[95:88];
                        end
                        state<=0;
                    end
                    default:begin end
                endcase
            end else if(state!=0)begin
                if(age>=BYTE_TIMEOUT_CYCLES-1)begin state<=0;age<=0;end else age<=age+1'b1;
            end
        end
    end
endmodule
