// OV5640 1280x720 DVP -> 320x180 RGB333 double BSRAM buffer -> 720p HDMI.
// 9-bit native BSRAM mode fits both frames; RGB565 inference rounded to 128
// blocks and exceeded this part's 118-block limit. Preview is 512 colours.
// Camera and control clocks are independent. No legacy encrypted DDR/FIFO IP.
// Two-bank toggle handshake: publish a complete frame, swap only in display
// blanking, acknowledge, then reuse the OLD display bank on a new camera frame.
module sin12_camera_hdmi(
 input wire clk50M,reset_n,camera_vsync,camera_href,camera_pclk,
 input wire [7:0]camera_data,
 output wire camera_sclk,camera_xclk,camera_rst_n,camera_pwdn,
 inout wire camera_sdat,
 output wire tmds_clk_p,tmds_clk_n,
 output wire[2:0]tmds_data_p,tmds_data_n,
 output wire init_done_o,frame_valid_o
);
 wire serial_clk,source_serial_clk,pixel_clk,xclk,unused_clk,locked;
 wire serializer_reset,clock_ready;
 camera_pll u_pll(.clkin(clk50M),.clkout0(source_serial_clk),.clkout1(xclk),
  .clkout2(unused_clk),.lock(locked),.mdclk(clk50M),.reset(~reset_n));
 sin12_video_startup u_startup(.sys_clk(clk50M),.source_serial_clk(source_serial_clk),
  .reset_n(reset_n),.pll_locked(locked),.serial_clk(serial_clk),
  .serializer_reset(serializer_reset),.ready(clock_ready));
 CLKDIV u_pixel_div(.RESETN(~serializer_reset),.HCLKIN(serial_clk),.CLKOUT(pixel_clk),.CALIB(1'b1));
 defparam u_pixel_div.DIV_MODE="5";
 assign camera_xclk=xclk;
 wire video_reset_n=~serializer_reset;
 // Pixel logic has its own reset domain: async assertion, two pixel clocks
 // to release. Keep IOLOGIC reset on the proven gated-clock startup path.
 (* syn_preserve=1, syn_keep=1 *) reg pixel_release_meta=0;
 (* syn_preserve=1, syn_keep=1 *) reg pixel_release_sync=0;
 always @(posedge pixel_clk or negedge video_reset_n)begin
  if(!video_reset_n)begin pixel_release_meta<=0;pixel_release_sync<=0;end
  else begin pixel_release_meta<=1;pixel_release_sync<=pixel_release_meta;end
 end
 wire pixel_reset_n=pixel_release_sync;
 camera_init #(.SYS_CLOCK(50_000_000),.SCL_CLOCK(400_000),.CAMERA_TYPE("ov5640"),
  .IMAGE_TYPE(0),.IMAGE_WIDTH(1280),.IMAGE_HEIGHT(720),.IMAGE_FLIP_EN(0),.IMAGE_MIRROR_EN(0)) u_init(
  .Clk(clk50M),.Rst_n(video_reset_n),.Init_Done(init_done_o),
  .camera_rst_n(camera_rst_n),.camera_pwdn(camera_pwdn),
  .i2c_sclk(camera_sclk),.i2c_sdat(camera_sdat));

 localparam integer FRAME_WORDS=320*180;
 (* syn_ramstyle="block_ram" *) reg[8:0] memory[0:FRAME_WORDS*2-1];
 reg request_toggle=0,published_bank=0;
 reg ack_toggle=0,ack_meta=0,ack_sync=0;
 reg init_meta=0,init_sync=0;
 reg vs_previous=0,href_previous=0,phase=0,capturing=0,write_bank=0;
 reg[7:0] high_byte=0;
 reg[10:0] source_x=0,source_y=0;
 reg[16:0] written=0;
 wire pending=request_toggle!=ack_sync;
 // Sequential pointer avoids a row multiply plus two wide additions on the
 // PCLK-to-BSRAM address path. It advances only for a selected complete pixel.
 reg[16:0] write_address=0;
 always @(posedge camera_pclk or negedge video_reset_n) begin
  if(!video_reset_n)begin
   ack_meta<=0;ack_sync<=0;init_meta<=0;init_sync<=0;request_toggle<=0;published_bank<=0;
   vs_previous<=0;href_previous<=0;phase<=0;capturing<=0;write_bank<=0;
   high_byte<=0;source_x<=0;source_y<=0;written<=0;write_address<=0;
  end else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;init_meta<=init_done_o;init_sync<=init_meta;
   vs_previous<=camera_vsync;href_previous<=camera_href;
   if(camera_vsync)begin
    source_x<=0;source_y<=0;phase<=0;capturing<=0;
    if(!vs_previous && capturing && written==FRAME_WORDS && !pending)begin
     published_bank<=write_bank;request_toggle<=~request_toggle;
    end
   end else if(vs_previous)begin
    capturing<=init_sync && !pending;written<=0;source_x<=0;source_y<=0;phase<=0;
    write_address<=write_bank?17'd57600:17'd0;
   end else if(camera_href)begin
    phase<=~phase;
    if(!phase)high_byte<=camera_data;
    else begin
     if(capturing && source_x<1280 && source_y<720 && source_x[1:0]==0 && source_y[1:0]==0)begin
      written<=written+1'b1;write_address<=write_address+1'b1;
     end
     source_x<=source_x+1'b1;
    end
   end else begin
    phase<=0;source_x<=0;
    if(href_previous)source_y<=source_y+1'b1;
   end
   // After display acknowledges, producer switches to the other bank. It only
   // captures on the NEXT VSYNC boundary, never a partial in-flight frame.
   if(!pending && !capturing)write_bank<=~published_bank;
  end
 end
 // RAM writes intentionally have no asynchronous reset (BSRAM inference).
 always @(posedge camera_pclk)begin
  if(video_reset_n && capturing && !camera_vsync && camera_href && phase &&
     source_x<1280 && source_y<720 && source_x[1:0]==0 && source_y[1:0]==0)
   memory[write_address]<={high_byte[7:5],high_byte[2:0],camera_data[4:2]};
 end

 reg[10:0] h=0;reg[9:0] v=0;
 reg req_meta=0,req_sync=0,bank_meta=0,bank_sync=0,front_bank=1,have_frame=0;
 wire de=h<1280 && v<720;
 wire hs=h>=1390 && h<1430;
 wire vs=v>=725 && v<730;
 always @(posedge pixel_clk or negedge pixel_reset_n)begin
  if(!pixel_reset_n)begin
   h<=0;v<=0;req_meta<=0;req_sync<=0;bank_meta<=0;bank_sync<=0;
   front_bank<=1;have_frame<=0;ack_toggle<=0;
  end else begin
   if(h==1649)begin h<=0;if(v==749)v<=0;else v<=v+1'b1;end else h<=h+1'b1;
   req_meta<=request_toggle;req_sync<=req_meta;bank_meta<=published_bank;bank_sync<=bank_meta;
   if(h==0 && v==720 && req_sync!=ack_toggle)begin
    front_bank<=bank_sync;have_frame<=1;ack_toggle<=req_sync;
   end
  end
 end
 assign frame_valid_o=have_frame;
 reg[16:0] read_address=0;reg[8:0] pixel=0;
 reg[1:0] de_pipe=0,hs_pipe=0,vs_pipe=0;
 always @(posedge pixel_clk)begin
  read_address<=de ? ((front_bank?17'd57600:17'd0)+(v[9:2]*17'd320)+h[10:2]):17'd0;
  pixel<=memory[read_address];
  de_pipe<={de_pipe[0],de && have_frame};hs_pipe<={hs_pipe[0],hs};vs_pipe<={vs_pipe[0],vs};
 end
 dvi_encoder #(.SEPARATE_RESET(1)) u_dvi(.pixelclk(pixel_clk),.pixelclk5x(serial_clk),.rst_n(pixel_reset_n),.serializer_reset_i(serializer_reset),
  .blue_din({pixel[2:0],pixel[2:0],pixel[2:1]}),
  .green_din({pixel[5:3],pixel[5:3],pixel[5:4]}),
  .red_din({pixel[8:6],pixel[8:6],pixel[8:7]}),
  .hsync(hs_pipe[1]),.vsync(vs_pipe[1]),.de(de_pipe[1]),
  .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n));
endmodule
