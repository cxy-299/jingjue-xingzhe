// R5 explicit stopped-only control. No command here ever starts a motor.
// S then 250ms of stopped encoder samples is required before U or A.
module motor_recovery_guard #(parameter integer QUIET_SAMPLES=25)(
 input wire clk,rst_n,sample_tick_i,stopped_i,sensors_clear_i,
 input wire ascii_valid_i,error_i,input wire[7:0]ascii_i,
 input wire signed[15:0]speed0_i,speed1_i,speed2_i,speed3_i,
 input wire[3:0]blocked_i,severe_i,
 output reg clear_block_o=0,avoid_enabled_o=0,
 output reg[1:0]recovery_result_o=0,
 output reg[7:0]ack_sequence_o=0
);
 localparam integer WIDTH=QUIET_SAMPLES<2?1:$clog2(QUIET_SAMPLES+1);
 reg[WIDTH-1:0]quiet=0;reg stop_seen=0;reg[3:0]previous_blocked=0;
 wire still=speed0_i>=-1 && speed0_i<=1 && speed1_i>=-1 && speed1_i<=1 &&
            speed2_i>=-1 && speed2_i<=1 && speed3_i>=-1 && speed3_i<=1;
 wire qualified=stop_seen && stopped_i && still && quiet>=QUIET_SAMPLES && sensors_clear_i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin quiet<=0;stop_seen<=0;previous_blocked<=0;clear_block_o<=0;avoid_enabled_o<=0;recovery_result_o<=0;ack_sequence_o<=0;end
  else begin
   clear_block_o<=0;
   previous_blocked<=blocked_i;
   if((blocked_i!=0 && previous_blocked==0) || error_i)stop_seen<=0;
   // S survives the real deceleration/pipeline delay. A fresh motion intent
   // invalidates it; motion itself only resets the stable-stop timer.
   if(!stopped_i || !still)quiet<=0;
   else if(sample_tick_i && quiet<QUIET_SAMPLES)quiet<=quiet+1'b1;
   if(ascii_valid_i && !error_i)case(ascii_i)
    "S":begin stop_seen<=1;quiet<=0;end
    "F","B","L","R","G","N","M","V":stop_seen<=0;
    "U":begin
     ack_sequence_o<=ack_sequence_o+1'b1;
     if(qualified && blocked_i!=0 && severe_i==0)begin clear_block_o<=1;recovery_result_o<=1;end
     else recovery_result_o<=2;
    end
    "A":begin
     ack_sequence_o<=ack_sequence_o+1'b1;
     if(qualified && blocked_i==0 && severe_i==0)begin avoid_enabled_o<=1;recovery_result_o<=1;end
     else recovery_result_o<=2;
    end
    "a":begin ack_sequence_o<=ack_sequence_o+1'b1;avoid_enabled_o<=0;recovery_result_o<=1;end
    default:;
   endcase
  end
 end
endmodule
