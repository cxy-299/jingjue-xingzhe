// Bounded restoring divider. No combinational '/' across a pose/control path.
module nav_unsigned_divider #(parameter WIDTH=24)(
    input wire clk,rst_n,start_i,
    input wire [WIDTH-1:0] numerator_i,denominator_i,
    output reg busy_o=0,done_o=0,
    output reg [WIDTH-1:0] quotient_o=0
);
    reg [WIDTH-1:0] numerator=0,denominator=1,quotient=0;
    reg [WIDTH:0] remainder=0;
    reg [5:0] bits_left=0;
    wire [WIDTH:0] shifted={remainder[WIDTH-1:0],numerator[WIDTH-1]};
    wire subtract=shifted>={1'b0,denominator};
    wire [WIDTH-1:0] next_quotient={quotient[WIDTH-2:0],subtract};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin busy_o<=0;done_o<=0;quotient_o<=0;numerator<=0;
            denominator<=1;quotient<=0;remainder<=0;bits_left<=0;end
        else begin
            done_o<=0;
            if(start_i && !busy_o)begin
                numerator<=numerator_i;denominator<=denominator_i;
                remainder<=0;quotient<=0;bits_left<=WIDTH;busy_o<=1;
            end else if(busy_o)begin
                numerator<=numerator<<1;quotient<=next_quotient;
                remainder<=subtract ? shifted-{1'b0,denominator}:shifted;
                bits_left<=bits_left-1'b1;
                if(bits_left==1)begin quotient_o<=next_quotient;busy_o<=0;done_o<=1;end
            end
        end
    end
endmodule
