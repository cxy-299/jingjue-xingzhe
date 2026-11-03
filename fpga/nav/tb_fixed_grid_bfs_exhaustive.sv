`timescale 1ns/1ps
// 独立 Python BFS 生成全 400 个终点的期望步数；逐路点检查安全与邻接关系。
module tb_fixed_grid_bfs_exhaustive;
    reg clk=0, rst_n=0, valid=0, advance=0;
    reg [7:0] gx=0, gy=0;
    wire busy, ready, failed, wp_valid;
    wire [7:0] wx, wy, accepted_x, accepted_y;
    wire [8:0] steps;
    reg map_ref [0:399];
    reg [8:0] expected [0:399];
    integer goal, cycles, walked, lx, ly, rejected, reached, max_cycles;
    always #5 clk=~clk;
    fixed_grid_bfs dut(.clk(clk),.rst_n(rst_n),.goal_valid_i(valid),
        .goal_x_i(gx),.goal_y_i(gy),.advance_i(advance),.busy_o(busy),
        .route_ready_o(ready),.no_path_o(failed),.waypoint_valid_o(wp_valid),
        .waypoint_x_o(wx),.waypoint_y_o(wy),.path_steps_o(steps),
        .accepted_goal_x_o(accepted_x),.accepted_goal_y_o(accepted_y));
    task request_goal(input [7:0] x,input [7:0] y);
        begin
            @(negedge clk); gx=x; gy=y; valid=1;
            @(negedge clk); valid=0;
        end
    endtask
    task wait_result;
        begin
            cycles=0;
            while(!ready && !failed && cycles<10000) begin
                @(negedge clk); cycles=cycles+1;
            end
            if(cycles>=10000) $fatal(1,"FAIL 全图规划超时 (%0d,%0d)",gx,gy);
        end
    endtask
    initial begin
        $readmemb("nav_map_20x20.mem",map_ref);
        $readmemh("bfs_expected_steps.mem",expected);
        repeat(4) @(negedge clk); rst_n=1;
        reached=0; rejected=0; max_cycles=0;
        for(goal=0;goal<400;goal=goal+1) begin
            request_goal(goal%20,goal/20); wait_result();
            if(cycles>max_cycles) max_cycles=cycles;
            if(accepted_x!=gx || accepted_y!=gy) $fatal(1,"FAIL 终点记录不一致");
            if(expected[goal]===9'h1ff) begin
                rejected=rejected+1;
                if(!failed || ready || wp_valid) $fatal(1,"FAIL 不可达格被接受 %0d",goal);
                if(map_ref[goal] && cycles>3) $fatal(1,"FAIL 障碍目标未提前拒绝");
            end else begin
                reached=reached+1;
                if(!ready || failed || steps!==expected[goal])
                    $fatal(1,"FAIL 步数 %0d 实际=%0d 期望=%0d",goal,steps,expected[goal]);
                walked=0; lx=18; ly=1;
                while(wp_valid) begin
                    if(wx>=20 || wy>=20 || map_ref[wy*20+wx]!==0)
                        $fatal(1,"FAIL 路点不安全");
                    if((wx>lx?wx-lx:lx-wx)+(wy>ly?wy-ly:ly-wy)!=1)
                        $fatal(1,"FAIL 路点不相邻");
                    lx=wx; ly=wy; walked=walked+1;
                    @(negedge clk); advance=1;
                    @(negedge clk); advance=0;
                end
                if(walked!=expected[goal] || lx!=gx || ly!=gy) $fatal(1,"FAIL 路点终止错误");
            end
        end
        // 搜索进行中换目标、以及回溯期间换目标，旧路径不得被误发布。
        request_goal(2,17); repeat(10) @(negedge clk);
        request_goal(3,12); wait_result();
        if(!ready || steps!=26 || accepted_x!=3 || accepted_y!=12) $fatal(1,"FAIL 搜索抢占");
        request_goal(2,17);
        cycles=0;
        while(dut.state!=5 && cycles<10000) begin @(negedge clk); cycles=cycles+1; end
        if(cycles>=10000) $fatal(1,"FAIL 未进入回溯状态");
        request_goal(11,4); wait_result();
        if(!failed || ready || wp_valid) $fatal(1,"FAIL 回溯抢占");
        $display("PASS tb_fixed_grid_bfs_exhaustive: 400 goals, %0d reachable, %0d rejected, all waypoints, preemption, max_result_cycles=%0d",reached,rejected,max_cycles);
        $finish;
    end
endmodule
