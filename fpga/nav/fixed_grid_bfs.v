`timescale 1ns/1ps
// 20×20 固定地图四邻域 BFS：输入终点格，FPGA 内部计算下一路点。
// 地图由 nav-map-2m.json 生成到 .mem，并随位流初始化；这里不直接驱动电机。
// 地址 row*20+col，row=0 是地图最下方；起点固定在 (18,1)。
module fixed_grid_bfs #(
    parameter MAP_FILE = "nav_map_20x20.mem"
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       goal_valid_i,
    input  wire [7:0] goal_x_i,
    input  wire [7:0] goal_y_i,
    input  wire       advance_i,
    output reg        busy_o,
    output reg        route_ready_o,
    output reg        no_path_o,
    output reg        waypoint_valid_o,
    output wire [7:0] waypoint_x_o,
    output wire [7:0] waypoint_y_o,
    output reg  [8:0] path_steps_o,
    output reg  [7:0] accepted_goal_x_o,
    output reg  [7:0] accepted_goal_y_o
);
    localparam [8:0] START_IDX = 9'd38; // 1*20+18
    localparam [3:0] S_IDLE=0, S_POP=1, S_PREP=2, S_MAP_WAIT=3,
                     S_CHECK=4, S_TRACE=5, S_READY=6, S_FAIL=7, S_ENQUEUE=8,
                     S_GOAL_WAIT=9, S_GOAL_CHECK=10;

    // 占据图按地址 0..399 从低位到高位排列；1 是障碍，0 是可通行。
    // 该常量由 nav_map_20x20.mem 转换，仿真会逐格核对两者，避免地图漂移。
    // 显式常量不依赖综合器对 $readmem* 初始化文件路径/位宽的处理。
    localparam [399:0] MAP_BITS = 400'h
        FFFFF80011800398607D8F07D9F8399F8118F0C1861E1803F1803F1819E183CC187E0187E0187E0183C018180180001FFFFF;
    reg [8:0] map_addr;
    reg map_blocked;
    always @(posedge clk) map_blocked <= MAP_BITS[map_addr];

    reg [3:0] state;
    reg [399:0] visited;
    reg [8:0] queue_mem [0:399];
    reg [8:0] parent_mem [0:399];
    reg [8:0] path_mem [0:399]; // 反序存放：path[0] 是终点
    reg [8:0] head, tail, current, goal_idx, trace_node, trace_count, waypoint_cursor;
    reg [2:0] neighbor_dir;
    reg enqueue_neighbor;

    wire [8:0] requested_idx = goal_y_i * 9'd20 + goal_x_i;
    wire [4:0] current_x = current % 9'd20;
    wire [4:0] current_y = current / 9'd20;
    reg neighbor_exists;
    reg [8:0] neighbor_idx;
    wire [8:0] waypoint_idx = path_mem[waypoint_cursor];
    assign waypoint_x_o = waypoint_valid_o ? waypoint_idx % 9'd20 : 8'd0;
    assign waypoint_y_o = waypoint_valid_o ? waypoint_idx / 9'd20 : 8'd0;

    always @* begin
        neighbor_exists = 1'b0;
        neighbor_idx = 9'd0;
        case (neighbor_dir)
            3'd0: if (current_x < 19) begin neighbor_exists=1'b1; neighbor_idx=current+9'd1; end
            3'd1: if (current_x > 0)  begin neighbor_exists=1'b1; neighbor_idx=current-9'd1; end
            3'd2: if (current_y < 19) begin neighbor_exists=1'b1; neighbor_idx=current+9'd20; end
            3'd3: if (current_y > 0)  begin neighbor_exists=1'b1; neighbor_idx=current-9'd20; end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy_o <= 1'b0;
            route_ready_o <= 1'b0;
            no_path_o <= 1'b0;
            waypoint_valid_o <= 1'b0;
            path_steps_o <= 9'd0;
            accepted_goal_x_o <= 8'd0;
            accepted_goal_y_o <= 8'd0;
            visited <= 400'd0;
            head <= 9'd0; tail <= 9'd0; current <= 9'd0; goal_idx <= 9'd0;
            trace_node <= 9'd0; trace_count <= 9'd0; waypoint_cursor <= 9'd0;
            neighbor_dir <= 3'd0; map_addr <= 9'd0;
            enqueue_neighbor <= 1'b0;
        end else if (goal_valid_i) begin
            // 新目标打断旧搜索/旧路径；越界目标被拒绝，不能误触发旧路线。
            route_ready_o <= 1'b0;
            no_path_o <= 1'b0;
            waypoint_valid_o <= 1'b0;
            path_steps_o <= 9'd0;
            accepted_goal_x_o <= goal_x_i;
            accepted_goal_y_o <= goal_y_i;
            visited <= 400'd0;
            head <= 9'd0;
            tail <= 9'd1;
            queue_mem[0] <= START_IDX;
            visited[START_IDX] <= 1'b1;
            goal_idx <= requested_idx;
            if (goal_x_i >= 20 || goal_y_i >= 20) begin
                busy_o <= 1'b0;
                no_path_o <= 1'b1;
                state <= S_FAIL;
            end else if (requested_idx == START_IDX) begin
                busy_o <= 1'b0;
                route_ready_o <= 1'b1;
                path_mem[0] <= START_IDX;
                state <= S_READY;
            end else begin
                busy_o <= 1'b1;
                // 先检查终点占据位：障碍目标无需遍历整幅地图才判断不可达。
                map_addr <= requested_idx;
                state <= S_GOAL_WAIT;
            end
        end else begin
            case (state)
                S_GOAL_WAIT: state <= S_GOAL_CHECK;
                S_GOAL_CHECK: begin
                    if (map_blocked) begin
                        busy_o <= 1'b0;
                        no_path_o <= 1'b1;
                        state <= S_FAIL;
                    end else state <= S_POP;
                end
                S_POP: begin
                    if (head == tail) begin
                        busy_o <= 1'b0;
                        no_path_o <= 1'b1;
                        state <= S_FAIL;
                    end else begin
                        current <= queue_mem[head];
                        head <= head + 1'b1;
                        neighbor_dir <= 3'd0;
                        state <= S_PREP;
                    end
                end
                S_PREP: begin
                    if (neighbor_dir == 3'd4) state <= S_POP;
                    else if (!neighbor_exists) neighbor_dir <= neighbor_dir + 1'b1;
                    else begin
                        map_addr <= neighbor_idx;
                        state <= S_MAP_WAIT;
                    end
                end
                // 同步 ROM 在此拍取得 map_addr 对应的障碍位。
                S_MAP_WAIT: state <= S_CHECK;
                S_CHECK: begin
                    // 先锁存地图和 visited 判定，下一拍再写队列/父节点，
                    // 避免读取结果直接穿过大范围写使能译码器。
                    enqueue_neighbor <= !map_blocked && !visited[map_addr];
                    state <= S_ENQUEUE;
                end
                S_ENQUEUE: begin
                    if (enqueue_neighbor) begin
                        visited[map_addr] <= 1'b1;
                        parent_mem[map_addr] <= current;
                        queue_mem[tail] <= map_addr;
                        tail <= tail + 1'b1;
                        if (map_addr == goal_idx) begin
                            trace_node <= goal_idx;
                            trace_count <= 9'd0;
                            state <= S_TRACE;
                        end else begin
                            neighbor_dir <= neighbor_dir + 1'b1;
                            state <= S_PREP;
                        end
                    end else begin
                        neighbor_dir <= neighbor_dir + 1'b1;
                        state <= S_PREP;
                    end
                end
                S_TRACE: begin
                    path_mem[trace_count] <= trace_node;
                    if (trace_node == START_IDX) begin
                        path_steps_o <= trace_count;
                        route_ready_o <= 1'b1;
                        busy_o <= 1'b0;
                        if (trace_count != 0) begin
                            waypoint_cursor <= trace_count - 1'b1;
                            waypoint_valid_o <= 1'b1;
                        end
                        state <= S_READY;
                    end else begin
                        trace_node <= parent_mem[trace_node];
                        trace_count <= trace_count + 1'b1;
                    end
                end
                S_READY: if (advance_i && waypoint_valid_o) begin
                    // 外部定位控制器确认抵达当前路点后，才提供下一格。
                    if (waypoint_cursor == 0) waypoint_valid_o <= 1'b0;
                    else waypoint_cursor <= waypoint_cursor - 1'b1;
                end
                default: begin end
            endcase
        end
    end
endmodule
