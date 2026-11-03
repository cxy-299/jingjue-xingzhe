// Offline byte-parser compatibility only. No UART electrical timing or motor.
module tb_a4_identity_protocol;
reg clk=0,rst_n=0,valid=0;reg[7:0] data=0;
always #10 clk=~clk;
wire req,vision;wire[15:0] reqclass,seenclass;wire[31:0] job,seenjob;
wire present,confirmed;wire[15:0] crcerrors;
bt_mission_packet_rx commands(.clk(clk),.rst_n(rst_n),.byte_i(data),.valid_i(valid),.error_i(1'b0),
 .request_o(req),.class_o(reqclass),.mission_o(job));
vision_packet_parser perceptions(.clk(clk),.rst_n(rst_n),.byte_i(data),.byte_valid_i(valid),
 .vision_valid_o(vision),.class_id_o(seenclass),.mission_id_o(seenjob),
 .target_present_o(present),.target_confirmed_o(confirmed),.crc_error_count_o(crcerrors));
reg[7:0] bytes[0:65535];integer count=0,requests=0,observations=0,k,length;
reg[1023:0] vector_path;integer fd,scan;
always @(posedge clk)begin
 #1;
 if(req)begin
  if(reqclass!==(16'ha400+requests) || job!==(32'h12340000+requests))$fatal(1,"A4 request identity corrupted");
  requests=requests+1;
 end
 if(vision)begin
  if(seenclass!==(16'ha400+observations) || seenjob!==(32'h12340000+observations)
    || !present || !confirmed)$fatal(1,"A4 perception identity corrupted");
  observations=observations+1;
 end
end
initial begin
 if(!$value$plusargs("vectors=%s",vector_path))$fatal(1,"Missing vector file");
 fd=$fopen(vector_path,"r");if(!fd)$fatal(1,"Cannot read vectors");
 while(!$feof(fd))begin scan=$fscanf(fd,"%h",bytes[count]);if(scan==1)count=count+1;end
 $fclose(fd);repeat(4)@(negedge clk);rst_n=1;
 for(k=0;k<count;k=k+1)begin
  @(negedge clk);data=bytes[k];valid=1;@(negedge clk);valid=0;
 end
 repeat(10)@(negedge clk);
 if(requests!=10 || observations!=10 || crcerrors!=1)$fatal(1,"Bad count req=%d obs=%d crc=%d",requests,observations,crcerrors);
 $display("A4_R12_PRODUCTION_BYTE_PARSERS_10_DIGIT_IDS_AND_BAD_CRC_PASS");$finish;
end
initial begin #1000000;$fatal(1,"A4 protocol timeout");end
endmodule

