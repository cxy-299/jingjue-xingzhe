module system_mapped_target (
  clk_50m_i_d,
  n177_5,
  n1712_2,
  inverted,
  \g_heading.requested_angle ,
  turn_yaw,
  converted_valid,
  wrapped_target
)
;
input clk_50m_i_d;
input n177_5;
input n1712_2;
input inverted;
input [15:0] \g_heading.requested_angle ;
input [15:0] turn_yaw;
output converted_valid;
output [15:0] wrapped_target;
wire n317_3;
wire n318_3;
wire n319_3;
wire n320_3;
wire n321_3;
wire n322_3;
wire n323_3;
wire n324_3;
wire n325_3;
wire n326_3;
wire n327_3;
wire n328_3;
wire n329_3;
wire n330_3;
wire n331_3;
wire n332_3;
wire n333_3;
wire n416_3;
wire n417_3;
wire n418_3;
wire n419_3;
wire n420_3;
wire n421_3;
wire n422_3;
wire n423_3;
wire n424_3;
wire n425_3;
wire n426_3;
wire n318_4;
wire n319_4;
wire n322_4;
wire n322_5;
wire n325_5;
wire n327_4;
wire n327_5;
wire n328_4;
wire n331_4;
wire n416_5;
wire n418_4;
wire n420_6;
wire n421_4;
wire n421_5;
wire n423_4;
wire n423_5;
wire n424_4;
wire n424_5;
wire n425_4;
wire n425_5;
wire n426_4;
wire n318_6;
wire n318_7;
wire n416_6;
wire n416_7;
wire n416_8;
wire n416_9;
wire n416_10;
wire n416_11;
wire n418_6;
wire n420_7;
wire n420_8;
wire n420_9;
wire n421_6;
wire n424_6;
wire n416_12;
wire n416_13;
wire n416_14;
wire n416_15;
wire n416_16;
wire n416_17;
wire n416_18;
wire n416_19;
wire n416_20;
wire n416_21;
wire n416_22;
wire n318_9;
wire n418_8;
wire n420_13;
wire n427_6;
wire n325_7;
wire n420_15;
wire n416_24;
wire n317_6;
wire inv1;
wire inv2;
wire n52_1;
wire n52_2;
wire n51_1;
wire n51_2;
wire n50_1;
wire n50_2;
wire n49_1;
wire n49_2;
wire n48_1;
wire n48_2;
wire n47_1;
wire n47_2;
wire n46_1;
wire n46_2;
wire n45_1;
wire n45_2;
wire n44_1;
wire n44_2;
wire n43_1;
wire n43_2;
wire n42_1;
wire n42_2;
wire n41_1;
wire n41_2;
wire n40_1;
wire n40_2;
wire n39_1;
wire n39_2;
wire n38_1;
wire n38_2;
wire n353_1;
wire n353_2;
wire n352_1;
wire n352_2;
wire n351_1;
wire n351_2;
wire n350_1;
wire n350_2;
wire n349_1;
wire n349_2;
wire n348_1;
wire n348_2;
wire n347_1;
wire n347_2;
wire n346_1;
wire n346_2;
wire n345_1;
wire n345_2;
wire n344_1;
wire n344_2;
wire n343_1;
wire n343_2;
wire n342_1;
wire n342_2;
wire n341_1;
wire n341_2;
wire n340_1;
wire n340_2;
wire n339_1;
wire n339_2;
wire n338_1;
wire n338_2;
wire n337_1;
wire n337_2;
wire n336_1;
wire n336_0_COUT;
wire n200_2;
wire n200_3;
wire n199_2;
wire n199_3;
wire n198_2;
wire n198_3;
wire n197_2;
wire n197_3;
wire n196_2;
wire n196_3;
wire n195_2;
wire n195_3;
wire n194_2;
wire n194_3;
wire n193_2;
wire n193_3;
wire n192_2;
wire n192_3;
wire n191_2;
wire n191_3;
wire n190_2;
wire n190_3;
wire n189_2;
wire n189_3;
wire n188_2;
wire n188_3;
wire n187_2;
wire n187_3;
wire n186_2;
wire n186_3;
wire n185_2;
wire n185_3;
wire n184_2;
wire n184_3;
wire n183_2;
wire n183_3;
wire n182_2;
wire n182_3;
wire n181_2;
wire n181_3;
wire n180_2;
wire n180_3;
wire n179_2;
wire n179_3;
wire n178_2;
wire n178_3;
wire n177_2;
wire n177_3;
wire n176_2;
wire n176_3;
wire n175_2;
wire n175_3;
wire n174_2;
wire n174_0_COUT;
wire n74_2;
wire n74_3;
wire n73_2;
wire n73_3;
wire n72_2;
wire n72_3;
wire n71_2;
wire n71_3;
wire n70_2;
wire n70_3;
wire n69_2;
wire n69_3;
wire n68_2;
wire n68_3;
wire n67_2;
wire n67_3;
wire n66_2;
wire n66_3;
wire n65_2;
wire n65_3;
wire n64_2;
wire n64_3;
wire n63_2;
wire n63_3;
wire n62_2;
wire n62_3;
wire n61_2;
wire n61_3;
wire n60_2;
wire n60_3;
wire [3:0] valid_q;
wire [26:0] hi_q;
wire [26:0] lo_q;
wire [26:0] product_q;
wire [17:0] delta_q;
wire [17:0] sum_q;
wire [15:0] yaw0;
wire [15:0] yaw1;
wire [15:0] yaw2;
wire VCC;
wire GND;
  LUT4 n317_s0 (
    .F(n317_3),
    .I0(delta_q[17]),
    .I1(inv2),
    .I2(delta_q[16]),
    .I3(n317_6) 
);
defparam n317_s0.INIT=16'h6A66;
  LUT4 n318_s0 (
    .F(n318_3),
    .I0(inv2),
    .I1(delta_q[16]),
    .I2(n318_4),
    .I3(n318_9) 
);
defparam n318_s0.INIT=16'hC666;
  LUT4 n319_s0 (
    .F(n319_3),
    .I0(inv2),
    .I1(delta_q[15]),
    .I2(n318_4),
    .I3(n319_4) 
);
defparam n319_s0.INIT=16'hC666;
  LUT4 n320_s0 (
    .F(n320_3),
    .I0(inv2),
    .I1(delta_q[14]),
    .I2(delta_q[13]),
    .I3(n318_4) 
);
defparam n320_s0.INIT=16'h6C66;
  LUT3 n321_s0 (
    .F(n321_3),
    .I0(inv2),
    .I1(delta_q[13]),
    .I2(n318_4) 
);
defparam n321_s0.INIT=8'hC6;
  LUT4 n322_s0 (
    .F(n322_3),
    .I0(inv2),
    .I1(delta_q[12]),
    .I2(n322_4),
    .I3(n322_5) 
);
defparam n322_s0.INIT=16'hC666;
  LUT4 n323_s0 (
    .F(n323_3),
    .I0(inv2),
    .I1(delta_q[11]),
    .I2(delta_q[10]),
    .I3(n322_4) 
);
defparam n323_s0.INIT=16'h6C66;
  LUT3 n324_s0 (
    .F(n324_3),
    .I0(inv2),
    .I1(delta_q[10]),
    .I2(n322_4) 
);
defparam n324_s0.INIT=8'hC6;
  LUT4 n325_s0 (
    .F(n325_3),
    .I0(inv2),
    .I1(delta_q[9]),
    .I2(n325_7),
    .I3(n325_5) 
);
defparam n325_s0.INIT=16'hC666;
  LUT4 n326_s0 (
    .F(n326_3),
    .I0(inv2),
    .I1(delta_q[8]),
    .I2(delta_q[7]),
    .I3(n325_7) 
);
defparam n326_s0.INIT=16'h6C66;
  LUT4 n327_s0 (
    .F(n327_3),
    .I0(inv2),
    .I1(delta_q[7]),
    .I2(n327_4),
    .I3(n327_5) 
);
defparam n327_s0.INIT=16'hC666;
  LUT4 n328_s0 (
    .F(n328_3),
    .I0(inv2),
    .I1(delta_q[6]),
    .I2(n327_4),
    .I3(n328_4) 
);
defparam n328_s0.INIT=16'hC666;
  LUT4 n329_s0 (
    .F(n329_3),
    .I0(inv2),
    .I1(delta_q[5]),
    .I2(delta_q[4]),
    .I3(n327_4) 
);
defparam n329_s0.INIT=16'h6C66;
  LUT3 n330_s0 (
    .F(n330_3),
    .I0(inv2),
    .I1(delta_q[4]),
    .I2(n327_4) 
);
defparam n330_s0.INIT=8'hC6;
  LUT2 n331_s0 (
    .F(n331_3),
    .I0(delta_q[3]),
    .I1(n331_4) 
);
defparam n331_s0.INIT=4'h6;
  LUT4 n332_s0 (
    .F(n332_3),
    .I0(inv2),
    .I1(delta_q[2]),
    .I2(delta_q[1]),
    .I3(delta_q[0]) 
);
defparam n332_s0.INIT=16'h666C;
  LUT3 n333_s0 (
    .F(n333_3),
    .I0(inv2),
    .I1(delta_q[1]),
    .I2(delta_q[0]) 
);
defparam n333_s0.INIT=8'h6C;
  LUT4 n416_s0 (
    .F(n416_3),
    .I0(sum_q[15]),
    .I1(sum_q[14]),
    .I2(n416_24),
    .I3(n416_5) 
);
defparam n416_s0.INIT=16'h596A;
  LUT3 n417_s0 (
    .F(n417_3),
    .I0(sum_q[14]),
    .I1(n416_24),
    .I2(n416_5) 
);
defparam n417_s0.INIT=8'h56;
  LUT4 n418_s0 (
    .F(n418_3),
    .I0(sum_q[13]),
    .I1(sum_q[12]),
    .I2(n418_4),
    .I3(n418_8) 
);
defparam n418_s0.INIT=16'h569A;
  LUT3 n419_s0 (
    .F(n419_3),
    .I0(sum_q[12]),
    .I1(n418_4),
    .I2(n418_8) 
);
defparam n419_s0.INIT=8'h56;
  LUT4 n420_s0 (
    .F(n420_3),
    .I0(sum_q[11]),
    .I1(n420_15),
    .I2(n420_13),
    .I3(n420_6) 
);
defparam n420_s0.INIT=16'h55A6;
  LUT4 n421_s0 (
    .F(n421_3),
    .I0(sum_q[10]),
    .I1(sum_q[9]),
    .I2(n421_4),
    .I3(n421_5) 
);
defparam n421_s0.INIT=16'h569A;
  LUT3 n422_s0 (
    .F(n422_3),
    .I0(sum_q[9]),
    .I1(n421_4),
    .I2(n421_5) 
);
defparam n422_s0.INIT=8'h56;
  LUT4 n423_s0 (
    .F(n423_3),
    .I0(sum_q[8]),
    .I1(n420_15),
    .I2(n423_4),
    .I3(n423_5) 
);
defparam n423_s0.INIT=16'h55A6;
  LUT4 n424_s0 (
    .F(n424_3),
    .I0(sum_q[7]),
    .I1(n424_4),
    .I2(n420_15),
    .I3(n424_5) 
);
defparam n424_s0.INIT=16'h556A;
  LUT4 n425_s0 (
    .F(n425_3),
    .I0(sum_q[6]),
    .I1(sum_q[17]),
    .I2(n425_4),
    .I3(n425_5) 
);
defparam n425_s0.INIT=16'h596A;
  LUT4 n426_s0 (
    .F(n426_3),
    .I0(sum_q[5]),
    .I1(sum_q[4]),
    .I2(n420_15),
    .I3(n426_4) 
);
defparam n426_s0.INIT=16'h969A;
  LUT4 n318_s1 (
    .F(n318_4),
    .I0(n327_4),
    .I1(n327_5),
    .I2(n318_6),
    .I3(n318_7) 
);
defparam n318_s1.INIT=16'h8000;
  LUT2 n319_s1 (
    .F(n319_4),
    .I0(delta_q[14]),
    .I1(delta_q[13]) 
);
defparam n319_s1.INIT=4'h1;
  LUT3 n322_s1 (
    .F(n322_4),
    .I0(n327_4),
    .I1(n327_5),
    .I2(n318_6) 
);
defparam n322_s1.INIT=8'h80;
  LUT2 n322_s2 (
    .F(n322_5),
    .I0(delta_q[11]),
    .I1(delta_q[10]) 
);
defparam n322_s2.INIT=4'h1;
  LUT2 n325_s2 (
    .F(n325_5),
    .I0(delta_q[8]),
    .I1(delta_q[7]) 
);
defparam n325_s2.INIT=4'h1;
  LUT4 n327_s1 (
    .F(n327_4),
    .I0(delta_q[3]),
    .I1(delta_q[2]),
    .I2(delta_q[1]),
    .I3(delta_q[0]) 
);
defparam n327_s1.INIT=16'h0001;
  LUT3 n327_s2 (
    .F(n327_5),
    .I0(delta_q[6]),
    .I1(delta_q[5]),
    .I2(delta_q[4]) 
);
defparam n327_s2.INIT=8'h01;
  LUT2 n328_s1 (
    .F(n328_4),
    .I0(delta_q[5]),
    .I1(delta_q[4]) 
);
defparam n328_s1.INIT=4'h1;
  LUT4 n331_s1 (
    .F(n331_4),
    .I0(inv2),
    .I1(delta_q[2]),
    .I2(delta_q[1]),
    .I3(delta_q[0]) 
);
defparam n331_s1.INIT=16'hAAA8;
  LUT4 n416_s2 (
    .F(n416_5),
    .I0(sum_q[17]),
    .I1(n416_9),
    .I2(n416_10),
    .I3(n416_11) 
);
defparam n416_s2.INIT=16'h008A;
  LUT4 n418_s1 (
    .F(n418_4),
    .I0(sum_q[17]),
    .I1(n416_6),
    .I2(n416_7),
    .I3(n418_6) 
);
defparam n418_s1.INIT=16'h0051;
  LUT3 n420_s3 (
    .F(n420_6),
    .I0(sum_q[17]),
    .I1(n420_9),
    .I2(n416_11) 
);
defparam n420_s3.INIT=8'h02;
  LUT4 n421_s1 (
    .F(n421_4),
    .I0(sum_q[17]),
    .I1(n416_6),
    .I2(n416_7),
    .I3(n420_7) 
);
defparam n421_s1.INIT=16'h0051;
  LUT4 n421_s2 (
    .F(n421_5),
    .I0(sum_q[8]),
    .I1(sum_q[17]),
    .I2(n421_6),
    .I3(n416_11) 
);
defparam n421_s2.INIT=16'h00C8;
  LUT4 n423_s1 (
    .F(n423_4),
    .I0(sum_q[7]),
    .I1(sum_q[6]),
    .I2(sum_q[5]),
    .I3(sum_q[4]) 
);
defparam n423_s1.INIT=16'h0001;
  LUT3 n423_s2 (
    .F(n423_5),
    .I0(sum_q[17]),
    .I1(n421_6),
    .I2(n416_11) 
);
defparam n423_s2.INIT=8'h02;
  LUT3 n424_s1 (
    .F(n424_4),
    .I0(sum_q[6]),
    .I1(sum_q[5]),
    .I2(sum_q[4]) 
);
defparam n424_s1.INIT=8'h01;
  LUT4 n424_s2 (
    .F(n424_5),
    .I0(sum_q[5]),
    .I1(sum_q[4]),
    .I2(n416_11),
    .I3(n424_6) 
);
defparam n424_s2.INIT=16'h0800;
  LUT3 n425_s1 (
    .F(n425_4),
    .I0(sum_q[5]),
    .I1(sum_q[4]),
    .I2(n416_11) 
);
defparam n425_s1.INIT=8'h08;
  LUT4 n425_s2 (
    .F(n425_5),
    .I0(sum_q[5]),
    .I1(sum_q[4]),
    .I2(n416_6),
    .I3(n416_7) 
);
defparam n425_s2.INIT=16'h1101;
  LUT2 n426_s1 (
    .F(n426_4),
    .I0(sum_q[17]),
    .I1(n416_11) 
);
defparam n426_s1.INIT=4'h2;
  LUT3 n318_s3 (
    .F(n318_6),
    .I0(delta_q[9]),
    .I1(delta_q[8]),
    .I2(delta_q[7]) 
);
defparam n318_s3.INIT=8'h01;
  LUT3 n318_s4 (
    .F(n318_7),
    .I0(delta_q[12]),
    .I1(delta_q[11]),
    .I2(delta_q[10]) 
);
defparam n318_s4.INIT=8'h01;
  LUT2 n416_s3 (
    .F(n416_6),
    .I0(sum_q[15]),
    .I1(sum_q[16]) 
);
defparam n416_s3.INIT=4'h1;
  LUT4 n416_s4 (
    .F(n416_7),
    .I0(sum_q[10]),
    .I1(n416_12),
    .I2(n416_13),
    .I3(n416_14) 
);
defparam n416_s4.INIT=16'h3B00;
  LUT4 n416_s5 (
    .F(n416_8),
    .I0(sum_q[13]),
    .I1(sum_q[12]),
    .I2(sum_q[17]),
    .I3(n418_6) 
);
defparam n416_s5.INIT=16'h0F0E;
  LUT2 n416_s6 (
    .F(n416_9),
    .I0(sum_q[11]),
    .I1(n420_9) 
);
defparam n416_s6.INIT=4'h1;
  LUT2 n416_s7 (
    .F(n416_10),
    .I0(sum_q[13]),
    .I1(sum_q[12]) 
);
defparam n416_s7.INIT=4'h8;
  LUT4 n416_s8 (
    .F(n416_11),
    .I0(n416_15),
    .I1(n416_16),
    .I2(n416_17),
    .I3(n416_18) 
);
defparam n416_s8.INIT=16'h20F0;
  LUT4 n418_s3 (
    .F(n418_6),
    .I0(sum_q[11]),
    .I1(sum_q[8]),
    .I2(n423_4),
    .I3(n420_8) 
);
defparam n418_s3.INIT=16'h08AA;
  LUT2 n420_s4 (
    .F(n420_7),
    .I0(sum_q[8]),
    .I1(n423_4) 
);
defparam n420_s4.INIT=4'h2;
  LUT2 n420_s5 (
    .F(n420_8),
    .I0(sum_q[10]),
    .I1(sum_q[9]) 
);
defparam n420_s5.INIT=4'h1;
  LUT4 n420_s6 (
    .F(n420_9),
    .I0(sum_q[10]),
    .I1(sum_q[9]),
    .I2(sum_q[8]),
    .I3(n421_6) 
);
defparam n420_s6.INIT=16'h8880;
  LUT4 n421_s3 (
    .F(n421_6),
    .I0(sum_q[7]),
    .I1(sum_q[6]),
    .I2(sum_q[5]),
    .I3(sum_q[4]) 
);
defparam n421_s3.INIT=16'h8000;
  LUT2 n424_s3 (
    .F(n424_6),
    .I0(sum_q[6]),
    .I1(sum_q[17]) 
);
defparam n424_s3.INIT=4'h8;
  LUT2 n416_s9 (
    .F(n416_12),
    .I0(sum_q[12]),
    .I1(sum_q[11]) 
);
defparam n416_s9.INIT=4'h1;
  LUT4 n416_s10 (
    .F(n416_13),
    .I0(sum_q[7]),
    .I1(n424_4),
    .I2(n416_19),
    .I3(n416_20) 
);
defparam n416_s10.INIT=16'h5D00;
  LUT2 n416_s11 (
    .F(n416_14),
    .I0(sum_q[14]),
    .I1(sum_q[13]) 
);
defparam n416_s11.INIT=4'h8;
  LUT2 n416_s12 (
    .F(n416_15),
    .I0(sum_q[12]),
    .I1(sum_q[11]) 
);
defparam n416_s12.INIT=4'h8;
  LUT4 n416_s13 (
    .F(n416_16),
    .I0(sum_q[10]),
    .I1(sum_q[7]),
    .I2(n416_21),
    .I3(n416_22) 
);
defparam n416_s13.INIT=16'h0155;
  LUT2 n416_s14 (
    .F(n416_17),
    .I0(sum_q[15]),
    .I1(sum_q[16]) 
);
defparam n416_s14.INIT=4'h8;
  LUT2 n416_s15 (
    .F(n416_18),
    .I0(sum_q[14]),
    .I1(sum_q[13]) 
);
defparam n416_s15.INIT=4'h1;
  LUT4 n416_s16 (
    .F(n416_19),
    .I0(sum_q[0]),
    .I1(sum_q[1]),
    .I2(sum_q[2]),
    .I3(sum_q[3]) 
);
defparam n416_s16.INIT=16'hFE00;
  LUT2 n416_s17 (
    .F(n416_20),
    .I0(sum_q[9]),
    .I1(sum_q[8]) 
);
defparam n416_s17.INIT=4'h1;
  LUT4 n416_s18 (
    .F(n416_21),
    .I0(sum_q[6]),
    .I1(sum_q[5]),
    .I2(sum_q[4]),
    .I3(sum_q[3]) 
);
defparam n416_s18.INIT=16'h8000;
  LUT2 n416_s19 (
    .F(n416_22),
    .I0(sum_q[9]),
    .I1(sum_q[8]) 
);
defparam n416_s19.INIT=4'h8;
  LUT3 n318_s5 (
    .F(n318_9),
    .I0(delta_q[15]),
    .I1(delta_q[14]),
    .I2(delta_q[13]) 
);
defparam n318_s5.INIT=8'h01;
  LUT4 n418_s4 (
    .F(n418_8),
    .I0(sum_q[17]),
    .I1(sum_q[11]),
    .I2(n420_9),
    .I3(n416_11) 
);
defparam n418_s4.INIT=16'h00A8;
  LUT4 n420_s8 (
    .F(n420_13),
    .I0(sum_q[8]),
    .I1(n423_4),
    .I2(sum_q[10]),
    .I3(sum_q[9]) 
);
defparam n420_s8.INIT=16'h000D;
  LUT4 n427_s2 (
    .F(n427_6),
    .I0(sum_q[4]),
    .I1(n420_15),
    .I2(sum_q[17]),
    .I3(n416_11) 
);
defparam n427_s2.INIT=16'h6656;
  LUT4 n325_s3 (
    .F(n325_7),
    .I0(n327_4),
    .I1(delta_q[6]),
    .I2(delta_q[5]),
    .I3(delta_q[4]) 
);
defparam n325_s3.INIT=16'h0002;
  LUT4 n420_s9 (
    .F(n420_15),
    .I0(sum_q[17]),
    .I1(sum_q[15]),
    .I2(sum_q[16]),
    .I3(n416_7) 
);
defparam n420_s9.INIT=16'h5554;
  LUT4 n416_s20 (
    .F(n416_24),
    .I0(sum_q[15]),
    .I1(sum_q[16]),
    .I2(n416_7),
    .I3(n416_8) 
);
defparam n416_s20.INIT=16'hFE00;
  LUT4 n317_s2 (
    .F(n317_6),
    .I0(n318_4),
    .I1(delta_q[15]),
    .I2(delta_q[14]),
    .I3(delta_q[13]) 
);
defparam n317_s2.INIT=16'h0002;
  DFFCE valid_q_3_s0 (
    .Q(valid_q[3]),
    .D(valid_q[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam valid_q_3_s0.INIT=1'b0;
  DFFCE valid_q_2_s0 (
    .Q(valid_q[2]),
    .D(valid_q[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam valid_q_2_s0.INIT=1'b0;
  DFFCE valid_q_1_s0 (
    .Q(valid_q[1]),
    .D(valid_q[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam valid_q_1_s0.INIT=1'b0;
  DFFCE valid_q_0_s0 (
    .Q(valid_q[0]),
    .D(n1712_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam valid_q_0_s0.INIT=1'b0;
  DFFCE hi_q_26_s0 (
    .Q(hi_q[26]),
    .D(\g_heading.requested_angle [15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_26_s0.INIT=1'b0;
  DFFCE hi_q_25_s0 (
    .Q(hi_q[25]),
    .D(n38_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_25_s0.INIT=1'b0;
  DFFCE hi_q_24_s0 (
    .Q(hi_q[24]),
    .D(n38_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_24_s0.INIT=1'b0;
  DFFCE hi_q_23_s0 (
    .Q(hi_q[23]),
    .D(n39_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_23_s0.INIT=1'b0;
  DFFCE hi_q_22_s0 (
    .Q(hi_q[22]),
    .D(n40_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_22_s0.INIT=1'b0;
  DFFCE hi_q_21_s0 (
    .Q(hi_q[21]),
    .D(n41_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_21_s0.INIT=1'b0;
  DFFCE hi_q_20_s0 (
    .Q(hi_q[20]),
    .D(n42_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_20_s0.INIT=1'b0;
  DFFCE hi_q_19_s0 (
    .Q(hi_q[19]),
    .D(n43_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_19_s0.INIT=1'b0;
  DFFCE hi_q_18_s0 (
    .Q(hi_q[18]),
    .D(n44_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_18_s0.INIT=1'b0;
  DFFCE hi_q_17_s0 (
    .Q(hi_q[17]),
    .D(n45_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_17_s0.INIT=1'b0;
  DFFCE hi_q_16_s0 (
    .Q(hi_q[16]),
    .D(n46_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_16_s0.INIT=1'b0;
  DFFCE hi_q_15_s0 (
    .Q(hi_q[15]),
    .D(n47_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_15_s0.INIT=1'b0;
  DFFCE hi_q_14_s0 (
    .Q(hi_q[14]),
    .D(n48_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_14_s0.INIT=1'b0;
  DFFCE hi_q_13_s0 (
    .Q(hi_q[13]),
    .D(n49_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_13_s0.INIT=1'b0;
  DFFCE hi_q_12_s0 (
    .Q(hi_q[12]),
    .D(n50_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_12_s0.INIT=1'b0;
  DFFCE hi_q_11_s0 (
    .Q(hi_q[11]),
    .D(n51_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_11_s0.INIT=1'b0;
  DFFCE hi_q_10_s0 (
    .Q(hi_q[10]),
    .D(n52_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_10_s0.INIT=1'b0;
  DFFCE hi_q_9_s0 (
    .Q(hi_q[9]),
    .D(\g_heading.requested_angle [0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_9_s0.INIT=1'b0;
  DFFCE hi_q_8_s0 (
    .Q(hi_q[8]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_8_s0.INIT=1'b0;
  DFFCE hi_q_7_s0 (
    .Q(hi_q[7]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_7_s0.INIT=1'b0;
  DFFCE hi_q_6_s0 (
    .Q(hi_q[6]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_6_s0.INIT=1'b0;
  DFFCE hi_q_5_s0 (
    .Q(hi_q[5]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_5_s0.INIT=1'b0;
  DFFCE hi_q_4_s0 (
    .Q(hi_q[4]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_4_s0.INIT=1'b0;
  DFFCE hi_q_3_s0 (
    .Q(hi_q[3]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_3_s0.INIT=1'b0;
  DFFCE hi_q_2_s0 (
    .Q(hi_q[2]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_2_s0.INIT=1'b0;
  DFFCE hi_q_1_s0 (
    .Q(hi_q[1]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_1_s0.INIT=1'b0;
  DFFCE hi_q_0_s0 (
    .Q(hi_q[0]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam hi_q_0_s0.INIT=1'b0;
  DFFCE lo_q_26_s0 (
    .Q(lo_q[26]),
    .D(\g_heading.requested_angle [15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_26_s0.INIT=1'b0;
  DFFCE lo_q_25_s0 (
    .Q(lo_q[25]),
    .D(\g_heading.requested_angle [15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_25_s0.INIT=1'b0;
  DFFCE lo_q_24_s0 (
    .Q(lo_q[24]),
    .D(\g_heading.requested_angle [15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_24_s0.INIT=1'b0;
  DFFCE lo_q_23_s0 (
    .Q(lo_q[23]),
    .D(\g_heading.requested_angle [15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_23_s0.INIT=1'b0;
  DFFCE lo_q_22_s0 (
    .Q(lo_q[22]),
    .D(\g_heading.requested_angle [15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_22_s0.INIT=1'b0;
  DFFCE lo_q_21_s0 (
    .Q(lo_q[21]),
    .D(n60_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_21_s0.INIT=1'b0;
  DFFCE lo_q_20_s0 (
    .Q(lo_q[20]),
    .D(n60_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_20_s0.INIT=1'b0;
  DFFCE lo_q_19_s0 (
    .Q(lo_q[19]),
    .D(n61_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_19_s0.INIT=1'b0;
  DFFCE lo_q_18_s0 (
    .Q(lo_q[18]),
    .D(n62_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_18_s0.INIT=1'b0;
  DFFCE lo_q_17_s0 (
    .Q(lo_q[17]),
    .D(n63_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_17_s0.INIT=1'b0;
  DFFCE lo_q_16_s0 (
    .Q(lo_q[16]),
    .D(n64_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_16_s0.INIT=1'b0;
  DFFCE lo_q_15_s0 (
    .Q(lo_q[15]),
    .D(n65_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_15_s0.INIT=1'b0;
  DFFCE lo_q_14_s0 (
    .Q(lo_q[14]),
    .D(n66_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_14_s0.INIT=1'b0;
  DFFCE lo_q_13_s0 (
    .Q(lo_q[13]),
    .D(n67_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_13_s0.INIT=1'b0;
  DFFCE lo_q_12_s0 (
    .Q(lo_q[12]),
    .D(n68_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_12_s0.INIT=1'b0;
  DFFCE lo_q_11_s0 (
    .Q(lo_q[11]),
    .D(n69_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_11_s0.INIT=1'b0;
  DFFCE lo_q_10_s0 (
    .Q(lo_q[10]),
    .D(n70_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_10_s0.INIT=1'b0;
  DFFCE lo_q_9_s0 (
    .Q(lo_q[9]),
    .D(n71_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_9_s0.INIT=1'b0;
  DFFCE lo_q_8_s0 (
    .Q(lo_q[8]),
    .D(n72_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_8_s0.INIT=1'b0;
  DFFCE lo_q_7_s0 (
    .Q(lo_q[7]),
    .D(n73_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_7_s0.INIT=1'b0;
  DFFCE lo_q_6_s0 (
    .Q(lo_q[6]),
    .D(n74_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_6_s0.INIT=1'b0;
  DFFCE lo_q_5_s0 (
    .Q(lo_q[5]),
    .D(\g_heading.requested_angle [2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_5_s0.INIT=1'b0;
  DFFCE lo_q_4_s0 (
    .Q(lo_q[4]),
    .D(\g_heading.requested_angle [1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_4_s0.INIT=1'b0;
  DFFCE lo_q_3_s0 (
    .Q(lo_q[3]),
    .D(\g_heading.requested_angle [0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_3_s0.INIT=1'b0;
  DFFCE lo_q_2_s0 (
    .Q(lo_q[2]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_2_s0.INIT=1'b0;
  DFFCE lo_q_1_s0 (
    .Q(lo_q[1]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_1_s0.INIT=1'b0;
  DFFCE lo_q_0_s0 (
    .Q(lo_q[0]),
    .D(GND),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam lo_q_0_s0.INIT=1'b0;
  DFFCE product_q_26_s0 (
    .Q(product_q[26]),
    .D(n174_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_26_s0.INIT=1'b0;
  DFFCE product_q_25_s0 (
    .Q(product_q[25]),
    .D(n175_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_25_s0.INIT=1'b0;
  DFFCE product_q_24_s0 (
    .Q(product_q[24]),
    .D(n176_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_24_s0.INIT=1'b0;
  DFFCE product_q_23_s0 (
    .Q(product_q[23]),
    .D(n177_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_23_s0.INIT=1'b0;
  DFFCE product_q_22_s0 (
    .Q(product_q[22]),
    .D(n178_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_22_s0.INIT=1'b0;
  DFFCE product_q_21_s0 (
    .Q(product_q[21]),
    .D(n179_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_21_s0.INIT=1'b0;
  DFFCE product_q_20_s0 (
    .Q(product_q[20]),
    .D(n180_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_20_s0.INIT=1'b0;
  DFFCE product_q_19_s0 (
    .Q(product_q[19]),
    .D(n181_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_19_s0.INIT=1'b0;
  DFFCE product_q_18_s0 (
    .Q(product_q[18]),
    .D(n182_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_18_s0.INIT=1'b0;
  DFFCE product_q_17_s0 (
    .Q(product_q[17]),
    .D(n183_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_17_s0.INIT=1'b0;
  DFFCE product_q_16_s0 (
    .Q(product_q[16]),
    .D(n184_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_16_s0.INIT=1'b0;
  DFFCE product_q_15_s0 (
    .Q(product_q[15]),
    .D(n185_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_15_s0.INIT=1'b0;
  DFFCE product_q_14_s0 (
    .Q(product_q[14]),
    .D(n186_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_14_s0.INIT=1'b0;
  DFFCE product_q_13_s0 (
    .Q(product_q[13]),
    .D(n187_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_13_s0.INIT=1'b0;
  DFFCE product_q_12_s0 (
    .Q(product_q[12]),
    .D(n188_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_12_s0.INIT=1'b0;
  DFFCE product_q_11_s0 (
    .Q(product_q[11]),
    .D(n189_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_11_s0.INIT=1'b0;
  DFFCE product_q_10_s0 (
    .Q(product_q[10]),
    .D(n190_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_10_s0.INIT=1'b0;
  DFFCE product_q_9_s0 (
    .Q(product_q[9]),
    .D(n191_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_9_s0.INIT=1'b0;
  DFFCE product_q_8_s0 (
    .Q(product_q[8]),
    .D(n192_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_8_s0.INIT=1'b0;
  DFFCE product_q_7_s0 (
    .Q(product_q[7]),
    .D(n193_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_7_s0.INIT=1'b0;
  DFFCE product_q_6_s0 (
    .Q(product_q[6]),
    .D(n194_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_6_s0.INIT=1'b0;
  DFFCE product_q_5_s0 (
    .Q(product_q[5]),
    .D(n195_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_5_s0.INIT=1'b0;
  DFFCE product_q_4_s0 (
    .Q(product_q[4]),
    .D(n196_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_4_s0.INIT=1'b0;
  DFFCE product_q_3_s0 (
    .Q(product_q[3]),
    .D(n197_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_3_s0.INIT=1'b0;
  DFFCE product_q_2_s0 (
    .Q(product_q[2]),
    .D(n198_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_2_s0.INIT=1'b0;
  DFFCE product_q_1_s0 (
    .Q(product_q[1]),
    .D(n199_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_1_s0.INIT=1'b0;
  DFFCE product_q_0_s0 (
    .Q(product_q[0]),
    .D(n200_2),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam product_q_0_s0.INIT=1'b0;
  DFFCE delta_q_17_s0 (
    .Q(delta_q[17]),
    .D(product_q[26]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_17_s0.INIT=1'b0;
  DFFCE delta_q_16_s0 (
    .Q(delta_q[16]),
    .D(product_q[26]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_16_s0.INIT=1'b0;
  DFFCE delta_q_15_s0 (
    .Q(delta_q[15]),
    .D(product_q[25]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_15_s0.INIT=1'b0;
  DFFCE delta_q_14_s0 (
    .Q(delta_q[14]),
    .D(product_q[24]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_14_s0.INIT=1'b0;
  DFFCE delta_q_13_s0 (
    .Q(delta_q[13]),
    .D(product_q[23]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_13_s0.INIT=1'b0;
  DFFCE delta_q_12_s0 (
    .Q(delta_q[12]),
    .D(product_q[22]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_12_s0.INIT=1'b0;
  DFFCE delta_q_11_s0 (
    .Q(delta_q[11]),
    .D(product_q[21]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_11_s0.INIT=1'b0;
  DFFCE delta_q_10_s0 (
    .Q(delta_q[10]),
    .D(product_q[20]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_10_s0.INIT=1'b0;
  DFFCE delta_q_9_s0 (
    .Q(delta_q[9]),
    .D(product_q[19]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_9_s0.INIT=1'b0;
  DFFCE delta_q_8_s0 (
    .Q(delta_q[8]),
    .D(product_q[18]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_8_s0.INIT=1'b0;
  DFFCE delta_q_7_s0 (
    .Q(delta_q[7]),
    .D(product_q[17]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_7_s0.INIT=1'b0;
  DFFCE delta_q_6_s0 (
    .Q(delta_q[6]),
    .D(product_q[16]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_6_s0.INIT=1'b0;
  DFFCE delta_q_5_s0 (
    .Q(delta_q[5]),
    .D(product_q[15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_5_s0.INIT=1'b0;
  DFFCE delta_q_4_s0 (
    .Q(delta_q[4]),
    .D(product_q[14]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_4_s0.INIT=1'b0;
  DFFCE delta_q_3_s0 (
    .Q(delta_q[3]),
    .D(product_q[13]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_3_s0.INIT=1'b0;
  DFFCE delta_q_2_s0 (
    .Q(delta_q[2]),
    .D(product_q[12]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_2_s0.INIT=1'b0;
  DFFCE delta_q_1_s0 (
    .Q(delta_q[1]),
    .D(product_q[11]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_1_s0.INIT=1'b0;
  DFFCE delta_q_0_s0 (
    .Q(delta_q[0]),
    .D(product_q[10]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam delta_q_0_s0.INIT=1'b0;
  DFFCE sum_q_17_s0 (
    .Q(sum_q[17]),
    .D(n336_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_17_s0.INIT=1'b0;
  DFFCE sum_q_16_s0 (
    .Q(sum_q[16]),
    .D(n337_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_16_s0.INIT=1'b0;
  DFFCE sum_q_15_s0 (
    .Q(sum_q[15]),
    .D(n338_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_15_s0.INIT=1'b0;
  DFFCE sum_q_14_s0 (
    .Q(sum_q[14]),
    .D(n339_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_14_s0.INIT=1'b0;
  DFFCE sum_q_13_s0 (
    .Q(sum_q[13]),
    .D(n340_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_13_s0.INIT=1'b0;
  DFFCE sum_q_12_s0 (
    .Q(sum_q[12]),
    .D(n341_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_12_s0.INIT=1'b0;
  DFFCE sum_q_11_s0 (
    .Q(sum_q[11]),
    .D(n342_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_11_s0.INIT=1'b0;
  DFFCE sum_q_10_s0 (
    .Q(sum_q[10]),
    .D(n343_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_10_s0.INIT=1'b0;
  DFFCE sum_q_9_s0 (
    .Q(sum_q[9]),
    .D(n344_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_9_s0.INIT=1'b0;
  DFFCE sum_q_8_s0 (
    .Q(sum_q[8]),
    .D(n345_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_8_s0.INIT=1'b0;
  DFFCE sum_q_7_s0 (
    .Q(sum_q[7]),
    .D(n346_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_7_s0.INIT=1'b0;
  DFFCE sum_q_6_s0 (
    .Q(sum_q[6]),
    .D(n347_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_6_s0.INIT=1'b0;
  DFFCE sum_q_5_s0 (
    .Q(sum_q[5]),
    .D(n348_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_5_s0.INIT=1'b0;
  DFFCE sum_q_4_s0 (
    .Q(sum_q[4]),
    .D(n349_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_4_s0.INIT=1'b0;
  DFFCE sum_q_3_s0 (
    .Q(sum_q[3]),
    .D(n350_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_3_s0.INIT=1'b0;
  DFFCE sum_q_2_s0 (
    .Q(sum_q[2]),
    .D(n351_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_2_s0.INIT=1'b0;
  DFFCE sum_q_1_s0 (
    .Q(sum_q[1]),
    .D(n352_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_1_s0.INIT=1'b0;
  DFFCE sum_q_0_s0 (
    .Q(sum_q[0]),
    .D(n353_1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[2]) 
);
defparam sum_q_0_s0.INIT=1'b0;
  DFFCE target_o_15_s0 (
    .Q(wrapped_target[15]),
    .D(n416_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_15_s0.INIT=1'b0;
  DFFCE target_o_14_s0 (
    .Q(wrapped_target[14]),
    .D(n417_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_14_s0.INIT=1'b0;
  DFFCE target_o_13_s0 (
    .Q(wrapped_target[13]),
    .D(n418_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_13_s0.INIT=1'b0;
  DFFCE target_o_12_s0 (
    .Q(wrapped_target[12]),
    .D(n419_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_12_s0.INIT=1'b0;
  DFFCE target_o_11_s0 (
    .Q(wrapped_target[11]),
    .D(n420_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_11_s0.INIT=1'b0;
  DFFCE target_o_10_s0 (
    .Q(wrapped_target[10]),
    .D(n421_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_10_s0.INIT=1'b0;
  DFFCE target_o_9_s0 (
    .Q(wrapped_target[9]),
    .D(n422_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_9_s0.INIT=1'b0;
  DFFCE target_o_8_s0 (
    .Q(wrapped_target[8]),
    .D(n423_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_8_s0.INIT=1'b0;
  DFFCE target_o_7_s0 (
    .Q(wrapped_target[7]),
    .D(n424_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_7_s0.INIT=1'b0;
  DFFCE target_o_6_s0 (
    .Q(wrapped_target[6]),
    .D(n425_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_6_s0.INIT=1'b0;
  DFFCE target_o_5_s0 (
    .Q(wrapped_target[5]),
    .D(n426_3),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_5_s0.INIT=1'b0;
  DFFCE target_o_4_s0 (
    .Q(wrapped_target[4]),
    .D(n427_6),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_4_s0.INIT=1'b0;
  DFFCE target_o_3_s0 (
    .Q(wrapped_target[3]),
    .D(sum_q[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_3_s0.INIT=1'b0;
  DFFCE target_o_2_s0 (
    .Q(wrapped_target[2]),
    .D(sum_q[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_2_s0.INIT=1'b0;
  DFFCE target_o_1_s0 (
    .Q(wrapped_target[1]),
    .D(sum_q[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_1_s0.INIT=1'b0;
  DFFCE target_o_0_s0 (
    .Q(wrapped_target[0]),
    .D(sum_q[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[3]) 
);
defparam target_o_0_s0.INIT=1'b0;
  DFFCE yaw0_15_s0 (
    .Q(yaw0[15]),
    .D(turn_yaw[15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_15_s0.INIT=1'b0;
  DFFCE yaw0_14_s0 (
    .Q(yaw0[14]),
    .D(turn_yaw[14]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_14_s0.INIT=1'b0;
  DFFCE yaw0_13_s0 (
    .Q(yaw0[13]),
    .D(turn_yaw[13]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_13_s0.INIT=1'b0;
  DFFCE yaw0_12_s0 (
    .Q(yaw0[12]),
    .D(turn_yaw[12]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_12_s0.INIT=1'b0;
  DFFCE yaw0_11_s0 (
    .Q(yaw0[11]),
    .D(turn_yaw[11]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_11_s0.INIT=1'b0;
  DFFCE yaw0_10_s0 (
    .Q(yaw0[10]),
    .D(turn_yaw[10]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_10_s0.INIT=1'b0;
  DFFCE yaw0_9_s0 (
    .Q(yaw0[9]),
    .D(turn_yaw[9]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_9_s0.INIT=1'b0;
  DFFCE yaw0_8_s0 (
    .Q(yaw0[8]),
    .D(turn_yaw[8]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_8_s0.INIT=1'b0;
  DFFCE yaw0_7_s0 (
    .Q(yaw0[7]),
    .D(turn_yaw[7]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_7_s0.INIT=1'b0;
  DFFCE yaw0_6_s0 (
    .Q(yaw0[6]),
    .D(turn_yaw[6]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_6_s0.INIT=1'b0;
  DFFCE yaw0_5_s0 (
    .Q(yaw0[5]),
    .D(turn_yaw[5]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_5_s0.INIT=1'b0;
  DFFCE yaw0_4_s0 (
    .Q(yaw0[4]),
    .D(turn_yaw[4]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_4_s0.INIT=1'b0;
  DFFCE yaw0_3_s0 (
    .Q(yaw0[3]),
    .D(turn_yaw[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_3_s0.INIT=1'b0;
  DFFCE yaw0_2_s0 (
    .Q(yaw0[2]),
    .D(turn_yaw[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_2_s0.INIT=1'b0;
  DFFCE yaw0_1_s0 (
    .Q(yaw0[1]),
    .D(turn_yaw[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_1_s0.INIT=1'b0;
  DFFCE yaw0_0_s0 (
    .Q(yaw0[0]),
    .D(turn_yaw[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(n1712_2) 
);
defparam yaw0_0_s0.INIT=1'b0;
  DFFCE yaw1_15_s0 (
    .Q(yaw1[15]),
    .D(yaw0[15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_15_s0.INIT=1'b0;
  DFFCE yaw1_14_s0 (
    .Q(yaw1[14]),
    .D(yaw0[14]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_14_s0.INIT=1'b0;
  DFFCE yaw1_13_s0 (
    .Q(yaw1[13]),
    .D(yaw0[13]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_13_s0.INIT=1'b0;
  DFFCE yaw1_12_s0 (
    .Q(yaw1[12]),
    .D(yaw0[12]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_12_s0.INIT=1'b0;
  DFFCE yaw1_11_s0 (
    .Q(yaw1[11]),
    .D(yaw0[11]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_11_s0.INIT=1'b0;
  DFFCE yaw1_10_s0 (
    .Q(yaw1[10]),
    .D(yaw0[10]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_10_s0.INIT=1'b0;
  DFFCE yaw1_9_s0 (
    .Q(yaw1[9]),
    .D(yaw0[9]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_9_s0.INIT=1'b0;
  DFFCE yaw1_8_s0 (
    .Q(yaw1[8]),
    .D(yaw0[8]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_8_s0.INIT=1'b0;
  DFFCE yaw1_7_s0 (
    .Q(yaw1[7]),
    .D(yaw0[7]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_7_s0.INIT=1'b0;
  DFFCE yaw1_6_s0 (
    .Q(yaw1[6]),
    .D(yaw0[6]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_6_s0.INIT=1'b0;
  DFFCE yaw1_5_s0 (
    .Q(yaw1[5]),
    .D(yaw0[5]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_5_s0.INIT=1'b0;
  DFFCE yaw1_4_s0 (
    .Q(yaw1[4]),
    .D(yaw0[4]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_4_s0.INIT=1'b0;
  DFFCE yaw1_3_s0 (
    .Q(yaw1[3]),
    .D(yaw0[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_3_s0.INIT=1'b0;
  DFFCE yaw1_2_s0 (
    .Q(yaw1[2]),
    .D(yaw0[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_2_s0.INIT=1'b0;
  DFFCE yaw1_1_s0 (
    .Q(yaw1[1]),
    .D(yaw0[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_1_s0.INIT=1'b0;
  DFFCE yaw1_0_s0 (
    .Q(yaw1[0]),
    .D(yaw0[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam yaw1_0_s0.INIT=1'b0;
  DFFCE yaw2_15_s0 (
    .Q(yaw2[15]),
    .D(yaw1[15]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_15_s0.INIT=1'b0;
  DFFCE yaw2_14_s0 (
    .Q(yaw2[14]),
    .D(yaw1[14]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_14_s0.INIT=1'b0;
  DFFCE yaw2_13_s0 (
    .Q(yaw2[13]),
    .D(yaw1[13]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_13_s0.INIT=1'b0;
  DFFCE yaw2_12_s0 (
    .Q(yaw2[12]),
    .D(yaw1[12]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_12_s0.INIT=1'b0;
  DFFCE yaw2_11_s0 (
    .Q(yaw2[11]),
    .D(yaw1[11]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_11_s0.INIT=1'b0;
  DFFCE yaw2_10_s0 (
    .Q(yaw2[10]),
    .D(yaw1[10]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_10_s0.INIT=1'b0;
  DFFCE yaw2_9_s0 (
    .Q(yaw2[9]),
    .D(yaw1[9]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_9_s0.INIT=1'b0;
  DFFCE yaw2_8_s0 (
    .Q(yaw2[8]),
    .D(yaw1[8]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_8_s0.INIT=1'b0;
  DFFCE yaw2_7_s0 (
    .Q(yaw2[7]),
    .D(yaw1[7]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_7_s0.INIT=1'b0;
  DFFCE yaw2_6_s0 (
    .Q(yaw2[6]),
    .D(yaw1[6]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_6_s0.INIT=1'b0;
  DFFCE yaw2_5_s0 (
    .Q(yaw2[5]),
    .D(yaw1[5]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_5_s0.INIT=1'b0;
  DFFCE yaw2_4_s0 (
    .Q(yaw2[4]),
    .D(yaw1[4]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_4_s0.INIT=1'b0;
  DFFCE yaw2_3_s0 (
    .Q(yaw2[3]),
    .D(yaw1[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_3_s0.INIT=1'b0;
  DFFCE yaw2_2_s0 (
    .Q(yaw2[2]),
    .D(yaw1[2]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_2_s0.INIT=1'b0;
  DFFCE yaw2_1_s0 (
    .Q(yaw2[1]),
    .D(yaw1[1]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_1_s0.INIT=1'b0;
  DFFCE yaw2_0_s0 (
    .Q(yaw2[0]),
    .D(yaw1[0]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam yaw2_0_s0.INIT=1'b0;
  DFFCE inv1_s0 (
    .Q(inv1),
    .D(inverted),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[0]) 
);
defparam inv1_s0.INIT=1'b0;
  DFFCE inv2_s0 (
    .Q(inv2),
    .D(inv1),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(valid_q[1]) 
);
defparam inv2_s0.INIT=1'b0;
  DFFCE valid_q_4_s0 (
    .Q(converted_valid),
    .D(valid_q[3]),
    .CLK(clk_50m_i_d),
    .CLEAR(n177_5),
    .CE(VCC) 
);
defparam valid_q_4_s0.INIT=1'b0;
  ALU n52_s (
    .SUM(n52_1),
    .COUT(n52_2),
    .I0(\g_heading.requested_angle [0]),
    .I1(\g_heading.requested_angle [1]),
    .I3(VCC),
    .CIN(GND) 
);
defparam n52_s.ALU_MODE=0;
  ALU n51_s (
    .SUM(n51_1),
    .COUT(n51_2),
    .I0(\g_heading.requested_angle [1]),
    .I1(\g_heading.requested_angle [2]),
    .I3(VCC),
    .CIN(n52_2) 
);
defparam n51_s.ALU_MODE=0;
  ALU n50_s (
    .SUM(n50_1),
    .COUT(n50_2),
    .I0(\g_heading.requested_angle [2]),
    .I1(\g_heading.requested_angle [3]),
    .I3(VCC),
    .CIN(n51_2) 
);
defparam n50_s.ALU_MODE=0;
  ALU n49_s (
    .SUM(n49_1),
    .COUT(n49_2),
    .I0(\g_heading.requested_angle [3]),
    .I1(\g_heading.requested_angle [4]),
    .I3(VCC),
    .CIN(n50_2) 
);
defparam n49_s.ALU_MODE=0;
  ALU n48_s (
    .SUM(n48_1),
    .COUT(n48_2),
    .I0(\g_heading.requested_angle [4]),
    .I1(\g_heading.requested_angle [5]),
    .I3(VCC),
    .CIN(n49_2) 
);
defparam n48_s.ALU_MODE=0;
  ALU n47_s (
    .SUM(n47_1),
    .COUT(n47_2),
    .I0(\g_heading.requested_angle [5]),
    .I1(\g_heading.requested_angle [6]),
    .I3(VCC),
    .CIN(n48_2) 
);
defparam n47_s.ALU_MODE=0;
  ALU n46_s (
    .SUM(n46_1),
    .COUT(n46_2),
    .I0(\g_heading.requested_angle [6]),
    .I1(\g_heading.requested_angle [7]),
    .I3(VCC),
    .CIN(n47_2) 
);
defparam n46_s.ALU_MODE=0;
  ALU n45_s (
    .SUM(n45_1),
    .COUT(n45_2),
    .I0(\g_heading.requested_angle [7]),
    .I1(\g_heading.requested_angle [8]),
    .I3(VCC),
    .CIN(n46_2) 
);
defparam n45_s.ALU_MODE=0;
  ALU n44_s (
    .SUM(n44_1),
    .COUT(n44_2),
    .I0(\g_heading.requested_angle [8]),
    .I1(\g_heading.requested_angle [9]),
    .I3(VCC),
    .CIN(n45_2) 
);
defparam n44_s.ALU_MODE=0;
  ALU n43_s (
    .SUM(n43_1),
    .COUT(n43_2),
    .I0(\g_heading.requested_angle [9]),
    .I1(\g_heading.requested_angle [10]),
    .I3(VCC),
    .CIN(n44_2) 
);
defparam n43_s.ALU_MODE=0;
  ALU n42_s (
    .SUM(n42_1),
    .COUT(n42_2),
    .I0(\g_heading.requested_angle [10]),
    .I1(\g_heading.requested_angle [11]),
    .I3(VCC),
    .CIN(n43_2) 
);
defparam n42_s.ALU_MODE=0;
  ALU n41_s (
    .SUM(n41_1),
    .COUT(n41_2),
    .I0(\g_heading.requested_angle [11]),
    .I1(\g_heading.requested_angle [12]),
    .I3(VCC),
    .CIN(n42_2) 
);
defparam n41_s.ALU_MODE=0;
  ALU n40_s (
    .SUM(n40_1),
    .COUT(n40_2),
    .I0(\g_heading.requested_angle [12]),
    .I1(\g_heading.requested_angle [13]),
    .I3(VCC),
    .CIN(n41_2) 
);
defparam n40_s.ALU_MODE=0;
  ALU n39_s (
    .SUM(n39_1),
    .COUT(n39_2),
    .I0(\g_heading.requested_angle [13]),
    .I1(\g_heading.requested_angle [14]),
    .I3(VCC),
    .CIN(n40_2) 
);
defparam n39_s.ALU_MODE=0;
  ALU n38_s (
    .SUM(n38_1),
    .COUT(n38_2),
    .I0(\g_heading.requested_angle [14]),
    .I1(\g_heading.requested_angle [15]),
    .I3(VCC),
    .CIN(n39_2) 
);
defparam n38_s.ALU_MODE=0;
  ALU n353_s (
    .SUM(n353_1),
    .COUT(n353_2),
    .I0(yaw2[0]),
    .I1(delta_q[0]),
    .I3(VCC),
    .CIN(GND) 
);
defparam n353_s.ALU_MODE=0;
  ALU n352_s (
    .SUM(n352_1),
    .COUT(n352_2),
    .I0(yaw2[1]),
    .I1(n333_3),
    .I3(VCC),
    .CIN(n353_2) 
);
defparam n352_s.ALU_MODE=0;
  ALU n351_s (
    .SUM(n351_1),
    .COUT(n351_2),
    .I0(yaw2[2]),
    .I1(n332_3),
    .I3(VCC),
    .CIN(n352_2) 
);
defparam n351_s.ALU_MODE=0;
  ALU n350_s (
    .SUM(n350_1),
    .COUT(n350_2),
    .I0(yaw2[3]),
    .I1(n331_3),
    .I3(VCC),
    .CIN(n351_2) 
);
defparam n350_s.ALU_MODE=0;
  ALU n349_s (
    .SUM(n349_1),
    .COUT(n349_2),
    .I0(yaw2[4]),
    .I1(n330_3),
    .I3(VCC),
    .CIN(n350_2) 
);
defparam n349_s.ALU_MODE=0;
  ALU n348_s (
    .SUM(n348_1),
    .COUT(n348_2),
    .I0(yaw2[5]),
    .I1(n329_3),
    .I3(VCC),
    .CIN(n349_2) 
);
defparam n348_s.ALU_MODE=0;
  ALU n347_s (
    .SUM(n347_1),
    .COUT(n347_2),
    .I0(yaw2[6]),
    .I1(n328_3),
    .I3(VCC),
    .CIN(n348_2) 
);
defparam n347_s.ALU_MODE=0;
  ALU n346_s (
    .SUM(n346_1),
    .COUT(n346_2),
    .I0(yaw2[7]),
    .I1(n327_3),
    .I3(VCC),
    .CIN(n347_2) 
);
defparam n346_s.ALU_MODE=0;
  ALU n345_s (
    .SUM(n345_1),
    .COUT(n345_2),
    .I0(yaw2[8]),
    .I1(n326_3),
    .I3(VCC),
    .CIN(n346_2) 
);
defparam n345_s.ALU_MODE=0;
  ALU n344_s (
    .SUM(n344_1),
    .COUT(n344_2),
    .I0(yaw2[9]),
    .I1(n325_3),
    .I3(VCC),
    .CIN(n345_2) 
);
defparam n344_s.ALU_MODE=0;
  ALU n343_s (
    .SUM(n343_1),
    .COUT(n343_2),
    .I0(yaw2[10]),
    .I1(n324_3),
    .I3(VCC),
    .CIN(n344_2) 
);
defparam n343_s.ALU_MODE=0;
  ALU n342_s (
    .SUM(n342_1),
    .COUT(n342_2),
    .I0(yaw2[11]),
    .I1(n323_3),
    .I3(VCC),
    .CIN(n343_2) 
);
defparam n342_s.ALU_MODE=0;
  ALU n341_s (
    .SUM(n341_1),
    .COUT(n341_2),
    .I0(yaw2[12]),
    .I1(n322_3),
    .I3(VCC),
    .CIN(n342_2) 
);
defparam n341_s.ALU_MODE=0;
  ALU n340_s (
    .SUM(n340_1),
    .COUT(n340_2),
    .I0(yaw2[13]),
    .I1(n321_3),
    .I3(VCC),
    .CIN(n341_2) 
);
defparam n340_s.ALU_MODE=0;
  ALU n339_s (
    .SUM(n339_1),
    .COUT(n339_2),
    .I0(yaw2[14]),
    .I1(n320_3),
    .I3(VCC),
    .CIN(n340_2) 
);
defparam n339_s.ALU_MODE=0;
  ALU n338_s (
    .SUM(n338_1),
    .COUT(n338_2),
    .I0(yaw2[15]),
    .I1(n319_3),
    .I3(VCC),
    .CIN(n339_2) 
);
defparam n338_s.ALU_MODE=0;
  ALU n337_s (
    .SUM(n337_1),
    .COUT(n337_2),
    .I0(yaw2[15]),
    .I1(n318_3),
    .I3(VCC),
    .CIN(n338_2) 
);
defparam n337_s.ALU_MODE=0;
  ALU n336_s (
    .SUM(n336_1),
    .COUT(n336_0_COUT),
    .I0(yaw2[15]),
    .I1(n317_3),
    .I3(VCC),
    .CIN(n337_2) 
);
defparam n336_s.ALU_MODE=0;
  ALU n200_s (
    .SUM(n200_2),
    .COUT(n200_3),
    .I0(hi_q[0]),
    .I1(lo_q[0]),
    .I3(VCC),
    .CIN(VCC) 
);
defparam n200_s.ALU_MODE=1;
  ALU n199_s (
    .SUM(n199_2),
    .COUT(n199_3),
    .I0(hi_q[1]),
    .I1(lo_q[1]),
    .I3(VCC),
    .CIN(n200_3) 
);
defparam n199_s.ALU_MODE=1;
  ALU n198_s (
    .SUM(n198_2),
    .COUT(n198_3),
    .I0(hi_q[2]),
    .I1(lo_q[2]),
    .I3(VCC),
    .CIN(n199_3) 
);
defparam n198_s.ALU_MODE=1;
  ALU n197_s (
    .SUM(n197_2),
    .COUT(n197_3),
    .I0(hi_q[3]),
    .I1(lo_q[3]),
    .I3(VCC),
    .CIN(n198_3) 
);
defparam n197_s.ALU_MODE=1;
  ALU n196_s (
    .SUM(n196_2),
    .COUT(n196_3),
    .I0(hi_q[4]),
    .I1(lo_q[4]),
    .I3(VCC),
    .CIN(n197_3) 
);
defparam n196_s.ALU_MODE=1;
  ALU n195_s (
    .SUM(n195_2),
    .COUT(n195_3),
    .I0(hi_q[5]),
    .I1(lo_q[5]),
    .I3(VCC),
    .CIN(n196_3) 
);
defparam n195_s.ALU_MODE=1;
  ALU n194_s (
    .SUM(n194_2),
    .COUT(n194_3),
    .I0(hi_q[6]),
    .I1(lo_q[6]),
    .I3(VCC),
    .CIN(n195_3) 
);
defparam n194_s.ALU_MODE=1;
  ALU n193_s (
    .SUM(n193_2),
    .COUT(n193_3),
    .I0(hi_q[7]),
    .I1(lo_q[7]),
    .I3(VCC),
    .CIN(n194_3) 
);
defparam n193_s.ALU_MODE=1;
  ALU n192_s (
    .SUM(n192_2),
    .COUT(n192_3),
    .I0(hi_q[8]),
    .I1(lo_q[8]),
    .I3(VCC),
    .CIN(n193_3) 
);
defparam n192_s.ALU_MODE=1;
  ALU n191_s (
    .SUM(n191_2),
    .COUT(n191_3),
    .I0(hi_q[9]),
    .I1(lo_q[9]),
    .I3(VCC),
    .CIN(n192_3) 
);
defparam n191_s.ALU_MODE=1;
  ALU n190_s (
    .SUM(n190_2),
    .COUT(n190_3),
    .I0(hi_q[10]),
    .I1(lo_q[10]),
    .I3(VCC),
    .CIN(n191_3) 
);
defparam n190_s.ALU_MODE=1;
  ALU n189_s (
    .SUM(n189_2),
    .COUT(n189_3),
    .I0(hi_q[11]),
    .I1(lo_q[11]),
    .I3(VCC),
    .CIN(n190_3) 
);
defparam n189_s.ALU_MODE=1;
  ALU n188_s (
    .SUM(n188_2),
    .COUT(n188_3),
    .I0(hi_q[12]),
    .I1(lo_q[12]),
    .I3(VCC),
    .CIN(n189_3) 
);
defparam n188_s.ALU_MODE=1;
  ALU n187_s (
    .SUM(n187_2),
    .COUT(n187_3),
    .I0(hi_q[13]),
    .I1(lo_q[13]),
    .I3(VCC),
    .CIN(n188_3) 
);
defparam n187_s.ALU_MODE=1;
  ALU n186_s (
    .SUM(n186_2),
    .COUT(n186_3),
    .I0(hi_q[14]),
    .I1(lo_q[14]),
    .I3(VCC),
    .CIN(n187_3) 
);
defparam n186_s.ALU_MODE=1;
  ALU n185_s (
    .SUM(n185_2),
    .COUT(n185_3),
    .I0(hi_q[15]),
    .I1(lo_q[15]),
    .I3(VCC),
    .CIN(n186_3) 
);
defparam n185_s.ALU_MODE=1;
  ALU n184_s (
    .SUM(n184_2),
    .COUT(n184_3),
    .I0(hi_q[16]),
    .I1(lo_q[16]),
    .I3(VCC),
    .CIN(n185_3) 
);
defparam n184_s.ALU_MODE=1;
  ALU n183_s (
    .SUM(n183_2),
    .COUT(n183_3),
    .I0(hi_q[17]),
    .I1(lo_q[17]),
    .I3(VCC),
    .CIN(n184_3) 
);
defparam n183_s.ALU_MODE=1;
  ALU n182_s (
    .SUM(n182_2),
    .COUT(n182_3),
    .I0(hi_q[18]),
    .I1(lo_q[18]),
    .I3(VCC),
    .CIN(n183_3) 
);
defparam n182_s.ALU_MODE=1;
  ALU n181_s (
    .SUM(n181_2),
    .COUT(n181_3),
    .I0(hi_q[19]),
    .I1(lo_q[19]),
    .I3(VCC),
    .CIN(n182_3) 
);
defparam n181_s.ALU_MODE=1;
  ALU n180_s (
    .SUM(n180_2),
    .COUT(n180_3),
    .I0(hi_q[20]),
    .I1(lo_q[20]),
    .I3(VCC),
    .CIN(n181_3) 
);
defparam n180_s.ALU_MODE=1;
  ALU n179_s (
    .SUM(n179_2),
    .COUT(n179_3),
    .I0(hi_q[21]),
    .I1(lo_q[21]),
    .I3(VCC),
    .CIN(n180_3) 
);
defparam n179_s.ALU_MODE=1;
  ALU n178_s (
    .SUM(n178_2),
    .COUT(n178_3),
    .I0(hi_q[22]),
    .I1(lo_q[22]),
    .I3(VCC),
    .CIN(n179_3) 
);
defparam n178_s.ALU_MODE=1;
  ALU n177_s (
    .SUM(n177_2),
    .COUT(n177_3),
    .I0(hi_q[23]),
    .I1(lo_q[23]),
    .I3(VCC),
    .CIN(n178_3) 
);
defparam n177_s.ALU_MODE=1;
  ALU n176_s (
    .SUM(n176_2),
    .COUT(n176_3),
    .I0(hi_q[24]),
    .I1(lo_q[24]),
    .I3(VCC),
    .CIN(n177_3) 
);
defparam n176_s.ALU_MODE=1;
  ALU n175_s (
    .SUM(n175_2),
    .COUT(n175_3),
    .I0(hi_q[25]),
    .I1(lo_q[25]),
    .I3(VCC),
    .CIN(n176_3) 
);
defparam n175_s.ALU_MODE=1;
  ALU n174_s (
    .SUM(n174_2),
    .COUT(n174_0_COUT),
    .I0(hi_q[26]),
    .I1(lo_q[26]),
    .I3(VCC),
    .CIN(n175_3) 
);
defparam n174_s.ALU_MODE=1;
  ALU n74_s (
    .SUM(n74_2),
    .COUT(n74_3),
    .I0(\g_heading.requested_angle [0]),
    .I1(\g_heading.requested_angle [3]),
    .I3(VCC),
    .CIN(GND) 
);
defparam n74_s.ALU_MODE=0;
  ALU n73_s (
    .SUM(n73_2),
    .COUT(n73_3),
    .I0(\g_heading.requested_angle [1]),
    .I1(\g_heading.requested_angle [4]),
    .I3(VCC),
    .CIN(n74_3) 
);
defparam n73_s.ALU_MODE=0;
  ALU n72_s (
    .SUM(n72_2),
    .COUT(n72_3),
    .I0(\g_heading.requested_angle [2]),
    .I1(\g_heading.requested_angle [5]),
    .I3(VCC),
    .CIN(n73_3) 
);
defparam n72_s.ALU_MODE=0;
  ALU n71_s (
    .SUM(n71_2),
    .COUT(n71_3),
    .I0(\g_heading.requested_angle [3]),
    .I1(\g_heading.requested_angle [6]),
    .I3(VCC),
    .CIN(n72_3) 
);
defparam n71_s.ALU_MODE=0;
  ALU n70_s (
    .SUM(n70_2),
    .COUT(n70_3),
    .I0(\g_heading.requested_angle [4]),
    .I1(\g_heading.requested_angle [7]),
    .I3(VCC),
    .CIN(n71_3) 
);
defparam n70_s.ALU_MODE=0;
  ALU n69_s (
    .SUM(n69_2),
    .COUT(n69_3),
    .I0(\g_heading.requested_angle [5]),
    .I1(\g_heading.requested_angle [8]),
    .I3(VCC),
    .CIN(n70_3) 
);
defparam n69_s.ALU_MODE=0;
  ALU n68_s (
    .SUM(n68_2),
    .COUT(n68_3),
    .I0(\g_heading.requested_angle [6]),
    .I1(\g_heading.requested_angle [9]),
    .I3(VCC),
    .CIN(n69_3) 
);
defparam n68_s.ALU_MODE=0;
  ALU n67_s (
    .SUM(n67_2),
    .COUT(n67_3),
    .I0(\g_heading.requested_angle [7]),
    .I1(\g_heading.requested_angle [10]),
    .I3(VCC),
    .CIN(n68_3) 
);
defparam n67_s.ALU_MODE=0;
  ALU n66_s (
    .SUM(n66_2),
    .COUT(n66_3),
    .I0(\g_heading.requested_angle [8]),
    .I1(\g_heading.requested_angle [11]),
    .I3(VCC),
    .CIN(n67_3) 
);
defparam n66_s.ALU_MODE=0;
  ALU n65_s (
    .SUM(n65_2),
    .COUT(n65_3),
    .I0(\g_heading.requested_angle [9]),
    .I1(\g_heading.requested_angle [12]),
    .I3(VCC),
    .CIN(n66_3) 
);
defparam n65_s.ALU_MODE=0;
  ALU n64_s (
    .SUM(n64_2),
    .COUT(n64_3),
    .I0(\g_heading.requested_angle [10]),
    .I1(\g_heading.requested_angle [13]),
    .I3(VCC),
    .CIN(n65_3) 
);
defparam n64_s.ALU_MODE=0;
  ALU n63_s (
    .SUM(n63_2),
    .COUT(n63_3),
    .I0(\g_heading.requested_angle [11]),
    .I1(\g_heading.requested_angle [14]),
    .I3(VCC),
    .CIN(n64_3) 
);
defparam n63_s.ALU_MODE=0;
  ALU n62_s (
    .SUM(n62_2),
    .COUT(n62_3),
    .I0(\g_heading.requested_angle [12]),
    .I1(\g_heading.requested_angle [15]),
    .I3(VCC),
    .CIN(n63_3) 
);
defparam n62_s.ALU_MODE=0;
  ALU n61_s (
    .SUM(n61_2),
    .COUT(n61_3),
    .I0(\g_heading.requested_angle [13]),
    .I1(\g_heading.requested_angle [15]),
    .I3(VCC),
    .CIN(n62_3) 
);
defparam n61_s.ALU_MODE=0;
  ALU n60_s (
    .SUM(n60_2),
    .COUT(n60_3),
    .I0(\g_heading.requested_angle [14]),
    .I1(\g_heading.requested_angle [15]),
    .I3(VCC),
    .CIN(n61_3) 
);
defparam n60_s.ALU_MODE=0;
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
endmodule