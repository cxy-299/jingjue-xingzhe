// 20x20 four-neighbour BFS. Occupancy/start/goal are snapshotted per request.
// Returns the FIRST waypoint, reconstructed on the FPGA; no host route input.
module grid_bfs_dynamic #(parameter integer ALLOW_SAFE_START_ESCAPE=0) (
    input wire clk,rst_n,request_i,cancel_i,
    input wire [8:0] start_i,goal_i,
    input wire start_escape_i,
    input wire [399:0] occupied_i,
    input wire [1599:0] denied_edges_i,
    output reg busy_o=0,ready_o=0,no_path_o=0,
    output reg [8:0] next_o=0,
    output reg [8:0] length_o=0
);
    localparam IDLE=0,POP=1,CALC=2,CHECK=3,TRACE=4,DECODE=5,INIT=6,TRACE_CHECK=7;
    reg [2:0] state=0;
    reg [399:0] blocked=0,visited=0;
    reg [8:0] queue_mem[0:399],parent[0:399];
    reg [8:0] head=0,tail=0,cur=0,first=0,dest=0,trace=0,steps=0;
    reg [4:0] x=0,y=0;
    reg [1:0] direction=0;
    reg [8:0] neighbor=0;
    reg neighbor_valid=0,edge_denied=0;
    reg escape_start=0;
    reg [3:0] edge_row=0;
    reg [8:0] parent_read=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;busy_o<=0;ready_o<=0;no_path_o<=0;next_o<=0;length_o<=0;
            blocked<=0;visited<=0;head<=0;tail<=0;cur<=0;first<=0;dest<=0;
            trace<=0;steps<=0;x<=0;y<=0;direction<=0;neighbor<=0;neighbor_valid<=0;edge_denied<=0;
            edge_row<=0;parent_read<=0;escape_start<=0;
        end else begin
            ready_o<=0;
            if(cancel_i)begin state<=IDLE;busy_o<=0;end
            else case(state)
                IDLE:if(request_i)begin
                    blocked<=occupied_i;visited<=0;head<=0;tail<=1;
                    first<=start_i;dest<=goal_i;length_o<=0;no_path_o<=0;
                    escape_start<=ALLOW_SAFE_START_ESCAPE && start_escape_i;
                    busy_o<=1;state<=INIT;
                end
                INIT:begin
                    if(first>=400 || dest>=400)begin ready_o<=1;no_path_o<=1;busy_o<=0;state<=IDLE;end
                    else if((blocked[first] && !escape_start) || blocked[dest])begin ready_o<=1;no_path_o<=1;busy_o<=0;state<=IDLE;end
                    else if(first==dest)begin ready_o<=1;next_o<=first;busy_o<=0;state<=IDLE;end
                    else begin
                        visited[first]<=1;queue_mem[0]<=first;state<=POP;
                    end
                end
                POP:if(head==tail)begin
                    busy_o<=0;ready_o<=1;no_path_o<=1;state<=IDLE;
                end else begin
                    cur<=queue_mem[head];
                    head<=head+1'b1;direction<=0;state<=DECODE;
                end
                DECODE:begin x<=cur%20;y<=cur/20;edge_row<=denied_edges_i[cur*4+:4];state<=CALC;end
                CALC:begin
                    edge_denied<=edge_row[direction];
                    case(direction)
                        0:begin neighbor<=cur+20;neighbor_valid<=y<19;end
                        1:begin neighbor<=cur-1;neighbor_valid<=x>0;end
                        2:begin neighbor<=cur-20;neighbor_valid<=y>0;end
                        3:begin neighbor<=cur+1;neighbor_valid<=x<19;end
                    endcase
                    state<=CHECK;
                end
                CHECK:begin
                    state<=direction==3 ? POP : CALC;direction<=direction+1'b1;
                    if(neighbor_valid && !edge_denied && !blocked[neighbor] && !visited[neighbor])begin
                        visited[neighbor]<=1;parent[neighbor]<=cur;
                        if(neighbor==dest)begin trace<=dest;steps<=1;state<=TRACE;end
                        else if(tail<400)begin queue_mem[tail]<=neighbor;tail<=tail+1'b1;end
                        else begin busy_o<=0;ready_o<=1;no_path_o<=1;state<=IDLE;end
                    end
                end
                TRACE:begin parent_read<=parent[trace];state<=TRACE_CHECK;end
                TRACE_CHECK:if(parent_read==first)begin
                    next_o<=trace;length_o<=steps;busy_o<=0;ready_o<=1;state<=IDLE;
                end else if(steps>=399)begin
                    busy_o<=0;ready_o<=1;no_path_o<=1;state<=IDLE;
                end else begin trace<=parent_read;steps<=steps+1'b1;state<=TRACE;end
                default:begin state<=IDLE;busy_o<=0;end
            endcase
        end
    end
endmodule
