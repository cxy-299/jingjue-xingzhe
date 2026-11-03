`timescale 1ns/1ps
// Identical testbench is used for RTL and Gowin's mapped converter netlist.
module tb_sin12_r7_target;
`ifdef GOWIN_GATE
    GSR GSR(.GSRI(1'b1));
`endif
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid_i=0,inverted_i=0;
    reg signed [15:0] angle_cdeg_i=0,yaw_i=0;
    wire valid_o;wire signed [15:0] target_o;
    sin12_turn_target_pipeline dut(.*);
    integer expected[0:4];reg [4:0] pending=0;
    integer n,checked=0,ref_angle,ref_yaw,ref_inv,reference_value,seed=14330;
    always @(posedge clk)begin
        if(!rst_n)pending=0;
        else begin
            for(integer j=4;j>0;j=j-1)expected[j]=expected[j-1];
            reference_value=($signed(angle_cdeg_i)*1464)>>>10;
            if(inverted_i)reference_value=-reference_value;
            reference_value=reference_value+$signed(yaw_i);
            if(reference_value>25736)reference_value=reference_value-51472;
            if(reference_value< -25736)reference_value=reference_value+51472;
            expected[0]=reference_value;
            pending={pending[3:0],valid_i};
        end
        #1;
        if(valid_o!==pending[4])$fatal(1,"valid latency mismatch");
        if(valid_o)begin
            if($signed(target_o)!==expected[4])$fatal(1,"target got %d expected %d",$signed(target_o),expected[4]);
            checked=checked+1;
        end
    end
    task drive(input integer a,y,inv,v);
        @(negedge clk);angle_cdeg_i=a;yaw_i=y;inverted_i=inv;valid_i=v;
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        // Actual hardware failures, both directions/inverted mount, wrap endpoints.
        drive(9000,3984,0,1);drive(-9000,3984,0,1);
        drive(9000,21140,0,1);drive(9000,21140,1,1);
        for(integer yaw=-25736;yaw<=25736;yaw=yaw+6434)
            for(integer a=-18000;a<=18000;a=a+500)begin
                drive(a,yaw,0,1);drive(a,yaw,1,1);
            end
        for(n=0;n<1000;n=n+1)begin
            ref_angle=($unsigned($random(seed))%36001)-18000;
            ref_yaw=($unsigned($random(seed))%51473)-25736;
            drive(ref_angle,ref_yaw,n%2,n%7!=0);
        end
        // Asynchronous abort must flush every pending transaction.
        @(negedge clk);rst_n=0;valid_i=0;
        repeat(3)@(negedge clk);rst_n=1;
        repeat(8)@(negedge clk);
        drive(-9000,-25500,1,1);drive(0,0,0,0);
        repeat(8)@(negedge clk);
        if(checked<2000)$fatal(1,"insufficient coverage %d",checked);
        $display("R7_SIGNED_TARGET_PIPELINE_PASS vectors=%0d",checked);$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
