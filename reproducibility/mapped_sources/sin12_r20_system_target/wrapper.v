module sin12_turn_target_pipeline(
input clk,rst_n,valid_i,input signed[15:0]angle_cdeg_i,yaw_i,input inverted_i,
output valid_o,output signed[15:0]target_o);
wire inverted;
DFFCE shared_inverted(.Q(inverted),.D(inverted_i),.CLK(clk),.CLEAR(!rst_n),.CE(valid_i));
defparam shared_inverted.INIT=1'b0;
system_mapped_target actual(.clk_50m_i_d(clk),.n177_5(!rst_n),.n1712_2(valid_i),
.inverted(inverted),.\g_heading.requested_angle (angle_cdeg_i),.turn_yaw(yaw_i),
.converted_valid(valid_o),.wrapped_target(target_o));
endmodule
