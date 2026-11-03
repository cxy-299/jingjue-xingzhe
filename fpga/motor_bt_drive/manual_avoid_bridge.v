// Single-owner adapter: a held ordinary F can hand a near ray to the SAME
// onboard planner. All detour travel uses fresh, forward-facing ToF probes.
// It never claims rear/side coverage and never drives backwards or blindly strafes.
module manual_avoid_bridge #(
 parameter integer EARLY_STOP_MM=400,QUIET_SAMPLES=25,LEASE_SAMPLES=30,START_TIMEOUT=150,
 parameter integer CONTINUE_ENABLE=0
)(
 input wire clk,rst_n,sample_tick_i,enabled_i,sensors_ok_i,hard_stop_i,motor_fault_i,
 input wire[2:0]manual_command_i,input wire stopped_i,other_active_i,
 input wire tof_sample_i,input wire[15:0]distance_i,
 input wire ascii_valid_i,error_i,input wire[7:0]ascii_i,
 input wire nav_active_i,nav_local_i,input wire[7:0]nav_state_i,input wire[15:0]nav_sequence_i,
 output wire capture_o,output reg request_o=0,output reg[15:0]sequence_o=0,
 output wire lease_pulse_o,output wire cancel_o,
 output reg[7:0]state_o=0,reason_o=0,
 output wire inhibit_o, output reg resume_o=0
);
 localparam IDLE=0,QUIET=1,START=2,RUN=3,DONE=4,STOPPED=5,RESUME=6;
 localparam QW=QUIET_SAMPLES<2?1:$clog2(QUIET_SAMPLES+1);
 localparam LW=LEASE_SAMPLES<2?1:$clog2(LEASE_SAMPLES+1);
 localparam AW=START_TIMEOUT<2?1:$clog2(START_TIMEOUT+1);
 reg[QW-1:0]quiet=0;
 reg[LW-1:0]lease=0;
 reg[AW-1:0]age=0;
 reg resume_forward_seen=0;
 wire held_f=ascii_valid_i && !error_i && ascii_i=="F";
 wire operator_cancel=ascii_valid_i && (ascii_i=="S" || ascii_i=="B" || ascii_i=="L" || ascii_i=="R" || ascii_i=="V" || ascii_i=="a");
 assign capture_o=state_o==QUIET || state_o==START || state_o==RUN || state_o==RESUME;
 // A failed detour must not hand a still-streaming F straight back to manual.
 // Only an explicit S releases this inhibit. Successful detours use RESUME.
 assign inhibit_o=CONTINUE_ENABLE && state_o==STOPPED;
 assign lease_pulse_o=capture_o && held_f;
 assign cancel_o=capture_o && (!enabled_i || !sensors_ok_i || hard_stop_i || motor_fault_i ||
                    other_active_i || error_i || operator_cancel || lease>=LEASE_SAMPLES);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state_o<=IDLE;reason_o<=0;quiet<=0;lease<=0;age<=0;request_o<=0;sequence_o<=0;resume_forward_seen<=0;resume_o<=0;end
  else begin
   request_o<=0;
   resume_o<=0;
   if(sample_tick_i && capture_o)begin
    if(lease<LEASE_SAMPLES)lease<=lease+1'b1;
    if(age<START_TIMEOUT)age<=age+1'b1;
    if(state_o==QUIET)begin
     if(stopped_i)begin
      if(quiet<QUIET_SAMPLES)quiet<=quiet+1'b1;
      if(quiet>=QUIET_SAMPLES-1)begin
       sequence_o<=nav_sequence_i+1'b1;request_o<=1;state_o<=START;age<=0;
      end
     end else quiet<=0;
    end
    if(state_o==RESUME)begin
     if(stopped_i)begin if(quiet<QUIET_SAMPLES)quiet<=quiet+1'b1;end
     else quiet<=0;
    end
   end
   if(held_f)lease<=0;
   if(state_o==IDLE && enabled_i && manual_command_i==1 && !operator_cancel && !error_i && !nav_active_i && !other_active_i &&
      sensors_ok_i && !hard_stop_i && !motor_fault_i && tof_sample_i && distance_i<=EARLY_STOP_MM)begin
    state_o<=QUIET;reason_o<=0;quiet<=0;lease<=0;age<=0;
   end
   if(state_o==START && nav_active_i && nav_local_i)begin state_o<=RUN;age<=0;end
   if(state_o==START && age>=START_TIMEOUT)begin state_o<=STOPPED;reason_o<=6;end
   if(state_o==RUN && !nav_active_i)begin
    state_o<=nav_state_i==11 ? (CONTINUE_ENABLE ? RESUME:DONE):STOPPED;
    reason_o<=nav_state_i==11 ? 0:7;
    quiet<=0;age<=0;resume_forward_seen<=0;
   end
   // Restore straight travel only after the planner restored its initial yaw,
   // another F arrived, all wheels settled, and a NEW front range was sampled.
   // A local waypoint is an internal planning horizon, not a journey endpoint.
   if(state_o==RESUME)begin
    if(held_f)resume_forward_seen<=1;
    if(age>=START_TIMEOUT)begin state_o<=STOPPED;reason_o<=6;end
    else if(resume_forward_seen && stopped_i && quiet>=QUIET_SAMPLES && tof_sample_i)begin
     state_o<=distance_i>EARLY_STOP_MM ? IDLE:QUIET;
     resume_o<=distance_i>EARLY_STOP_MM;
     quiet<=0;age<=0;
    end
   end
   // Last assignment wins: a request must NEVER survive S in the same cycle.
   if(cancel_o)begin
    request_o<=0;resume_o<=0;state_o<=STOPPED;
    reason_o<=error_i?5:!sensors_ok_i?3:hard_stop_i?4:motor_fault_i?8:lease>=LEASE_SAMPLES?1:2;
   end
   if(ascii_valid_i && ascii_i=="S" && !capture_o)begin state_o<=IDLE;reason_o<=0;end
  end
 end
endmodule
