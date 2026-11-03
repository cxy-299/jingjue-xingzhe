`timescale 1ns/1ps
// 固定地图回归：最短路、逐路点前进、阻挡目标、起点目标、越界目标。
module tb_fixed_grid_bfs;
    reg clk=0, rst_n=0, goal_valid=0, advance=0;
    reg [7:0] goal_x=0, goal_y=0;
    wire busy, ready, no_path, waypoint_valid;
    wire [7:0] wx, wy;
    wire [8:0] steps;
    wire [7:0] accepted_x, accepted_y;
    integer timeout, walked, last_x, last_y, map_index;
    reg map_mem_ref [0:399];

    always #5 clk=~clk;
    fixed_grid_bfs dut (
        .clk(clk), .rst_n(rst_n), .goal_valid_i(goal_valid),
        .goal_x_i(goal_x), .goal_y_i(goal_y), .advance_i(advance),
        .busy_o(busy), .route_ready_o(ready), .no_path_o(no_path),
        .waypoint_valid_o(waypoint_valid), .waypoint_x_o(wx), .waypoint_y_o(wy),
        .path_steps_o(steps), .accepted_goal_x_o(accepted_x), .accepted_goal_y_o(accepted_y)
    );

    task send_goal(input [7:0] x, input [7:0] y);
        begin
            @(negedge clk); goal_x=x; goal_y=y; goal_valid=1;
            @(negedge clk); goal_valid=0;
        end
    endtask
    task wait_result;
        begin
            timeout=0;
            while (!ready && !no_path && timeout<10000) begin
                @(negedge clk); timeout=timeout+1;
            end
            if(timeout>=10000) $fatal(1,"规划超时");
        end
    endtask

    initial begin
        // 原始地图逐格比对编译进 RTL 的常量，防止修改地图后忘记重新生成常量。
        $readmemb("nav_map_20x20.mem", map_mem_ref);
        for (map_index=0; map_index<400; map_index=map_index+1)
            if (dut.MAP_BITS[map_index] !== map_mem_ref[map_index])
                $fatal(1,"地图常量与 .mem 不一致，地址=%0d",map_index);
        repeat(4) @(negedge clk); rst_n=1;
        send_goal(2,17);
        wait_result();
        if(!ready || no_path || steps!==9'd34 || accepted_x!=2 || accepted_y!=17)
            $fatal(1,"示例终点路径错误 ready=%b no_path=%b steps=%0d",ready,no_path,steps);

        walked=0; last_x=18; last_y=1;
        while(waypoint_valid) begin
            if(wx>=20 || wy>=20 || map_mem_ref[wy*20+wx] !== 1'b0)
                $fatal(1,"路点落入障碍/边界 (%0d,%0d)",wx,wy);
            if(((wx>last_x?wx-last_x:last_x-wx)+(wy>last_y?wy-last_y:last_y-wy)) != 1)
                $fatal(1,"路点不相邻 (%0d,%0d)->(%0d,%0d)",last_x,last_y,wx,wy);
            last_x=wx; last_y=wy; walked=walked+1;
            @(negedge clk); advance=1;
            @(negedge clk); advance=0;
        end
        if(walked!=34 || last_x!=2 || last_y!=17)
            $fatal(1,"路点遍历错误 walked=%0d endpoint=(%0d,%0d)",walked,last_x,last_y);

        // 三个其他方位的终点用于防止规划器只适配示例路线。
        send_goal(17,18); wait_result();
        if(!ready || no_path || steps!=18) $fatal(1,"上方终点步数错误");
        send_goal(1,1); wait_result();
        if(!ready || no_path || steps!=17) $fatal(1,"左下终点步数错误");
        send_goal(18,18); wait_result();
        if(!ready || no_path || steps!=17) $fatal(1,"右上终点步数错误");

        send_goal(11,4); // 落在实体障碍 A 内
        wait_result();
        if(!no_path || ready || waypoint_valid) $fatal(1,"障碍内目标应不可达");

        send_goal(18,1);
        wait_result();
        if(!ready || steps!=0 || waypoint_valid) $fatal(1,"起点即终点应为零步");

        send_goal(20,1);
        wait_result();
        if(!no_path || ready) $fatal(1,"越界终点应被拒绝");

        $display("PASS tb_fixed_grid_bfs: 34-step route, 3 other goals, safe waypoints, blocked/start/out-of-range goals");
        $finish;
    end
endmodule
