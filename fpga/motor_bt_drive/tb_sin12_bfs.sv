`timescale 1ns/1ps
module tb_sin12_bfs;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,request=0;reg [2047:0] cases[0:47],v=0;
    wire busy,ready,nopath;wire [8:0] nxt,len;
    integer i,cycles;
    grid_bfs_dynamic dut(.clk(clk),.rst_n(rst),.request_i(request),.cancel_i(1'b0),
        .occupied_i(v[399:0]),.denied_edges_i(v[1999:400]),.start_i(v[2008:2000]),.goal_i(v[2017:2009]),
        .busy_o(busy),.ready_o(ready),.no_path_o(nopath),.next_o(nxt),.length_o(len));
    initial begin
        $readmemh("sin12_planner_vectors.mem",cases);
        repeat(4)@(negedge clk);rst=1;
        for(i=0;i<48;i++)begin
            @(negedge clk);v=cases[i];request=1;
            @(negedge clk);request=0;cycles=0;
            while(!ready && cycles<5000)begin @(negedge clk);cycles++;end
            if(!ready)$fatal(1,"BFS case %d timeout",i);
            if(v[2026:2018]==511)begin if(!nopath)$fatal(1,"BFS false path case %d",i);end
            else if(nopath || len!=v[2026:2018] || nxt!=v[2035:2027])
                $fatal(1,"BFS oracle mismatch %d: length %d/%d next %d/%d",i,len,v[2026:2018],nxt,v[2035:2027]);
        end
        $display("SIN12_BFS_48_CPU_ORACLE_CASES_PASS");$finish;
    end
endmodule
