module r20_mapped_tof (
  clk_50m_i_d,
  n177_5,
  tof0_uart_rx_i_d,
  v0_p,
  d0_p
)
;
input clk_50m_i_d;
input n177_5;
input tof0_uart_rx_i_d;
output v0_p;
output [12:0] d0_p;
wire n250_5;
wire n232_7;
wire n231_7;
wire n230_7;
wire n229_7;
wire n228_7;
wire n227_7;
wire n226_7;
wire n225_7;
wire n224_7;
wire n223_7;
wire n222_7;
wire n221_7;
wire n220_7;
wire n219_7;
wire n218_7;
wire n217_7;
wire n216_7;
wire n215_7;
wire n233_6;
wire n366_5;
wire n366_6;
wire n366_7;
wire n232_8;
wire n232_9;
wire n231_8;
wire n230_8;
wire n233_7;
wire n366_8;
wire n366_9;
wire n366_10;
wire n366_11;
wire n366_12;
wire n232_10;
wire n232_11;
wire n232_12;
wire n232_13;
wire n232_14;
wire n232_15;
wire n230_10;
wire n230_11;
wire n366_13;
wire n366_14;
wire n366_15;
wire n230_13;
wire n230_15;
wire n230_17;
wire n215_10;
wire n216_10;
wire n217_10;
wire n218_10;
wire n219_10;
wire n220_10;
wire n221_10;
wire n222_10;
wire n223_10;
wire n224_10;
wire n225_10;
wire n226_10;
wire n227_10;
wire n228_10;
wire n229_10;
wire n230_19;
wire digit_seen;
wire suffix_seen;
wire line_bad;
wire n83_1;
wire n83_2;
wire n82_1;
wire n82_2;
wire n81_1;
wire n81_2;
wire n80_1;
wire n80_2;
wire n79_1;
wire n79_2;
wire n78_1;
wire n78_2;
wire n77_1;
wire n77_2;
wire n76_1;
wire n76_2;
wire n75_1;
wire n75_2;
wire n74_1;
wire n74_2;
wire n73_1;
wire n73_2;
wire n72_1;
wire n72_2;
wire n71_1;
wire n71_0_COUT;
wire n99_1;
wire n99_2;
wire n98_1;
wire n98_2;
wire n97_1;
wire n97_2;
wire n96_1;
wire n96_2;
wire n95_1;
wire n95_2;
wire n94_1;
wire n94_2;
wire n93_1;
wire n93_2;
wire n92_1;
wire n92_2;
wire n91_1;
wire n91_2;
wire n90_1;
wire n90_2;
wire n89_1;
wire n89_2;
wire n88_1;
wire n88_2;
wire n87_1;
wire n87_2;
wire n86_1;
wire n86_2;
wire n85_1;
wire n85_0_COUT;
wire rx_valid;
wire rx_frame_error;
wire [15:0] accumulator;
wire [7:0] rx_data;
wire VCC;
wire GND;
  LUT4 n366_s1 (
    .F(n250_5),
    .I0(accumulator[7]),
    .I1(n366_5),
    .I2(n366_6),
    .I3(n366_7) 
);
defparam n366_s1.INIT=16'h04CC;
  LUT4 n232_s2 (
    .F(n232_7),
    .I0(rx_frame_error),
    .I1(suffix_seen),
    .I2(n232_8),
    .I3(n232_9) 
);
defparam n232_s2.INIT=16'h0504;
  LUT4 n231_s2 (
    .F(n231_7),
    .I0(rx_frame_error),
    .I1(digit_seen),
    .I2(n232_8),
    .I3(n231_8) 
);
defparam n231_s2.INIT=16'h0504;
  LUT4 n230_s2 (
    .F(n230_7),
    .I0(rx_frame_error),
    .I1(rx_data[0]),
    .I2(n230_8),
    .I3(n230_19) 
);
defparam n230_s2.INIT=16'h5540;
  LUT4 n229_s2 (
    .F(n229_7),
    .I0(rx_frame_error),
    .I1(n99_1),
    .I2(n230_8),
    .I3(n229_10) 
);
defparam n229_s2.INIT=16'h5540;
  LUT4 n228_s2 (
    .F(n228_7),
    .I0(rx_frame_error),
    .I1(n98_1),
    .I2(n230_8),
    .I3(n228_10) 
);
defparam n228_s2.INIT=16'h5540;
  LUT4 n227_s2 (
    .F(n227_7),
    .I0(rx_frame_error),
    .I1(n97_1),
    .I2(n230_8),
    .I3(n227_10) 
);
defparam n227_s2.INIT=16'h5540;
  LUT4 n226_s2 (
    .F(n226_7),
    .I0(rx_frame_error),
    .I1(n96_1),
    .I2(n230_8),
    .I3(n226_10) 
);
defparam n226_s2.INIT=16'h5540;
  LUT4 n225_s2 (
    .F(n225_7),
    .I0(rx_frame_error),
    .I1(n95_1),
    .I2(n230_8),
    .I3(n225_10) 
);
defparam n225_s2.INIT=16'h5540;
  LUT4 n224_s2 (
    .F(n224_7),
    .I0(rx_frame_error),
    .I1(n94_1),
    .I2(n230_8),
    .I3(n224_10) 
);
defparam n224_s2.INIT=16'h5540;
  LUT4 n223_s2 (
    .F(n223_7),
    .I0(rx_frame_error),
    .I1(n93_1),
    .I2(n230_8),
    .I3(n223_10) 
);
defparam n223_s2.INIT=16'h5540;
  LUT4 n222_s2 (
    .F(n222_7),
    .I0(rx_frame_error),
    .I1(n92_1),
    .I2(n230_8),
    .I3(n222_10) 
);
defparam n222_s2.INIT=16'h5540;
  LUT4 n221_s2 (
    .F(n221_7),
    .I0(rx_frame_error),
    .I1(n91_1),
    .I2(n230_8),
    .I3(n221_10) 
);
defparam n221_s2.INIT=16'h5540;
  LUT4 n220_s2 (
    .F(n220_7),
    .I0(rx_frame_error),
    .I1(n90_1),
    .I2(n230_8),
    .I3(n220_10) 
);
defparam n220_s2.INIT=16'h5540;
  LUT4 n219_s2 (
    .F(n219_7),
    .I0(rx_frame_error),
    .I1(n89_1),
    .I2(n230_8),
    .I3(n219_10) 
);
defparam n219_s2.INIT=16'h5540;
  LUT4 n218_s2 (
    .F(n218_7),
    .I0(rx_frame_error),
    .I1(n88_1),
    .I2(n230_8),
    .I3(n218_10) 
);
defparam n218_s2.INIT=16'h5540;
  LUT4 n217_s2 (
    .F(n217_7),
    .I0(rx_frame_error),
    .I1(n87_1),
    .I2(n230_8),
    .I3(n217_10) 
);
defparam n217_s2.INIT=16'h5540;
  LUT4 n216_s2 (
    .F(n216_7),
    .I0(rx_frame_error),
    .I1(n86_1),
    .I2(n230_8),
    .I3(n216_10) 
);
defparam n216_s2.INIT=16'h5540;
  LUT4 n215_s2 (
    .F(n215_7),
    .I0(rx_frame_error),
    .I1(n85_1),
    .I2(n230_8),
    .I3(n215_10) 
);
defparam n215_s2.INIT=16'h5540;
  LUT2 n233_s1 (
    .F(n233_6),
    .I0(rx_frame_error),
    .I1(n233_7) 
);
defparam n233_s1.INIT=4'hE;
  LUT4 n366_s2 (
    .F(n366_5),
    .I0(n366_8),
    .I1(n232_8),
    .I2(n366_9),
    .I3(n366_10) 
);
defparam n366_s2.INIT=16'h4C00;
  LUT4 n366_s3 (
    .F(n366_6),
    .I0(accumulator[2]),
    .I1(accumulator[5]),
    .I2(accumulator[6]),
    .I3(n366_11) 
);
defparam n366_s3.INIT=16'hE0F0;
  LUT4 n366_s4 (
    .F(n366_7),
    .I0(accumulator[10]),
    .I1(accumulator[11]),
    .I2(accumulator[12]),
    .I3(n366_12) 
);
defparam n366_s4.INIT=16'h8000;
  LUT4 n232_s3 (
    .F(n232_8),
    .I0(rx_data[5]),
    .I1(rx_valid),
    .I2(n232_10),
    .I3(n232_11) 
);
defparam n232_s3.INIT=16'h0400;
  LUT4 n232_s4 (
    .F(n232_9),
    .I0(n232_12),
    .I1(n232_13),
    .I2(n232_14),
    .I3(n232_15) 
);
defparam n232_s4.INIT=16'hDF00;
  LUT4 n231_s3 (
    .F(n231_8),
    .I0(rx_valid),
    .I1(n232_12),
    .I2(n232_13),
    .I3(n232_14) 
);
defparam n231_s3.INIT=16'h0800;
  LUT3 n230_s3 (
    .F(n230_8),
    .I0(n230_10),
    .I1(n231_8),
    .I2(n230_11) 
);
defparam n230_s3.INIT=8'h40;
  LUT4 n233_s2 (
    .F(n233_7),
    .I0(line_bad),
    .I1(n232_8),
    .I2(n231_8),
    .I3(n230_11) 
);
defparam n233_s2.INIT=16'h2232;
  LUT4 n366_s5 (
    .F(n366_8),
    .I0(accumulator[10]),
    .I1(accumulator[11]),
    .I2(accumulator[12]),
    .I3(n366_13) 
);
defparam n366_s5.INIT=16'h0100;
  LUT4 n366_s6 (
    .F(n366_9),
    .I0(accumulator[8]),
    .I1(accumulator[9]),
    .I2(n366_14),
    .I3(n366_15) 
);
defparam n366_s6.INIT=16'h0010;
  LUT4 n366_s7 (
    .F(n366_10),
    .I0(rx_frame_error),
    .I1(line_bad),
    .I2(digit_seen),
    .I3(n366_13) 
);
defparam n366_s7.INIT=16'h1000;
  LUT4 n366_s8 (
    .F(n366_11),
    .I0(accumulator[0]),
    .I1(accumulator[1]),
    .I2(accumulator[3]),
    .I3(accumulator[4]) 
);
defparam n366_s8.INIT=16'h0001;
  LUT2 n366_s9 (
    .F(n366_12),
    .I0(accumulator[8]),
    .I1(accumulator[9]) 
);
defparam n366_s9.INIT=4'h8;
  LUT3 n232_s5 (
    .F(n232_10),
    .I0(rx_data[0]),
    .I1(rx_data[1]),
    .I2(rx_data[2]) 
);
defparam n232_s5.INIT=8'hDB;
  LUT4 n232_s6 (
    .F(n232_11),
    .I0(rx_data[3]),
    .I1(rx_data[4]),
    .I2(rx_data[6]),
    .I3(rx_data[7]) 
);
defparam n232_s6.INIT=16'h0002;
  LUT2 n232_s7 (
    .F(n232_12),
    .I0(rx_data[6]),
    .I1(rx_data[7]) 
);
defparam n232_s7.INIT=4'h1;
  LUT3 n232_s8 (
    .F(n232_13),
    .I0(rx_data[1]),
    .I1(rx_data[2]),
    .I2(rx_data[3]) 
);
defparam n232_s8.INIT=8'hE0;
  LUT4 n232_s9 (
    .F(n232_14),
    .I0(rx_data[4]),
    .I1(rx_data[5]),
    .I2(line_bad),
    .I3(suffix_seen) 
);
defparam n232_s9.INIT=16'h0008;
  LUT3 n232_s10 (
    .F(n232_15),
    .I0(line_bad),
    .I1(digit_seen),
    .I2(rx_valid) 
);
defparam n232_s10.INIT=8'h40;
  LUT3 n230_s5 (
    .F(n230_10),
    .I0(rx_data[5]),
    .I1(n232_10),
    .I2(n232_11) 
);
defparam n230_s5.INIT=8'h10;
  LUT4 n230_s6 (
    .F(n230_11),
    .I0(n366_8),
    .I1(n366_14),
    .I2(n366_12),
    .I3(n230_13) 
);
defparam n230_s6.INIT=16'h0A8A;
  LUT3 n366_s10 (
    .F(n366_13),
    .I0(accumulator[13]),
    .I1(accumulator[14]),
    .I2(accumulator[15]) 
);
defparam n366_s10.INIT=8'h01;
  LUT2 n366_s11 (
    .F(n366_14),
    .I0(accumulator[6]),
    .I1(accumulator[7]) 
);
defparam n366_s11.INIT=4'h1;
  LUT3 n366_s12 (
    .F(n366_15),
    .I0(accumulator[3]),
    .I1(accumulator[4]),
    .I2(accumulator[5]) 
);
defparam n366_s12.INIT=8'hE0;
  LUT4 n230_s8 (
    .F(n230_13),
    .I0(accumulator[2]),
    .I1(accumulator[5]),
    .I2(n366_11),
    .I3(n230_15) 
);
defparam n230_s8.INIT=16'h8CCC;
  LUT4 n230_s10 (
    .F(n230_15),
    .I0(rx_data[0]),
    .I1(rx_data[1]),
    .I2(rx_data[2]),
    .I3(rx_data[3]) 
);
defparam n230_s10.INIT=16'h0001;
  LUT4 n230_s11 (
    .F(n230_17),
    .I0(rx_data[6]),
    .I1(rx_data[7]),
    .I2(n232_13),
    .I3(n232_14) 
);
defparam n230_s11.INIT=16'h0100;
  LUT4 n215_s4 (
    .F(n215_10),
    .I0(accumulator[15]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n215_s4.INIT=16'h222A;
  LUT4 n216_s4 (
    .F(n216_10),
    .I0(accumulator[14]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n216_s4.INIT=16'h222A;
  LUT4 n217_s4 (
    .F(n217_10),
    .I0(accumulator[13]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n217_s4.INIT=16'h222A;
  LUT4 n218_s4 (
    .F(n218_10),
    .I0(accumulator[12]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n218_s4.INIT=16'h222A;
  LUT4 n219_s4 (
    .F(n219_10),
    .I0(accumulator[11]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n219_s4.INIT=16'h222A;
  LUT4 n220_s4 (
    .F(n220_10),
    .I0(accumulator[10]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n220_s4.INIT=16'h222A;
  LUT4 n221_s4 (
    .F(n221_10),
    .I0(accumulator[9]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n221_s4.INIT=16'h222A;
  LUT4 n222_s4 (
    .F(n222_10),
    .I0(accumulator[8]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n222_s4.INIT=16'h222A;
  LUT4 n223_s4 (
    .F(n223_10),
    .I0(accumulator[7]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n223_s4.INIT=16'h222A;
  LUT4 n224_s4 (
    .F(n224_10),
    .I0(accumulator[6]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n224_s4.INIT=16'h222A;
  LUT4 n225_s4 (
    .F(n225_10),
    .I0(accumulator[5]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n225_s4.INIT=16'h222A;
  LUT4 n226_s4 (
    .F(n226_10),
    .I0(accumulator[4]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n226_s4.INIT=16'h222A;
  LUT4 n227_s4 (
    .F(n227_10),
    .I0(accumulator[3]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n227_s4.INIT=16'h222A;
  LUT4 n228_s4 (
    .F(n228_10),
    .I0(accumulator[2]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n228_s4.INIT=16'h222A;
  LUT4 n229_s4 (
    .F(n229_10),
    .I0(accumulator[1]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n229_s4.INIT=16'h222A;
  LUT4 n230_s12 (
    .F(n230_19),
    .I0(accumulator[0]),
    .I1(rx_valid),
    .I2(n230_10),
    .I3(n230_17) 
);
defparam n230_s12.INIT=16'h222A;
  DFFCE accumulator_14_s0 (
    .Q(accumulator[14]),
    .D(n216_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_14_s0.INIT=1'b0;
  DFFCE accumulator_13_s0 (
    .Q(accumulator[13]),
    .D(n217_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_13_s0.INIT=1'b0;
  DFFCE accumulator_12_s0 (
    .Q(accumulator[12]),
    .D(n218_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_12_s0.INIT=1'b0;
  DFFCE accumulator_11_s0 (
    .Q(accumulator[11]),
    .D(n219_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_11_s0.INIT=1'b0;
  DFFCE accumulator_10_s0 (
    .Q(accumulator[10]),
    .D(n220_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_10_s0.INIT=1'b0;
  DFFCE accumulator_9_s0 (
    .Q(accumulator[9]),
    .D(n221_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_9_s0.INIT=1'b0;
  DFFCE accumulator_8_s0 (
    .Q(accumulator[8]),
    .D(n222_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_8_s0.INIT=1'b0;
  DFFCE accumulator_7_s0 (
    .Q(accumulator[7]),
    .D(n223_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_7_s0.INIT=1'b0;
  DFFCE accumulator_6_s0 (
    .Q(accumulator[6]),
    .D(n224_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_6_s0.INIT=1'b0;
  DFFCE accumulator_5_s0 (
    .Q(accumulator[5]),
    .D(n225_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_5_s0.INIT=1'b0;
  DFFCE accumulator_4_s0 (
    .Q(accumulator[4]),
    .D(n226_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_4_s0.INIT=1'b0;
  DFFCE accumulator_3_s0 (
    .Q(accumulator[3]),
    .D(n227_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_3_s0.INIT=1'b0;
  DFFCE accumulator_2_s0 (
    .Q(accumulator[2]),
    .D(n228_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_2_s0.INIT=1'b0;
  DFFCE accumulator_1_s0 (
    .Q(accumulator[1]),
    .D(n229_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_1_s0.INIT=1'b0;
  DFFCE accumulator_0_s0 (
    .Q(accumulator[0]),
    .D(n230_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_0_s0.INIT=1'b0;
  DFFCE digit_seen_s0 (
    .Q(digit_seen),
    .D(n231_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam digit_seen_s0.INIT=1'b0;
  DFFCE suffix_seen_s0 (
    .Q(suffix_seen),
    .D(n232_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam suffix_seen_s0.INIT=1'b0;
  DFFCE line_bad_s0 (
    .Q(line_bad),
    .D(n233_6),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam line_bad_s0.INIT=1'b0;
  DFFCE distance_mm_o_12_s0 (
    .Q(d0_p[12]),
    .D(accumulator[12]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_11_s0 (
    .Q(d0_p[11]),
    .D(accumulator[11]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_10_s0 (
    .Q(d0_p[10]),
    .D(accumulator[10]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_9_s0 (
    .Q(d0_p[9]),
    .D(accumulator[9]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_8_s0 (
    .Q(d0_p[8]),
    .D(accumulator[8]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_7_s0 (
    .Q(d0_p[7]),
    .D(accumulator[7]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_6_s0 (
    .Q(d0_p[6]),
    .D(accumulator[6]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_5_s0 (
    .Q(d0_p[5]),
    .D(accumulator[5]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_4_s0 (
    .Q(d0_p[4]),
    .D(accumulator[4]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_3_s0 (
    .Q(d0_p[3]),
    .D(accumulator[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_2_s0 (
    .Q(d0_p[2]),
    .D(accumulator[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_1_s0 (
    .Q(d0_p[1]),
    .D(accumulator[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE distance_mm_o_0_s0 (
    .Q(d0_p[0]),
    .D(accumulator[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n250_5) 
);
  DFFCE valid_pulse_o_s0 (
    .Q(v0_p),
    .D(n250_5),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam valid_pulse_o_s0.INIT=1'b0;
  DFFCE accumulator_15_s0 (
    .Q(accumulator[15]),
    .D(n215_7),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam accumulator_15_s0.INIT=1'b0;
  ALU n83_s (
    .SUM(n83_1),
    .COUT(n83_2),
    .I0(accumulator[0]),
    .I1(accumulator[2]),
    .I3(VCC),
    .CIN(GND) 
);
defparam n83_s.ALU_MODE=0;
  ALU n82_s (
    .SUM(n82_1),
    .COUT(n82_2),
    .I0(accumulator[1]),
    .I1(accumulator[3]),
    .I3(VCC),
    .CIN(n83_2) 
);
defparam n82_s.ALU_MODE=0;
  ALU n81_s (
    .SUM(n81_1),
    .COUT(n81_2),
    .I0(accumulator[2]),
    .I1(accumulator[4]),
    .I3(VCC),
    .CIN(n82_2) 
);
defparam n81_s.ALU_MODE=0;
  ALU n80_s (
    .SUM(n80_1),
    .COUT(n80_2),
    .I0(accumulator[3]),
    .I1(accumulator[5]),
    .I3(VCC),
    .CIN(n81_2) 
);
defparam n80_s.ALU_MODE=0;
  ALU n79_s (
    .SUM(n79_1),
    .COUT(n79_2),
    .I0(accumulator[4]),
    .I1(accumulator[6]),
    .I3(VCC),
    .CIN(n80_2) 
);
defparam n79_s.ALU_MODE=0;
  ALU n78_s (
    .SUM(n78_1),
    .COUT(n78_2),
    .I0(accumulator[5]),
    .I1(accumulator[7]),
    .I3(VCC),
    .CIN(n79_2) 
);
defparam n78_s.ALU_MODE=0;
  ALU n77_s (
    .SUM(n77_1),
    .COUT(n77_2),
    .I0(accumulator[6]),
    .I1(accumulator[8]),
    .I3(VCC),
    .CIN(n78_2) 
);
defparam n77_s.ALU_MODE=0;
  ALU n76_s (
    .SUM(n76_1),
    .COUT(n76_2),
    .I0(accumulator[7]),
    .I1(accumulator[9]),
    .I3(VCC),
    .CIN(n77_2) 
);
defparam n76_s.ALU_MODE=0;
  ALU n75_s (
    .SUM(n75_1),
    .COUT(n75_2),
    .I0(accumulator[8]),
    .I1(accumulator[10]),
    .I3(VCC),
    .CIN(n76_2) 
);
defparam n75_s.ALU_MODE=0;
  ALU n74_s (
    .SUM(n74_1),
    .COUT(n74_2),
    .I0(accumulator[9]),
    .I1(accumulator[11]),
    .I3(VCC),
    .CIN(n75_2) 
);
defparam n74_s.ALU_MODE=0;
  ALU n73_s (
    .SUM(n73_1),
    .COUT(n73_2),
    .I0(accumulator[10]),
    .I1(accumulator[12]),
    .I3(VCC),
    .CIN(n74_2) 
);
defparam n73_s.ALU_MODE=0;
  ALU n72_s (
    .SUM(n72_1),
    .COUT(n72_2),
    .I0(accumulator[11]),
    .I1(accumulator[13]),
    .I3(VCC),
    .CIN(n73_2) 
);
defparam n72_s.ALU_MODE=0;
  ALU n71_s (
    .SUM(n71_1),
    .COUT(n71_0_COUT),
    .I0(accumulator[12]),
    .I1(accumulator[14]),
    .I3(VCC),
    .CIN(n72_2) 
);
defparam n71_s.ALU_MODE=0;
  ALU n99_s (
    .SUM(n99_1),
    .COUT(n99_2),
    .I0(accumulator[0]),
    .I1(rx_data[1]),
    .I3(VCC),
    .CIN(GND) 
);
defparam n99_s.ALU_MODE=0;
  ALU n98_s (
    .SUM(n98_1),
    .COUT(n98_2),
    .I0(accumulator[1]),
    .I1(rx_data[2]),
    .I3(VCC),
    .CIN(n99_2) 
);
defparam n98_s.ALU_MODE=0;
  ALU n97_s (
    .SUM(n97_1),
    .COUT(n97_2),
    .I0(n83_1),
    .I1(rx_data[3]),
    .I3(VCC),
    .CIN(n98_2) 
);
defparam n97_s.ALU_MODE=0;
  ALU n96_s (
    .SUM(n96_1),
    .COUT(n96_2),
    .I0(n82_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n97_2) 
);
defparam n96_s.ALU_MODE=0;
  ALU n95_s (
    .SUM(n95_1),
    .COUT(n95_2),
    .I0(n81_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n96_2) 
);
defparam n95_s.ALU_MODE=0;
  ALU n94_s (
    .SUM(n94_1),
    .COUT(n94_2),
    .I0(n80_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n95_2) 
);
defparam n94_s.ALU_MODE=0;
  ALU n93_s (
    .SUM(n93_1),
    .COUT(n93_2),
    .I0(n79_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n94_2) 
);
defparam n93_s.ALU_MODE=0;
  ALU n92_s (
    .SUM(n92_1),
    .COUT(n92_2),
    .I0(n78_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n93_2) 
);
defparam n92_s.ALU_MODE=0;
  ALU n91_s (
    .SUM(n91_1),
    .COUT(n91_2),
    .I0(n77_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n92_2) 
);
defparam n91_s.ALU_MODE=0;
  ALU n90_s (
    .SUM(n90_1),
    .COUT(n90_2),
    .I0(n76_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n91_2) 
);
defparam n90_s.ALU_MODE=0;
  ALU n89_s (
    .SUM(n89_1),
    .COUT(n89_2),
    .I0(n75_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n90_2) 
);
defparam n89_s.ALU_MODE=0;
  ALU n88_s (
    .SUM(n88_1),
    .COUT(n88_2),
    .I0(n74_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n89_2) 
);
defparam n88_s.ALU_MODE=0;
  ALU n87_s (
    .SUM(n87_1),
    .COUT(n87_2),
    .I0(n73_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n88_2) 
);
defparam n87_s.ALU_MODE=0;
  ALU n86_s (
    .SUM(n86_1),
    .COUT(n86_2),
    .I0(n72_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n87_2) 
);
defparam n86_s.ALU_MODE=0;
  ALU n85_s (
    .SUM(n85_1),
    .COUT(n85_0_COUT),
    .I0(n71_1),
    .I1(GND),
    .I3(VCC),
    .CIN(n86_2) 
);
defparam n85_s.ALU_MODE=0;
  uart_rx_0 u_rx (
    .clk_50m_i_d(clk_50m_i_d),
    .n177_5(n177_5),
    .tof0_uart_rx_i_d(tof0_uart_rx_i_d),
    .rx_valid(rx_valid),
    .rx_frame_error(rx_frame_error),
    .rx_data(rx_data[7:0])
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule

module uart_rx_0 (
  clk_50m_i_d,
  n177_5,
  tof0_uart_rx_i_d,
  rx_valid,
  rx_frame_error,
  rx_data
)
;
input clk_50m_i_d;
input n177_5;
input tof0_uart_rx_i_d;
output rx_valid;
output rx_frame_error;
output [7:0] rx_data;
wire n200_3;
wire n326_15;
wire n328_9;
wire n338_9;
wire n339_9;
wire n340_9;
wire n341_9;
wire n342_9;
wire n343_9;
wire n344_9;
wire n345_9;
wire n347_11;
wire n346_11;
wire n325_16;
wire n324_15;
wire n323_15;
wire n322_15;
wire n321_15;
wire n320_15;
wire n319_15;
wire n318_15;
wire n317_15;
wire n316_15;
wire n315_15;
wire n314_15;
wire n313_15;
wire n312_15;
wire n311_15;
wire n310_15;
wire n309_15;
wire n308_15;
wire n307_15;
wire n306_15;
wire n305_15;
wire n304_15;
wire n303_15;
wire n302_15;
wire n301_15;
wire n300_15;
wire n299_15;
wire n298_15;
wire n297_15;
wire n296_15;
wire n295_15;
wire n294_15;
wire n337_13;
wire n200_4;
wire n200_5;
wire n200_6;
wire n200_7;
wire n328_10;
wire n328_11;
wire n328_12;
wire n328_13;
wire n338_10;
wire n339_10;
wire n340_10;
wire n341_10;
wire n342_10;
wire n343_10;
wire n344_10;
wire n345_10;
wire bit_index_2_9;
wire n325_17;
wire n323_16;
wire n321_16;
wire n320_16;
wire n317_16;
wire n316_16;
wire n315_16;
wire n314_16;
wire n313_16;
wire n312_16;
wire n311_16;
wire n310_16;
wire n308_16;
wire n307_16;
wire n306_16;
wire n305_16;
wire n304_16;
wire n303_16;
wire n301_16;
wire n300_16;
wire n299_16;
wire n298_16;
wire n297_16;
wire n296_16;
wire n295_16;
wire n294_16;
wire n337_14;
wire n200_8;
wire n200_9;
wire n200_10;
wire n328_14;
wire n328_15;
wire n328_16;
wire n328_17;
wire n328_18;
wire n328_19;
wire n328_20;
wire n338_11;
wire n339_11;
wire n340_11;
wire n341_11;
wire n325_18;
wire n318_17;
wire n314_17;
wire n310_17;
wire n309_17;
wire n306_17;
wire n305_17;
wire n303_17;
wire n302_17;
wire n300_17;
wire n299_17;
wire n297_17;
wire n296_17;
wire n295_17;
wire n302_18;
wire n325_21;
wire n318_19;
wire n319_18;
wire n322_18;
wire n309_19;
wire n302_20;
wire n348_14;
wire bit_index_2_11;
wire rx_sync;
wire rx_meta;
wire n327_15;
wire [31:0] clock_count;
wire [7:0] shift_reg;
wire [1:0] state;
wire [2:0] bit_index;
wire VCC;
wire GND;
  LUT4 n200_s0 (
    .F(n200_3),
    .I0(n200_4),
    .I1(n200_5),
    .I2(n200_6),
    .I3(n200_7) 
);
defparam n200_s0.INIT=16'hFFA8;
  LUT3 n326_s7 (
    .F(n326_15),
    .I0(rx_sync),
    .I1(state[0]),
    .I2(state[1]) 
);
defparam n326_s7.INIT=8'h34;
  LUT4 n328_s5 (
    .F(n328_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n328_13) 
);
defparam n328_s5.INIT=16'h8000;
  LUT4 n338_s5 (
    .F(n338_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n338_10) 
);
defparam n338_s5.INIT=16'h8000;
  LUT4 n339_s5 (
    .F(n339_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n339_10) 
);
defparam n339_s5.INIT=16'h8000;
  LUT4 n340_s5 (
    .F(n340_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n340_10) 
);
defparam n340_s5.INIT=16'h8000;
  LUT4 n341_s5 (
    .F(n341_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n341_10) 
);
defparam n341_s5.INIT=16'h8000;
  LUT4 n342_s5 (
    .F(n342_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n342_10) 
);
defparam n342_s5.INIT=16'h8000;
  LUT4 n343_s5 (
    .F(n343_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n343_10) 
);
defparam n343_s5.INIT=16'h8000;
  LUT4 n344_s5 (
    .F(n344_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n344_10) 
);
defparam n344_s5.INIT=16'h8000;
  LUT4 n345_s5 (
    .F(n345_9),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n345_10) 
);
defparam n345_s5.INIT=16'h8000;
  LUT3 n347_s5 (
    .F(n347_11),
    .I0(bit_index[0]),
    .I1(bit_index[1]),
    .I2(state[1]) 
);
defparam n347_s5.INIT=8'h60;
  LUT4 n346_s5 (
    .F(n346_11),
    .I0(bit_index[0]),
    .I1(bit_index[1]),
    .I2(bit_index[2]),
    .I3(state[1]) 
);
defparam n346_s5.INIT=16'h7800;
  LUT3 n325_s8 (
    .F(n325_16),
    .I0(clock_count[0]),
    .I1(bit_index_2_9),
    .I2(n325_17) 
);
defparam n325_s8.INIT=8'h54;
  LUT4 n324_s7 (
    .F(n324_15),
    .I0(clock_count[0]),
    .I1(clock_count[1]),
    .I2(bit_index_2_9),
    .I3(n325_17) 
);
defparam n324_s7.INIT=16'h6660;
  LUT4 n323_s7 (
    .F(n323_15),
    .I0(clock_count[2]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n323_16) 
);
defparam n323_s7.INIT=16'h54A8;
  LUT3 n322_s7 (
    .F(n322_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n322_18) 
);
defparam n322_s7.INIT=8'h0E;
  LUT4 n321_s7 (
    .F(n321_15),
    .I0(clock_count[4]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n321_16) 
);
defparam n321_s7.INIT=16'h54A8;
  LUT4 n320_s7 (
    .F(n320_15),
    .I0(clock_count[5]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n320_16) 
);
defparam n320_s7.INIT=16'h54A8;
  LUT3 n319_s7 (
    .F(n319_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n319_18) 
);
defparam n319_s7.INIT=8'h0E;
  LUT4 n318_s7 (
    .F(n318_15),
    .I0(clock_count[7]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n318_19) 
);
defparam n318_s7.INIT=16'h54A8;
  LUT3 n317_s7 (
    .F(n317_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n317_16) 
);
defparam n317_s7.INIT=8'h0E;
  LUT3 n316_s7 (
    .F(n316_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n316_16) 
);
defparam n316_s7.INIT=8'h0E;
  LUT4 n315_s7 (
    .F(n315_15),
    .I0(clock_count[10]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n315_16) 
);
defparam n315_s7.INIT=16'h54A8;
  LUT4 n314_s7 (
    .F(n314_15),
    .I0(clock_count[11]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n314_16) 
);
defparam n314_s7.INIT=16'h54A8;
  LUT3 n313_s7 (
    .F(n313_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n313_16) 
);
defparam n313_s7.INIT=8'h0E;
  LUT3 n312_s7 (
    .F(n312_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n312_16) 
);
defparam n312_s7.INIT=8'h0E;
  LUT4 n311_s7 (
    .F(n311_15),
    .I0(clock_count[14]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n311_16) 
);
defparam n311_s7.INIT=16'h54A8;
  LUT3 n310_s7 (
    .F(n310_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n310_16) 
);
defparam n310_s7.INIT=8'h0E;
  LUT3 n309_s7 (
    .F(n309_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n309_19) 
);
defparam n309_s7.INIT=8'h0E;
  LUT3 n308_s7 (
    .F(n308_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n308_16) 
);
defparam n308_s7.INIT=8'h0E;
  LUT4 n307_s7 (
    .F(n307_15),
    .I0(clock_count[18]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n307_16) 
);
defparam n307_s7.INIT=16'h54A8;
  LUT4 n306_s7 (
    .F(n306_15),
    .I0(clock_count[19]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n306_16) 
);
defparam n306_s7.INIT=16'h54A8;
  LUT3 n305_s7 (
    .F(n305_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n305_16) 
);
defparam n305_s7.INIT=8'h0E;
  LUT4 n304_s7 (
    .F(n304_15),
    .I0(clock_count[21]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n304_16) 
);
defparam n304_s7.INIT=16'h54A8;
  LUT4 n303_s7 (
    .F(n303_15),
    .I0(clock_count[22]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n303_16) 
);
defparam n303_s7.INIT=16'h54A8;
  LUT4 n302_s7 (
    .F(n302_15),
    .I0(clock_count[23]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n302_20) 
);
defparam n302_s7.INIT=16'h54A8;
  LUT3 n301_s7 (
    .F(n301_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n301_16) 
);
defparam n301_s7.INIT=8'h0E;
  LUT3 n300_s7 (
    .F(n300_15),
    .I0(bit_index_2_9),
    .I1(n325_17),
    .I2(n300_16) 
);
defparam n300_s7.INIT=8'h0E;
  LUT4 n299_s7 (
    .F(n299_15),
    .I0(clock_count[26]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n299_16) 
);
defparam n299_s7.INIT=16'h54A8;
  LUT4 n298_s7 (
    .F(n298_15),
    .I0(clock_count[27]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n298_16) 
);
defparam n298_s7.INIT=16'h54A8;
  LUT4 n297_s7 (
    .F(n297_15),
    .I0(clock_count[28]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n297_16) 
);
defparam n297_s7.INIT=16'h54A8;
  LUT4 n296_s7 (
    .F(n296_15),
    .I0(clock_count[29]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n296_16) 
);
defparam n296_s7.INIT=16'h54A8;
  LUT4 n295_s7 (
    .F(n295_15),
    .I0(clock_count[30]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n295_16) 
);
defparam n295_s7.INIT=16'h54A8;
  LUT4 n294_s7 (
    .F(n294_15),
    .I0(clock_count[31]),
    .I1(bit_index_2_9),
    .I2(n325_17),
    .I3(n294_16) 
);
defparam n294_s7.INIT=16'h54A8;
  LUT4 n337_s5 (
    .F(n337_13),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n328_12),
    .I3(n337_14) 
);
defparam n337_s5.INIT=16'h8000;
  LUT2 n200_s1 (
    .F(n200_4),
    .I0(n328_10),
    .I1(n328_11) 
);
defparam n200_s1.INIT=4'h8;
  LUT4 n200_s2 (
    .F(n200_5),
    .I0(state[0]),
    .I1(state[1]),
    .I2(n200_8),
    .I3(n200_9) 
);
defparam n200_s2.INIT=16'h2000;
  LUT3 n200_s3 (
    .F(n200_6),
    .I0(state[1]),
    .I1(n328_12),
    .I2(n200_10) 
);
defparam n200_s3.INIT=8'h08;
  LUT3 n200_s4 (
    .F(n200_7),
    .I0(rx_sync),
    .I1(state[0]),
    .I2(state[1]) 
);
defparam n200_s4.INIT=8'h01;
  LUT4 n328_s6 (
    .F(n328_10),
    .I0(clock_count[1]),
    .I1(clock_count[2]),
    .I2(n328_14),
    .I3(n328_15) 
);
defparam n328_s6.INIT=16'h1000;
  LUT4 n328_s7 (
    .F(n328_11),
    .I0(n328_16),
    .I1(n328_17),
    .I2(n328_18),
    .I3(n328_19) 
);
defparam n328_s7.INIT=16'h8000;
  LUT3 n328_s8 (
    .F(n328_12),
    .I0(clock_count[0]),
    .I1(clock_count[3]),
    .I2(n328_20) 
);
defparam n328_s8.INIT=8'h20;
  LUT3 n328_s9 (
    .F(n328_13),
    .I0(rx_sync),
    .I1(state[0]),
    .I2(state[1]) 
);
defparam n328_s9.INIT=8'h80;
  LUT2 n338_s6 (
    .F(n338_10),
    .I0(bit_index[2]),
    .I1(n338_11) 
);
defparam n338_s6.INIT=4'h8;
  LUT2 n339_s6 (
    .F(n339_10),
    .I0(bit_index[2]),
    .I1(n339_11) 
);
defparam n339_s6.INIT=4'h8;
  LUT2 n340_s6 (
    .F(n340_10),
    .I0(bit_index[2]),
    .I1(n340_11) 
);
defparam n340_s6.INIT=4'h8;
  LUT2 n341_s6 (
    .F(n341_10),
    .I0(bit_index[2]),
    .I1(n341_11) 
);
defparam n341_s6.INIT=4'h8;
  LUT2 n342_s6 (
    .F(n342_10),
    .I0(bit_index[2]),
    .I1(n338_11) 
);
defparam n342_s6.INIT=4'h4;
  LUT2 n343_s6 (
    .F(n343_10),
    .I0(bit_index[2]),
    .I1(n339_11) 
);
defparam n343_s6.INIT=4'h4;
  LUT2 n344_s6 (
    .F(n344_10),
    .I0(bit_index[2]),
    .I1(n340_11) 
);
defparam n344_s6.INIT=4'h4;
  LUT2 n345_s6 (
    .F(n345_10),
    .I0(bit_index[2]),
    .I1(n341_11) 
);
defparam n345_s6.INIT=4'h4;
  LUT4 bit_index_2_s4 (
    .F(bit_index_2_9),
    .I0(state[1]),
    .I1(n328_10),
    .I2(n328_11),
    .I3(n328_12) 
);
defparam bit_index_2_s4.INIT=16'h2AAA;
  LUT4 n325_s9 (
    .F(n325_17),
    .I0(n328_10),
    .I1(n328_11),
    .I2(n325_18),
    .I3(n325_21) 
);
defparam n325_s9.INIT=16'h70F0;
  LUT2 n323_s8 (
    .F(n323_16),
    .I0(clock_count[0]),
    .I1(clock_count[1]) 
);
defparam n323_s8.INIT=4'h8;
  LUT4 n321_s8 (
    .F(n321_16),
    .I0(clock_count[0]),
    .I1(clock_count[1]),
    .I2(clock_count[2]),
    .I3(clock_count[3]) 
);
defparam n321_s8.INIT=16'h8000;
  LUT2 n320_s8 (
    .F(n320_16),
    .I0(clock_count[4]),
    .I1(n321_16) 
);
defparam n320_s8.INIT=4'h8;
  LUT3 n317_s8 (
    .F(n317_16),
    .I0(clock_count[7]),
    .I1(clock_count[8]),
    .I2(n318_19) 
);
defparam n317_s8.INIT=8'h93;
  LUT4 n316_s8 (
    .F(n316_16),
    .I0(clock_count[7]),
    .I1(clock_count[8]),
    .I2(clock_count[9]),
    .I3(n318_19) 
);
defparam n316_s8.INIT=16'h870F;
  LUT4 n315_s8 (
    .F(n315_16),
    .I0(clock_count[7]),
    .I1(clock_count[8]),
    .I2(clock_count[9]),
    .I3(n318_19) 
);
defparam n315_s8.INIT=16'h8000;
  LUT3 n314_s8 (
    .F(n314_16),
    .I0(n321_16),
    .I1(n318_17),
    .I2(n314_17) 
);
defparam n314_s8.INIT=8'h80;
  LUT3 n313_s8 (
    .F(n313_16),
    .I0(clock_count[11]),
    .I1(clock_count[12]),
    .I2(n314_16) 
);
defparam n313_s8.INIT=8'h93;
  LUT4 n312_s8 (
    .F(n312_16),
    .I0(clock_count[11]),
    .I1(clock_count[12]),
    .I2(clock_count[13]),
    .I3(n314_16) 
);
defparam n312_s8.INIT=16'h870F;
  LUT4 n311_s8 (
    .F(n311_16),
    .I0(clock_count[11]),
    .I1(clock_count[12]),
    .I2(clock_count[13]),
    .I3(n314_16) 
);
defparam n311_s8.INIT=16'h8000;
  LUT3 n310_s8 (
    .F(n310_16),
    .I0(clock_count[15]),
    .I1(n314_16),
    .I2(n310_17) 
);
defparam n310_s8.INIT=8'h95;
  LUT4 n308_s8 (
    .F(n308_16),
    .I0(clock_count[16]),
    .I1(clock_count[17]),
    .I2(n314_16),
    .I3(n309_17) 
);
defparam n308_s8.INIT=16'h9333;
  LUT4 n307_s8 (
    .F(n307_16),
    .I0(clock_count[16]),
    .I1(clock_count[17]),
    .I2(n314_16),
    .I3(n309_17) 
);
defparam n307_s8.INIT=16'h8000;
  LUT4 n306_s8 (
    .F(n306_16),
    .I0(clock_count[16]),
    .I1(n314_16),
    .I2(n309_17),
    .I3(n306_17) 
);
defparam n306_s8.INIT=16'h8000;
  LUT4 n305_s8 (
    .F(n305_16),
    .I0(clock_count[20]),
    .I1(n314_16),
    .I2(n309_17),
    .I3(n305_17) 
);
defparam n305_s8.INIT=16'h9555;
  LUT4 n304_s8 (
    .F(n304_16),
    .I0(clock_count[20]),
    .I1(n314_16),
    .I2(n309_17),
    .I3(n305_17) 
);
defparam n304_s8.INIT=16'h8000;
  LUT4 n303_s8 (
    .F(n303_16),
    .I0(n314_16),
    .I1(n309_17),
    .I2(n305_17),
    .I3(n303_17) 
);
defparam n303_s8.INIT=16'h8000;
  LUT4 n301_s8 (
    .F(n301_16),
    .I0(clock_count[23]),
    .I1(clock_count[24]),
    .I2(n314_16),
    .I3(n302_17) 
);
defparam n301_s8.INIT=16'h9333;
  LUT4 n300_s8 (
    .F(n300_16),
    .I0(clock_count[25]),
    .I1(n314_16),
    .I2(n302_17),
    .I3(n300_17) 
);
defparam n300_s8.INIT=16'h9555;
  LUT3 n299_s8 (
    .F(n299_16),
    .I0(n314_16),
    .I1(n302_17),
    .I2(n299_17) 
);
defparam n299_s8.INIT=8'h80;
  LUT4 n298_s8 (
    .F(n298_16),
    .I0(clock_count[26]),
    .I1(n314_16),
    .I2(n302_17),
    .I3(n299_17) 
);
defparam n298_s8.INIT=16'h8000;
  LUT4 n297_s8 (
    .F(n297_16),
    .I0(n314_16),
    .I1(n302_17),
    .I2(n299_17),
    .I3(n297_17) 
);
defparam n297_s8.INIT=16'h8000;
  LUT4 n296_s8 (
    .F(n296_16),
    .I0(n314_16),
    .I1(n302_17),
    .I2(n299_17),
    .I3(n296_17) 
);
defparam n296_s8.INIT=16'h8000;
  LUT3 n295_s8 (
    .F(n295_16),
    .I0(n314_16),
    .I1(n302_17),
    .I2(n295_17) 
);
defparam n295_s8.INIT=8'h80;
  LUT4 n294_s8 (
    .F(n294_16),
    .I0(clock_count[30]),
    .I1(n314_16),
    .I2(n302_17),
    .I3(n295_17) 
);
defparam n294_s8.INIT=16'h8000;
  LUT3 n337_s6 (
    .F(n337_14),
    .I0(rx_sync),
    .I1(state[0]),
    .I2(state[1]) 
);
defparam n337_s6.INIT=8'h40;
  LUT4 n200_s5 (
    .F(n200_8),
    .I0(clock_count[0]),
    .I1(clock_count[3]),
    .I2(clock_count[5]),
    .I3(clock_count[6]) 
);
defparam n200_s5.INIT=16'h0400;
  LUT2 n200_s6 (
    .F(n200_9),
    .I0(clock_count[7]),
    .I1(clock_count[8]) 
);
defparam n200_s6.INIT=4'h2;
  LUT4 n200_s7 (
    .F(n200_10),
    .I0(state[0]),
    .I1(bit_index[0]),
    .I2(bit_index[1]),
    .I3(bit_index[2]) 
);
defparam n200_s7.INIT=16'h1555;
  LUT4 n328_s10 (
    .F(n328_14),
    .I0(clock_count[12]),
    .I1(clock_count[13]),
    .I2(clock_count[14]),
    .I3(clock_count[15]) 
);
defparam n328_s10.INIT=16'h0001;
  LUT4 n328_s11 (
    .F(n328_15),
    .I0(clock_count[4]),
    .I1(clock_count[9]),
    .I2(clock_count[10]),
    .I3(clock_count[11]) 
);
defparam n328_s11.INIT=16'h0002;
  LUT4 n328_s12 (
    .F(n328_16),
    .I0(clock_count[16]),
    .I1(clock_count[17]),
    .I2(clock_count[18]),
    .I3(clock_count[19]) 
);
defparam n328_s12.INIT=16'h0001;
  LUT4 n328_s13 (
    .F(n328_17),
    .I0(clock_count[28]),
    .I1(clock_count[29]),
    .I2(clock_count[30]),
    .I3(clock_count[31]) 
);
defparam n328_s13.INIT=16'h0001;
  LUT4 n328_s14 (
    .F(n328_18),
    .I0(clock_count[20]),
    .I1(clock_count[21]),
    .I2(clock_count[22]),
    .I3(clock_count[23]) 
);
defparam n328_s14.INIT=16'h0001;
  LUT4 n328_s15 (
    .F(n328_19),
    .I0(clock_count[24]),
    .I1(clock_count[25]),
    .I2(clock_count[26]),
    .I3(clock_count[27]) 
);
defparam n328_s15.INIT=16'h0001;
  LUT4 n328_s16 (
    .F(n328_20),
    .I0(clock_count[5]),
    .I1(clock_count[6]),
    .I2(clock_count[7]),
    .I3(clock_count[8]) 
);
defparam n328_s16.INIT=16'h2000;
  LUT4 n338_s7 (
    .F(n338_11),
    .I0(state[0]),
    .I1(bit_index[0]),
    .I2(bit_index[1]),
    .I3(state[1]) 
);
defparam n338_s7.INIT=16'h4000;
  LUT4 n339_s7 (
    .F(n339_11),
    .I0(state[0]),
    .I1(bit_index[0]),
    .I2(bit_index[1]),
    .I3(state[1]) 
);
defparam n339_s7.INIT=16'h1000;
  LUT4 n340_s7 (
    .F(n340_11),
    .I0(state[0]),
    .I1(bit_index[0]),
    .I2(bit_index[1]),
    .I3(state[1]) 
);
defparam n340_s7.INIT=16'h0400;
  LUT4 n341_s7 (
    .F(n341_11),
    .I0(state[0]),
    .I1(bit_index[0]),
    .I2(bit_index[1]),
    .I3(state[1]) 
);
defparam n341_s7.INIT=16'h0100;
  LUT2 n325_s10 (
    .F(n325_18),
    .I0(state[0]),
    .I1(state[1]) 
);
defparam n325_s10.INIT=4'h2;
  LUT3 n318_s9 (
    .F(n318_17),
    .I0(clock_count[4]),
    .I1(clock_count[5]),
    .I2(clock_count[6]) 
);
defparam n318_s9.INIT=8'h80;
  LUT4 n314_s9 (
    .F(n314_17),
    .I0(clock_count[7]),
    .I1(clock_count[8]),
    .I2(clock_count[9]),
    .I3(clock_count[10]) 
);
defparam n314_s9.INIT=16'h8000;
  LUT4 n310_s9 (
    .F(n310_17),
    .I0(clock_count[11]),
    .I1(clock_count[12]),
    .I2(clock_count[13]),
    .I3(clock_count[14]) 
);
defparam n310_s9.INIT=16'h8000;
  LUT2 n309_s9 (
    .F(n309_17),
    .I0(clock_count[15]),
    .I1(n310_17) 
);
defparam n309_s9.INIT=4'h8;
  LUT2 n306_s9 (
    .F(n306_17),
    .I0(clock_count[17]),
    .I1(clock_count[18]) 
);
defparam n306_s9.INIT=4'h8;
  LUT4 n305_s9 (
    .F(n305_17),
    .I0(clock_count[16]),
    .I1(clock_count[17]),
    .I2(clock_count[18]),
    .I3(clock_count[19]) 
);
defparam n305_s9.INIT=16'h8000;
  LUT2 n303_s9 (
    .F(n303_17),
    .I0(clock_count[20]),
    .I1(clock_count[21]) 
);
defparam n303_s9.INIT=4'h8;
  LUT4 n302_s9 (
    .F(n302_17),
    .I0(clock_count[15]),
    .I1(n310_17),
    .I2(n305_17),
    .I3(n302_18) 
);
defparam n302_s9.INIT=16'h8000;
  LUT2 n300_s9 (
    .F(n300_17),
    .I0(clock_count[23]),
    .I1(clock_count[24]) 
);
defparam n300_s9.INIT=4'h8;
  LUT3 n299_s9 (
    .F(n299_17),
    .I0(clock_count[23]),
    .I1(clock_count[24]),
    .I2(clock_count[25]) 
);
defparam n299_s9.INIT=8'h80;
  LUT2 n297_s9 (
    .F(n297_17),
    .I0(clock_count[26]),
    .I1(clock_count[27]) 
);
defparam n297_s9.INIT=4'h8;
  LUT3 n296_s9 (
    .F(n296_17),
    .I0(clock_count[26]),
    .I1(clock_count[27]),
    .I2(clock_count[28]) 
);
defparam n296_s9.INIT=8'h80;
  LUT3 n295_s9 (
    .F(n295_17),
    .I0(clock_count[29]),
    .I1(n299_17),
    .I2(n296_17) 
);
defparam n295_s9.INIT=8'h80;
  LUT3 n302_s10 (
    .F(n302_18),
    .I0(clock_count[20]),
    .I1(clock_count[21]),
    .I2(clock_count[22]) 
);
defparam n302_s10.INIT=8'h80;
  LUT3 n325_s12 (
    .F(n325_21),
    .I0(n200_8),
    .I1(clock_count[7]),
    .I2(clock_count[8]) 
);
defparam n325_s12.INIT=8'h08;
  LUT4 n318_s10 (
    .F(n318_19),
    .I0(n321_16),
    .I1(clock_count[4]),
    .I2(clock_count[5]),
    .I3(clock_count[6]) 
);
defparam n318_s10.INIT=16'h8000;
  LUT4 n319_s9 (
    .F(n319_18),
    .I0(clock_count[5]),
    .I1(clock_count[6]),
    .I2(clock_count[4]),
    .I3(n321_16) 
);
defparam n319_s9.INIT=16'h9333;
  LUT4 n322_s9 (
    .F(n322_18),
    .I0(clock_count[2]),
    .I1(clock_count[3]),
    .I2(clock_count[0]),
    .I3(clock_count[1]) 
);
defparam n322_s9.INIT=16'h9333;
  LUT4 n309_s10 (
    .F(n309_19),
    .I0(clock_count[16]),
    .I1(n314_16),
    .I2(clock_count[15]),
    .I3(n310_17) 
);
defparam n309_s10.INIT=16'h9555;
  LUT4 n302_s11 (
    .F(n302_20),
    .I0(n321_16),
    .I1(n318_17),
    .I2(n314_17),
    .I3(n302_17) 
);
defparam n302_s11.INIT=16'h8000;
  LUT4 n348_s7 (
    .F(n348_14),
    .I0(bit_index[0]),
    .I1(state[1]),
    .I2(state[0]),
    .I3(bit_index_2_9) 
);
defparam n348_s7.INIT=16'hAAA4;
  LUT2 bit_index_2_s5 (
    .F(bit_index_2_11),
    .I0(state[0]),
    .I1(bit_index_2_9) 
);
defparam bit_index_2_s5.INIT=4'h1;
  DFFPE rx_sync_s0 (
    .Q(rx_sync),
    .D(rx_meta),
    .CLK(clk_50m_i_d),
    .PRESET(n177_5),
    .CE(VCC) 
);
defparam rx_sync_s0.INIT=1'b1;
  DFFCE clock_count_31_s0 (
    .Q(clock_count[31]),
    .D(n294_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_31_s0.INIT=1'b0;
  DFFCE clock_count_30_s0 (
    .Q(clock_count[30]),
    .D(n295_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_30_s0.INIT=1'b0;
  DFFCE clock_count_29_s0 (
    .Q(clock_count[29]),
    .D(n296_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_29_s0.INIT=1'b0;
  DFFCE clock_count_28_s0 (
    .Q(clock_count[28]),
    .D(n297_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_28_s0.INIT=1'b0;
  DFFCE clock_count_27_s0 (
    .Q(clock_count[27]),
    .D(n298_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_27_s0.INIT=1'b0;
  DFFCE clock_count_26_s0 (
    .Q(clock_count[26]),
    .D(n299_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_26_s0.INIT=1'b0;
  DFFCE clock_count_25_s0 (
    .Q(clock_count[25]),
    .D(n300_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_25_s0.INIT=1'b0;
  DFFCE clock_count_24_s0 (
    .Q(clock_count[24]),
    .D(n301_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_24_s0.INIT=1'b0;
  DFFCE clock_count_23_s0 (
    .Q(clock_count[23]),
    .D(n302_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_23_s0.INIT=1'b0;
  DFFCE clock_count_22_s0 (
    .Q(clock_count[22]),
    .D(n303_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_22_s0.INIT=1'b0;
  DFFCE clock_count_21_s0 (
    .Q(clock_count[21]),
    .D(n304_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_21_s0.INIT=1'b0;
  DFFCE clock_count_20_s0 (
    .Q(clock_count[20]),
    .D(n305_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_20_s0.INIT=1'b0;
  DFFCE clock_count_19_s0 (
    .Q(clock_count[19]),
    .D(n306_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_19_s0.INIT=1'b0;
  DFFCE clock_count_18_s0 (
    .Q(clock_count[18]),
    .D(n307_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_18_s0.INIT=1'b0;
  DFFCE clock_count_17_s0 (
    .Q(clock_count[17]),
    .D(n308_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_17_s0.INIT=1'b0;
  DFFCE clock_count_16_s0 (
    .Q(clock_count[16]),
    .D(n309_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_16_s0.INIT=1'b0;
  DFFCE clock_count_15_s0 (
    .Q(clock_count[15]),
    .D(n310_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_15_s0.INIT=1'b0;
  DFFCE clock_count_14_s0 (
    .Q(clock_count[14]),
    .D(n311_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_14_s0.INIT=1'b0;
  DFFCE clock_count_13_s0 (
    .Q(clock_count[13]),
    .D(n312_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_13_s0.INIT=1'b0;
  DFFCE clock_count_12_s0 (
    .Q(clock_count[12]),
    .D(n313_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_12_s0.INIT=1'b0;
  DFFCE clock_count_11_s0 (
    .Q(clock_count[11]),
    .D(n314_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_11_s0.INIT=1'b0;
  DFFCE clock_count_10_s0 (
    .Q(clock_count[10]),
    .D(n315_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_10_s0.INIT=1'b0;
  DFFCE clock_count_9_s0 (
    .Q(clock_count[9]),
    .D(n316_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_9_s0.INIT=1'b0;
  DFFCE clock_count_8_s0 (
    .Q(clock_count[8]),
    .D(n317_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_8_s0.INIT=1'b0;
  DFFCE clock_count_7_s0 (
    .Q(clock_count[7]),
    .D(n318_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_7_s0.INIT=1'b0;
  DFFCE clock_count_6_s0 (
    .Q(clock_count[6]),
    .D(n319_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_6_s0.INIT=1'b0;
  DFFCE clock_count_5_s0 (
    .Q(clock_count[5]),
    .D(n320_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_5_s0.INIT=1'b0;
  DFFCE clock_count_4_s0 (
    .Q(clock_count[4]),
    .D(n321_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_4_s0.INIT=1'b0;
  DFFCE clock_count_3_s0 (
    .Q(clock_count[3]),
    .D(n322_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_3_s0.INIT=1'b0;
  DFFCE clock_count_2_s0 (
    .Q(clock_count[2]),
    .D(n323_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_2_s0.INIT=1'b0;
  DFFCE clock_count_1_s0 (
    .Q(clock_count[1]),
    .D(n324_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_1_s0.INIT=1'b0;
  DFFCE clock_count_0_s0 (
    .Q(clock_count[0]),
    .D(n325_16),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam clock_count_0_s0.INIT=1'b0;
  DFFCE shift_reg_7_s0 (
    .Q(shift_reg[7]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n338_9) 
);
  DFFCE shift_reg_6_s0 (
    .Q(shift_reg[6]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n339_9) 
);
  DFFCE shift_reg_5_s0 (
    .Q(shift_reg[5]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n340_9) 
);
  DFFCE shift_reg_4_s0 (
    .Q(shift_reg[4]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n341_9) 
);
  DFFCE shift_reg_3_s0 (
    .Q(shift_reg[3]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n342_9) 
);
  DFFCE shift_reg_2_s0 (
    .Q(shift_reg[2]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n343_9) 
);
  DFFCE shift_reg_1_s0 (
    .Q(shift_reg[1]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n344_9) 
);
  DFFCE shift_reg_0_s0 (
    .Q(shift_reg[0]),
    .D(rx_sync),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n345_9) 
);
  DFFCE data_o_7_s0 (
    .Q(rx_data[7]),
    .D(shift_reg[7]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_6_s0 (
    .Q(rx_data[6]),
    .D(shift_reg[6]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_5_s0 (
    .Q(rx_data[5]),
    .D(shift_reg[5]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_4_s0 (
    .Q(rx_data[4]),
    .D(shift_reg[4]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_3_s0 (
    .Q(rx_data[3]),
    .D(shift_reg[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_2_s0 (
    .Q(rx_data[2]),
    .D(shift_reg[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_1_s0 (
    .Q(rx_data[1]),
    .D(shift_reg[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_o_0_s0 (
    .Q(rx_data[0]),
    .D(shift_reg[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n328_9) 
);
  DFFCE data_valid_o_s0 (
    .Q(rx_valid),
    .D(n328_9),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam data_valid_o_s0.INIT=1'b0;
  DFFCE framing_error_o_s0 (
    .Q(rx_frame_error),
    .D(n337_13),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam framing_error_o_s0.INIT=1'b0;
  DFFPE rx_meta_s0 (
    .Q(rx_meta),
    .D(tof0_uart_rx_i_d),
    .CLK(clk_50m_i_d),
    .PRESET(n177_5),
    .CE(VCC) 
);
defparam rx_meta_s0.INIT=1'b1;
  DFFCE state_1_s1 (
    .Q(state[1]),
    .D(n326_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n200_3) 
);
defparam state_1_s1.INIT=1'b0;
  DFFCE state_0_s1 (
    .Q(state[0]),
    .D(n327_15),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n200_3) 
);
defparam state_0_s1.INIT=1'b0;
  DFFCE bit_index_2_s1 (
    .Q(bit_index[2]),
    .D(n346_11),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(bit_index_2_11) 
);
defparam bit_index_2_s1.INIT=1'b0;
  DFFCE bit_index_1_s1 (
    .Q(bit_index[1]),
    .D(n347_11),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(bit_index_2_11) 
);
defparam bit_index_1_s1.INIT=1'b0;
  DFFCE bit_index_0_s3 (
    .Q(bit_index[0]),
    .D(n348_14),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam bit_index_0_s3.INIT=1'b0;
  INV n327_s7 (
    .O(n327_15),
    .I(state[0]) 
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule