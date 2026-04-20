module TG68K_ALU
  (input  clk,
   input  Reset,
   input  clkena_lw,
   input  [1:0] CPU,
   input  execOPC,
   input  decodeOPC,
   input  exe_condition,
   input  exec_tas,
   input  long_start,
   input  non_aligned,
   input  check_aligned,
   input  movem_presub,
   input  set_stop,
   input  Z_error,
   input  [1:0] rot_bits,
   input  [90:0] exec,
   input  [31:0] OP1out,
   input  [31:0] OP2out,
   input  [31:0] reg_QA,
   input  [31:0] reg_QB,
   input  [15:0] opcode,
   input  [15:0] exe_opcode,
   input  [1:0] exe_datatype,
   input  [15:0] sndOPC,
   input  [15:0] last_data_read,
   input  [15:0] data_read,
   input  [7:0] FlagsSR,
   input  [6:0] micro_state,
   input  [7:0] bf_ext_in,
   output [7:0] bf_ext_out,
   input  [5:0] bf_shift,
   input  [5:0] bf_width,
   input  [31:0] bf_ffo_offset,
   input  [4:0] bf_loffset,
   output set_V_Flag,
   output [7:0] Flags,
   output [2:0] c_out,
   output [31:0] addsub_q,
   output [31:0] ALUout);
  wire [31:0] op1in;
  wire [31:0] addsub_a;
  wire [31:0] addsub_b;
  wire [33:0] notaddsub_b;
  wire [33:0] add_result;
  wire [2:0] addsub_ofl;
  wire opaddsub;
  wire [3:0] c_in;
  wire [2:0] flag_z;
  wire [3:0] set_flags;
  wire [7:0] ccrin;
  wire [3:0] last_flags1;
  wire [9:0] bcd_pur;
  wire [8:0] bcd_kor;
  wire halve_carry;
  wire vflag_a;
  wire bcd_a_carry;
  wire [8:0] bcd_a;
  wire [127:0] result_mulu;
  wire [63:0] result_div;
  wire [31:0] result_div_pre;
  wire v_flag;
  wire rot_rot;
  wire rot_x;
  wire rot_c;
  wire [31:0] rot_out;
  wire asl_vflag;
  wire [4:0] bit_number;
  wire [31:0] bits_out;
  wire one_bit_in;
  wire bchg;
  wire bset;
  wire mulu_sign;
  wire muls_msb;
  wire [63:0] mulu_reg;
  wire fasign;
  wire [31:0] faktorb;
  wire [63:0] div_reg;
  wire [63:0] div_quot;
  wire div_neg;
  wire div_bit;
  wire [32:0] div_sub;
  wire [32:0] div_over;
  wire nozero;
  wire div_qsign;
  wire [63:0] dividend;
  wire divs;
  wire signedop;
  wire op1_sign;
  wire [15:0] op2outext;
  wire [31:0] datareg;
  wire [31:0] bf_datareg;
  wire [39:0] result;
  wire [39:0] result_tmp;
  wire [31:0] unshifted_bitmask;
  wire [39:0] inmux0;
  wire [39:0] inmux1;
  wire [39:0] inmux2;
  wire [31:0] inmux3;
  wire [39:0] shifted_bitmask;
  wire [37:0] bitmaskmux0;
  wire [35:0] bitmaskmux1;
  wire [31:0] bitmaskmux2;
  wire [31:0] bitmaskmux3;
  wire [31:0] bf_set2;
  wire [39:0] shift;
  wire [5:0] bf_firstbit;
  wire [3:0] mux;
  wire [4:0] bitnr;
  wire [31:0] mask;
  wire mask_not_zero;
  wire bf_bset;
  wire bf_nflag;
  wire bf_bchg;
  wire bf_ins;
  wire bf_exts;
  wire bf_fffo;
  wire bf_d32;
  wire bf_s32;
  wire [33:0] hot_msb;
  wire [32:0] vector;
  wire [65:0] result_bs;
  wire [5:0] bit_nr;
  wire [5:0] bit_msb;
  wire [5:0] bs_shift;
  wire [5:0] bs_shift_mod;
  wire [32:0] asl_over;
  wire [32:0] asl_over_xor;
  wire [32:0] asr_sign;
  wire msb;
  wire [5:0] ring;
  wire [31:0] alu;
  wire [31:0] bsout;
  wire bs_v;
  wire bs_c;
  wire bs_x;
  wire n8;
  wire n9;
  wire [23:0] n10;
  wire [6:0] n11;
  wire n12;
  wire [31:0] n13;
  wire [31:0] n14;
  wire [31:0] n15;
  wire [31:0] n16;
  wire [31:0] n17;
  wire [31:0] n18;
  wire n19;
  wire n20;
  wire n21;
  wire [7:0] n22;
  wire n23;
  wire n25;
  wire n26;
  wire [31:0] n27;
  wire [31:0] n28;
  wire [31:0] n29;
  wire n30;
  wire n32;
  wire n33;
  wire n35;
  wire [15:0] n36;
  wire [15:0] n37;
  wire [31:0] n38;
  wire n39;
  wire [31:0] n40;
  wire [31:0] n41;
  wire [31:0] n42;
  wire [31:0] n43;
  wire n44;
  wire [31:0] n45;
  wire n46;
  wire [31:0] n47;
  wire n48;
  wire [7:0] n49;
  wire n50;
  wire [31:0] n51;
  wire n52;
  wire n53;
  wire n54;
  wire n55;
  wire [15:0] n56;
  wire [15:0] n57;
  wire [31:0] n58;
  wire n59;
  wire n60;
  wire n61;
  wire n62;
  wire [7:0] n64;
  wire n65;
  wire [3:0] n66;
  wire [3:0] n67;
  wire [7:0] n68;
  wire [7:0] n69;
  wire [7:0] n70;
  wire [15:0] n71;
  wire [7:0] n72;
  wire [7:0] n73;
  wire [7:0] n74;
  wire [7:0] n75;
  wire [7:0] n76;
  wire [15:0] n77;
  wire [15:0] n78;
  wire [15:0] n79;
  wire [15:0] n80;
  wire [15:0] n81;
  wire [15:0] n82;
  wire [31:0] n83;
  wire [31:0] n84;
  wire [31:0] n85;
  wire [31:0] n86;
  wire [31:0] n87;
  wire [31:0] n88;
  wire [31:0] n89;
  wire [7:0] n90;
  wire [7:0] n91;
  wire [23:0] n92;
  wire [23:0] n93;
  wire [23:0] n94;
  wire [31:0] n95;
  wire [31:0] n96;
  wire [31:0] n97;
  wire [31:0] n98;
  wire [31:0] n99;
  wire [7:0] n100;
  wire [7:0] n101;
  wire [23:0] n102;
  wire [23:0] n103;
  wire [23:0] n104;
  wire n109;
  wire n110;
  wire n111;
  wire n112;
  wire [1:0] n113;
  wire n114;
  wire [2:0] n115;
  wire [28:0] n116;
  wire [31:0] n117;
  wire [1:0] n118;
  wire [31:0] n120;
  wire [31:0] n121;
  wire [31:0] n122;
  wire n123;
  wire n126;
  wire n128;
  wire [3:0] n129;
  wire [7:0] n131;
  wire [11:0] n133;
  wire [3:0] n134;
  wire [15:0] n135;
  wire n136;
  wire n137;
  wire n138;
  wire n139;
  wire n140;
  wire n141;
  wire n142;
  wire n143;
  wire n145;
  wire n146;
  wire n147;
  wire n148;
  wire n149;
  wire n150;
  wire n152;
  wire n153;
  wire n154;
  wire n155;
  wire n156;
  wire n157;
  wire n158;
  wire n159;
  wire [31:0] n162;
  wire [31:0] n164;
  wire [31:0] n166;
  wire n167;
  wire n168;
  wire n169;
  wire n170;
  wire n171;
  wire n173;
  wire n174;
  wire [31:0] n175;
  wire n176;
  wire n177;
  wire [15:0] n178;
  wire [15:0] n179;
  wire [15:0] n180;
  wire [15:0] n181;
  wire [15:0] n182;
  wire n184;
  wire n185;
  wire n186;
  wire n187;
  wire n188;
  wire n189;
  wire n190;
  wire [31:0] n192;
  wire [31:0] n193;
  wire n194;
  wire n195;
  wire n197;
  wire [31:0] n200;
  wire [31:0] n201;
  wire [31:0] n202;
  wire [31:0] n203;
  wire [31:0] n204;
  wire [31:0] n205;
  wire n206;
  wire n207;
  wire [32:0] n209;
  wire n210;
  wire [33:0] n211;
  wire [32:0] n213;
  wire n214;
  wire [33:0] n215;
  wire [33:0] n216;
  wire [33:0] n217;
  wire [32:0] n219;
  wire n220;
  wire [33:0] n221;
  wire [33:0] n222;
  wire n223;
  wire n224;
  wire n225;
  wire n226;
  wire n227;
  wire n228;
  wire n229;
  wire n230;
  wire n231;
  wire n232;
  wire n233;
  wire [31:0] n234;
  wire n235;
  wire n236;
  wire n237;
  wire n238;
  wire n239;
  wire n240;
  wire n241;
  wire n242;
  wire n243;
  wire n244;
  wire n245;
  wire n246;
  wire n247;
  wire n248;
  wire n249;
  wire n250;
  wire n251;
  wire n252;
  wire n253;
  wire n254;
  wire n255;
  wire [2:0] n256;
  wire n260;
  wire [8:0] n261;
  wire [9:0] n262;
  wire n263;
  wire n264;
  wire n265;
  wire n266;
  wire n267;
  wire [3:0] n270;
  localparam [8:0] n271 = 9'b000000000;
  wire n273;
  wire [3:0] n275;
  wire [3:0] n276;
  wire n277;
  wire n278;
  wire n279;
  wire n280;
  wire n281;
  wire n282;
  wire [8:0] n283;
  wire [8:0] n284;
  wire n285;
  wire n286;
  wire n287;
  wire n288;
  wire n289;
  wire [3:0] n291;
  wire n292;
  wire n293;
  wire n294;
  wire n295;
  wire n296;
  wire n297;
  wire n298;
  wire n299;
  wire n300;
  wire n301;
  wire n302;
  wire n303;
  wire n304;
  wire [3:0] n306;
  wire n307;
  wire n308;
  wire n309;
  wire n310;
  wire [8:0] n311;
  wire [8:0] n312;
  wire [7:0] n313;
  wire [7:0] n314;
  wire [7:0] n315;
  wire n316;
  wire [8:0] n317;
  wire n318;
  wire n320;
  wire n321;
  wire n322;
  wire n323;
  wire [1:0] n328;
  wire n330;
  wire n332;
  wire [1:0] n333;
  reg n336;
  reg n340;
  wire n346;
  wire n347;
  wire [1:0] n348;
  wire n350;
  wire [4:0] n351;
  wire [2:0] n352;
  wire [4:0] n354;
  wire [4:0] n355;
  wire [1:0] n356;
  wire n358;
  wire [4:0] n359;
  wire [2:0] n360;
  wire [4:0] n362;
  wire [4:0] n363;
  wire [4:0] n364;
  wire n370;
  wire n371;
  wire n372;
  wire [1:0] n378;
  wire n380;
  wire n383;
  wire [2:0] n385;
  wire n387;
  wire n389;
  wire n391;
  wire n393;
  wire n395;
  wire [4:0] n396;
  reg n399;
  reg n403;
  reg n407;
  reg n411;
  reg n415;
  reg n418;
  wire [1:0] n419;
  wire n421;
  wire n424;
  wire [7:0] n426;
  wire [31:0] n443;
  wire [4:0] n444;
  wire n446;
  wire n449;
  wire n450;
  wire n453;
  localparam [31:0] n454 = 32'b00000000000000000000000000000000;
  wire [4:0] n456;
  wire n458;
  wire n461;
  wire n462;
  wire n464;
  wire n465;
  wire [4:0] n467;
  wire n469;
  wire n472;
  wire n473;
  wire n475;
  wire n476;
  wire [4:0] n478;
  wire n480;
  wire n483;
  wire n484;
  wire n486;
  wire n487;
  wire [4:0] n489;
  wire n491;
  wire n494;
  wire n495;
  wire n497;
  wire n498;
  wire [4:0] n500;
  wire n502;
  wire n505;
  wire n506;
  wire n508;
  wire n509;
  wire [4:0] n511;
  wire n513;
  wire n516;
  wire n517;
  wire n519;
  wire n520;
  wire [4:0] n522;
  wire n524;
  wire n527;
  wire n528;
  wire n530;
  wire n531;
  wire [4:0] n533;
  wire n535;
  wire n538;
  wire n539;
  wire n541;
  wire n542;
  wire [4:0] n544;
  wire n546;
  wire n549;
  wire n550;
  wire n552;
  wire n553;
  wire [4:0] n555;
  wire n557;
  wire n560;
  wire n561;
  wire n563;
  wire n564;
  wire [4:0] n566;
  wire n568;
  wire n571;
  wire n572;
  wire n574;
  wire n575;
  wire [4:0] n577;
  wire n579;
  wire n582;
  wire n583;
  wire n585;
  wire n586;
  wire [4:0] n588;
  wire n590;
  wire n593;
  wire n594;
  wire n596;
  wire n597;
  wire [4:0] n599;
  wire n601;
  wire n604;
  wire n605;
  wire n607;
  wire n608;
  wire [4:0] n610;
  wire n612;
  wire n615;
  wire n616;
  wire n618;
  wire n619;
  wire [4:0] n621;
  wire n623;
  wire n626;
  wire n627;
  wire n629;
  wire n630;
  wire [4:0] n632;
  wire n634;
  wire n637;
  wire n638;
  wire n640;
  wire n641;
  wire [4:0] n643;
  wire n645;
  wire n648;
  wire n649;
  wire n651;
  wire n652;
  wire [4:0] n654;
  wire n656;
  wire n659;
  wire n660;
  wire n662;
  wire n663;
  wire [4:0] n665;
  wire n667;
  wire n670;
  wire n671;
  wire n673;
  wire n674;
  wire [4:0] n676;
  wire n678;
  wire n681;
  wire n682;
  wire n684;
  wire n685;
  wire [4:0] n687;
  wire n689;
  wire n692;
  wire n693;
  wire n695;
  wire n696;
  wire [4:0] n698;
  wire n700;
  wire n703;
  wire n704;
  wire n706;
  wire n707;
  wire [4:0] n709;
  wire n711;
  wire n714;
  wire n715;
  wire n717;
  wire n718;
  wire [4:0] n720;
  wire n722;
  wire n725;
  wire n726;
  wire n728;
  wire n729;
  wire [4:0] n731;
  wire n733;
  wire n736;
  wire n737;
  wire n739;
  wire n740;
  wire [4:0] n742;
  wire n744;
  wire n747;
  wire n748;
  wire n750;
  wire n751;
  wire [4:0] n753;
  wire n755;
  wire n758;
  wire n759;
  wire n761;
  wire n762;
  wire [4:0] n764;
  wire n766;
  wire n769;
  wire n770;
  wire n772;
  wire n773;
  wire [4:0] n775;
  wire n777;
  wire n780;
  wire n781;
  wire n782;
  wire n783;
  wire n784;
  wire n785;
  wire [4:0] n786;
  wire n788;
  wire n791;
  wire n792;
  wire [4:0] n794;
  wire n797;
  wire [31:0] n798;
  wire [31:0] n799;
  wire n800;
  wire [15:0] n801;
  wire [15:0] n802;
  wire [31:0] n803;
  wire [31:0] n804;
  wire n805;
  wire [23:0] n806;
  wire [7:0] n807;
  wire [31:0] n808;
  wire [31:0] n809;
  wire n810;
  wire [35:0] n812;
  wire [3:0] n813;
  wire [3:0] n814;
  wire [3:0] n815;
  wire [31:0] n816;
  wire [35:0] n818;
  wire [35:0] n819;
  wire [35:0] n820;
  wire n821;
  wire [37:0] n823;
  wire [1:0] n824;
  wire [1:0] n825;
  wire [1:0] n826;
  wire [35:0] n827;
  wire [37:0] n829;
  wire [37:0] n830;
  wire [37:0] n831;
  wire n832;
  wire [38:0] n834;
  wire [39:0] n836;
  wire n837;
  wire n838;
  wire n839;
  wire [38:0] n840;
  wire [39:0] n842;
  wire [39:0] n843;
  wire [39:0] n844;
  wire [39:0] n845;
  wire [7:0] n846;
  wire [7:0] n847;
  wire [7:0] n848;
  wire [31:0] n849;
  wire n850;
  wire n851;
  wire [38:0] n852;
  wire [39:0] n853;
  wire [39:0] n854;
  wire n855;
  wire [1:0] n856;
  wire [37:0] n857;
  wire [39:0] n858;
  wire [39:0] n859;
  wire n860;
  wire [3:0] n861;
  wire [35:0] n862;
  wire [39:0] n863;
  wire [39:0] n864;
  wire n865;
  wire [7:0] n866;
  wire [23:0] n867;
  wire [31:0] n868;
  wire [31:0] n869;
  wire [31:0] n870;
  wire n871;
  wire [15:0] n872;
  wire [15:0] n873;
  wire [31:0] n874;
  wire [31:0] n875;
  wire [7:0] n876;
  wire [31:0] n877;
  wire [7:0] n878;
  wire [39:0] n879;
  wire [39:0] n881;
  wire [39:0] n882;
  wire [39:0] n883;
  wire [39:0] n885;
  wire [39:0] n886;
  wire [39:0] n887;
  wire [39:0] n888;
  wire n889;
  wire n890;
  wire n891;
  wire n892;
  wire n894;
  wire n895;
  wire n896;
  wire n897;
  wire n899;
  wire n900;
  wire n901;
  wire n902;
  wire n904;
  wire n905;
  wire n906;
  wire n907;
  wire n909;
  wire n910;
  wire n911;
  wire n912;
  wire n914;
  wire n915;
  wire n916;
  wire n917;
  wire n919;
  wire n920;
  wire n921;
  wire n922;
  wire n924;
  wire n925;
  wire n926;
  wire n927;
  wire n929;
  wire n930;
  wire n931;
  wire n932;
  wire n934;
  wire n935;
  wire n936;
  wire n937;
  wire n939;
  wire n940;
  wire n941;
  wire n942;
  wire n944;
  wire n945;
  wire n946;
  wire n947;
  wire n949;
  wire n950;
  wire n951;
  wire n952;
  wire n954;
  wire n955;
  wire n956;
  wire n957;
  wire n959;
  wire n960;
  wire n961;
  wire n962;
  wire n964;
  wire n965;
  wire n966;
  wire n967;
  wire n969;
  wire n970;
  wire n971;
  wire n972;
  wire n974;
  wire n975;
  wire n976;
  wire n977;
  wire n979;
  wire n980;
  wire n981;
  wire n982;
  wire n984;
  wire n985;
  wire n986;
  wire n987;
  wire n989;
  wire n990;
  wire n991;
  wire n992;
  wire n994;
  wire n995;
  wire n996;
  wire n997;
  wire n999;
  wire n1000;
  wire n1001;
  wire n1002;
  wire n1004;
  wire n1005;
  wire n1006;
  wire n1007;
  wire n1009;
  wire n1010;
  wire n1011;
  wire n1012;
  wire n1014;
  wire n1015;
  wire n1016;
  wire n1017;
  wire n1019;
  wire n1020;
  wire n1021;
  wire n1022;
  wire n1024;
  wire n1025;
  wire n1026;
  wire n1027;
  wire n1029;
  wire n1030;
  wire n1031;
  wire n1032;
  wire n1034;
  wire n1035;
  wire n1036;
  wire n1037;
  wire n1039;
  wire n1040;
  wire n1041;
  wire n1042;
  wire n1044;
  wire n1045;
  wire n1046;
  wire n1047;
  wire n1049;
  wire n1050;
  wire n1051;
  wire n1052;
  wire n1054;
  wire n1055;
  wire n1056;
  wire n1057;
  wire n1059;
  wire n1060;
  wire n1061;
  wire n1062;
  wire n1064;
  wire n1065;
  wire n1066;
  wire n1067;
  wire n1069;
  wire n1070;
  wire n1071;
  wire n1072;
  wire n1074;
  wire n1075;
  wire n1076;
  wire n1077;
  wire n1079;
  wire n1080;
  wire n1081;
  wire n1082;
  wire n1083;
  wire n1084;
  wire n1085;
  wire n1086;
  wire [5:0] n1088;
  wire [5:0] n1089;
  wire [5:0] n1090;
  wire [3:0] n1091;
  wire n1093;
  wire [3:0] n1094;
  wire n1096;
  wire [3:0] n1097;
  wire n1099;
  wire [3:0] n1100;
  wire n1102;
  wire [3:0] n1104;
  wire n1106;
  wire [3:0] n1107;
  wire n1109;
  wire [3:0] n1111;
  wire n1113;
  wire [3:0] n1115;
  wire [3:0] n1116;
  wire [3:0] n1117;
  wire n1119;
  wire [3:0] n1120;
  wire [3:0] n1122;
  wire [1:0] n1123;
  wire n1124;
  wire n1125;
  wire n1126;
  wire n1128;
  wire [3:0] n1129;
  wire [3:0] n1130;
  wire [1:0] n1131;
  wire [1:0] n1133;
  wire [3:0] n1134;
  wire [3:0] n1137;
  wire [1:0] n1138;
  wire [2:0] n1139;
  wire [1:0] n1140;
  wire [1:0] n1141;
  wire n1142;
  wire n1144;
  wire [3:0] n1145;
  wire [3:0] n1147;
  wire [2:0] n1148;
  wire n1149;
  wire n1151;
  wire n1152;
  wire n1153;
  wire n1154;
  wire n1156;
  wire [3:0] n1157;
  wire [3:0] n1159;
  wire [2:0] n1160;
  wire n1161;
  wire n1162;
  wire [1:0] n1163;
  wire [1:0] n1165;
  wire [3:0] n1166;
  wire [3:0] n1167;
  wire [2:0] n1168;
  wire [2:0] n1170;
  localparam [4:0] n1171 = 5'b11111;
  wire [1:0] n1173;
  wire n1175;
  wire n1177;
  wire n1178;
  wire n1180;
  wire n1181;
  wire n1184;
  wire n1185;
  wire n1186;
  wire n1188;
  wire n1189;
  wire n1190;
  wire n1192;
  wire n1193;
  wire [1:0] n1194;
  wire n1195;
  wire n1196;
  wire n1197;
  wire n1198;
  wire n1199;
  wire n1202;
  wire [1:0] n1207;
  wire n1208;
  wire n1210;
  wire n1211;
  wire n1213;
  wire n1215;
  wire n1216;
  wire n1217;
  wire n1219;
  wire [2:0] n1220;
  reg n1221;
  wire n1239;
  wire n1240;
  wire n1242;
  wire n1243;
  wire n1245;
  wire n1246;
  wire n1249;
  wire n1250;
  wire n1270;
  wire n1271;
  wire n1274;
  wire n1275;
  wire [31:0] n1276;
  wire n1281;
  wire [1:0] n1282;
  wire n1284;
  wire n1286;
  wire n1288;
  wire n1289;
  wire n1291;
  wire [2:0] n1292;
  reg [5:0] n1297;
  wire [1:0] n1298;
  wire n1300;
  wire n1302;
  wire n1304;
  wire n1305;
  wire n1307;
  wire [2:0] n1308;
  reg [5:0] n1313;
  wire [5:0] n1314;
  wire [1:0] n1316;
  wire n1318;
  wire n1319;
  wire n1320;
  wire n1321;
  wire n1322;
  wire [5:0] n1323;
  wire [2:0] n1324;
  wire [2:0] n1325;
  wire n1327;
  wire [2:0] n1330;
  wire [5:0] n1331;
  wire [5:0] n1332;
  wire [5:0] n1334;
  localparam [33:0] n1337 = 34'b0000000000000000000000000000000000;
  wire n1341;
  wire [5:0] n1342;
  wire [5:0] n1344;
  wire [30:0] n1346;
  wire [31:0] n1348;
  wire [30:0] n1349;
  wire [31:0] n1351;
  wire [31:0] n1352;
  wire [32:0] n1353;
  wire [1:0] n1354;
  wire n1357;
  wire n1360;
  wire n1362;
  wire n1363;
  wire [1:0] n1364;
  wire n1365;
  reg n1366;
  wire n1367;
  reg n1368;
  wire [7:0] n1370;
  wire [15:0] n1371;
  wire [6:0] n1372;
  wire [31:0] n1373;
  wire [32:0] n1375;
  wire [32:0] n1376;
  wire n1378;
  wire n1379;
  wire n1380;
  wire n1381;
  wire n1382;
  wire n1384;
  wire n1386;
  wire n1387;
  wire n1388;
  wire [1:0] n1389;
  wire n1390;
  wire n1392;
  wire n1393;
  wire n1395;
  wire n1397;
  wire n1398;
  wire n1399;
  wire n1401;
  wire [2:0] n1402;
  reg n1403;
  wire n1404;
  wire n1406;
  wire n1407;
  wire [1:0] n1408;
  wire [7:0] n1409;
  wire [7:0] n1410;
  wire [7:0] n1411;
  wire n1412;
  wire n1414;
  wire [15:0] n1415;
  wire [15:0] n1416;
  wire [15:0] n1417;
  wire n1418;
  wire n1420;
  wire n1422;
  wire n1423;
  wire [31:0] n1424;
  wire [31:0] n1425;
  wire [31:0] n1426;
  wire n1427;
  wire n1429;
  wire [2:0] n1430;
  wire [7:0] n1431;
  wire [7:0] n1432;
  reg [7:0] n1434;
  wire [7:0] n1435;
  wire [7:0] n1436;
  reg [7:0] n1438;
  wire [15:0] n1439;
  reg [15:0] n1441;
  reg n1442;
  wire n1443;
  wire n1444;
  wire n1445;
  wire n1447;
  wire [1:0] n1448;
  wire [7:0] n1449;
  wire [7:0] n1450;
  wire [7:0] n1451;
  wire n1452;
  wire n1453;
  wire n1454;
  wire n1456;
  wire [15:0] n1457;
  wire [15:0] n1458;
  wire [15:0] n1459;
  wire n1460;
  wire n1461;
  wire n1462;
  wire n1464;
  wire n1466;
  wire n1467;
  wire [31:0] n1468;
  wire [31:0] n1469;
  wire [31:0] n1470;
  wire n1471;
  wire n1472;
  wire n1473;
  wire n1475;
  wire [2:0] n1476;
  wire [7:0] n1477;
  wire [7:0] n1478;
  reg [7:0] n1480;
  wire [7:0] n1481;
  wire [7:0] n1482;
  reg [7:0] n1484;
  wire [15:0] n1485;
  reg [15:0] n1487;
  reg n1488;
  wire n1489;
  wire n1490;
  wire [31:0] n1491;
  wire [31:0] n1492;
  wire [31:0] n1493;
  wire [31:0] n1494;
  wire [31:0] n1495;
  wire n1496;
  wire [31:0] n1497;
  wire [31:0] n1498;
  wire n1500;
  wire n1501;
  wire n1503;
  wire n1505;
  wire n1506;
  wire n1508;
  wire n1509;
  wire n1511;
  wire n1512;
  wire n1513;
  wire n1515;
  wire n1517;
  wire [5:0] n1519;
  wire n1521;
  wire [5:0] n1523;
  wire n1525;
  wire [5:0] n1527;
  wire n1529;
  wire [5:0] n1531;
  wire n1533;
  wire [5:0] n1535;
  wire n1537;
  wire [5:0] n1539;
  wire [5:0] n1540;
  wire [5:0] n1541;
  wire [5:0] n1542;
  wire [5:0] n1543;
  wire [5:0] n1544;
  wire [5:0] n1545;
  wire [5:0] n1547;
  wire n1549;
  wire n1551;
  wire [5:0] n1553;
  wire n1555;
  wire [5:0] n1557;
  wire n1559;
  wire [5:0] n1561;
  wire [5:0] n1562;
  wire [5:0] n1563;
  wire [5:0] n1564;
  wire n1566;
  wire n1568;
  wire [5:0] n1570;
  wire [5:0] n1571;
  wire n1573;
  wire [2:0] n1574;
  wire [5:0] n1576;
  wire n1578;
  wire [3:0] n1579;
  wire [5:0] n1581;
  wire n1583;
  wire [4:0] n1584;
  wire [5:0] n1586;
  wire n1588;
  wire [5:0] n1589;
  reg [5:0] n1591;
  wire n1592;
  wire n1593;
  wire [5:0] n1594;
  wire [5:0] n1595;
  wire n1596;
  wire n1597;
  wire n1598;
  wire n1599;
  wire [5:0] n1601;
  wire [5:0] n1602;
  wire n1603;
  wire n1604;
  wire n1605;
  wire [5:0] n1607;
  wire [5:0] n1608;
  wire [5:0] n1609;
  wire n1610;
  wire n1611;
  wire n1612;
  wire [5:0] n1614;
  wire [5:0] n1616;
  wire n1618;
  wire [5:0] n1619;
  wire n1620;
  wire [5:0] n1621;
  wire n1622;
  wire [31:0] n1623;
  wire [31:0] n1624;
  wire [31:0] n1625;
  localparam [32:0] n1626 = 33'b000000000000000000000000000000000;
  wire n1627;
  wire n1629;
  wire n1630;
  wire n1631;
  wire n1632;
  wire n1633;
  wire [31:0] n1634;
  wire [31:0] n1635;
  wire n1636;
  wire n1638;
  wire [31:0] n1639;
  wire n1640;
  wire [32:0] n1642;
  wire [1:0] n1643;
  wire n1644;
  localparam [23:0] n1645 = 24'b000000000000000000000000;
  localparam [23:0] n1646 = 24'b000000000000000000000000;
  wire n1648;
  wire n1649;
  wire n1650;
  wire n1651;
  wire [22:0] n1652;
  wire n1654;
  wire n1655;
  localparam [15:0] n1656 = 16'b0000000000000000;
  wire n1659;
  wire n1660;
  wire n1661;
  wire n1662;
  wire [14:0] n1663;
  wire n1665;
  wire n1667;
  wire n1668;
  wire n1669;
  wire n1671;
  wire n1672;
  wire n1673;
  wire n1674;
  wire n1676;
  wire [2:0] n1677;
  wire n1678;
  reg n1679;
  wire [6:0] n1680;
  wire [6:0] n1681;
  reg [6:0] n1682;
  wire n1683;
  wire n1684;
  reg n1685;
  wire [14:0] n1686;
  wire [14:0] n1687;
  reg [14:0] n1688;
  wire n1689;
  reg n1690;
  wire [7:0] n1692;
  reg n1696;
  wire [7:0] n1697;
  wire [7:0] n1698;
  reg [7:0] n1699;
  wire [15:0] n1700;
  wire [15:0] n1701;
  reg [15:0] n1702;
  wire [7:0] n1704;
  wire [65:0] n1706;
  wire [30:0] n1707;
  wire [31:0] n1708;
  wire [65:0] n1709;
  wire n1713;
  wire [7:0] n1714;
  wire [7:0] n1715;
  wire n1716;
  wire [7:0] n1717;
  wire [7:0] n1718;
  wire n1719;
  wire [7:0] n1720;
  wire [7:0] n1721;
  wire [7:0] n1722;
  wire [7:0] n1723;
  wire [7:0] n1724;
  wire [7:0] n1725;
  wire n1726;
  wire n1727;
  wire n1728;
  wire n1729;
  wire [7:0] n1730;
  wire n1732;
  wire [7:0] n1734;
  wire n1736;
  wire [15:0] n1738;
  wire n1740;
  wire n1743;
  wire [1:0] n1744;
  wire [1:0] n1746;
  wire [2:0] n1747;
  wire [2:0] n1749;
  wire [2:0] n1751;
  wire n1754;
  wire n1755;
  wire n1756;
  wire [1:0] n1757;
  wire n1758;
  wire [2:0] n1759;
  wire n1760;
  wire [3:0] n1761;
  wire n1762;
  wire n1763;
  wire n1764;
  wire [1:0] n1765;
  wire [1:0] n1766;
  wire [1:0] n1767;
  wire [1:0] n1768;
  wire n1770;
  wire n1771;
  wire n1772;
  wire n1773;
  wire n1774;
  wire [1:0] n1775;
  wire n1776;
  wire [2:0] n1777;
  wire n1778;
  wire [3:0] n1779;
  wire n1780;
  wire n1781;
  wire [1:0] n1782;
  wire n1783;
  wire [2:0] n1784;
  wire n1785;
  wire [3:0] n1786;
  wire [3:0] n1787;
  wire [3:0] n1788;
  wire [3:0] n1789;
  wire n1791;
  wire n1792;
  wire [7:0] n1793;
  wire [7:0] n1794;
  wire n1795;
  wire [7:0] n1796;
  wire [7:0] n1797;
  wire n1798;
  wire n1799;
  wire n1800;
  wire n1801;
  wire n1802;
  wire n1803;
  wire n1805;
  wire n1806;
  wire n1808;
  wire n1809;
  wire n1810;
  wire n1811;
  wire n1812;
  wire [1:0] n1814;
  wire [3:0] n1816;
  wire [3:0] n1818;
  wire [3:0] n1819;
  wire [3:0] n1820;
  wire n1821;
  wire n1822;
  wire [3:0] n1823;
  wire n1824;
  wire n1825;
  wire n1826;
  wire n1828;
  wire n1829;
  wire n1830;
  wire n1831;
  wire n1832;
  wire n1833;
  wire n1834;
  wire n1835;
  wire n1836;
  wire n1837;
  wire n1838;
  wire n1839;
  wire n1840;
  wire n1841;
  wire n1843;
  wire n1845;
  wire n1847;
  wire n1848;
  wire n1849;
  wire [1:0] n1850;
  wire [3:0] n1852;
  wire n1853;
  wire n1854;
  wire [1:0] n1855;
  wire [3:0] n1857;
  wire [3:0] n1858;
  wire [3:0] n1859;
  wire n1860;
  wire n1862;
  wire n1863;
  wire n1864;
  wire n1865;
  wire n1866;
  wire n1870;
  wire n1871;
  wire n1872;
  wire n1873;
  wire n1874;
  wire n1875;
  wire n1876;
  wire n1877;
  wire n1878;
  wire n1879;
  wire n1880;
  wire n1881;
  wire n1882;
  wire n1883;
  wire n1885;
  wire n1886;
  wire n1889;
  wire n1890;
  wire n1891;
  wire n1892;
  wire n1893;
  wire [1:0] n1894;
  wire n1896;
  wire n1897;
  wire n1898;
  wire n1899;
  wire n1900;
  wire n1903;
  wire n1904;
  wire [1:0] n1905;
  wire n1906;
  wire n1907;
  wire n1908;
  wire n1909;
  wire n1910;
  wire n1911;
  wire n1912;
  wire n1913;
  wire n1914;
  wire n1915;
  wire n1916;
  wire n1917;
  wire n1918;
  wire n1919;
  wire n1920;
  wire n1921;
  wire n1922;
  wire n1923;
  wire n1924;
  wire n1925;
  wire n1926;
  wire n1927;
  wire n1929;
  wire n1930;
  wire n1931;
  wire n1932;
  wire n1933;
  wire n1934;
  wire n1936;
  wire n1937;
  wire n1938;
  wire n1939;
  wire [15:0] n1940;
  wire n1942;
  wire n1944;
  wire [15:0] n1945;
  wire n1947;
  wire n1948;
  wire n1949;
  wire n1952;
  wire [3:0] n1955;
  wire [3:0] n1956;
  wire [3:0] n1957;
  wire [3:0] n1958;
  wire [3:0] n1959;
  wire [1:0] n1960;
  wire [1:0] n1961;
  wire [1:0] n1962;
  wire n1963;
  wire n1964;
  wire n1965;
  wire n1966;
  wire n1967;
  wire [3:0] n1968;
  wire [3:0] n1969;
  wire [3:0] n1970;
  wire [3:0] n1971;
  wire [3:0] n1972;
  wire [3:0] n1973;
  wire [3:0] n1974;
  wire [3:0] n1975;
  wire [3:0] n1976;
  wire [3:0] n1977;
  wire [3:0] n1978;
  wire [4:0] n1979;
  wire [4:0] n1980;
  wire [4:0] n1981;
  wire [3:0] n1982;
  wire [3:0] n1983;
  wire [3:0] n1984;
  wire n1985;
  wire n1986;
  wire n1987;
  wire [3:0] n1988;
  wire [4:0] n1989;
  wire [4:0] n1990;
  wire [4:0] n1991;
  wire [2:0] n1992;
  wire [2:0] n1993;
  wire [2:0] n1994;
  wire [3:0] n1996;
  wire [7:0] n1997;
  wire [7:0] n1998;
  wire [3:0] n1999;
  wire n2000;
  wire [7:0] n2002;
  wire [3:0] n2003;
  wire n2004;
  wire [4:0] n2006;
  wire [7:0] n2007;
  wire n2014;
  wire n2015;
  wire n2016;
  wire n2017;
  wire n2019;
  wire n2020;
  wire n2021;
  wire n2024;
  wire [62:0] n2025;
  wire [63:0] n2026;
  wire n2027;
  wire [31:0] n2028;
  wire [32:0] n2029;
  wire [32:0] n2030;
  wire [32:0] n2031;
  wire [31:0] n2032;
  wire [32:0] n2033;
  wire [32:0] n2034;
  wire [32:0] n2035;
  wire [32:0] n2036;
  wire [32:0] n2037;
  wire [32:0] n2038;
  wire [30:0] n2039;
  wire n2040;
  wire n2042;
  wire [15:0] n2043;
  wire [31:0] n2045;
  wire [31:0] n2046;
  wire [31:0] n2069;
  wire n2077;
  wire n2078;
  wire n2079;
  wire n2080;
  wire n2081;
  wire n2082;
  wire n2083;
  wire n2084;
  wire n2086;
  wire n2087;
  wire n2088;
  wire n2089;
  wire n2090;
  wire n2091;
  wire n2092;
  wire n2093;
  wire n2094;
  wire n2095;
  wire n2096;
  wire n2097;
  wire n2098;
  wire n2099;
  wire n2100;
  wire n2101;
  wire n2102;
  wire n2103;
  wire n2104;
  wire n2105;
  wire n2106;
  wire n2107;
  wire n2108;
  wire n2109;
  wire n2110;
  wire n2111;
  wire n2112;
  wire n2113;
  wire n2114;
  wire n2115;
  wire n2116;
  wire n2117;
  wire n2118;
  wire n2119;
  wire n2120;
  wire n2121;
  wire n2122;
  wire n2123;
  wire n2124;
  wire n2125;
  wire n2126;
  wire n2127;
  wire n2128;
  wire n2129;
  wire n2130;
  wire n2131;
  wire n2132;
  wire n2133;
  wire n2134;
  wire n2135;
  wire n2136;
  wire n2137;
  wire n2138;
  wire n2139;
  wire n2140;
  wire n2141;
  wire n2142;
  wire n2143;
  wire n2144;
  wire n2145;
  wire n2146;
  wire n2147;
  wire n2148;
  wire n2149;
  wire [31:0] n2150;
  wire n2151;
  wire n2153;
  wire n2154;
  wire n2155;
  wire n2156;
  wire n2157;
  wire [31:0] n2158;
  wire n2159;
  wire n2160;
  wire [63:0] n2161;
  wire [15:0] n2162;
  wire [15:0] n2163;
  wire [31:0] n2164;
  wire [31:0] n2165;
  wire [15:0] n2166;
  wire [15:0] n2167;
  wire [15:0] n2168;
  wire n2170;
  wire n2171;
  wire n2172;
  wire [15:0] n2173;
  wire [15:0] n2175;
  wire n2176;
  wire n2177;
  wire [32:0] n2178;
  wire [32:0] n2180;
  wire [32:0] n2181;
  wire [32:0] n2182;
  wire [16:0] n2184;
  wire [15:0] n2185;
  wire [32:0] n2186;
  wire [32:0] n2187;
  wire [32:0] n2188;
  wire n2189;
  wire [31:0] n2190;
  wire [31:0] n2191;
  wire [31:0] n2192;
  wire [30:0] n2193;
  wire n2194;
  wire [31:0] n2195;
  wire [31:0] n2196;
  wire [31:0] n2198;
  wire [31:0] n2199;
  wire [31:0] n2200;
  wire n2201;
  wire n2202;
  wire n2203;
  wire n2204;
  wire n2205;
  wire n2206;
  wire n2207;
  wire n2208;
  wire n2209;
  wire n2210;
  wire n2211;
  wire n2212;
  wire n2214;
  wire n2217;
  wire n2223;
  wire n2226;
  wire n2227;
  wire n2228;
  wire [63:0] n2230;
  wire [63:0] n2231;
  wire n2234;
  wire n2235;
  wire n2236;
  wire [63:0] n2237;
  wire n2239;
  wire n2242;
  wire n2243;
  wire n2244;
  wire n2245;
  wire [31:0] n2246;
  wire [32:0] n2248;
  wire [16:0] n2250;
  wire [15:0] n2251;
  wire [32:0] n2252;
  wire [32:0] n2253;
  wire n2256;
  wire n2257;
  wire [31:0] n2258;
  wire [31:0] n2260;
  wire [31:0] n2261;
  wire [31:0] n2262;
  wire [63:0] n2263;
  wire n2265;
  wire n2266;
  wire n2268;
  wire n2269;
  wire n2272;
  wire [31:0] n2282;
  wire [2:0] n2283;
  wire [3:0] n2284;
  wire [8:0] n2285;
  wire [127:0] n2287;
  wire [63:0] n2291;
  wire [63:0] n2294;
  wire [63:0] n2296;
  wire [31:0] n2299;
  wire [39:0] n2301;
  wire [31:0] n2302;
  wire [39:0] n2304;
  wire [4:0] n2305;
  wire [32:0] n2307;
  wire [32:0] n2308;
  wire [32:0] n2309;
  wire [31:0] n2310;
  wire [7:0] n2311;
  reg [7:0] n2312;
  reg [7:0] n2313;
  reg [3:0] n2314;
  wire [63:0] n2315;
  reg [63:0] n2316;
  wire n2317;
  reg n2318;
  reg n2319;
  wire n2320;
  reg n2321;
  wire n2322;
  reg n2323;
  wire [31:0] n2324;
  wire [31:0] n2325;
  reg [31:0] n2326;
  wire [63:0] n2327;
  reg [63:0] n2328;
  wire n2329;
  reg n2330;
  wire [32:0] n2331;
  reg [32:0] n2332;
  wire n2333;
  reg n2334;
  wire n2335;
  reg n2336;
  wire n2337;
  reg n2338;
  wire n2339;
  reg n2340;
  wire n2341;
  reg n2342;
  wire n2343;
  reg n2344;
  wire n2345;
  reg n2346;
  wire n2347;
  reg n2348;
  wire n2349;
  reg n2350;
  wire n2351;
  reg n2352;
  wire n2353;
  wire n2354;
  wire n2355;
  wire n2356;
  wire n2357;
  wire n2358;
  wire n2359;
  wire n2360;
  wire n2361;
  wire n2362;
  wire n2363;
  wire n2364;
  wire n2365;
  wire n2366;
  wire n2367;
  wire n2368;
  wire n2369;
  wire n2370;
  wire n2371;
  wire n2372;
  wire n2373;
  wire n2374;
  wire n2375;
  wire n2376;
  wire n2377;
  wire n2378;
  wire n2379;
  wire n2380;
  wire n2381;
  wire n2382;
  wire n2383;
  wire n2384;
  wire n2385;
  wire n2386;
  wire n2387;
  wire n2388;
  wire n2389;
  wire n2390;
  wire n2391;
  wire n2392;
  wire n2393;
  wire n2394;
  wire n2395;
  wire n2396;
  wire n2397;
  wire n2398;
  wire n2399;
  wire n2400;
  wire n2401;
  wire n2402;
  wire n2403;
  wire n2404;
  wire n2405;
  wire n2406;
  wire n2407;
  wire n2408;
  wire n2409;
  wire n2410;
  wire n2411;
  wire n2412;
  wire n2413;
  wire n2414;
  wire n2415;
  wire n2416;
  wire n2417;
  wire n2418;
  wire n2419;
  wire n2420;
  wire n2421;
  wire n2422;
  wire n2423;
  wire n2424;
  wire n2425;
  wire n2426;
  wire n2427;
  wire n2428;
  wire n2429;
  wire n2430;
  wire n2431;
  wire n2432;
  wire n2433;
  wire n2434;
  wire n2435;
  wire n2436;
  wire n2437;
  wire n2438;
  wire n2439;
  wire n2440;
  wire n2441;
  wire n2442;
  wire n2443;
  wire n2444;
  wire n2445;
  wire n2446;
  wire n2447;
  wire n2448;
  wire n2449;
  wire n2450;
  wire n2451;
  wire n2452;
  wire n2453;
  wire n2454;
  wire n2455;
  wire n2456;
  wire n2457;
  wire n2458;
  wire n2459;
  wire n2460;
  wire n2461;
  wire n2462;
  wire n2463;
  wire n2464;
  wire n2465;
  wire n2466;
  wire n2467;
  wire n2468;
  wire n2469;
  wire n2470;
  wire n2471;
  wire n2472;
  wire n2473;
  wire n2474;
  wire n2475;
  wire n2476;
  wire n2477;
  wire n2478;
  wire n2479;
  wire n2480;
  wire n2481;
  wire n2482;
  wire n2483;
  wire n2484;
  wire n2485;
  wire n2486;
  wire n2487;
  wire [31:0] n2488;
  wire n2489;
  wire n2490;
  wire n2491;
  wire n2492;
  wire n2493;
  wire n2494;
  wire n2495;
  wire n2496;
  wire n2497;
  wire n2498;
  wire n2499;
  wire n2500;
  wire n2501;
  wire n2502;
  wire n2503;
  wire n2504;
  wire n2505;
  wire n2506;
  wire n2507;
  wire n2508;
  wire n2509;
  wire n2510;
  wire n2511;
  wire n2512;
  wire n2513;
  wire n2514;
  wire n2515;
  wire n2516;
  wire n2517;
  wire n2518;
  wire n2519;
  wire n2520;
  wire n2521;
  wire n2522;
  wire n2523;
  wire n2524;
  wire n2525;
  wire n2526;
  wire n2527;
  wire n2528;
  wire n2529;
  wire n2530;
  wire n2531;
  wire n2532;
  wire n2533;
  wire n2534;
  wire n2535;
  wire n2536;
  wire n2537;
  wire n2538;
  wire n2539;
  wire n2540;
  wire n2541;
  wire n2542;
  wire n2543;
  wire n2544;
  wire n2545;
  wire n2546;
  wire n2547;
  wire n2548;
  wire n2549;
  wire n2550;
  wire n2551;
  wire n2552;
  wire n2553;
  wire n2554;
  wire n2555;
  wire n2556;
  wire n2557;
  wire n2558;
  wire n2559;
  wire n2560;
  wire n2561;
  wire n2562;
  wire n2563;
  wire n2564;
  wire n2565;
  wire n2566;
  wire n2567;
  wire n2568;
  wire n2569;
  wire n2570;
  wire n2571;
  wire n2572;
  wire n2573;
  wire n2574;
  wire n2575;
  wire n2576;
  wire n2577;
  wire n2578;
  wire n2579;
  wire n2580;
  wire n2581;
  wire n2582;
  wire n2583;
  wire n2584;
  wire n2585;
  wire n2586;
  wire n2587;
  wire n2588;
  wire n2589;
  wire n2590;
  wire n2591;
  wire n2592;
  wire n2593;
  wire n2594;
  wire n2595;
  wire n2596;
  wire n2597;
  wire n2598;
  wire n2599;
  wire n2600;
  wire n2601;
  wire n2602;
  wire n2603;
  wire n2604;
  wire n2605;
  wire n2606;
  wire n2607;
  wire n2608;
  wire n2609;
  wire n2610;
  wire n2611;
  wire n2612;
  wire n2613;
  wire n2614;
  wire n2615;
  wire n2616;
  wire n2617;
  wire n2618;
  wire n2619;
  wire n2620;
  wire n2621;
  wire n2622;
  wire n2623;
  wire n2624;
  wire n2625;
  wire n2626;
  wire n2627;
  wire n2628;
  wire n2629;
  wire n2630;
  wire n2631;
  wire n2632;
  wire n2633;
  wire n2634;
  wire n2635;
  wire n2636;
  wire n2637;
  wire [33:0] n2638;
  assign bf_ext_out = n2312; //(module output)
  assign set_V_Flag = n2217; //(module output)
  assign Flags = n2313; //(module output)
  assign c_out = n256; //(module output)
  assign addsub_q = n234; //(module output)
  assign ALUout = n18; //(module output)
  /*# TG68K_ALU.vhd:86:16 */
  assign op1in = n2282; // (signal)
  /*# TG68K_ALU.vhd:87:16 */
  assign addsub_a = n122; // (signal)
  /*# TG68K_ALU.vhd:88:16 */
  assign addsub_b = n205; // (signal)
  /*# TG68K_ALU.vhd:89:16 */
  assign notaddsub_b = n217; // (signal)
  /*# TG68K_ALU.vhd:90:16 */
  assign add_result = n222; // (signal)
  /*# TG68K_ALU.vhd:91:16 */
  assign addsub_ofl = n2283; // (signal)
  /*# TG68K_ALU.vhd:92:16 */
  assign opaddsub = n184; // (signal)
  /*# TG68K_ALU.vhd:93:16 */
  assign c_in = n2284; // (signal)
  /*# TG68K_ALU.vhd:94:16 */
  assign flag_z = n1751; // (signal)
  /*# TG68K_ALU.vhd:95:16 */
  assign set_flags = n1789; // (signal)
  /*# TG68K_ALU.vhd:96:16 */
  assign ccrin = n1725; // (signal)
  /*# TG68K_ALU.vhd:97:16 */
  assign last_flags1 = n2314; // (signal)
  /*# TG68K_ALU.vhd:100:16 */
  assign bcd_pur = n262; // (signal)
  /*# TG68K_ALU.vhd:101:16 */
  assign bcd_kor = n2285; // (signal)
  /*# TG68K_ALU.vhd:102:16 */
  assign halve_carry = n267; // (signal)
  /*# TG68K_ALU.vhd:103:16 */
  assign vflag_a = n320; // (signal)
  /*# TG68K_ALU.vhd:104:16 */
  assign bcd_a_carry = n323; // (signal)
  /*# TG68K_ALU.vhd:105:16 */
  assign bcd_a = n317; // (signal)
  /*# TG68K_ALU.vhd:106:16 */
  assign result_mulu = n2287; // (signal)
  /*# TG68K_ALU.vhd:107:16 */
  assign result_div = n2316; // (signal)
  /*# TG68K_ALU.vhd:108:16 */
  assign result_div_pre = n2200; // (signal)
  /*# TG68K_ALU.vhd:110:16 */
  assign v_flag = n2318; // (signal)
  /*# TG68K_ALU.vhd:112:16 */
  assign rot_rot = n1221; // (signal)
  /*# TG68K_ALU.vhd:115:16 */
  assign rot_x = n1274; // (signal)
  /*# TG68K_ALU.vhd:116:16 */
  assign rot_c = n1275; // (signal)
  /*# TG68K_ALU.vhd:117:16 */
  assign rot_out = n1276; // (signal)
  /*# TG68K_ALU.vhd:118:16 */
  assign asl_vflag = n2319; // (signal)
  /*# TG68K_ALU.vhd:120:16 */
  assign bit_number = n364; // (signal)
  /*# TG68K_ALU.vhd:121:16 */
  assign bits_out = n2488; // (signal)
  /*# TG68K_ALU.vhd:122:16 */
  assign one_bit_in = n2353; // (signal)
  /*# TG68K_ALU.vhd:123:16 */
  assign bchg = n2321; // (signal)
  /*# TG68K_ALU.vhd:124:16 */
  assign bset = n2323; // (signal)
  /*# TG68K_ALU.vhd:126:16 */
  assign mulu_sign = n2024; // (signal)
  /*# TG68K_ALU.vhd:128:16 */
  assign muls_msb = n2019; // (signal)
  /*# TG68K_ALU.vhd:129:16 */
  assign mulu_reg = n2291; // (signal)
  /*# TG68K_ALU.vhd:130:16 */
  assign fasign = 1'bX; // (signal)
  /*# TG68K_ALU.vhd:132:16 */
  assign faktorb = n2046; // (signal)
  /*# TG68K_ALU.vhd:134:16 */
  assign div_reg = n2328; // (signal)
  /*# TG68K_ALU.vhd:135:16 */
  assign div_quot = n2294; // (signal)
  /*# TG68K_ALU.vhd:137:16 */
  assign div_neg = n2330; // (signal)
  /*# TG68K_ALU.vhd:138:16 */
  assign div_bit = n2189; // (signal)
  /*# TG68K_ALU.vhd:139:16 */
  assign div_sub = n2188; // (signal)
  /*# TG68K_ALU.vhd:140:16 */
  assign div_over = n2332; // (signal)
  /*# TG68K_ALU.vhd:141:16 */
  assign nozero = n2334; // (signal)
  /*# TG68K_ALU.vhd:142:16 */
  assign div_qsign = n2160; // (signal)
  /*# TG68K_ALU.vhd:143:16 */
  assign dividend = n2296; // (signal)
  /*# TG68K_ALU.vhd:144:16 */
  assign divs = n2084; // (signal)
  /*# TG68K_ALU.vhd:145:16 */
  assign signedop = n2336; // (signal)
  /*# TG68K_ALU.vhd:146:16 */
  assign op1_sign = n2338; // (signal)
  /*# TG68K_ALU.vhd:148:16 */
  assign op2outext = n2175; // (signal)
  /*# TG68K_ALU.vhd:151:16 */
  assign datareg = n2299; // (signal)
  /*# TG68K_ALU.vhd:153:16 */
  assign bf_datareg = n799; // (signal)
  /*# TG68K_ALU.vhd:154:16 */
  assign result = n2301; // (signal)
  /*# TG68K_ALU.vhd:155:16 */
  assign result_tmp = n888; // (signal)
  /*# TG68K_ALU.vhd:156:16 */
  assign unshifted_bitmask = n2302; // (signal)
  /*# TG68K_ALU.vhd:158:16 */
  assign inmux0 = n854; // (signal)
  /*# TG68K_ALU.vhd:159:16 */
  assign inmux1 = n859; // (signal)
  /*# TG68K_ALU.vhd:160:16 */
  assign inmux2 = n864; // (signal)
  /*# TG68K_ALU.vhd:161:16 */
  assign inmux3 = n870; // (signal)
  /*# TG68K_ALU.vhd:162:16 */
  assign shifted_bitmask = n844; // (signal)
  /*# TG68K_ALU.vhd:163:16 */
  assign bitmaskmux0 = n831; // (signal)
  /*# TG68K_ALU.vhd:164:16 */
  assign bitmaskmux1 = n820; // (signal)
  /*# TG68K_ALU.vhd:165:16 */
  assign bitmaskmux2 = n809; // (signal)
  /*# TG68K_ALU.vhd:166:16 */
  assign bitmaskmux3 = n804; // (signal)
  /*# TG68K_ALU.vhd:167:16 */
  assign bf_set2 = n875; // (signal)
  /*# TG68K_ALU.vhd:168:16 */
  assign shift = n2304; // (signal)
  /*# TG68K_ALU.vhd:169:16 */
  assign bf_firstbit = n1090; // (signal)
  /*# TG68K_ALU.vhd:170:16 */
  assign mux = n1167; // (signal)
  /*# TG68K_ALU.vhd:171:16 */
  assign bitnr = n2305; // (signal)
  /*# TG68K_ALU.vhd:172:16 */
  assign mask = datareg; // (signal)
  /*# TG68K_ALU.vhd:173:16 */
  assign mask_not_zero = n1202; // (signal)
  /*# TG68K_ALU.vhd:174:16 */
  assign bf_bset = n2340; // (signal)
  /*# TG68K_ALU.vhd:175:16 */
  assign bf_nflag = n2489; // (signal)
  /*# TG68K_ALU.vhd:176:16 */
  assign bf_bchg = n2342; // (signal)
  /*# TG68K_ALU.vhd:177:16 */
  assign bf_ins = n2344; // (signal)
  /*# TG68K_ALU.vhd:178:16 */
  assign bf_exts = n2346; // (signal)
  /*# TG68K_ALU.vhd:179:16 */
  assign bf_fffo = n2348; // (signal)
  /*# TG68K_ALU.vhd:180:16 */
  assign bf_d32 = n2350; // (signal)
  /*# TG68K_ALU.vhd:181:16 */
  assign bf_s32 = n2352; // (signal)
  /*# TG68K_ALU.vhd:187:16 */
  assign hot_msb = n2638; // (signal)
  /*# TG68K_ALU.vhd:188:16 */
  assign vector = n2307; // (signal)
  /*# TG68K_ALU.vhd:189:16 */
  assign result_bs = n1709; // (signal)
  /*# TG68K_ALU.vhd:190:16 */
  assign bit_nr = n1621; // (signal)
  /*# TG68K_ALU.vhd:191:16 */
  assign bit_msb = n1344; // (signal)
  /*# TG68K_ALU.vhd:192:16 */
  assign bs_shift = n1334; // (signal)
  /*# TG68K_ALU.vhd:193:16 */
  assign bs_shift_mod = n1591; // (signal)
  /*# TG68K_ALU.vhd:194:16 */
  assign asl_over = n1376; // (signal)
  /*# TG68K_ALU.vhd:195:16 */
  assign asl_over_xor = n2308; // (signal)
  /*# TG68K_ALU.vhd:196:16 */
  assign asr_sign = n2309; // (signal)
  /*# TG68K_ALU.vhd:197:16 */
  assign msb = n1696; // (signal)
  /*# TG68K_ALU.vhd:198:16 */
  assign ring = n1314; // (signal)
  /*# TG68K_ALU.vhd:199:16 */
  assign alu = n1498; // (signal)
  /*# TG68K_ALU.vhd:200:16 */
  assign bsout = n2310; // (signal)
  /*# TG68K_ALU.vhd:201:16 */
  assign bs_v = n1511; // (signal)
  /*# TG68K_ALU.vhd:202:16 */
  assign bs_c = n1638; // (signal)
  /*# TG68K_ALU.vhd:203:16 */
  assign bs_x = n1513; // (signal)
  /*# TG68K_ALU.vhd:215:35 */
  assign n8 = op1in[7]; // extract
  /*# TG68K_ALU.vhd:215:39 */
  assign n9 = n8 | exec_tas;
  /*# TG68K_ALU.vhd:76:17 */
  assign n10 = op1in[31:8]; // extract
  /*# TG68K_ALU.vhd:76:17 */
  assign n11 = op1in[6:0]; // extract
  /*# TG68K_ALU.vhd:216:24 */
  assign n12 = exec[76]; // extract
  /*# TG68K_ALU.vhd:217:41 */
  assign n13 = result[31:0]; // extract
  /*# TG68K_ALU.vhd:219:57 */
  assign n14 = {26'b0, bf_firstbit};  // uext
  /*# TG68K_ALU.vhd:219:57 */
  assign n15 = bf_ffo_offset - n14;
  /*# TG68K_ALU.vhd:218:25 */
  assign n16 = bf_fffo ? n15 : n13;
  /*# TG68K_ALU.vhd:76:17 */
  assign n17 = {n10, n9, n11};
  /*# TG68K_ALU.vhd:216:17 */
  assign n18 = n12 ? n16 : n17;
  /*# TG68K_ALU.vhd:224:24 */
  assign n19 = exec[12]; // extract
  /*# TG68K_ALU.vhd:224:45 */
  assign n20 = exec[13]; // extract
  /*# TG68K_ALU.vhd:224:38 */
  assign n21 = n19 | n20;
  /*# TG68K_ALU.vhd:225:51 */
  assign n22 = bcd_a[7:0]; // extract
  /*# TG68K_ALU.vhd:226:27 */
  assign n23 = exec[20]; // extract
  /*# TG68K_ALU.vhd:226:41 */
  assign n25 = 1'b1 & n23;
  /*# TG68K_ALU.vhd:234:40 */
  assign n26 = exec[67]; // extract
  /*# TG68K_ALU.vhd:235:61 */
  assign n27 = result_mulu[31:0]; // extract
  /*# TG68K_ALU.vhd:238:58 */
  assign n28 = mulu_reg[31:0]; // extract
  /*# TG68K_ALU.vhd:234:33 */
  assign n29 = n26 ? n27 : n28;
  /*# TG68K_ALU.vhd:241:27 */
  assign n30 = exec[21]; // extract
  /*# TG68K_ALU.vhd:241:41 */
  assign n32 = 1'b1 & n30;
  /*# TG68K_ALU.vhd:242:38 */
  assign n33 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:242:47 */
  assign n35 = n33 | 1'b0;
  /*# TG68K_ALU.vhd:244:52 */
  assign n36 = result_div[47:32]; // extract
  /*# TG68K_ALU.vhd:244:77 */
  assign n37 = result_div[15:0]; // extract
  /*# TG68K_ALU.vhd:244:66 */
  assign n38 = {n36, n37};
  /*# TG68K_ALU.vhd:246:40 */
  assign n39 = exec[68]; // extract
  /*# TG68K_ALU.vhd:247:60 */
  assign n40 = result_div[63:32]; // extract
  /*# TG68K_ALU.vhd:249:60 */
  assign n41 = result_div[31:0]; // extract
  /*# TG68K_ALU.vhd:246:33 */
  assign n42 = n39 ? n40 : n41;
  /*# TG68K_ALU.vhd:242:25 */
  assign n43 = n35 ? n38 : n42;
  /*# TG68K_ALU.vhd:252:27 */
  assign n44 = exec[5]; // extract
  /*# TG68K_ALU.vhd:253:41 */
  assign n45 = OP2out | OP1out;
  /*# TG68K_ALU.vhd:254:27 */
  assign n46 = exec[6]; // extract
  /*# TG68K_ALU.vhd:255:41 */
  assign n47 = OP2out & OP1out;
  /*# TG68K_ALU.vhd:256:27 */
  assign n48 = exec[16]; // extract
  /*# TG68K_ALU.vhd:257:46 */
  assign n49 = {exe_condition, exe_condition, exe_condition, exe_condition, exe_condition, exe_condition, exe_condition, exe_condition};
  /*# TG68K_ALU.vhd:258:27 */
  assign n50 = exec[7]; // extract
  /*# TG68K_ALU.vhd:259:41 */
  assign n51 = OP2out ^ OP1out;
  /*# TG68K_ALU.vhd:261:27 */
  assign n52 = exec[85]; // extract
  /*# TG68K_ALU.vhd:264:27 */
  assign n53 = exec[9]; // extract
  /*# TG68K_ALU.vhd:266:27 */
  assign n54 = exec[81]; // extract
  /*# TG68K_ALU.vhd:268:27 */
  assign n55 = exec[15]; // extract
  /*# TG68K_ALU.vhd:269:40 */
  assign n56 = OP1out[15:0]; // extract
  /*# TG68K_ALU.vhd:269:61 */
  assign n57 = OP1out[31:16]; // extract
  /*# TG68K_ALU.vhd:269:53 */
  assign n58 = {n56, n57};
  /*# TG68K_ALU.vhd:270:27 */
  assign n59 = exec[14]; // extract
  /*# TG68K_ALU.vhd:272:27 */
  assign n60 = exec[75]; // extract
  /*# TG68K_ALU.vhd:274:27 */
  assign n61 = exec[2]; // extract
  /*# TG68K_ALU.vhd:276:38 */
  assign n62 = exe_opcode[9]; // extract
  /*# TG68K_ALU.vhd:276:25 */
  assign n64 = n62 ? 8'b00000000 : FlagsSR;
  /*# TG68K_ALU.vhd:281:27 */
  assign n65 = exec[77]; // extract
  /*# TG68K_ALU.vhd:282:54 */
  assign n66 = n234[11:8]; // extract
  /*# TG68K_ALU.vhd:282:78 */
  assign n67 = n234[3:0]; // extract
  /*# TG68K_ALU.vhd:282:68 */
  assign n68 = {n66, n67};
  /*# TG68K_ALU.vhd:86:16 */
  assign n69 = n234[7:0]; // extract
  /*# TG68K_ALU.vhd:281:17 */
  assign n70 = n65 ? n68 : n69;
  /*# TG68K_ALU.vhd:274:17 */
  assign n71 = {n64, n2313};
  /*# TG68K_ALU.vhd:274:17 */
  assign n72 = n71[7:0]; // extract
  /*# TG68K_ALU.vhd:274:17 */
  assign n73 = n61 ? n72 : n70;
  /*# TG68K_ALU.vhd:274:17 */
  assign n74 = n71[15:8]; // extract
  /*# TG68K_ALU.vhd:86:16 */
  assign n75 = n234[15:8]; // extract
  /*# TG68K_ALU.vhd:274:17 */
  assign n76 = n61 ? n74 : n75;
  /*# TG68K_ALU.vhd:272:17 */
  assign n77 = {n76, n73};
  /*# TG68K_ALU.vhd:153:16 */
  assign n78 = bf_datareg[15:0]; // extract
  /*# TG68K_ALU.vhd:272:17 */
  assign n79 = n60 ? n78 : n77;
  /*# TG68K_ALU.vhd:153:16 */
  assign n80 = bf_datareg[31:16]; // extract
  /*# TG68K_ALU.vhd:86:16 */
  assign n81 = n234[31:16]; // extract
  /*# TG68K_ALU.vhd:272:17 */
  assign n82 = n60 ? n80 : n81;
  /*# TG68K_ALU.vhd:270:17 */
  assign n83 = {n82, n79};
  /*# TG68K_ALU.vhd:270:17 */
  assign n84 = n59 ? bits_out : n83;
  /*# TG68K_ALU.vhd:268:17 */
  assign n85 = n55 ? n58 : n84;
  /*# TG68K_ALU.vhd:266:17 */
  assign n86 = n54 ? bsout : n85;
  /*# TG68K_ALU.vhd:264:17 */
  assign n87 = n53 ? rot_out : n86;
  /*# TG68K_ALU.vhd:261:17 */
  assign n88 = n52 ? OP2out : n87;
  /*# TG68K_ALU.vhd:258:17 */
  assign n89 = n50 ? n51 : n88;
  /*# TG68K_ALU.vhd:258:17 */
  assign n90 = n89[7:0]; // extract
  /*# TG68K_ALU.vhd:256:17 */
  assign n91 = n48 ? n49 : n90;
  /*# TG68K_ALU.vhd:258:17 */
  assign n92 = n89[31:8]; // extract
  /*# TG68K_ALU.vhd:86:16 */
  assign n93 = n234[31:8]; // extract
  /*# TG68K_ALU.vhd:256:17 */
  assign n94 = n48 ? n93 : n92;
  /*# TG68K_ALU.vhd:254:17 */
  assign n95 = {n94, n91};
  /*# TG68K_ALU.vhd:254:17 */
  assign n96 = n46 ? n47 : n95;
  /*# TG68K_ALU.vhd:252:17 */
  assign n97 = n44 ? n45 : n96;
  /*# TG68K_ALU.vhd:241:17 */
  assign n98 = n32 ? n43 : n97;
  /*# TG68K_ALU.vhd:226:17 */
  assign n99 = n25 ? n29 : n98;
  /*# TG68K_ALU.vhd:226:17 */
  assign n100 = n99[7:0]; // extract
  /*# TG68K_ALU.vhd:224:17 */
  assign n101 = n21 ? n22 : n100;
  /*# TG68K_ALU.vhd:226:17 */
  assign n102 = n99[31:8]; // extract
  /*# TG68K_ALU.vhd:86:16 */
  assign n103 = n234[31:8]; // extract
  /*# TG68K_ALU.vhd:224:17 */
  assign n104 = n21 ? n103 : n102;
  /*# TG68K_ALU.vhd:293:24 */
  assign n109 = exec[29]; // extract
  /*# TG68K_ALU.vhd:294:34 */
  assign n110 = sndOPC[11]; // extract
  /*# TG68K_ALU.vhd:295:51 */
  assign n111 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:295:62 */
  assign n112 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:295:55 */
  assign n113 = {n111, n112};
  /*# TG68K_ALU.vhd:295:73 */
  assign n114 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:295:66 */
  assign n115 = {n113, n114};
  /*# TG68K_ALU.vhd:295:84 */
  assign n116 = OP1out[31:3]; // extract
  /*# TG68K_ALU.vhd:295:77 */
  assign n117 = {n115, n116};
  /*# TG68K_ALU.vhd:297:84 */
  assign n118 = sndOPC[10:9]; // extract
  /*# TG68K_ALU.vhd:297:77 */
  assign n120 = {30'b000000000000000000000000000000, n118};
  /*# TG68K_ALU.vhd:294:25 */
  assign n121 = n110 ? n117 : n120;
  /*# TG68K_ALU.vhd:293:17 */
  assign n122 = n109 ? n121 : OP1out;
  /*# TG68K_ALU.vhd:301:24 */
  assign n123 = exec[48]; // extract
  /*# TG68K_ALU.vhd:301:17 */
  assign n126 = n123 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:309:24 */
  assign n128 = exec[78]; // extract
  /*# TG68K_ALU.vhd:310:65 */
  assign n129 = OP2out[7:4]; // extract
  /*# TG68K_ALU.vhd:310:57 */
  assign n131 = {4'b0000, n129};
  /*# TG68K_ALU.vhd:310:78 */
  assign n133 = {n131, 4'b0000};
  /*# TG68K_ALU.vhd:310:95 */
  assign n134 = OP2out[3:0]; // extract
  /*# TG68K_ALU.vhd:310:87 */
  assign n135 = {n133, n134};
  /*# TG68K_ALU.vhd:311:30 */
  assign n136 = ~execOPC;
  /*# TG68K_ALU.vhd:311:43 */
  assign n137 = exec[53]; // extract
  /*# TG68K_ALU.vhd:311:55 */
  assign n138 = ~n137;
  /*# TG68K_ALU.vhd:311:35 */
  assign n139 = n138 & n136;
  /*# TG68K_ALU.vhd:311:68 */
  assign n140 = exec[29]; // extract
  /*# TG68K_ALU.vhd:311:82 */
  assign n141 = ~n140;
  /*# TG68K_ALU.vhd:311:60 */
  assign n142 = n141 & n139;
  /*# TG68K_ALU.vhd:312:38 */
  assign n143 = ~long_start;
  /*# TG68K_ALU.vhd:312:59 */
  assign n145 = exe_datatype == 2'b00;
  /*# TG68K_ALU.vhd:312:43 */
  assign n146 = n145 & n143;
  /*# TG68K_ALU.vhd:312:73 */
  assign n147 = exec[50]; // extract
  /*# TG68K_ALU.vhd:312:81 */
  assign n148 = ~n147;
  /*# TG68K_ALU.vhd:312:65 */
  assign n149 = n148 & n146;
  /*# TG68K_ALU.vhd:314:41 */
  assign n150 = ~long_start;
  /*# TG68K_ALU.vhd:314:62 */
  assign n152 = exe_datatype == 2'b10;
  /*# TG68K_ALU.vhd:314:46 */
  assign n153 = n152 & n150;
  /*# TG68K_ALU.vhd:314:77 */
  assign n154 = exec[47]; // extract
  /*# TG68K_ALU.vhd:314:93 */
  assign n155 = exec[46]; // extract
  /*# TG68K_ALU.vhd:314:86 */
  assign n156 = n154 | n155;
  /*# TG68K_ALU.vhd:314:103 */
  assign n157 = n156 | movem_presub;
  /*# TG68K_ALU.vhd:314:68 */
  assign n158 = n157 & n153;
  /*# TG68K_ALU.vhd:315:40 */
  assign n159 = exec[69]; // extract
  /*# TG68K_ALU.vhd:315:33 */
  assign n162 = n159 ? 32'b00000000000000000000000000000110 : 32'b00000000000000000000000000000100;
  /*# TG68K_ALU.vhd:314:25 */
  assign n164 = n158 ? n162 : 32'b00000000000000000000000000000010;
  /*# TG68K_ALU.vhd:312:25 */
  assign n166 = n149 ? 32'b00000000000000000000000000000001 : n164;
  /*# TG68K_ALU.vhd:324:33 */
  assign n167 = exec[28]; // extract
  /*# TG68K_ALU.vhd:324:59 */
  assign n168 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:324:50 */
  assign n169 = n168 & n167;
  /*# TG68K_ALU.vhd:324:75 */
  assign n170 = exec[31]; // extract
  /*# TG68K_ALU.vhd:324:68 */
  assign n171 = n169 | n170;
  /*# TG68K_ALU.vhd:324:25 */
  assign n173 = n171 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:327:41 */
  assign n174 = exec[56]; // extract
  /*# TG68K_ALU.vhd:311:17 */
  assign n175 = n142 ? n166 : OP2out;
  /*# TG68K_ALU.vhd:311:17 */
  assign n176 = n142 ? n126 : n174;
  /*# TG68K_ALU.vhd:311:17 */
  assign n177 = n142 ? 1'b0 : n173;
  /*# TG68K_ALU.vhd:311:17 */
  assign n178 = n175[15:0]; // extract
  /*# TG68K_ALU.vhd:309:17 */
  assign n179 = n128 ? n135 : n178;
  /*# TG68K_ALU.vhd:311:17 */
  assign n180 = n175[31:16]; // extract
  /*# TG68K_ALU.vhd:88:16 */
  assign n181 = OP2out[31:16]; // extract
  /*# TG68K_ALU.vhd:309:17 */
  assign n182 = n128 ? n181 : n180;
  /*# TG68K_ALU.vhd:309:17 */
  assign n184 = n128 ? n126 : n176;
  /*# TG68K_ALU.vhd:309:17 */
  assign n185 = n128 ? 1'b0 : n177;
  /*# TG68K_ALU.vhd:331:24 */
  assign n186 = exec[69]; // extract
  /*# TG68K_ALU.vhd:331:43 */
  assign n187 = n186 | check_aligned;
  /*# TG68K_ALU.vhd:332:36 */
  assign n188 = ~movem_presub;
  /*# TG68K_ALU.vhd:333:64 */
  assign n189 = ~long_start;
  /*# TG68K_ALU.vhd:333:48 */
  assign n190 = n189 & non_aligned;
  /*# TG68K_ALU.vhd:88:16 */
  assign n192 = {n182, n179};
  /*# TG68K_ALU.vhd:333:25 */
  assign n193 = n190 ? 32'b00000000000000000000000000000000 : n192;
  /*# TG68K_ALU.vhd:337:64 */
  assign n194 = ~long_start;
  /*# TG68K_ALU.vhd:337:48 */
  assign n195 = n194 & non_aligned;
  /*# TG68K_ALU.vhd:338:44 */
  assign n197 = exe_datatype == 2'b10;
  /*# TG68K_ALU.vhd:338:27 */
  assign n200 = n197 ? 32'b00000000000000000000000000001000 : 32'b00000000000000000000000000000100;
  /*# TG68K_ALU.vhd:88:16 */
  assign n201 = {n182, n179};
  /*# TG68K_ALU.vhd:337:25 */
  assign n202 = n195 ? n200 : n201;
  /*# TG68K_ALU.vhd:332:19 */
  assign n203 = n188 ? n193 : n202;
  /*# TG68K_ALU.vhd:88:16 */
  assign n204 = {n182, n179};
  /*# TG68K_ALU.vhd:331:17 */
  assign n205 = n187 ? n203 : n204;
  /*# TG68K_ALU.vhd:347:28 */
  assign n206 = ~opaddsub;
  /*# TG68K_ALU.vhd:347:33 */
  assign n207 = n206 | long_start;
  /*# TG68K_ALU.vhd:348:43 */
  assign n209 = {1'b0, addsub_b};
  /*# TG68K_ALU.vhd:348:57 */
  assign n210 = c_in[0]; // extract
  /*# TG68K_ALU.vhd:348:52 */
  assign n211 = {n209, n210};
  /*# TG68K_ALU.vhd:350:48 */
  assign n213 = {1'b0, addsub_b};
  /*# TG68K_ALU.vhd:350:62 */
  assign n214 = c_in[0]; // extract
  /*# TG68K_ALU.vhd:350:57 */
  assign n215 = {n213, n214};
  /*# TG68K_ALU.vhd:350:40 */
  assign n216 = ~n215;
  /*# TG68K_ALU.vhd:347:17 */
  assign n217 = n207 ? n211 : n216;
  /*# TG68K_ALU.vhd:352:36 */
  assign n219 = {1'b0, addsub_a};
  /*# TG68K_ALU.vhd:352:57 */
  assign n220 = notaddsub_b[0]; // extract
  /*# TG68K_ALU.vhd:352:45 */
  assign n221 = {n219, n220};
  /*# TG68K_ALU.vhd:352:61 */
  assign n222 = n221 + notaddsub_b;
  /*# TG68K_ALU.vhd:353:38 */
  assign n223 = add_result[9]; // extract
  /*# TG68K_ALU.vhd:353:54 */
  assign n224 = addsub_a[8]; // extract
  /*# TG68K_ALU.vhd:353:42 */
  assign n225 = n223 ^ n224;
  /*# TG68K_ALU.vhd:353:70 */
  assign n226 = addsub_b[8]; // extract
  /*# TG68K_ALU.vhd:353:58 */
  assign n227 = n225 ^ n226;
  /*# TG68K_ALU.vhd:354:38 */
  assign n228 = add_result[17]; // extract
  /*# TG68K_ALU.vhd:354:55 */
  assign n229 = addsub_a[16]; // extract
  /*# TG68K_ALU.vhd:354:43 */
  assign n230 = n228 ^ n229;
  /*# TG68K_ALU.vhd:354:72 */
  assign n231 = addsub_b[16]; // extract
  /*# TG68K_ALU.vhd:354:60 */
  assign n232 = n230 ^ n231;
  /*# TG68K_ALU.vhd:355:38 */
  assign n233 = add_result[33]; // extract
  /*# TG68K_ALU.vhd:356:39 */
  assign n234 = add_result[32:1]; // extract
  /*# TG68K_ALU.vhd:357:39 */
  assign n235 = c_in[1]; // extract
  /*# TG68K_ALU.vhd:357:57 */
  assign n236 = add_result[8]; // extract
  /*# TG68K_ALU.vhd:357:43 */
  assign n237 = n235 ^ n236;
  /*# TG68K_ALU.vhd:357:73 */
  assign n238 = addsub_a[7]; // extract
  /*# TG68K_ALU.vhd:357:61 */
  assign n239 = n237 ^ n238;
  /*# TG68K_ALU.vhd:357:89 */
  assign n240 = addsub_b[7]; // extract
  /*# TG68K_ALU.vhd:357:77 */
  assign n241 = n239 ^ n240;
  /*# TG68K_ALU.vhd:358:39 */
  assign n242 = c_in[2]; // extract
  /*# TG68K_ALU.vhd:358:57 */
  assign n243 = add_result[16]; // extract
  /*# TG68K_ALU.vhd:358:43 */
  assign n244 = n242 ^ n243;
  /*# TG68K_ALU.vhd:358:74 */
  assign n245 = addsub_a[15]; // extract
  /*# TG68K_ALU.vhd:358:62 */
  assign n246 = n244 ^ n245;
  /*# TG68K_ALU.vhd:358:91 */
  assign n247 = addsub_b[15]; // extract
  /*# TG68K_ALU.vhd:358:79 */
  assign n248 = n246 ^ n247;
  /*# TG68K_ALU.vhd:359:39 */
  assign n249 = c_in[3]; // extract
  /*# TG68K_ALU.vhd:359:57 */
  assign n250 = add_result[32]; // extract
  /*# TG68K_ALU.vhd:359:43 */
  assign n251 = n249 ^ n250;
  /*# TG68K_ALU.vhd:359:74 */
  assign n252 = addsub_a[31]; // extract
  /*# TG68K_ALU.vhd:359:62 */
  assign n253 = n251 ^ n252;
  /*# TG68K_ALU.vhd:359:91 */
  assign n254 = addsub_b[31]; // extract
  /*# TG68K_ALU.vhd:359:79 */
  assign n255 = n253 ^ n254;
  /*# TG68K_ALU.vhd:360:30 */
  assign n256 = c_in[3:1]; // extract
  /*# TG68K_ALU.vhd:370:32 */
  assign n260 = c_in[1]; // extract
  /*# TG68K_ALU.vhd:370:46 */
  assign n261 = add_result[8:0]; // extract
  /*# TG68K_ALU.vhd:370:35 */
  assign n262 = {n260, n261};
  /*# TG68K_ALU.vhd:372:38 */
  assign n263 = OP1out[4]; // extract
  /*# TG68K_ALU.vhd:372:52 */
  assign n264 = OP2out[4]; // extract
  /*# TG68K_ALU.vhd:372:42 */
  assign n265 = n263 ^ n264;
  /*# TG68K_ALU.vhd:372:67 */
  assign n266 = bcd_pur[5]; // extract
  /*# TG68K_ALU.vhd:372:56 */
  assign n267 = n265 ^ n266;
  /*# TG68K_ALU.vhd:373:17 */
  assign n270 = halve_carry ? 4'b0110 : 4'b0000;
  /*# TG68K_ALU.vhd:376:27 */
  assign n273 = bcd_pur[9]; // extract
  /*# TG68K_ALU.vhd:101:16 */
  assign n275 = n271[7:4]; // extract
  /*# TG68K_ALU.vhd:376:17 */
  assign n276 = n273 ? 4'b0110 : n275;
  /*# TG68K_ALU.vhd:101:16 */
  assign n277 = n271[8]; // extract
  /*# TG68K_ALU.vhd:379:24 */
  assign n278 = exec[12]; // extract
  /*# TG68K_ALU.vhd:380:47 */
  assign n279 = bcd_pur[8]; // extract
  /*# TG68K_ALU.vhd:380:36 */
  assign n280 = ~n279;
  /*# TG68K_ALU.vhd:380:60 */
  assign n281 = bcd_a[7]; // extract
  /*# TG68K_ALU.vhd:380:51 */
  assign n282 = n280 & n281;
  /*# TG68K_ALU.vhd:382:41 */
  assign n283 = bcd_pur[9:1]; // extract
  /*# TG68K_ALU.vhd:382:54 */
  assign n284 = n283 + bcd_kor;
  /*# TG68K_ALU.vhd:383:36 */
  assign n285 = bcd_pur[4]; // extract
  /*# TG68K_ALU.vhd:383:52 */
  assign n286 = bcd_pur[3]; // extract
  /*# TG68K_ALU.vhd:383:66 */
  assign n287 = bcd_pur[2]; // extract
  /*# TG68K_ALU.vhd:383:56 */
  assign n288 = n286 | n287;
  /*# TG68K_ALU.vhd:383:40 */
  assign n289 = n285 & n288;
  /*# TG68K_ALU.vhd:383:25 */
  assign n291 = n289 ? 4'b0110 : n270;
  /*# TG68K_ALU.vhd:386:36 */
  assign n292 = bcd_pur[8]; // extract
  /*# TG68K_ALU.vhd:386:52 */
  assign n293 = bcd_pur[7]; // extract
  /*# TG68K_ALU.vhd:386:66 */
  assign n294 = bcd_pur[6]; // extract
  /*# TG68K_ALU.vhd:386:56 */
  assign n295 = n293 | n294;
  /*# TG68K_ALU.vhd:386:81 */
  assign n296 = bcd_pur[5]; // extract
  /*# TG68K_ALU.vhd:386:96 */
  assign n297 = bcd_pur[4]; // extract
  /*# TG68K_ALU.vhd:386:85 */
  assign n298 = n296 & n297;
  /*# TG68K_ALU.vhd:386:112 */
  assign n299 = bcd_pur[3]; // extract
  /*# TG68K_ALU.vhd:386:126 */
  assign n300 = bcd_pur[2]; // extract
  /*# TG68K_ALU.vhd:386:116 */
  assign n301 = n299 | n300;
  /*# TG68K_ALU.vhd:386:100 */
  assign n302 = n298 & n301;
  /*# TG68K_ALU.vhd:386:70 */
  assign n303 = n295 | n302;
  /*# TG68K_ALU.vhd:386:40 */
  assign n304 = n292 & n303;
  /*# TG68K_ALU.vhd:386:25 */
  assign n306 = n304 ? 4'b0110 : n276;
  /*# TG68K_ALU.vhd:390:43 */
  assign n307 = bcd_pur[8]; // extract
  /*# TG68K_ALU.vhd:390:60 */
  assign n308 = bcd_a[7]; // extract
  /*# TG68K_ALU.vhd:390:51 */
  assign n309 = ~n308;
  /*# TG68K_ALU.vhd:390:47 */
  assign n310 = n307 & n309;
  /*# TG68K_ALU.vhd:392:41 */
  assign n311 = bcd_pur[9:1]; // extract
  /*# TG68K_ALU.vhd:392:54 */
  assign n312 = n311 - bcd_kor;
  /*# TG68K_ALU.vhd:379:17 */
  assign n313 = {n306, n291};
  /*# TG68K_ALU.vhd:101:16 */
  assign n314 = {n276, n270};
  /*# TG68K_ALU.vhd:379:17 */
  assign n315 = n278 ? n313 : n314;
  /*# TG68K_ALU.vhd:379:17 */
  assign n316 = n278 ? n282 : n310;
  /*# TG68K_ALU.vhd:379:17 */
  assign n317 = n278 ? n284 : n312;
  /*# TG68K_ALU.vhd:394:23 */
  assign n318 = CPU[1]; // extract
  /*# TG68K_ALU.vhd:394:17 */
  assign n320 = n318 ? 1'b0 : n316;
  /*# TG68K_ALU.vhd:397:39 */
  assign n321 = bcd_pur[9]; // extract
  /*# TG68K_ALU.vhd:397:51 */
  assign n322 = bcd_a[8]; // extract
  /*# TG68K_ALU.vhd:397:43 */
  assign n323 = n321 | n322;
  /*# TG68K_ALU.vhd:409:44 */
  assign n328 = opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:410:41 */
  assign n330 = n328 == 2'b01;
  /*# TG68K_ALU.vhd:412:41 */
  assign n332 = n328 == 2'b11;
  /*# TG68K_ALU.vhd:409:33 */
  assign n333 = {n332, n330};
  /*# TG68K_ALU.vhd:409:33 */
  always @*
    case (n333)
      2'b10: n336 = 1'b0;
      2'b01: n336 = 1'b1;
      default: n336 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:409:33 */
  always @*
    case (n333)
      2'b10: n340 = 1'b1;
      2'b01: n340 = 1'b0;
      default: n340 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:419:30 */
  assign n346 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:419:33 */
  assign n347 = ~n346;
  /*# TG68K_ALU.vhd:420:38 */
  assign n348 = exe_opcode[5:4]; // extract
  /*# TG68K_ALU.vhd:420:50 */
  assign n350 = n348 == 2'b00;
  /*# TG68K_ALU.vhd:421:53 */
  assign n351 = sndOPC[4:0]; // extract
  /*# TG68K_ALU.vhd:423:58 */
  assign n352 = sndOPC[2:0]; // extract
  /*# TG68K_ALU.vhd:423:51 */
  assign n354 = {2'b00, n352};
  /*# TG68K_ALU.vhd:420:25 */
  assign n355 = n350 ? n351 : n354;
  /*# TG68K_ALU.vhd:426:38 */
  assign n356 = exe_opcode[5:4]; // extract
  /*# TG68K_ALU.vhd:426:50 */
  assign n358 = n356 == 2'b00;
  /*# TG68K_ALU.vhd:427:53 */
  assign n359 = reg_QB[4:0]; // extract
  /*# TG68K_ALU.vhd:429:58 */
  assign n360 = reg_QB[2:0]; // extract
  /*# TG68K_ALU.vhd:429:51 */
  assign n362 = {2'b00, n360};
  /*# TG68K_ALU.vhd:426:25 */
  assign n363 = n358 ? n359 : n362;
  /*# TG68K_ALU.vhd:419:17 */
  assign n364 = n347 ? n355 : n363;
  /*# TG68K_ALU.vhd:435:65 */
  assign n370 = ~one_bit_in;
  /*# TG68K_ALU.vhd:435:61 */
  assign n371 = bchg & n370;
  /*# TG68K_ALU.vhd:435:81 */
  assign n372 = n371 | bset;
  /*# TG68K_ALU.vhd:456:42 */
  assign n378 = opcode[5:4]; // extract
  /*# TG68K_ALU.vhd:456:55 */
  assign n380 = n378 == 2'b00;
  /*# TG68K_ALU.vhd:456:33 */
  assign n383 = n380 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:459:44 */
  assign n385 = opcode[10:8]; // extract
  /*# TG68K_ALU.vhd:460:41 */
  assign n387 = n385 == 3'b010;
  /*# TG68K_ALU.vhd:461:41 */
  assign n389 = n385 == 3'b011;
  /*# TG68K_ALU.vhd:463:41 */
  assign n391 = n385 == 3'b101;
  /*# TG68K_ALU.vhd:464:41 */
  assign n393 = n385 == 3'b110;
  /*# TG68K_ALU.vhd:465:41 */
  assign n395 = n385 == 3'b111;
  /*# TG68K_ALU.vhd:459:33 */
  assign n396 = {n395, n393, n391, n389, n387};
  /*# TG68K_ALU.vhd:459:33 */
  always @*
    case (n396)
      5'b10000: n399 = 1'b0;
      5'b01000: n399 = 1'b1;
      5'b00100: n399 = 1'b0;
      5'b00010: n399 = 1'b0;
      5'b00001: n399 = 1'b0;
      default: n399 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:459:33 */
  always @*
    case (n396)
      5'b10000: n403 = 1'b0;
      5'b01000: n403 = 1'b0;
      5'b00100: n403 = 1'b0;
      5'b00010: n403 = 1'b0;
      5'b00001: n403 = 1'b1;
      default: n403 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:459:33 */
  always @*
    case (n396)
      5'b10000: n407 = 1'b1;
      5'b01000: n407 = 1'b0;
      5'b00100: n407 = 1'b0;
      5'b00010: n407 = 1'b0;
      5'b00001: n407 = 1'b0;
      default: n407 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:459:33 */
  always @*
    case (n396)
      5'b10000: n411 = 1'b0;
      5'b01000: n411 = 1'b0;
      5'b00100: n411 = 1'b0;
      5'b00010: n411 = 1'b1;
      5'b00001: n411 = 1'b0;
      default: n411 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:459:33 */
  always @*
    case (n396)
      5'b10000: n415 = 1'b0;
      5'b01000: n415 = 1'b0;
      5'b00100: n415 = 1'b1;
      5'b00010: n415 = 1'b0;
      5'b00001: n415 = 1'b0;
      default: n415 = 1'b0;
    endcase
  /*# TG68K_ALU.vhd:459:33 */
  always @*
    case (n396)
      5'b10000: n418 = 1'b1;
      5'b01000: n418 = n383;
      5'b00100: n418 = n383;
      5'b00010: n418 = n383;
      5'b00001: n418 = n383;
      default: n418 = n383;
    endcase
  /*# TG68K_ALU.vhd:469:42 */
  assign n419 = opcode[4:3]; // extract
  /*# TG68K_ALU.vhd:469:54 */
  assign n421 = n419 == 2'b00;
  /*# TG68K_ALU.vhd:469:33 */
  assign n424 = n421 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:472:53 */
  assign n426 = result[39:32]; // extract
  /*# TG68K_ALU.vhd:476:17 */
  assign n443 = bf_ins ? reg_QB : bf_set2;
  /*# TG68K_ALU.vhd:490:38 */
  assign n444 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n446 = $unsigned(5'b00000) > $unsigned(n444);
  /*# TG68K_ALU.vhd:151:16 */
  assign n449 = n443[0]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n450 = n446 ? 1'b0 : n449;
  /*# TG68K_ALU.vhd:490:25 */
  assign n453 = n446 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:490:38 */
  assign n456 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n458 = $unsigned(5'b00001) > $unsigned(n456);
  /*# TG68K_ALU.vhd:151:16 */
  assign n461 = n443[1]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n462 = n458 ? 1'b0 : n461;
  /*# TG68K_ALU.vhd:156:16 */
  assign n464 = n454[1]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n465 = n458 ? 1'b1 : n464;
  /*# TG68K_ALU.vhd:490:38 */
  assign n467 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n469 = $unsigned(5'b00010) > $unsigned(n467);
  /*# TG68K_ALU.vhd:151:16 */
  assign n472 = n443[2]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n473 = n469 ? 1'b0 : n472;
  /*# TG68K_ALU.vhd:156:16 */
  assign n475 = n454[2]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n476 = n469 ? 1'b1 : n475;
  /*# TG68K_ALU.vhd:490:38 */
  assign n478 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n480 = $unsigned(5'b00011) > $unsigned(n478);
  /*# TG68K_ALU.vhd:151:16 */
  assign n483 = n443[3]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n484 = n480 ? 1'b0 : n483;
  /*# TG68K_ALU.vhd:156:16 */
  assign n486 = n454[3]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n487 = n480 ? 1'b1 : n486;
  /*# TG68K_ALU.vhd:490:38 */
  assign n489 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n491 = $unsigned(5'b00100) > $unsigned(n489);
  /*# TG68K_ALU.vhd:151:16 */
  assign n494 = n443[4]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n495 = n491 ? 1'b0 : n494;
  /*# TG68K_ALU.vhd:156:16 */
  assign n497 = n454[4]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n498 = n491 ? 1'b1 : n497;
  /*# TG68K_ALU.vhd:490:38 */
  assign n500 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n502 = $unsigned(5'b00101) > $unsigned(n500);
  /*# TG68K_ALU.vhd:151:16 */
  assign n505 = n443[5]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n506 = n502 ? 1'b0 : n505;
  /*# TG68K_ALU.vhd:156:16 */
  assign n508 = n454[5]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n509 = n502 ? 1'b1 : n508;
  /*# TG68K_ALU.vhd:490:38 */
  assign n511 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n513 = $unsigned(5'b00110) > $unsigned(n511);
  /*# TG68K_ALU.vhd:151:16 */
  assign n516 = n443[6]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n517 = n513 ? 1'b0 : n516;
  /*# TG68K_ALU.vhd:156:16 */
  assign n519 = n454[6]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n520 = n513 ? 1'b1 : n519;
  /*# TG68K_ALU.vhd:490:38 */
  assign n522 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n524 = $unsigned(5'b00111) > $unsigned(n522);
  /*# TG68K_ALU.vhd:151:16 */
  assign n527 = n443[7]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n528 = n524 ? 1'b0 : n527;
  /*# TG68K_ALU.vhd:156:16 */
  assign n530 = n454[7]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n531 = n524 ? 1'b1 : n530;
  /*# TG68K_ALU.vhd:490:38 */
  assign n533 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n535 = $unsigned(5'b01000) > $unsigned(n533);
  /*# TG68K_ALU.vhd:151:16 */
  assign n538 = n443[8]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n539 = n535 ? 1'b0 : n538;
  /*# TG68K_ALU.vhd:156:16 */
  assign n541 = n454[8]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n542 = n535 ? 1'b1 : n541;
  /*# TG68K_ALU.vhd:490:38 */
  assign n544 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n546 = $unsigned(5'b01001) > $unsigned(n544);
  /*# TG68K_ALU.vhd:151:16 */
  assign n549 = n443[9]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n550 = n546 ? 1'b0 : n549;
  /*# TG68K_ALU.vhd:156:16 */
  assign n552 = n454[9]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n553 = n546 ? 1'b1 : n552;
  /*# TG68K_ALU.vhd:490:38 */
  assign n555 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n557 = $unsigned(5'b01010) > $unsigned(n555);
  /*# TG68K_ALU.vhd:151:16 */
  assign n560 = n443[10]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n561 = n557 ? 1'b0 : n560;
  /*# TG68K_ALU.vhd:156:16 */
  assign n563 = n454[10]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n564 = n557 ? 1'b1 : n563;
  /*# TG68K_ALU.vhd:490:38 */
  assign n566 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n568 = $unsigned(5'b01011) > $unsigned(n566);
  /*# TG68K_ALU.vhd:151:16 */
  assign n571 = n443[11]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n572 = n568 ? 1'b0 : n571;
  /*# TG68K_ALU.vhd:156:16 */
  assign n574 = n454[11]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n575 = n568 ? 1'b1 : n574;
  /*# TG68K_ALU.vhd:490:38 */
  assign n577 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n579 = $unsigned(5'b01100) > $unsigned(n577);
  /*# TG68K_ALU.vhd:151:16 */
  assign n582 = n443[12]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n583 = n579 ? 1'b0 : n582;
  /*# TG68K_ALU.vhd:156:16 */
  assign n585 = n454[12]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n586 = n579 ? 1'b1 : n585;
  /*# TG68K_ALU.vhd:490:38 */
  assign n588 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n590 = $unsigned(5'b01101) > $unsigned(n588);
  /*# TG68K_ALU.vhd:151:16 */
  assign n593 = n443[13]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n594 = n590 ? 1'b0 : n593;
  /*# TG68K_ALU.vhd:156:16 */
  assign n596 = n454[13]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n597 = n590 ? 1'b1 : n596;
  /*# TG68K_ALU.vhd:490:38 */
  assign n599 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n601 = $unsigned(5'b01110) > $unsigned(n599);
  /*# TG68K_ALU.vhd:151:16 */
  assign n604 = n443[14]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n605 = n601 ? 1'b0 : n604;
  /*# TG68K_ALU.vhd:156:16 */
  assign n607 = n454[14]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n608 = n601 ? 1'b1 : n607;
  /*# TG68K_ALU.vhd:490:38 */
  assign n610 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n612 = $unsigned(5'b01111) > $unsigned(n610);
  /*# TG68K_ALU.vhd:151:16 */
  assign n615 = n443[15]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n616 = n612 ? 1'b0 : n615;
  /*# TG68K_ALU.vhd:156:16 */
  assign n618 = n454[15]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n619 = n612 ? 1'b1 : n618;
  /*# TG68K_ALU.vhd:490:38 */
  assign n621 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n623 = $unsigned(5'b10000) > $unsigned(n621);
  /*# TG68K_ALU.vhd:151:16 */
  assign n626 = n443[16]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n627 = n623 ? 1'b0 : n626;
  /*# TG68K_ALU.vhd:156:16 */
  assign n629 = n454[16]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n630 = n623 ? 1'b1 : n629;
  /*# TG68K_ALU.vhd:490:38 */
  assign n632 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n634 = $unsigned(5'b10001) > $unsigned(n632);
  /*# TG68K_ALU.vhd:151:16 */
  assign n637 = n443[17]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n638 = n634 ? 1'b0 : n637;
  /*# TG68K_ALU.vhd:156:16 */
  assign n640 = n454[17]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n641 = n634 ? 1'b1 : n640;
  /*# TG68K_ALU.vhd:490:38 */
  assign n643 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n645 = $unsigned(5'b10010) > $unsigned(n643);
  /*# TG68K_ALU.vhd:151:16 */
  assign n648 = n443[18]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n649 = n645 ? 1'b0 : n648;
  /*# TG68K_ALU.vhd:156:16 */
  assign n651 = n454[18]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n652 = n645 ? 1'b1 : n651;
  /*# TG68K_ALU.vhd:490:38 */
  assign n654 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n656 = $unsigned(5'b10011) > $unsigned(n654);
  /*# TG68K_ALU.vhd:151:16 */
  assign n659 = n443[19]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n660 = n656 ? 1'b0 : n659;
  /*# TG68K_ALU.vhd:156:16 */
  assign n662 = n454[19]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n663 = n656 ? 1'b1 : n662;
  /*# TG68K_ALU.vhd:490:38 */
  assign n665 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n667 = $unsigned(5'b10100) > $unsigned(n665);
  /*# TG68K_ALU.vhd:151:16 */
  assign n670 = n443[20]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n671 = n667 ? 1'b0 : n670;
  /*# TG68K_ALU.vhd:156:16 */
  assign n673 = n454[20]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n674 = n667 ? 1'b1 : n673;
  /*# TG68K_ALU.vhd:490:38 */
  assign n676 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n678 = $unsigned(5'b10101) > $unsigned(n676);
  /*# TG68K_ALU.vhd:151:16 */
  assign n681 = n443[21]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n682 = n678 ? 1'b0 : n681;
  /*# TG68K_ALU.vhd:156:16 */
  assign n684 = n454[21]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n685 = n678 ? 1'b1 : n684;
  /*# TG68K_ALU.vhd:490:38 */
  assign n687 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n689 = $unsigned(5'b10110) > $unsigned(n687);
  /*# TG68K_ALU.vhd:151:16 */
  assign n692 = n443[22]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n693 = n689 ? 1'b0 : n692;
  /*# TG68K_ALU.vhd:156:16 */
  assign n695 = n454[22]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n696 = n689 ? 1'b1 : n695;
  /*# TG68K_ALU.vhd:490:38 */
  assign n698 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n700 = $unsigned(5'b10111) > $unsigned(n698);
  /*# TG68K_ALU.vhd:151:16 */
  assign n703 = n443[23]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n704 = n700 ? 1'b0 : n703;
  /*# TG68K_ALU.vhd:156:16 */
  assign n706 = n454[23]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n707 = n700 ? 1'b1 : n706;
  /*# TG68K_ALU.vhd:490:38 */
  assign n709 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n711 = $unsigned(5'b11000) > $unsigned(n709);
  /*# TG68K_ALU.vhd:151:16 */
  assign n714 = n443[24]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n715 = n711 ? 1'b0 : n714;
  /*# TG68K_ALU.vhd:156:16 */
  assign n717 = n454[24]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n718 = n711 ? 1'b1 : n717;
  /*# TG68K_ALU.vhd:490:38 */
  assign n720 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n722 = $unsigned(5'b11001) > $unsigned(n720);
  /*# TG68K_ALU.vhd:151:16 */
  assign n725 = n443[25]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n726 = n722 ? 1'b0 : n725;
  /*# TG68K_ALU.vhd:156:16 */
  assign n728 = n454[25]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n729 = n722 ? 1'b1 : n728;
  /*# TG68K_ALU.vhd:490:38 */
  assign n731 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n733 = $unsigned(5'b11010) > $unsigned(n731);
  /*# TG68K_ALU.vhd:151:16 */
  assign n736 = n443[26]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n737 = n733 ? 1'b0 : n736;
  /*# TG68K_ALU.vhd:156:16 */
  assign n739 = n454[26]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n740 = n733 ? 1'b1 : n739;
  /*# TG68K_ALU.vhd:490:38 */
  assign n742 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n744 = $unsigned(5'b11011) > $unsigned(n742);
  /*# TG68K_ALU.vhd:151:16 */
  assign n747 = n443[27]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n748 = n744 ? 1'b0 : n747;
  /*# TG68K_ALU.vhd:156:16 */
  assign n750 = n454[27]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n751 = n744 ? 1'b1 : n750;
  /*# TG68K_ALU.vhd:490:38 */
  assign n753 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n755 = $unsigned(5'b11100) > $unsigned(n753);
  /*# TG68K_ALU.vhd:151:16 */
  assign n758 = n443[28]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n759 = n755 ? 1'b0 : n758;
  /*# TG68K_ALU.vhd:156:16 */
  assign n761 = n454[28]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n762 = n755 ? 1'b1 : n761;
  /*# TG68K_ALU.vhd:490:38 */
  assign n764 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n766 = $unsigned(5'b11101) > $unsigned(n764);
  /*# TG68K_ALU.vhd:151:16 */
  assign n769 = n443[29]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n770 = n766 ? 1'b0 : n769;
  /*# TG68K_ALU.vhd:156:16 */
  assign n772 = n454[29]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n773 = n766 ? 1'b1 : n772;
  /*# TG68K_ALU.vhd:490:38 */
  assign n775 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n777 = $unsigned(5'b11110) > $unsigned(n775);
  /*# TG68K_ALU.vhd:151:16 */
  assign n780 = n443[30]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n781 = n777 ? 1'b0 : n780;
  /*# TG68K_ALU.vhd:151:16 */
  assign n782 = n443[31]; // extract
  /*# TG68K_ALU.vhd:156:16 */
  assign n783 = n454[30]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n784 = n777 ? 1'b1 : n783;
  /*# TG68K_ALU.vhd:156:16 */
  assign n785 = n454[31]; // extract
  /*# TG68K_ALU.vhd:490:38 */
  assign n786 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n788 = $unsigned(5'b11111) > $unsigned(n786);
  /*# TG68K_ALU.vhd:490:25 */
  assign n791 = n788 ? 1'b0 : n782;
  /*# TG68K_ALU.vhd:490:25 */
  assign n792 = n788 ? 1'b1 : n785;
  /*# TG68K_ALU.vhd:496:37 */
  assign n794 = bf_width[4:0];  // trunc
  /*# TG68K_ALU.vhd:497:32 */
  assign n797 = bf_nflag & bf_exts;
  /*# TG68K_ALU.vhd:498:47 */
  assign n798 = datareg | unshifted_bitmask;
  /*# TG68K_ALU.vhd:497:17 */
  assign n799 = n797 ? n798 : datareg;
  /*# TG68K_ALU.vhd:504:30 */
  assign n800 = bf_loffset[4]; // extract
  /*# TG68K_ALU.vhd:505:57 */
  assign n801 = unshifted_bitmask[15:0]; // extract
  /*# TG68K_ALU.vhd:505:88 */
  assign n802 = unshifted_bitmask[31:16]; // extract
  /*# TG68K_ALU.vhd:505:70 */
  assign n803 = {n801, n802};
  /*# TG68K_ALU.vhd:504:17 */
  assign n804 = n800 ? n803 : unshifted_bitmask;
  /*# TG68K_ALU.vhd:509:30 */
  assign n805 = bf_loffset[3]; // extract
  /*# TG68K_ALU.vhd:510:64 */
  assign n806 = bitmaskmux3[23:0]; // extract
  /*# TG68K_ALU.vhd:510:89 */
  assign n807 = bitmaskmux3[31:24]; // extract
  /*# TG68K_ALU.vhd:510:77 */
  assign n808 = {n806, n807};
  /*# TG68K_ALU.vhd:509:17 */
  assign n809 = n805 ? n808 : bitmaskmux3;
  /*# TG68K_ALU.vhd:514:30 */
  assign n810 = bf_loffset[2]; // extract
  /*# TG68K_ALU.vhd:515:51 */
  assign n812 = {bitmaskmux2, 4'b1111};
  /*# TG68K_ALU.vhd:517:71 */
  assign n813 = bitmaskmux2[31:28]; // extract
  /*# TG68K_ALU.vhd:164:16 */
  assign n814 = n812[3:0]; // extract
  /*# TG68K_ALU.vhd:516:25 */
  assign n815 = bf_d32 ? n813 : n814;
  /*# TG68K_ALU.vhd:164:16 */
  assign n816 = n812[35:4]; // extract
  /*# TG68K_ALU.vhd:520:46 */
  assign n818 = {4'b1111, bitmaskmux2};
  /*# TG68K_ALU.vhd:514:17 */
  assign n819 = {n816, n815};
  /*# TG68K_ALU.vhd:514:17 */
  assign n820 = n810 ? n819 : n818;
  /*# TG68K_ALU.vhd:522:30 */
  assign n821 = bf_loffset[1]; // extract
  /*# TG68K_ALU.vhd:523:51 */
  assign n823 = {bitmaskmux1, 2'b11};
  /*# TG68K_ALU.vhd:525:71 */
  assign n824 = bitmaskmux1[31:30]; // extract
  /*# TG68K_ALU.vhd:163:16 */
  assign n825 = n823[1:0]; // extract
  /*# TG68K_ALU.vhd:524:25 */
  assign n826 = bf_d32 ? n824 : n825;
  /*# TG68K_ALU.vhd:163:16 */
  assign n827 = n823[37:2]; // extract
  /*# TG68K_ALU.vhd:528:44 */
  assign n829 = {2'b11, bitmaskmux1};
  /*# TG68K_ALU.vhd:522:17 */
  assign n830 = {n827, n826};
  /*# TG68K_ALU.vhd:522:17 */
  assign n831 = n821 ? n830 : n829;
  /*# TG68K_ALU.vhd:530:30 */
  assign n832 = bf_loffset[0]; // extract
  /*# TG68K_ALU.vhd:531:47 */
  assign n834 = {1'b1, bitmaskmux0};
  /*# TG68K_ALU.vhd:531:59 */
  assign n836 = {n834, 1'b1};
  /*# TG68K_ALU.vhd:533:66 */
  assign n837 = bitmaskmux0[31]; // extract
  /*# TG68K_ALU.vhd:162:16 */
  assign n838 = n836[0]; // extract
  /*# TG68K_ALU.vhd:532:25 */
  assign n839 = bf_d32 ? n837 : n838;
  /*# TG68K_ALU.vhd:162:16 */
  assign n840 = n836[39:1]; // extract
  /*# TG68K_ALU.vhd:536:48 */
  assign n842 = {2'b11, bitmaskmux0};
  /*# TG68K_ALU.vhd:530:17 */
  assign n843 = {n840, n839};
  /*# TG68K_ALU.vhd:530:17 */
  assign n844 = n832 ? n843 : n842;
  /*# TG68K_ALU.vhd:541:35 */
  assign n845 = {bf_ext_in, OP2out};
  /*# TG68K_ALU.vhd:543:54 */
  assign n846 = OP2out[7:0]; // extract
  /*# TG68K_ALU.vhd:168:16 */
  assign n847 = n845[39:32]; // extract
  /*# TG68K_ALU.vhd:542:17 */
  assign n848 = bf_s32 ? n846 : n847;
  /*# TG68K_ALU.vhd:168:16 */
  assign n849 = n845[31:0]; // extract
  /*# TG68K_ALU.vhd:546:28 */
  assign n850 = bf_shift[0]; // extract
  /*# TG68K_ALU.vhd:547:40 */
  assign n851 = shift[0]; // extract
  /*# TG68K_ALU.vhd:547:49 */
  assign n852 = shift[39:1]; // extract
  /*# TG68K_ALU.vhd:547:43 */
  assign n853 = {n851, n852};
  /*# TG68K_ALU.vhd:546:17 */
  assign n854 = n850 ? n853 : shift;
  /*# TG68K_ALU.vhd:551:28 */
  assign n855 = bf_shift[1]; // extract
  /*# TG68K_ALU.vhd:552:41 */
  assign n856 = inmux0[1:0]; // extract
  /*# TG68K_ALU.vhd:552:60 */
  assign n857 = inmux0[39:2]; // extract
  /*# TG68K_ALU.vhd:552:53 */
  assign n858 = {n856, n857};
  /*# TG68K_ALU.vhd:551:17 */
  assign n859 = n855 ? n858 : inmux0;
  /*# TG68K_ALU.vhd:556:28 */
  assign n860 = bf_shift[2]; // extract
  /*# TG68K_ALU.vhd:557:41 */
  assign n861 = inmux1[3:0]; // extract
  /*# TG68K_ALU.vhd:557:60 */
  assign n862 = inmux1[39:4]; // extract
  /*# TG68K_ALU.vhd:557:53 */
  assign n863 = {n861, n862};
  /*# TG68K_ALU.vhd:556:17 */
  assign n864 = n860 ? n863 : inmux1;
  /*# TG68K_ALU.vhd:561:28 */
  assign n865 = bf_shift[3]; // extract
  /*# TG68K_ALU.vhd:562:41 */
  assign n866 = inmux2[7:0]; // extract
  /*# TG68K_ALU.vhd:562:60 */
  assign n867 = inmux2[31:8]; // extract
  /*# TG68K_ALU.vhd:562:53 */
  assign n868 = {n866, n867};
  /*# TG68K_ALU.vhd:564:41 */
  assign n869 = inmux2[31:0]; // extract
  /*# TG68K_ALU.vhd:561:17 */
  assign n870 = n865 ? n868 : n869;
  /*# TG68K_ALU.vhd:566:28 */
  assign n871 = bf_shift[4]; // extract
  /*# TG68K_ALU.vhd:567:55 */
  assign n872 = inmux3[15:0]; // extract
  /*# TG68K_ALU.vhd:567:75 */
  assign n873 = inmux3[31:16]; // extract
  /*# TG68K_ALU.vhd:567:68 */
  assign n874 = {n872, n873};
  /*# TG68K_ALU.vhd:566:17 */
  assign n875 = n871 ? n874 : inmux3;
  /*# TG68K_ALU.vhd:574:56 */
  assign n876 = bf_set2[7:0]; // extract
  /*# TG68K_ALU.vhd:576:48 */
  assign n877 = ~OP2out;
  /*# TG68K_ALU.vhd:577:49 */
  assign n878 = ~bf_ext_in;
  /*# TG68K_ALU.vhd:575:17 */
  assign n879 = {n878, n877};
  /*# TG68K_ALU.vhd:575:17 */
  assign n881 = bf_bchg ? n879 : 40'b0000000000000000000000000000000000000000;
  /*# TG68K_ALU.vhd:572:17 */
  assign n882 = {n876, bf_set2};
  /*# TG68K_ALU.vhd:572:17 */
  assign n883 = bf_ins ? n882 : n881;
  /*# TG68K_ALU.vhd:581:17 */
  assign n885 = bf_bset ? 40'b1111111111111111111111111111111111111111 : n883;
  /*# TG68K_ALU.vhd:586:48 */
  assign n886 = {bf_ext_in, OP1out};
  /*# TG68K_ALU.vhd:588:48 */
  assign n887 = {bf_ext_in, OP2out};
  /*# TG68K_ALU.vhd:585:17 */
  assign n888 = bf_ins ? n886 : n887;
  /*# TG68K_ALU.vhd:591:43 */
  assign n889 = shifted_bitmask[0]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n890 = result_tmp[0]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n891 = n885[0]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n892 = n889 ? n890 : n891;
  /*# TG68K_ALU.vhd:591:43 */
  assign n894 = shifted_bitmask[1]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n895 = result_tmp[1]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n896 = n885[1]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n897 = n894 ? n895 : n896;
  /*# TG68K_ALU.vhd:591:43 */
  assign n899 = shifted_bitmask[2]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n900 = result_tmp[2]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n901 = n885[2]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n902 = n899 ? n900 : n901;
  /*# TG68K_ALU.vhd:591:43 */
  assign n904 = shifted_bitmask[3]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n905 = result_tmp[3]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n906 = n885[3]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n907 = n904 ? n905 : n906;
  /*# TG68K_ALU.vhd:591:43 */
  assign n909 = shifted_bitmask[4]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n910 = result_tmp[4]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n911 = n885[4]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n912 = n909 ? n910 : n911;
  /*# TG68K_ALU.vhd:591:43 */
  assign n914 = shifted_bitmask[5]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n915 = result_tmp[5]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n916 = n885[5]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n917 = n914 ? n915 : n916;
  /*# TG68K_ALU.vhd:591:43 */
  assign n919 = shifted_bitmask[6]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n920 = result_tmp[6]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n921 = n885[6]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n922 = n919 ? n920 : n921;
  /*# TG68K_ALU.vhd:591:43 */
  assign n924 = shifted_bitmask[7]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n925 = result_tmp[7]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n926 = n885[7]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n927 = n924 ? n925 : n926;
  /*# TG68K_ALU.vhd:591:43 */
  assign n929 = shifted_bitmask[8]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n930 = result_tmp[8]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n931 = n885[8]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n932 = n929 ? n930 : n931;
  /*# TG68K_ALU.vhd:591:43 */
  assign n934 = shifted_bitmask[9]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n935 = result_tmp[9]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n936 = n885[9]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n937 = n934 ? n935 : n936;
  /*# TG68K_ALU.vhd:591:43 */
  assign n939 = shifted_bitmask[10]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n940 = result_tmp[10]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n941 = n885[10]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n942 = n939 ? n940 : n941;
  /*# TG68K_ALU.vhd:591:43 */
  assign n944 = shifted_bitmask[11]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n945 = result_tmp[11]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n946 = n885[11]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n947 = n944 ? n945 : n946;
  /*# TG68K_ALU.vhd:591:43 */
  assign n949 = shifted_bitmask[12]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n950 = result_tmp[12]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n951 = n885[12]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n952 = n949 ? n950 : n951;
  /*# TG68K_ALU.vhd:591:43 */
  assign n954 = shifted_bitmask[13]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n955 = result_tmp[13]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n956 = n885[13]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n957 = n954 ? n955 : n956;
  /*# TG68K_ALU.vhd:591:43 */
  assign n959 = shifted_bitmask[14]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n960 = result_tmp[14]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n961 = n885[14]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n962 = n959 ? n960 : n961;
  /*# TG68K_ALU.vhd:591:43 */
  assign n964 = shifted_bitmask[15]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n965 = result_tmp[15]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n966 = n885[15]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n967 = n964 ? n965 : n966;
  /*# TG68K_ALU.vhd:591:43 */
  assign n969 = shifted_bitmask[16]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n970 = result_tmp[16]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n971 = n885[16]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n972 = n969 ? n970 : n971;
  /*# TG68K_ALU.vhd:591:43 */
  assign n974 = shifted_bitmask[17]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n975 = result_tmp[17]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n976 = n885[17]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n977 = n974 ? n975 : n976;
  /*# TG68K_ALU.vhd:591:43 */
  assign n979 = shifted_bitmask[18]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n980 = result_tmp[18]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n981 = n885[18]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n982 = n979 ? n980 : n981;
  /*# TG68K_ALU.vhd:591:43 */
  assign n984 = shifted_bitmask[19]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n985 = result_tmp[19]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n986 = n885[19]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n987 = n984 ? n985 : n986;
  /*# TG68K_ALU.vhd:591:43 */
  assign n989 = shifted_bitmask[20]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n990 = result_tmp[20]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n991 = n885[20]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n992 = n989 ? n990 : n991;
  /*# TG68K_ALU.vhd:591:43 */
  assign n994 = shifted_bitmask[21]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n995 = result_tmp[21]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n996 = n885[21]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n997 = n994 ? n995 : n996;
  /*# TG68K_ALU.vhd:591:43 */
  assign n999 = shifted_bitmask[22]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1000 = result_tmp[22]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1001 = n885[22]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1002 = n999 ? n1000 : n1001;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1004 = shifted_bitmask[23]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1005 = result_tmp[23]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1006 = n885[23]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1007 = n1004 ? n1005 : n1006;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1009 = shifted_bitmask[24]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1010 = result_tmp[24]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1011 = n885[24]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1012 = n1009 ? n1010 : n1011;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1014 = shifted_bitmask[25]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1015 = result_tmp[25]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1016 = n885[25]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1017 = n1014 ? n1015 : n1016;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1019 = shifted_bitmask[26]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1020 = result_tmp[26]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1021 = n885[26]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1022 = n1019 ? n1020 : n1021;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1024 = shifted_bitmask[27]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1025 = result_tmp[27]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1026 = n885[27]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1027 = n1024 ? n1025 : n1026;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1029 = shifted_bitmask[28]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1030 = result_tmp[28]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1031 = n885[28]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1032 = n1029 ? n1030 : n1031;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1034 = shifted_bitmask[29]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1035 = result_tmp[29]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1036 = n885[29]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1037 = n1034 ? n1035 : n1036;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1039 = shifted_bitmask[30]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1040 = result_tmp[30]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1041 = n885[30]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1042 = n1039 ? n1040 : n1041;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1044 = shifted_bitmask[31]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1045 = result_tmp[31]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1046 = n885[31]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1047 = n1044 ? n1045 : n1046;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1049 = shifted_bitmask[32]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1050 = result_tmp[32]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1051 = n885[32]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1052 = n1049 ? n1050 : n1051;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1054 = shifted_bitmask[33]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1055 = result_tmp[33]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1056 = n885[33]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1057 = n1054 ? n1055 : n1056;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1059 = shifted_bitmask[34]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1060 = result_tmp[34]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1061 = n885[34]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1062 = n1059 ? n1060 : n1061;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1064 = shifted_bitmask[35]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1065 = result_tmp[35]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1066 = n885[35]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1067 = n1064 ? n1065 : n1066;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1069 = shifted_bitmask[36]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1070 = result_tmp[36]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1071 = n885[36]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1072 = n1069 ? n1070 : n1071;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1074 = shifted_bitmask[37]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1075 = result_tmp[37]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1076 = n885[37]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1077 = n1074 ? n1075 : n1076;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1079 = shifted_bitmask[38]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1080 = result_tmp[38]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1081 = n885[38]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1082 = n1079 ? n1080 : n1081;
  /*# TG68K_ALU.vhd:154:16 */
  assign n1083 = n885[39]; // extract
  /*# TG68K_ALU.vhd:591:43 */
  assign n1084 = shifted_bitmask[39]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1085 = result_tmp[39]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1086 = n1084 ? n1085 : n1083;
  /*# TG68K_ALU.vhd:598:36 */
  assign n1088 = {1'b0, bitnr};
  /*# TG68K_ALU.vhd:598:43 */
  assign n1089 = {5'b0, mask_not_zero};  // uext
  /*# TG68K_ALU.vhd:598:43 */
  assign n1090 = n1088 + n1089;
  /*# TG68K_ALU.vhd:601:24 */
  assign n1091 = mask[31:28]; // extract
  /*# TG68K_ALU.vhd:601:38 */
  assign n1093 = n1091 == 4'b0000;
  /*# TG68K_ALU.vhd:602:32 */
  assign n1094 = mask[27:24]; // extract
  /*# TG68K_ALU.vhd:602:46 */
  assign n1096 = n1094 == 4'b0000;
  /*# TG68K_ALU.vhd:603:40 */
  assign n1097 = mask[23:20]; // extract
  /*# TG68K_ALU.vhd:603:54 */
  assign n1099 = n1097 == 4'b0000;
  /*# TG68K_ALU.vhd:604:48 */
  assign n1100 = mask[19:16]; // extract
  /*# TG68K_ALU.vhd:604:62 */
  assign n1102 = n1100 == 4'b0000;
  /*# TG68K_ALU.vhd:606:56 */
  assign n1104 = mask[15:12]; // extract
  /*# TG68K_ALU.vhd:606:70 */
  assign n1106 = n1104 == 4'b0000;
  /*# TG68K_ALU.vhd:607:64 */
  assign n1107 = mask[11:8]; // extract
  /*# TG68K_ALU.vhd:607:77 */
  assign n1109 = n1107 == 4'b0000;
  /*# TG68K_ALU.vhd:609:72 */
  assign n1111 = mask[7:4]; // extract
  /*# TG68K_ALU.vhd:609:84 */
  assign n1113 = n1111 == 4'b0000;
  /*# TG68K_ALU.vhd:611:84 */
  assign n1115 = mask[3:0]; // extract
  /*# TG68K_ALU.vhd:613:84 */
  assign n1116 = mask[7:4]; // extract
  /*# TG68K_ALU.vhd:609:65 */
  assign n1117 = n1113 ? n1115 : n1116;
  /*# TG68K_ALU.vhd:609:65 */
  assign n1119 = n1113 ? 1'b0 : 1'b1;
  /*# TG68K_ALU.vhd:616:76 */
  assign n1120 = mask[11:8]; // extract
  /*# TG68K_ALU.vhd:607:57 */
  assign n1122 = n1109 ? n1117 : n1120;
  /*# TG68K_ALU.vhd:607:57 */
  assign n1123 = {1'b0, n1119};
  /*# TG68K_ALU.vhd:607:57 */
  assign n1124 = n1123[0]; // extract
  /*# TG68K_ALU.vhd:607:57 */
  assign n1125 = n1109 ? n1124 : 1'b0;
  /*# TG68K_ALU.vhd:607:57 */
  assign n1126 = n1123[1]; // extract
  /*# TG68K_ALU.vhd:607:57 */
  assign n1128 = n1109 ? n1126 : 1'b1;
  /*# TG68K_ALU.vhd:620:68 */
  assign n1129 = mask[15:12]; // extract
  /*# TG68K_ALU.vhd:606:49 */
  assign n1130 = n1106 ? n1122 : n1129;
  /*# TG68K_ALU.vhd:606:49 */
  assign n1131 = {n1128, n1125};
  /*# TG68K_ALU.vhd:606:49 */
  assign n1133 = n1106 ? n1131 : 2'b11;
  /*# TG68K_ALU.vhd:623:60 */
  assign n1134 = mask[19:16]; // extract
  /*# TG68K_ALU.vhd:604:41 */
  assign n1137 = n1102 ? n1130 : n1134;
  /*# TG68K_ALU.vhd:604:41 */
  assign n1138 = {1'b0, 1'b0};
  /*# TG68K_ALU.vhd:604:41 */
  assign n1139 = {1'b0, n1133};
  /*# TG68K_ALU.vhd:604:41 */
  assign n1140 = n1139[1:0]; // extract
  /*# TG68K_ALU.vhd:604:41 */
  assign n1141 = n1102 ? n1140 : n1138;
  /*# TG68K_ALU.vhd:604:41 */
  assign n1142 = n1139[2]; // extract
  /*# TG68K_ALU.vhd:604:41 */
  assign n1144 = n1102 ? n1142 : 1'b1;
  /*# TG68K_ALU.vhd:628:52 */
  assign n1145 = mask[23:20]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1147 = n1099 ? n1137 : n1145;
  /*# TG68K_ALU.vhd:603:33 */
  assign n1148 = {n1144, n1141};
  /*# TG68K_ALU.vhd:603:33 */
  assign n1149 = n1148[0]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1151 = n1099 ? n1149 : 1'b1;
  /*# TG68K_ALU.vhd:603:33 */
  assign n1152 = n1148[1]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1153 = n1099 ? n1152 : 1'b0;
  /*# TG68K_ALU.vhd:603:33 */
  assign n1154 = n1148[2]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1156 = n1099 ? n1154 : 1'b1;
  /*# TG68K_ALU.vhd:632:44 */
  assign n1157 = mask[27:24]; // extract
  /*# TG68K_ALU.vhd:602:25 */
  assign n1159 = n1096 ? n1147 : n1157;
  /*# TG68K_ALU.vhd:602:25 */
  assign n1160 = {n1156, n1153, n1151};
  /*# TG68K_ALU.vhd:602:25 */
  assign n1161 = n1160[0]; // extract
  /*# TG68K_ALU.vhd:602:25 */
  assign n1162 = n1096 ? n1161 : 1'b0;
  /*# TG68K_ALU.vhd:602:25 */
  assign n1163 = n1160[2:1]; // extract
  /*# TG68K_ALU.vhd:602:25 */
  assign n1165 = n1096 ? n1163 : 2'b11;
  /*# TG68K_ALU.vhd:636:36 */
  assign n1166 = mask[31:28]; // extract
  /*# TG68K_ALU.vhd:601:17 */
  assign n1167 = n1093 ? n1159 : n1166;
  /*# TG68K_ALU.vhd:601:17 */
  assign n1168 = {n1165, n1162};
  /*# TG68K_ALU.vhd:601:17 */
  assign n1170 = n1093 ? n1168 : 3'b111;
  /*# TG68K_ALU.vhd:639:23 */
  assign n1173 = mux[3:2]; // extract
  /*# TG68K_ALU.vhd:639:35 */
  assign n1175 = n1173 == 2'b00;
  /*# TG68K_ALU.vhd:641:31 */
  assign n1177 = mux[1]; // extract
  /*# TG68K_ALU.vhd:641:34 */
  assign n1178 = ~n1177;
  /*# TG68K_ALU.vhd:643:39 */
  assign n1180 = mux[0]; // extract
  /*# TG68K_ALU.vhd:643:42 */
  assign n1181 = ~n1180;
  /*# TG68K_ALU.vhd:643:33 */
  assign n1184 = n1181 ? 1'b0 : 1'b1;
  /*# TG68K_ALU.vhd:171:16 */
  assign n1185 = n1171[0]; // extract
  /*# TG68K_ALU.vhd:641:25 */
  assign n1186 = n1178 ? 1'b0 : n1185;
  /*# TG68K_ALU.vhd:641:25 */
  assign n1188 = n1178 ? n1184 : 1'b1;
  /*# TG68K_ALU.vhd:648:31 */
  assign n1189 = mux[3]; // extract
  /*# TG68K_ALU.vhd:648:34 */
  assign n1190 = ~n1189;
  /*# TG68K_ALU.vhd:171:16 */
  assign n1192 = n1171[0]; // extract
  /*# TG68K_ALU.vhd:648:25 */
  assign n1193 = n1190 ? 1'b0 : n1192;
  /*# TG68K_ALU.vhd:639:17 */
  assign n1194 = {1'b0, n1186};
  /*# TG68K_ALU.vhd:639:17 */
  assign n1195 = n1194[0]; // extract
  /*# TG68K_ALU.vhd:639:17 */
  assign n1196 = n1175 ? n1195 : n1193;
  /*# TG68K_ALU.vhd:639:17 */
  assign n1197 = n1194[1]; // extract
  /*# TG68K_ALU.vhd:171:16 */
  assign n1198 = n1171[1]; // extract
  /*# TG68K_ALU.vhd:639:17 */
  assign n1199 = n1175 ? n1197 : n1198;
  /*# TG68K_ALU.vhd:639:17 */
  assign n1202 = n1175 ? n1188 : 1'b1;
  /*# TG68K_ALU.vhd:659:32 */
  assign n1207 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:661:66 */
  assign n1208 = OP1out[7]; // extract
  /*# TG68K_ALU.vhd:660:25 */
  assign n1210 = n1207 == 2'b00;
  /*# TG68K_ALU.vhd:663:66 */
  assign n1211 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:662:25 */
  assign n1213 = n1207 == 2'b01;
  /*# TG68K_ALU.vhd:662:34 */
  assign n1215 = n1207 == 2'b11;
  /*# TG68K_ALU.vhd:662:34 */
  assign n1216 = n1213 | n1215;
  /*# TG68K_ALU.vhd:665:66 */
  assign n1217 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:664:25 */
  assign n1219 = n1207 == 2'b10;
  /*# TG68K_ALU.vhd:659:17 */
  assign n1220 = {n1219, n1216, n1210};
  /*# TG68K_ALU.vhd:659:17 */
  always @*
    case (n1220)
      3'b100: n1221 = n1217;
      3'b010: n1221 = n1211;
      3'b001: n1221 = n1208;
      default: n1221 = rot_rot;
    endcase
  /*# TG68K_ALU.vhd:685:24 */
  assign n1239 = exec[23]; // extract
  /*# TG68K_ALU.vhd:687:39 */
  assign n1240 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:688:36 */
  assign n1242 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:689:47 */
  assign n1243 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:688:25 */
  assign n1245 = n1242 ? n1243 : 1'b0;
  /*# TG68K_ALU.vhd:694:38 */
  assign n1246 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:699:48 */
  assign n1249 = OP1out[0]; // extract
  /*# TG68K_ALU.vhd:700:48 */
  assign n1250 = OP1out[0]; // extract
  /*# TG68K_ALU.vhd:694:25 */
  assign n1270 = n1246 ? rot_rot : n1249;
  /*# TG68K_ALU.vhd:694:25 */
  assign n1271 = n1246 ? rot_rot : n1250;
  /*# TG68K_ALU.vhd:685:17 */
  assign n1274 = n1239 ? n1240 : n1270;
  /*# TG68K_ALU.vhd:685:17 */
  assign n1275 = n1239 ? n1245 : n1271;
  /*# TG68K_ALU.vhd:685:17 */
  assign n1276 = n1239 ? OP1out : bsout;
  /*# TG68K_ALU.vhd:723:28 */
  assign n1281 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:724:40 */
  assign n1282 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:725:33 */
  assign n1284 = n1282 == 2'b00;
  /*# TG68K_ALU.vhd:727:33 */
  assign n1286 = n1282 == 2'b01;
  /*# TG68K_ALU.vhd:727:42 */
  assign n1288 = n1282 == 2'b11;
  /*# TG68K_ALU.vhd:727:42 */
  assign n1289 = n1286 | n1288;
  /*# TG68K_ALU.vhd:729:33 */
  assign n1291 = n1282 == 2'b10;
  /*# TG68K_ALU.vhd:724:25 */
  assign n1292 = {n1291, n1289, n1284};
  /*# TG68K_ALU.vhd:724:25 */
  always @*
    case (n1292)
      3'b100: n1297 = 6'b100001;
      3'b010: n1297 = 6'b010001;
      3'b001: n1297 = 6'b001001;
      default: n1297 = 6'b100000;
    endcase
  /*# TG68K_ALU.vhd:734:40 */
  assign n1298 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:735:33 */
  assign n1300 = n1298 == 2'b00;
  /*# TG68K_ALU.vhd:737:33 */
  assign n1302 = n1298 == 2'b01;
  /*# TG68K_ALU.vhd:737:42 */
  assign n1304 = n1298 == 2'b11;
  /*# TG68K_ALU.vhd:737:42 */
  assign n1305 = n1302 | n1304;
  /*# TG68K_ALU.vhd:739:33 */
  assign n1307 = n1298 == 2'b10;
  /*# TG68K_ALU.vhd:734:25 */
  assign n1308 = {n1307, n1305, n1300};
  /*# TG68K_ALU.vhd:734:25 */
  always @*
    case (n1308)
      3'b100: n1313 = 6'b100000;
      3'b010: n1313 = 6'b010000;
      3'b001: n1313 = 6'b001000;
      default: n1313 = 6'b100000;
    endcase
  /*# TG68K_ALU.vhd:723:17 */
  assign n1314 = n1281 ? n1297 : n1313;
  /*# TG68K_ALU.vhd:745:30 */
  assign n1316 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:745:42 */
  assign n1318 = n1316 == 2'b11;
  /*# TG68K_ALU.vhd:745:55 */
  assign n1319 = exec[81]; // extract
  /*# TG68K_ALU.vhd:745:64 */
  assign n1320 = ~n1319;
  /*# TG68K_ALU.vhd:745:48 */
  assign n1321 = n1318 | n1320;
  /*# TG68K_ALU.vhd:747:33 */
  assign n1322 = exe_opcode[5]; // extract
  /*# TG68K_ALU.vhd:748:43 */
  assign n1323 = OP2out[5:0]; // extract
  /*# TG68K_ALU.vhd:750:59 */
  assign n1324 = exe_opcode[11:9]; // extract
  /*# TG68K_ALU.vhd:751:38 */
  assign n1325 = exe_opcode[11:9]; // extract
  /*# TG68K_ALU.vhd:751:51 */
  assign n1327 = n1325 == 3'b000;
  /*# TG68K_ALU.vhd:751:25 */
  assign n1330 = n1327 ? 3'b001 : 3'b000;
  /*# TG68K_ALU.vhd:747:17 */
  assign n1331 = {n1330, n1324};
  /*# TG68K_ALU.vhd:747:17 */
  assign n1332 = n1322 ? n1323 : n1331;
  /*# TG68K_ALU.vhd:745:17 */
  assign n1334 = n1321 ? 6'b000001 : n1332;
  /*# TG68K_ALU.vhd:762:29 */
  assign n1341 = $unsigned(bs_shift) < $unsigned(ring);
  /*# TG68K_ALU.vhd:763:40 */
  assign n1342 = ring - bs_shift;
  /*# TG68K_ALU.vhd:762:17 */
  assign n1344 = n1341 ? n1342 : 6'b000000;
  /*# TG68K_ALU.vhd:765:45 */
  assign n1346 = vector[30:0]; // extract
  /*# TG68K_ALU.vhd:765:38 */
  assign n1348 = {1'b0, n1346};
  /*# TG68K_ALU.vhd:765:75 */
  assign n1349 = vector[31:1]; // extract
  /*# TG68K_ALU.vhd:765:68 */
  assign n1351 = {1'b0, n1349};
  /*# TG68K_ALU.vhd:765:60 */
  assign n1352 = n1348 ^ n1351;
  /*# TG68K_ALU.vhd:765:90 */
  assign n1353 = {n1352, msb};
  /*# TG68K_ALU.vhd:766:32 */
  assign n1354 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:767:25 */
  assign n1357 = n1354 == 2'b00;
  /*# TG68K_ALU.vhd:769:25 */
  assign n1360 = n1354 == 2'b01;
  /*# TG68K_ALU.vhd:769:34 */
  assign n1362 = n1354 == 2'b11;
  /*# TG68K_ALU.vhd:769:34 */
  assign n1363 = n1360 | n1362;
  /*# TG68K_ALU.vhd:766:17 */
  assign n1364 = {n1363, n1357};
  /*# TG68K_ALU.vhd:195:16 */
  assign n1365 = n1353[8]; // extract
  /*# TG68K_ALU.vhd:766:17 */
  always @*
    case (n1364)
      2'b10: n1366 = n1365;
      2'b01: n1366 = 1'b0;
      default: n1366 = n1365;
    endcase
  /*# TG68K_ALU.vhd:195:16 */
  assign n1367 = n1353[16]; // extract
  /*# TG68K_ALU.vhd:766:17 */
  always @*
    case (n1364)
      2'b10: n1368 = 1'b0;
      2'b01: n1368 = n1367;
      default: n1368 = n1367;
    endcase
  /*# TG68K_ALU.vhd:195:16 */
  assign n1370 = n1353[7:0]; // extract
  /*# TG68K_ALU.vhd:195:16 */
  assign n1371 = n1353[32:17]; // extract
  /*# TG68K_ALU.vhd:195:16 */
  assign n1372 = n1353[15:9]; // extract
  /*# TG68K_ALU.vhd:773:56 */
  assign n1373 = hot_msb[31:0]; // extract
  /*# TG68K_ALU.vhd:773:48 */
  assign n1375 = {1'b0, n1373};
  /*# TG68K_ALU.vhd:773:42 */
  assign n1376 = asl_over_xor - n1375;
  /*# TG68K_ALU.vhd:775:28 */
  assign n1378 = rot_bits == 2'b00;
  /*# TG68K_ALU.vhd:775:48 */
  assign n1379 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:775:34 */
  assign n1380 = n1379 & n1378;
  /*# TG68K_ALU.vhd:776:45 */
  assign n1381 = asl_over[32]; // extract
  /*# TG68K_ALU.vhd:776:33 */
  assign n1382 = ~n1381;
  /*# TG68K_ALU.vhd:775:17 */
  assign n1384 = n1380 ? n1382 : 1'b0;
  /*# TG68K_ALU.vhd:780:30 */
  assign n1386 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:780:33 */
  assign n1387 = ~n1386;
  /*# TG68K_ALU.vhd:781:42 */
  assign n1388 = result_bs[31]; // extract
  /*# TG68K_ALU.vhd:783:40 */
  assign n1389 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:785:58 */
  assign n1390 = result_bs[8]; // extract
  /*# TG68K_ALU.vhd:784:33 */
  assign n1392 = n1389 == 2'b00;
  /*# TG68K_ALU.vhd:787:58 */
  assign n1393 = result_bs[16]; // extract
  /*# TG68K_ALU.vhd:786:33 */
  assign n1395 = n1389 == 2'b01;
  /*# TG68K_ALU.vhd:786:42 */
  assign n1397 = n1389 == 2'b11;
  /*# TG68K_ALU.vhd:786:42 */
  assign n1398 = n1395 | n1397;
  /*# TG68K_ALU.vhd:789:58 */
  assign n1399 = result_bs[32]; // extract
  /*# TG68K_ALU.vhd:788:33 */
  assign n1401 = n1389 == 2'b10;
  /*# TG68K_ALU.vhd:783:25 */
  assign n1402 = {n1401, n1398, n1392};
  /*# TG68K_ALU.vhd:783:25 */
  always @*
    case (n1402)
      3'b100: n1403 = n1399;
      3'b010: n1403 = n1393;
      3'b001: n1403 = n1390;
      default: n1403 = bs_c;
    endcase
  /*# TG68K_ALU.vhd:780:17 */
  assign n1404 = n1387 ? n1388 : n1403;
  /*# TG68K_ALU.vhd:795:28 */
  assign n1406 = rot_bits == 2'b11;
  /*# TG68K_ALU.vhd:796:38 */
  assign n1407 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:797:40 */
  assign n1408 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:799:69 */
  assign n1409 = result_bs[7:0]; // extract
  /*# TG68K_ALU.vhd:799:94 */
  assign n1410 = result_bs[15:8]; // extract
  /*# TG68K_ALU.vhd:799:82 */
  assign n1411 = n1409 | n1410;
  /*# TG68K_ALU.vhd:800:52 */
  assign n1412 = alu[7]; // extract
  /*# TG68K_ALU.vhd:798:33 */
  assign n1414 = n1408 == 2'b00;
  /*# TG68K_ALU.vhd:802:70 */
  assign n1415 = result_bs[15:0]; // extract
  /*# TG68K_ALU.vhd:802:96 */
  assign n1416 = result_bs[31:16]; // extract
  /*# TG68K_ALU.vhd:802:84 */
  assign n1417 = n1415 | n1416;
  /*# TG68K_ALU.vhd:803:52 */
  assign n1418 = alu[15]; // extract
  /*# TG68K_ALU.vhd:801:33 */
  assign n1420 = n1408 == 2'b01;
  /*# TG68K_ALU.vhd:801:42 */
  assign n1422 = n1408 == 2'b11;
  /*# TG68K_ALU.vhd:801:42 */
  assign n1423 = n1420 | n1422;
  /*# TG68K_ALU.vhd:805:57 */
  assign n1424 = result_bs[31:0]; // extract
  /*# TG68K_ALU.vhd:805:83 */
  assign n1425 = result_bs[63:32]; // extract
  /*# TG68K_ALU.vhd:805:71 */
  assign n1426 = n1424 | n1425;
  /*# TG68K_ALU.vhd:806:52 */
  assign n1427 = alu[31]; // extract
  /*# TG68K_ALU.vhd:804:33 */
  assign n1429 = n1408 == 2'b10;
  /*# TG68K_ALU.vhd:797:25 */
  assign n1430 = {n1429, n1423, n1414};
  /*# TG68K_ALU.vhd:802:84 */
  assign n1431 = n1417[7:0]; // extract
  /*# TG68K_ALU.vhd:805:71 */
  assign n1432 = n1426[7:0]; // extract
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1430)
      3'b100: n1434 = n1432;
      3'b010: n1434 = n1431;
      3'b001: n1434 = n1411;
      default: n1434 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:802:84 */
  assign n1435 = n1417[15:8]; // extract
  /*# TG68K_ALU.vhd:805:71 */
  assign n1436 = n1426[15:8]; // extract
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1430)
      3'b100: n1438 = n1436;
      3'b010: n1438 = n1435;
      3'b001: n1438 = 8'bX;
      default: n1438 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:805:71 */
  assign n1439 = n1426[31:16]; // extract
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1430)
      3'b100: n1441 = n1439;
      3'b010: n1441 = 16'bX;
      3'b001: n1441 = 16'bX;
      default: n1441 = 16'bX;
    endcase
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1430)
      3'b100: n1442 = n1427;
      3'b010: n1442 = n1418;
      3'b001: n1442 = n1412;
      default: n1442 = n1404;
    endcase
  /*# TG68K_ALU.vhd:809:38 */
  assign n1443 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:810:44 */
  assign n1444 = alu[0]; // extract
  /*# TG68K_ALU.vhd:809:25 */
  assign n1445 = n1443 ? n1444 : n1442;
  /*# TG68K_ALU.vhd:812:31 */
  assign n1447 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:813:40 */
  assign n1448 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:815:69 */
  assign n1449 = result_bs[7:0]; // extract
  /*# TG68K_ALU.vhd:815:94 */
  assign n1450 = result_bs[16:9]; // extract
  /*# TG68K_ALU.vhd:815:82 */
  assign n1451 = n1449 | n1450;
  /*# TG68K_ALU.vhd:816:58 */
  assign n1452 = result_bs[8]; // extract
  /*# TG68K_ALU.vhd:816:74 */
  assign n1453 = result_bs[17]; // extract
  /*# TG68K_ALU.vhd:816:62 */
  assign n1454 = n1452 | n1453;
  /*# TG68K_ALU.vhd:814:33 */
  assign n1456 = n1448 == 2'b00;
  /*# TG68K_ALU.vhd:818:70 */
  assign n1457 = result_bs[15:0]; // extract
  /*# TG68K_ALU.vhd:818:96 */
  assign n1458 = result_bs[32:17]; // extract
  /*# TG68K_ALU.vhd:818:84 */
  assign n1459 = n1457 | n1458;
  /*# TG68K_ALU.vhd:819:58 */
  assign n1460 = result_bs[16]; // extract
  /*# TG68K_ALU.vhd:819:75 */
  assign n1461 = result_bs[33]; // extract
  /*# TG68K_ALU.vhd:819:63 */
  assign n1462 = n1460 | n1461;
  /*# TG68K_ALU.vhd:817:33 */
  assign n1464 = n1448 == 2'b01;
  /*# TG68K_ALU.vhd:817:42 */
  assign n1466 = n1448 == 2'b11;
  /*# TG68K_ALU.vhd:817:42 */
  assign n1467 = n1464 | n1466;
  /*# TG68K_ALU.vhd:821:57 */
  assign n1468 = result_bs[31:0]; // extract
  /*# TG68K_ALU.vhd:821:83 */
  assign n1469 = result_bs[64:33]; // extract
  /*# TG68K_ALU.vhd:821:71 */
  assign n1470 = n1468 | n1469;
  /*# TG68K_ALU.vhd:822:58 */
  assign n1471 = result_bs[32]; // extract
  /*# TG68K_ALU.vhd:822:75 */
  assign n1472 = result_bs[65]; // extract
  /*# TG68K_ALU.vhd:822:63 */
  assign n1473 = n1471 | n1472;
  /*# TG68K_ALU.vhd:820:33 */
  assign n1475 = n1448 == 2'b10;
  /*# TG68K_ALU.vhd:813:25 */
  assign n1476 = {n1475, n1467, n1456};
  /*# TG68K_ALU.vhd:818:84 */
  assign n1477 = n1459[7:0]; // extract
  /*# TG68K_ALU.vhd:821:71 */
  assign n1478 = n1470[7:0]; // extract
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1476)
      3'b100: n1480 = n1478;
      3'b010: n1480 = n1477;
      3'b001: n1480 = n1451;
      default: n1480 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:818:84 */
  assign n1481 = n1459[15:8]; // extract
  /*# TG68K_ALU.vhd:821:71 */
  assign n1482 = n1470[15:8]; // extract
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1476)
      3'b100: n1484 = n1482;
      3'b010: n1484 = n1481;
      3'b001: n1484 = 8'bX;
      default: n1484 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:821:71 */
  assign n1485 = n1470[31:16]; // extract
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1476)
      3'b100: n1487 = n1485;
      3'b010: n1487 = 16'bX;
      3'b001: n1487 = 16'bX;
      default: n1487 = 16'bX;
    endcase
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1476)
      3'b100: n1488 = n1473;
      3'b010: n1488 = n1462;
      3'b001: n1488 = n1454;
      default: n1488 = n1404;
    endcase
  /*# TG68K_ALU.vhd:826:38 */
  assign n1489 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:826:41 */
  assign n1490 = ~n1489;
  /*# TG68K_ALU.vhd:827:49 */
  assign n1491 = result_bs[63:32]; // extract
  /*# TG68K_ALU.vhd:829:49 */
  assign n1492 = result_bs[31:0]; // extract
  /*# TG68K_ALU.vhd:826:25 */
  assign n1493 = n1490 ? n1491 : n1492;
  /*# TG68K_ALU.vhd:812:17 */
  assign n1494 = {n1487, n1484, n1480};
  /*# TG68K_ALU.vhd:812:17 */
  assign n1495 = n1447 ? n1494 : n1493;
  /*# TG68K_ALU.vhd:812:17 */
  assign n1496 = n1447 ? n1488 : n1404;
  /*# TG68K_ALU.vhd:795:17 */
  assign n1497 = {n1441, n1438, n1434};
  /*# TG68K_ALU.vhd:795:17 */
  assign n1498 = n1406 ? n1497 : n1495;
  /*# TG68K_ALU.vhd:795:17 */
  assign n1500 = n1406 ? n1445 : n1496;
  /*# TG68K_ALU.vhd:795:17 */
  assign n1501 = n1406 ? n1407 : bs_c;
  /*# TG68K_ALU.vhd:833:29 */
  assign n1503 = bs_shift == 6'b000000;
  /*# TG68K_ALU.vhd:834:36 */
  assign n1505 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:835:46 */
  assign n1506 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:834:25 */
  assign n1508 = n1505 ? n1506 : 1'b0;
  /*# TG68K_ALU.vhd:839:38 */
  assign n1509 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:833:17 */
  assign n1511 = n1503 ? 1'b0 : n1384;
  /*# TG68K_ALU.vhd:833:17 */
  assign n1512 = n1503 ? n1508 : n1500;
  /*# TG68K_ALU.vhd:833:17 */
  assign n1513 = n1503 ? n1509 : n1501;
  /*# TG68K_ALU.vhd:848:45 */
  assign n1515 = bs_shift == 6'b111111;
  /*# TG68K_ALU.vhd:850:48 */
  assign n1517 = $unsigned(bs_shift) > $unsigned(6'b110101);
  /*# TG68K_ALU.vhd:851:66 */
  assign n1519 = bs_shift - 6'b110110;
  /*# TG68K_ALU.vhd:852:48 */
  assign n1521 = $unsigned(bs_shift) > $unsigned(6'b101100);
  /*# TG68K_ALU.vhd:853:66 */
  assign n1523 = bs_shift - 6'b101101;
  /*# TG68K_ALU.vhd:854:48 */
  assign n1525 = $unsigned(bs_shift) > $unsigned(6'b100011);
  /*# TG68K_ALU.vhd:855:66 */
  assign n1527 = bs_shift - 6'b100100;
  /*# TG68K_ALU.vhd:856:48 */
  assign n1529 = $unsigned(bs_shift) > $unsigned(6'b011010);
  /*# TG68K_ALU.vhd:857:66 */
  assign n1531 = bs_shift - 6'b011011;
  /*# TG68K_ALU.vhd:858:48 */
  assign n1533 = $unsigned(bs_shift) > $unsigned(6'b010001);
  /*# TG68K_ALU.vhd:859:66 */
  assign n1535 = bs_shift - 6'b010010;
  /*# TG68K_ALU.vhd:860:48 */
  assign n1537 = $unsigned(bs_shift) > $unsigned(6'b001000);
  /*# TG68K_ALU.vhd:861:66 */
  assign n1539 = bs_shift - 6'b001001;
  /*# TG68K_ALU.vhd:860:33 */
  assign n1540 = n1537 ? n1539 : bs_shift;
  /*# TG68K_ALU.vhd:858:33 */
  assign n1541 = n1533 ? n1535 : n1540;
  /*# TG68K_ALU.vhd:856:33 */
  assign n1542 = n1529 ? n1531 : n1541;
  /*# TG68K_ALU.vhd:854:33 */
  assign n1543 = n1525 ? n1527 : n1542;
  /*# TG68K_ALU.vhd:852:33 */
  assign n1544 = n1521 ? n1523 : n1543;
  /*# TG68K_ALU.vhd:850:33 */
  assign n1545 = n1517 ? n1519 : n1544;
  /*# TG68K_ALU.vhd:848:33 */
  assign n1547 = n1515 ? 6'b000000 : n1545;
  /*# TG68K_ALU.vhd:847:25 */
  assign n1549 = ring == 6'b001001;
  /*# TG68K_ALU.vhd:866:45 */
  assign n1551 = $unsigned(bs_shift) > $unsigned(6'b110010);
  /*# TG68K_ALU.vhd:867:66 */
  assign n1553 = bs_shift - 6'b110011;
  /*# TG68K_ALU.vhd:868:48 */
  assign n1555 = $unsigned(bs_shift) > $unsigned(6'b100001);
  /*# TG68K_ALU.vhd:869:66 */
  assign n1557 = bs_shift - 6'b100010;
  /*# TG68K_ALU.vhd:870:48 */
  assign n1559 = $unsigned(bs_shift) > $unsigned(6'b010000);
  /*# TG68K_ALU.vhd:871:66 */
  assign n1561 = bs_shift - 6'b010001;
  /*# TG68K_ALU.vhd:870:33 */
  assign n1562 = n1559 ? n1561 : bs_shift;
  /*# TG68K_ALU.vhd:868:33 */
  assign n1563 = n1555 ? n1557 : n1562;
  /*# TG68K_ALU.vhd:866:33 */
  assign n1564 = n1551 ? n1553 : n1563;
  /*# TG68K_ALU.vhd:865:25 */
  assign n1566 = ring == 6'b010001;
  /*# TG68K_ALU.vhd:876:45 */
  assign n1568 = $unsigned(bs_shift) > $unsigned(6'b100000);
  /*# TG68K_ALU.vhd:877:66 */
  assign n1570 = bs_shift - 6'b100001;
  /*# TG68K_ALU.vhd:876:33 */
  assign n1571 = n1568 ? n1570 : bs_shift;
  /*# TG68K_ALU.vhd:875:25 */
  assign n1573 = ring == 6'b100001;
  /*# TG68K_ALU.vhd:881:74 */
  assign n1574 = bs_shift[2:0]; // extract
  /*# TG68K_ALU.vhd:881:64 */
  assign n1576 = {3'b000, n1574};
  /*# TG68K_ALU.vhd:881:25 */
  assign n1578 = ring == 6'b001000;
  /*# TG68K_ALU.vhd:882:74 */
  assign n1579 = bs_shift[3:0]; // extract
  /*# TG68K_ALU.vhd:882:64 */
  assign n1581 = {2'b00, n1579};
  /*# TG68K_ALU.vhd:882:25 */
  assign n1583 = ring == 6'b010000;
  /*# TG68K_ALU.vhd:883:74 */
  assign n1584 = bs_shift[4:0]; // extract
  /*# TG68K_ALU.vhd:883:64 */
  assign n1586 = {1'b0, n1584};
  /*# TG68K_ALU.vhd:883:25 */
  assign n1588 = ring == 6'b100000;
  /*# TG68K_ALU.vhd:846:17 */
  assign n1589 = {n1588, n1583, n1578, n1573, n1566, n1549};
  /*# TG68K_ALU.vhd:846:17 */
  always @*
    case (n1589)
      6'b100000: n1591 = n1586;
      6'b010000: n1591 = n1581;
      6'b001000: n1591 = n1576;
      6'b000100: n1591 = n1571;
      6'b000010: n1591 = n1564;
      6'b000001: n1591 = n1547;
      default: n1591 = 6'b000000;
    endcase
  /*# TG68K_ALU.vhd:888:30 */
  assign n1592 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:888:33 */
  assign n1593 = ~n1592;
  /*# TG68K_ALU.vhd:889:39 */
  assign n1594 = ring - bs_shift_mod;
  /*# TG68K_ALU.vhd:888:17 */
  assign n1595 = n1593 ? n1594 : bs_shift_mod;
  /*# TG68K_ALU.vhd:891:28 */
  assign n1596 = rot_bits[1]; // extract
  /*# TG68K_ALU.vhd:891:31 */
  assign n1597 = ~n1596;
  /*# TG68K_ALU.vhd:892:38 */
  assign n1598 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:892:41 */
  assign n1599 = ~n1598;
  /*# TG68K_ALU.vhd:893:45 */
  assign n1601 = 6'b100000 - bs_shift_mod;
  /*# TG68K_ALU.vhd:892:25 */
  assign n1602 = n1599 ? n1601 : n1595;
  /*# TG68K_ALU.vhd:895:37 */
  assign n1603 = bs_shift == ring;
  /*# TG68K_ALU.vhd:896:46 */
  assign n1604 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:896:49 */
  assign n1605 = ~n1604;
  /*# TG68K_ALU.vhd:897:53 */
  assign n1607 = 6'b100000 - ring;
  /*# TG68K_ALU.vhd:896:33 */
  assign n1608 = n1605 ? n1607 : ring;
  /*# TG68K_ALU.vhd:895:25 */
  assign n1609 = n1603 ? n1608 : n1602;
  /*# TG68K_ALU.vhd:902:37 */
  assign n1610 = $unsigned(bs_shift) > $unsigned(ring);
  /*# TG68K_ALU.vhd:903:46 */
  assign n1611 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:903:49 */
  assign n1612 = ~n1611;
  /*# TG68K_ALU.vhd:907:55 */
  assign n1614 = ring + 6'b000001;
  /*# TG68K_ALU.vhd:903:33 */
  assign n1616 = n1612 ? 6'b000000 : n1614;
  /*# TG68K_ALU.vhd:891:17 */
  assign n1618 = n1622 ? 1'b0 : n1512;
  /*# TG68K_ALU.vhd:902:25 */
  assign n1619 = n1610 ? n1616 : n1609;
  /*# TG68K_ALU.vhd:902:25 */
  assign n1620 = n1612 & n1610;
  /*# TG68K_ALU.vhd:891:17 */
  assign n1621 = n1597 ? n1619 : n1595;
  /*# TG68K_ALU.vhd:891:17 */
  assign n1622 = n1620 & n1597;
  /*# TG68K_ALU.vhd:915:50 */
  assign n1623 = asr_sign[31:0]; // extract
  /*# TG68K_ALU.vhd:915:74 */
  assign n1624 = hot_msb[31:0]; // extract
  /*# TG68K_ALU.vhd:915:64 */
  assign n1625 = n1623 | n1624;
  /*# TG68K_ALU.vhd:196:16 */
  assign n1627 = n1626[0]; // extract
  /*# TG68K_ALU.vhd:916:28 */
  assign n1629 = rot_bits == 2'b00;
  /*# TG68K_ALU.vhd:916:48 */
  assign n1630 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:916:51 */
  assign n1631 = ~n1630;
  /*# TG68K_ALU.vhd:916:34 */
  assign n1632 = n1631 & n1629;
  /*# TG68K_ALU.vhd:916:56 */
  assign n1633 = msb & n1632;
  /*# TG68K_ALU.vhd:917:49 */
  assign n1634 = asr_sign[32:1]; // extract
  /*# TG68K_ALU.vhd:917:38 */
  assign n1635 = alu | n1634;
  /*# TG68K_ALU.vhd:918:37 */
  assign n1636 = $unsigned(bs_shift) > $unsigned(ring);
  /*# TG68K_ALU.vhd:916:17 */
  assign n1638 = n1640 ? 1'b1 : n1618;
  /*# TG68K_ALU.vhd:916:17 */
  assign n1639 = n1633 ? n1635 : alu;
  /*# TG68K_ALU.vhd:916:17 */
  assign n1640 = n1636 & n1633;
  /*# TG68K_ALU.vhd:923:43 */
  assign n1642 = {1'b0, OP1out};
  /*# TG68K_ALU.vhd:924:32 */
  assign n1643 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:926:46 */
  assign n1644 = OP1out[7]; // extract
  /*# TG68K_ALU.vhd:929:44 */
  assign n1648 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:930:59 */
  assign n1649 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1650 = n1645[0]; // extract
  /*# TG68K_ALU.vhd:929:33 */
  assign n1651 = n1648 ? n1649 : n1650;
  /*# TG68K_ALU.vhd:188:16 */
  assign n1652 = n1645[23:1]; // extract
  /*# TG68K_ALU.vhd:925:25 */
  assign n1654 = n1643 == 2'b00;
  /*# TG68K_ALU.vhd:933:46 */
  assign n1655 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:936:44 */
  assign n1659 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:937:60 */
  assign n1660 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1661 = n1656[0]; // extract
  /*# TG68K_ALU.vhd:936:33 */
  assign n1662 = n1659 ? n1660 : n1661;
  /*# TG68K_ALU.vhd:188:16 */
  assign n1663 = n1656[15:1]; // extract
  /*# TG68K_ALU.vhd:932:25 */
  assign n1665 = n1643 == 2'b01;
  /*# TG68K_ALU.vhd:932:34 */
  assign n1667 = n1643 == 2'b11;
  /*# TG68K_ALU.vhd:932:34 */
  assign n1668 = n1665 | n1667;
  /*# TG68K_ALU.vhd:940:46 */
  assign n1669 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:941:44 */
  assign n1671 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:942:60 */
  assign n1672 = n2313[4]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1673 = n1642[32]; // extract
  /*# TG68K_ALU.vhd:941:33 */
  assign n1674 = n1671 ? n1672 : n1673;
  /*# TG68K_ALU.vhd:939:25 */
  assign n1676 = n1643 == 2'b10;
  /*# TG68K_ALU.vhd:924:17 */
  assign n1677 = {n1676, n1668, n1654};
  /*# TG68K_ALU.vhd:188:16 */
  assign n1678 = n1642[8]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1679 = n1678;
      3'b010: n1679 = n1678;
      3'b001: n1679 = n1651;
      default: n1679 = n1678;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1680 = n1652[6:0]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1681 = n1642[15:9]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1682 = n1681;
      3'b010: n1682 = n1681;
      3'b001: n1682 = n1680;
      default: n1682 = n1681;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1683 = n1652[7]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1684 = n1642[16]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1685 = n1684;
      3'b010: n1685 = n1662;
      3'b001: n1685 = n1683;
      default: n1685 = n1684;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1686 = n1652[22:8]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1687 = n1642[31:17]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1688 = n1687;
      3'b010: n1688 = n1663;
      3'b001: n1688 = n1686;
      default: n1688 = n1687;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1689 = n1642[32]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1690 = n1674;
      3'b010: n1690 = n1689;
      3'b001: n1690 = n1689;
      default: n1690 = n1689;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1692 = n1642[7:0]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1696 = n1669;
      3'b010: n1696 = n1655;
      3'b001: n1696 = n1644;
      default: n1696 = msb;
    endcase
  assign n1697 = n1646[7:0]; // extract
  /*# TG68K_ALU.vhd:200:16 */
  assign n1698 = n1639[15:8]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1699 = n1698;
      3'b010: n1699 = n1698;
      3'b001: n1699 = n1697;
      default: n1699 = n1698;
    endcase
  assign n1700 = n1646[23:8]; // extract
  /*# TG68K_ALU.vhd:200:16 */
  assign n1701 = n1639[31:16]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1677)
      3'b100: n1702 = n1701;
      3'b010: n1702 = 16'b0000000000000000;
      3'b001: n1702 = n1700;
      default: n1702 = n1701;
    endcase
  /*# TG68K_ALU.vhd:200:16 */
  assign n1704 = n1639[7:0]; // extract
  /*# TG68K_ALU.vhd:946:71 */
  assign n1706 = {33'b000000000000000000000000000000000, vector};
  /*# TG68K_ALU.vhd:946:84 */
  assign n1707 = {25'b0, bit_nr};  // uext
  /*# TG68K_ALU.vhd:946:80 */
  assign n1708 = {1'b0, n1707};  // uext
  /*# TG68K_ALU.vhd:946:80 */
  assign n1709 = n1706 << n1708;
  /*# TG68K_ALU.vhd:957:24 */
  assign n1713 = exec[17]; // extract
  /*# TG68K_ALU.vhd:958:58 */
  assign n1714 = last_data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:958:40 */
  assign n1715 = n2313 & n1714;
  /*# TG68K_ALU.vhd:959:27 */
  assign n1716 = exec[18]; // extract
  /*# TG68K_ALU.vhd:960:58 */
  assign n1717 = last_data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:960:40 */
  assign n1718 = n2313 ^ n1717;
  /*# TG68K_ALU.vhd:961:27 */
  assign n1719 = exec[19]; // extract
  /*# TG68K_ALU.vhd:962:57 */
  assign n1720 = last_data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:962:40 */
  assign n1721 = n2313 | n1720;
  /*# TG68K_ALU.vhd:964:40 */
  assign n1722 = OP2out[7:0]; // extract
  /*# TG68K_ALU.vhd:961:17 */
  assign n1723 = n1719 ? n1721 : n1722;
  /*# TG68K_ALU.vhd:959:17 */
  assign n1724 = n1716 ? n1718 : n1723;
  /*# TG68K_ALU.vhd:957:17 */
  assign n1725 = n1713 ? n1715 : n1724;
  /*# TG68K_ALU.vhd:971:24 */
  assign n1726 = exec[28]; // extract
  /*# TG68K_ALU.vhd:971:50 */
  assign n1727 = n2313[2]; // extract
  /*# TG68K_ALU.vhd:971:53 */
  assign n1728 = ~n1727;
  /*# TG68K_ALU.vhd:971:41 */
  assign n1729 = n1728 & n1726;
  /*# TG68K_ALU.vhd:973:28 */
  assign n1730 = op1in[7:0]; // extract
  /*# TG68K_ALU.vhd:973:40 */
  assign n1732 = n1730 == 8'b00000000;
  /*# TG68K_ALU.vhd:975:33 */
  assign n1734 = op1in[15:8]; // extract
  /*# TG68K_ALU.vhd:975:46 */
  assign n1736 = n1734 == 8'b00000000;
  /*# TG68K_ALU.vhd:977:41 */
  assign n1738 = op1in[31:16]; // extract
  /*# TG68K_ALU.vhd:977:55 */
  assign n1740 = n1738 == 16'b0000000000000000;
  /*# TG68K_ALU.vhd:977:33 */
  assign n1743 = n1740 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:975:25 */
  assign n1744 = {n1743, 1'b1};
  /*# TG68K_ALU.vhd:975:25 */
  assign n1746 = n1736 ? n1744 : 2'b00;
  /*# TG68K_ALU.vhd:973:17 */
  assign n1747 = {n1746, 1'b1};
  /*# TG68K_ALU.vhd:973:17 */
  assign n1749 = n1732 ? n1747 : 3'b000;
  /*# TG68K_ALU.vhd:971:17 */
  assign n1751 = n1729 ? 3'b000 : n1749;
  /*# TG68K_ALU.vhd:984:32 */
  assign n1754 = exe_datatype == 2'b00;
  /*# TG68K_ALU.vhd:985:43 */
  assign n1755 = op1in[7]; // extract
  /*# TG68K_ALU.vhd:985:53 */
  assign n1756 = flag_z[0]; // extract
  /*# TG68K_ALU.vhd:985:46 */
  assign n1757 = {n1755, n1756};
  /*# TG68K_ALU.vhd:985:67 */
  assign n1758 = addsub_ofl[0]; // extract
  /*# TG68K_ALU.vhd:985:56 */
  assign n1759 = {n1757, n1758};
  /*# TG68K_ALU.vhd:985:76 */
  assign n1760 = n256[0]; // extract
  /*# TG68K_ALU.vhd:985:70 */
  assign n1761 = {n1759, n1760};
  /*# TG68K_ALU.vhd:986:32 */
  assign n1762 = exec[12]; // extract
  /*# TG68K_ALU.vhd:986:53 */
  assign n1763 = exec[13]; // extract
  /*# TG68K_ALU.vhd:986:46 */
  assign n1764 = n1762 | n1763;
  /*# TG68K_ALU.vhd:986:25 */
  assign n1765 = {vflag_a, bcd_a_carry};
  /*# TG68K_ALU.vhd:95:16 */
  assign n1766 = n1761[1:0]; // extract
  /*# TG68K_ALU.vhd:986:25 */
  assign n1767 = n1764 ? n1765 : n1766;
  /*# TG68K_ALU.vhd:95:16 */
  assign n1768 = n1761[3:2]; // extract
  /*# TG68K_ALU.vhd:990:35 */
  assign n1770 = exe_datatype == 2'b10;
  /*# TG68K_ALU.vhd:990:48 */
  assign n1771 = exec[10]; // extract
  /*# TG68K_ALU.vhd:990:41 */
  assign n1772 = n1770 | n1771;
  /*# TG68K_ALU.vhd:991:43 */
  assign n1773 = op1in[31]; // extract
  /*# TG68K_ALU.vhd:991:54 */
  assign n1774 = flag_z[2]; // extract
  /*# TG68K_ALU.vhd:991:47 */
  assign n1775 = {n1773, n1774};
  /*# TG68K_ALU.vhd:991:68 */
  assign n1776 = addsub_ofl[2]; // extract
  /*# TG68K_ALU.vhd:991:57 */
  assign n1777 = {n1775, n1776};
  /*# TG68K_ALU.vhd:991:77 */
  assign n1778 = n256[2]; // extract
  /*# TG68K_ALU.vhd:991:71 */
  assign n1779 = {n1777, n1778};
  /*# TG68K_ALU.vhd:993:43 */
  assign n1780 = op1in[15]; // extract
  /*# TG68K_ALU.vhd:993:54 */
  assign n1781 = flag_z[1]; // extract
  /*# TG68K_ALU.vhd:993:47 */
  assign n1782 = {n1780, n1781};
  /*# TG68K_ALU.vhd:993:68 */
  assign n1783 = addsub_ofl[1]; // extract
  /*# TG68K_ALU.vhd:993:57 */
  assign n1784 = {n1782, n1783};
  /*# TG68K_ALU.vhd:993:77 */
  assign n1785 = n256[1]; // extract
  /*# TG68K_ALU.vhd:993:71 */
  assign n1786 = {n1784, n1785};
  /*# TG68K_ALU.vhd:990:17 */
  assign n1787 = n1772 ? n1779 : n1786;
  /*# TG68K_ALU.vhd:984:17 */
  assign n1788 = {n1768, n1767};
  /*# TG68K_ALU.vhd:984:17 */
  assign n1789 = n1754 ? n1788 : n1787;
  /*# TG68K_ALU.vhd:1000:40 */
  assign n1791 = exec[59]; // extract
  /*# TG68K_ALU.vhd:1000:55 */
  assign n1792 = n1791 | set_stop;
  /*# TG68K_ALU.vhd:1001:71 */
  assign n1793 = data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:1000:33 */
  assign n1794 = n1792 ? n1793 : n2313;
  /*# TG68K_ALU.vhd:1003:40 */
  assign n1795 = exec[60]; // extract
  /*# TG68K_ALU.vhd:1004:71 */
  assign n1796 = data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:1003:33 */
  assign n1797 = n1795 ? n1796 : n1794;
  /*# TG68K_ALU.vhd:1007:40 */
  assign n1798 = exec[9]; // extract
  /*# TG68K_ALU.vhd:1007:66 */
  assign n1799 = ~decodeOPC;
  /*# TG68K_ALU.vhd:1007:53 */
  assign n1800 = n1799 & n1798;
  /*# TG68K_ALU.vhd:1008:65 */
  assign n1801 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1008:69 */
  assign n1802 = n1801 ^ rot_rot;
  /*# TG68K_ALU.vhd:1008:82 */
  assign n1803 = n1802 | asl_vflag;
  /*# TG68K_ALU.vhd:1007:33 */
  assign n1805 = n1800 ? n1803 : 1'b0;
  /*# TG68K_ALU.vhd:1012:40 */
  assign n1806 = exec[51]; // extract
  /*# TG68K_ALU.vhd:1015:56 */
  assign n1808 = micro_state == 7'b0110011;
  /*# TG68K_ALU.vhd:1017:62 */
  assign n1809 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:1017:65 */
  assign n1810 = ~n1809;
  /*# TG68K_ALU.vhd:1019:92 */
  assign n1811 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1019:82 */
  assign n1812 = ~n1811;
  /*# TG68K_ALU.vhd:1019:81 */
  assign n1814 = {1'b0, n1812};
  /*# TG68K_ALU.vhd:1019:96 */
  assign n1816 = {n1814, 2'b00};
  /*# TG68K_ALU.vhd:1017:49 */
  assign n1818 = n1810 ? n1816 : 4'b0100;
  /*# TG68K_ALU.vhd:73:17 */
  assign n1819 = n1797[3:0]; // extract
  /*# TG68K_ALU.vhd:1015:41 */
  assign n1820 = n1808 ? n1818 : n1819;
  /*# TG68K_ALU.vhd:1024:43 */
  assign n1821 = exec[49]; // extract
  /*# TG68K_ALU.vhd:1024:53 */
  assign n1822 = ~n1821;
  /*# TG68K_ALU.vhd:1025:61 */
  assign n1823 = n2313[3:0]; // extract
  /*# TG68K_ALU.vhd:1026:48 */
  assign n1824 = exec[3]; // extract
  /*# TG68K_ALU.vhd:1027:70 */
  assign n1825 = set_flags[0]; // extract
  /*# TG68K_ALU.vhd:1028:51 */
  assign n1826 = exec[9]; // extract
  /*# TG68K_ALU.vhd:1028:76 */
  assign n1828 = rot_bits != 2'b11;
  /*# TG68K_ALU.vhd:1028:64 */
  assign n1829 = n1828 & n1826;
  /*# TG68K_ALU.vhd:1028:91 */
  assign n1830 = exec[23]; // extract
  /*# TG68K_ALU.vhd:1028:100 */
  assign n1831 = ~n1830;
  /*# TG68K_ALU.vhd:1028:83 */
  assign n1832 = n1831 & n1829;
  /*# TG68K_ALU.vhd:1030:51 */
  assign n1833 = exec[81]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1834 = n1797[4]; // extract
  /*# TG68K_ALU.vhd:1030:41 */
  assign n1835 = n1833 ? bs_x : n1834;
  /*# TG68K_ALU.vhd:1028:41 */
  assign n1836 = n1832 ? rot_x : n1835;
  /*# TG68K_ALU.vhd:1026:41 */
  assign n1837 = n1824 ? n1825 : n1836;
  /*# TG68K_ALU.vhd:1034:49 */
  assign n1838 = exec[8]; // extract
  /*# TG68K_ALU.vhd:1034:65 */
  assign n1839 = exec[86]; // extract
  /*# TG68K_ALU.vhd:1034:58 */
  assign n1840 = n1838 | n1839;
  /*# TG68K_ALU.vhd:1036:51 */
  assign n1841 = exec[21]; // extract
  /*# TG68K_ALU.vhd:1036:65 */
  assign n1843 = 1'b1 & n1841;
  /*# TG68K_ALU.vhd:1039:65 */
  assign n1845 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:1039:74 */
  assign n1847 = n1845 | 1'b0;
  /*# TG68K_ALU.vhd:1040:83 */
  assign n1848 = op1in[15]; // extract
  /*# TG68K_ALU.vhd:1040:94 */
  assign n1849 = flag_z[1]; // extract
  /*# TG68K_ALU.vhd:1040:87 */
  assign n1850 = {n1848, n1849};
  /*# TG68K_ALU.vhd:1040:97 */
  assign n1852 = {n1850, 2'b00};
  /*# TG68K_ALU.vhd:1042:83 */
  assign n1853 = op1in[31]; // extract
  /*# TG68K_ALU.vhd:1042:94 */
  assign n1854 = flag_z[2]; // extract
  /*# TG68K_ALU.vhd:1042:87 */
  assign n1855 = {n1853, n1854};
  /*# TG68K_ALU.vhd:1042:97 */
  assign n1857 = {n1855, 2'b00};
  /*# TG68K_ALU.vhd:1039:49 */
  assign n1858 = n1847 ? n1852 : n1857;
  /*# TG68K_ALU.vhd:1037:49 */
  assign n1859 = v_flag ? 4'b1010 : n1858;
  /*# TG68K_ALU.vhd:1044:51 */
  assign n1860 = exec[68]; // extract
  /*# TG68K_ALU.vhd:1044:72 */
  assign n1862 = 1'b1 & n1860;
  /*# TG68K_ALU.vhd:1045:70 */
  assign n1863 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1046:70 */
  assign n1864 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1046:83 */
  assign n1865 = n2313[2]; // extract
  /*# TG68K_ALU.vhd:1046:74 */
  assign n1866 = n1864 & n1865;
  /*# TG68K_ALU.vhd:1054:51 */
  assign n1870 = exec[5]; // extract
  /*# TG68K_ALU.vhd:1054:70 */
  assign n1871 = exec[6]; // extract
  /*# TG68K_ALU.vhd:1054:63 */
  assign n1872 = n1870 | n1871;
  /*# TG68K_ALU.vhd:1054:90 */
  assign n1873 = exec[7]; // extract
  /*# TG68K_ALU.vhd:1054:83 */
  assign n1874 = n1872 | n1873;
  /*# TG68K_ALU.vhd:1054:110 */
  assign n1875 = exec[0]; // extract
  /*# TG68K_ALU.vhd:1054:103 */
  assign n1876 = n1874 | n1875;
  /*# TG68K_ALU.vhd:1054:131 */
  assign n1877 = exec[1]; // extract
  /*# TG68K_ALU.vhd:1054:124 */
  assign n1878 = n1876 | n1877;
  /*# TG68K_ALU.vhd:1054:153 */
  assign n1879 = exec[15]; // extract
  /*# TG68K_ALU.vhd:1054:146 */
  assign n1880 = n1878 | n1879;
  /*# TG68K_ALU.vhd:1054:174 */
  assign n1881 = exec[75]; // extract
  /*# TG68K_ALU.vhd:1054:167 */
  assign n1882 = n1880 | n1881;
  /*# TG68K_ALU.vhd:1054:194 */
  assign n1883 = exec[20]; // extract
  /*# TG68K_ALU.vhd:1054:208 */
  assign n1885 = 1'b1 & n1883;
  /*# TG68K_ALU.vhd:1054:186 */
  assign n1886 = n1882 | n1885;
  /*# TG68K_ALU.vhd:1057:56 */
  assign n1889 = exec[75]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1890 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1057:49 */
  assign n1891 = n1889 ? bf_nflag : n1890;
  /*# TG68K_ALU.vhd:73:17 */
  assign n1892 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1060:51 */
  assign n1893 = exec[9]; // extract
  /*# TG68K_ALU.vhd:1061:79 */
  assign n1894 = set_flags[3:2]; // extract
  /*# TG68K_ALU.vhd:1063:60 */
  assign n1896 = rot_bits == 2'b00;
  /*# TG68K_ALU.vhd:1063:81 */
  assign n1897 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1063:85 */
  assign n1898 = n1897 ^ rot_rot;
  /*# TG68K_ALU.vhd:1063:98 */
  assign n1899 = n1898 | asl_vflag;
  /*# TG68K_ALU.vhd:1063:66 */
  assign n1900 = n1899 & n1896;
  /*# TG68K_ALU.vhd:1063:49 */
  assign n1903 = n1900 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1068:51 */
  assign n1904 = exec[81]; // extract
  /*# TG68K_ALU.vhd:1069:79 */
  assign n1905 = set_flags[3:2]; // extract
  /*# TG68K_ALU.vhd:1072:51 */
  assign n1906 = exec[14]; // extract
  /*# TG68K_ALU.vhd:1073:61 */
  assign n1907 = ~one_bit_in;
  /*# TG68K_ALU.vhd:1074:51 */
  assign n1908 = exec[87]; // extract
  /*# TG68K_ALU.vhd:1079:63 */
  assign n1909 = last_flags1[0]; // extract
  /*# TG68K_ALU.vhd:1079:66 */
  assign n1910 = ~n1909;
  /*# TG68K_ALU.vhd:1080:74 */
  assign n1911 = n2313[0]; // extract
  /*# TG68K_ALU.vhd:1080:95 */
  assign n1912 = set_flags[0]; // extract
  /*# TG68K_ALU.vhd:1080:82 */
  assign n1913 = ~n1912;
  /*# TG68K_ALU.vhd:1080:116 */
  assign n1914 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1080:103 */
  assign n1915 = ~n1914;
  /*# TG68K_ALU.vhd:1080:99 */
  assign n1916 = n1913 & n1915;
  /*# TG68K_ALU.vhd:1080:78 */
  assign n1917 = n1911 | n1916;
  /*# TG68K_ALU.vhd:1082:75 */
  assign n1918 = n2313[0]; // extract
  /*# TG68K_ALU.vhd:1082:92 */
  assign n1919 = set_flags[0]; // extract
  /*# TG68K_ALU.vhd:1082:79 */
  assign n1920 = n1918 ^ n1919;
  /*# TG68K_ALU.vhd:1082:111 */
  assign n1921 = n2313[2]; // extract
  /*# TG68K_ALU.vhd:1082:102 */
  assign n1922 = ~n1921;
  /*# TG68K_ALU.vhd:1082:97 */
  assign n1923 = n1920 & n1922;
  /*# TG68K_ALU.vhd:1082:132 */
  assign n1924 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1082:119 */
  assign n1925 = ~n1924;
  /*# TG68K_ALU.vhd:1082:115 */
  assign n1926 = n1923 & n1925;
  /*# TG68K_ALU.vhd:1079:49 */
  assign n1927 = n1910 ? n1917 : n1926;
  /*# TG68K_ALU.vhd:1085:66 */
  assign n1929 = n2313[2]; // extract
  /*# TG68K_ALU.vhd:1085:82 */
  assign n1930 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1085:70 */
  assign n1931 = n1929 | n1930;
  /*# TG68K_ALU.vhd:1086:76 */
  assign n1932 = last_flags1[0]; // extract
  /*# TG68K_ALU.vhd:1086:61 */
  assign n1933 = ~n1932;
  /*# TG68K_ALU.vhd:1087:51 */
  assign n1934 = exec[31]; // extract
  /*# TG68K_ALU.vhd:1088:64 */
  assign n1936 = exe_datatype == 2'b01;
  /*# TG68K_ALU.vhd:1089:75 */
  assign n1937 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:1091:75 */
  assign n1938 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:1088:49 */
  assign n1939 = n1936 ? n1937 : n1938;
  /*# TG68K_ALU.vhd:1093:58 */
  assign n1940 = OP1out[15:0]; // extract
  /*# TG68K_ALU.vhd:1093:71 */
  assign n1942 = n1940 == 16'b0000000000000000;
  /*# TG68K_ALU.vhd:1093:97 */
  assign n1944 = exe_datatype == 2'b01;
  /*# TG68K_ALU.vhd:1093:112 */
  assign n1945 = OP1out[31:16]; // extract
  /*# TG68K_ALU.vhd:1093:126 */
  assign n1947 = n1945 == 16'b0000000000000000;
  /*# TG68K_ALU.vhd:1093:103 */
  assign n1948 = n1944 | n1947;
  /*# TG68K_ALU.vhd:1093:80 */
  assign n1949 = n1948 & n1942;
  /*# TG68K_ALU.vhd:1093:49 */
  assign n1952 = n1949 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1087:41 */
  assign n1955 = {n1939, n1952, 1'b0, 1'b0};
  /*# TG68K_ALU.vhd:73:17 */
  assign n1956 = n1797[3:0]; // extract
  /*# TG68K_ALU.vhd:1087:41 */
  assign n1957 = n1934 ? n1955 : n1956;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n1958 = {n1933, n1931, 1'b0, n1927};
  /*# TG68K_ALU.vhd:1074:41 */
  assign n1959 = n1908 ? n1958 : n1957;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n1960 = n1959[1:0]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1961 = n1797[1:0]; // extract
  /*# TG68K_ALU.vhd:1072:41 */
  assign n1962 = n1906 ? n1961 : n1960;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n1963 = n1959[2]; // extract
  /*# TG68K_ALU.vhd:1072:41 */
  assign n1964 = n1906 ? n1907 : n1963;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n1965 = n1959[3]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1966 = n1797[3]; // extract
  /*# TG68K_ALU.vhd:1072:41 */
  assign n1967 = n1906 ? n1966 : n1965;
  /*# TG68K_ALU.vhd:1068:41 */
  assign n1968 = {n1967, n1964, n1962};
  /*# TG68K_ALU.vhd:1068:41 */
  assign n1969 = {n1905, bs_v, bs_c};
  /*# TG68K_ALU.vhd:1068:41 */
  assign n1970 = n1904 ? n1969 : n1968;
  /*# TG68K_ALU.vhd:1060:41 */
  assign n1971 = {n1894, n1903, rot_c};
  /*# TG68K_ALU.vhd:1060:41 */
  assign n1972 = n1893 ? n1971 : n1970;
  /*# TG68K_ALU.vhd:1054:41 */
  assign n1973 = {n1891, n1892, 2'b00};
  /*# TG68K_ALU.vhd:1054:41 */
  assign n1974 = n1886 ? n1973 : n1972;
  /*# TG68K_ALU.vhd:1044:41 */
  assign n1975 = {n1863, n1866, 1'b0, 1'b0};
  /*# TG68K_ALU.vhd:1044:41 */
  assign n1976 = n1862 ? n1975 : n1974;
  /*# TG68K_ALU.vhd:1036:41 */
  assign n1977 = n1843 ? n1859 : n1976;
  /*# TG68K_ALU.vhd:1034:41 */
  assign n1978 = n1840 ? set_flags : n1977;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n1979 = {n1837, n1978};
  /*# TG68K_ALU.vhd:73:17 */
  assign n1980 = n1797[4:0]; // extract
  /*# TG68K_ALU.vhd:1024:33 */
  assign n1981 = n1822 ? n1979 : n1980;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n1982 = n1822 ? n1823 : last_flags1;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n1983 = n1981[3:0]; // extract
  /*# TG68K_ALU.vhd:1014:33 */
  assign n1984 = Z_error ? n1820 : n1983;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n1985 = n1981[4]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1986 = n1797[4]; // extract
  /*# TG68K_ALU.vhd:1014:33 */
  assign n1987 = Z_error ? n1986 : n1985;
  /*# TG68K_ALU.vhd:1014:33 */
  assign n1988 = Z_error ? last_flags1 : n1982;
  /*# TG68K_ALU.vhd:1012:33 */
  assign n1989 = {n1987, n1984};
  /*# TG68K_ALU.vhd:96:16 */
  assign n1990 = ccrin[4:0]; // extract
  /*# TG68K_ALU.vhd:1012:33 */
  assign n1991 = n1806 ? n1990 : n1989;
  /*# TG68K_ALU.vhd:96:16 */
  assign n1992 = ccrin[7:5]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1993 = n1797[7:5]; // extract
  /*# TG68K_ALU.vhd:1012:33 */
  assign n1994 = n1806 ? n1992 : n1993;
  /*# TG68K_ALU.vhd:1012:33 */
  assign n1996 = n1806 ? last_flags1 : n1988;
  /*# TG68K_ALU.vhd:999:25 */
  assign n1997 = {n1994, n1991};
  /*# TG68K_ALU.vhd:999:25 */
  assign n1998 = clkena_lw ? n1997 : n2313;
  /*# TG68K_ALU.vhd:999:25 */
  assign n1999 = clkena_lw ? n1996 : last_flags1;
  /*# TG68K_ALU.vhd:999:25 */
  assign n2000 = clkena_lw ? n1805 : asl_vflag;
  /*# TG68K_ALU.vhd:997:25 */
  assign n2002 = Reset ? 8'b00000000 : n1998;
  /*# TG68K_ALU.vhd:997:25 */
  assign n2003 = Reset ? last_flags1 : n1999;
  /*# TG68K_ALU.vhd:997:25 */
  assign n2004 = Reset ? asl_vflag : n2000;
  /*# TG68K_ALU.vhd:73:17 */
  assign n2006 = n2002[4:0]; // extract
  /*# TG68K_ALU.vhd:996:17 */
  assign n2007 = {3'b000, n2006};
  /*# TG68K_ALU.vhd:1162:45 */
  assign n2014 = faktorb[31]; // extract
  /*# TG68K_ALU.vhd:1162:34 */
  assign n2015 = n2014 & signedop;
  /*# TG68K_ALU.vhd:1162:55 */
  assign n2016 = n2015 | fasign;
  /*# TG68K_ALU.vhd:1163:45 */
  assign n2017 = mulu_reg[63]; // extract
  /*# TG68K_ALU.vhd:1162:17 */
  assign n2019 = n2016 ? n2017 : 1'b0;
  /*# TG68K_ALU.vhd:1168:44 */
  assign n2020 = faktorb[31]; // extract
  /*# TG68K_ALU.vhd:1168:33 */
  assign n2021 = n2020 & signedop;
  /*# TG68K_ALU.vhd:1168:17 */
  assign n2024 = n2021 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1185:70 */
  assign n2025 = mulu_reg[63:1]; // extract
  /*# TG68K_ALU.vhd:1185:61 */
  assign n2026 = {muls_msb, n2025};
  /*# TG68K_ALU.vhd:1186:36 */
  assign n2027 = mulu_reg[0]; // extract
  /*# TG68K_ALU.vhd:1188:88 */
  assign n2028 = mulu_reg[63:32]; // extract
  /*# TG68K_ALU.vhd:1188:79 */
  assign n2029 = {muls_msb, n2028};
  /*# TG68K_ALU.vhd:1188:113 */
  assign n2030 = {mulu_sign, faktorb};
  /*# TG68K_ALU.vhd:1188:102 */
  assign n2031 = n2029 - n2030;
  /*# TG68K_ALU.vhd:1190:88 */
  assign n2032 = mulu_reg[63:32]; // extract
  /*# TG68K_ALU.vhd:1190:79 */
  assign n2033 = {muls_msb, n2032};
  /*# TG68K_ALU.vhd:1190:113 */
  assign n2034 = {mulu_sign, faktorb};
  /*# TG68K_ALU.vhd:1190:102 */
  assign n2035 = n2033 + n2034;
  /*# TG68K_ALU.vhd:1187:33 */
  assign n2036 = fasign ? n2031 : n2035;
  /*# TG68K_ALU.vhd:106:16 */
  assign n2037 = n2026[63:31]; // extract
  /*# TG68K_ALU.vhd:1186:25 */
  assign n2038 = n2027 ? n2036 : n2037;
  /*# TG68K_ALU.vhd:106:16 */
  assign n2039 = n2026[30:0]; // extract
  /*# TG68K_ALU.vhd:1194:30 */
  assign n2040 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:1194:39 */
  assign n2042 = n2040 | 1'b0;
  /*# TG68K_ALU.vhd:1195:56 */
  assign n2043 = OP2out[15:0]; // extract
  /*# TG68K_ALU.vhd:1194:17 */
  assign n2045 = {n2043, 16'b0000000000000000};
  /*# TG68K_ALU.vhd:1194:17 */
  assign n2046 = n2042 ? n2045 : OP2out;
  /*# TG68K_ALU.vhd:1227:77 */
  assign n2069 = result_mulu[63:32]; // extract
  /*# TG68K_ALU.vhd:1240:32 */
  assign n2077 = opcode[15]; // extract
  /*# TG68K_ALU.vhd:1240:47 */
  assign n2078 = opcode[8]; // extract
  /*# TG68K_ALU.vhd:1240:37 */
  assign n2079 = n2077 & n2078;
  /*# TG68K_ALU.vhd:1240:66 */
  assign n2080 = opcode[15]; // extract
  /*# TG68K_ALU.vhd:1240:56 */
  assign n2081 = ~n2080;
  /*# TG68K_ALU.vhd:1240:81 */
  assign n2082 = sndOPC[11]; // extract
  /*# TG68K_ALU.vhd:1240:71 */
  assign n2083 = n2081 & n2082;
  /*# TG68K_ALU.vhd:1240:52 */
  assign n2084 = n2079 | n2083;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2086 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2087 = divs & n2086;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2088 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2089 = divs & n2088;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2090 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2091 = divs & n2090;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2092 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2093 = divs & n2092;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2094 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2095 = divs & n2094;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2096 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2097 = divs & n2096;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2098 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2099 = divs & n2098;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2100 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2101 = divs & n2100;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2102 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2103 = divs & n2102;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2104 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2105 = divs & n2104;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2106 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2107 = divs & n2106;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2108 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2109 = divs & n2108;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2110 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2111 = divs & n2110;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2112 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2113 = divs & n2112;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2114 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2115 = divs & n2114;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2116 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2117 = divs & n2116;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2118 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2119 = divs & n2118;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2120 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2121 = divs & n2120;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2122 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2123 = divs & n2122;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2124 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2125 = divs & n2124;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2126 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2127 = divs & n2126;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2128 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2129 = divs & n2128;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2130 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2131 = divs & n2130;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2132 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2133 = divs & n2132;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2134 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2135 = divs & n2134;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2136 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2137 = divs & n2136;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2138 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2139 = divs & n2138;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2140 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2141 = divs & n2140;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2142 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2143 = divs & n2142;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2144 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2145 = divs & n2144;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2146 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2147 = divs & n2146;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2148 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2149 = divs & n2148;
  /*# TG68K_ALU.vhd:1242:43 */
  assign n2150 = {n2087, n2089, n2091, n2093, n2095, n2097, n2099, n2101, n2103, n2105, n2107, n2109, n2111, n2113, n2115, n2117, n2119, n2121, n2123, n2125, n2127, n2129, n2131, n2133, n2135, n2137, n2139, n2141, n2143, n2145, n2147, n2149};
  /*# TG68K_ALU.vhd:1243:30 */
  assign n2151 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:1243:39 */
  assign n2153 = n2151 | 1'b0;
  /*# TG68K_ALU.vhd:1245:52 */
  assign n2154 = result_div_pre[15]; // extract
  /*# TG68K_ALU.vhd:1248:38 */
  assign n2155 = exe_opcode[14]; // extract
  /*# TG68K_ALU.vhd:1248:57 */
  assign n2156 = sndOPC[10]; // extract
  /*# TG68K_ALU.vhd:1248:47 */
  assign n2157 = n2156 & n2155;
  /*# TG68K_ALU.vhd:1248:25 */
  assign n2158 = n2157 ? reg_QB : n2150;
  /*# TG68K_ALU.vhd:1251:52 */
  assign n2159 = result_div_pre[31]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2160 = n2153 ? n2154 : n2159;
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2161 = {n2158, reg_QA};
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2162 = n2161[15:0]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2163 = n2153 ? 16'b0000000000000000 : n2162;
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2164 = n2161[47:16]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2165 = n2153 ? reg_QA : n2164;
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2166 = n2161[63:48]; // extract
  /*# TG68K_ALU.vhd:143:16 */
  assign n2167 = n2150[31:16]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2168 = n2153 ? n2167 : n2166;
  /*# TG68K_ALU.vhd:1253:42 */
  assign n2170 = opcode[15]; // extract
  /*# TG68K_ALU.vhd:1253:46 */
  assign n2171 = ~n2170;
  /*# TG68K_ALU.vhd:1253:33 */
  assign n2172 = signedop | n2171;
  /*# TG68K_ALU.vhd:1254:44 */
  assign n2173 = OP2out[31:16]; // extract
  /*# TG68K_ALU.vhd:1253:17 */
  assign n2175 = n2172 ? n2173 : 16'b0000000000000000;
  /*# TG68K_ALU.vhd:1258:43 */
  assign n2176 = OP2out[31]; // extract
  /*# TG68K_ALU.vhd:1258:33 */
  assign n2177 = n2176 & signedop;
  /*# TG68K_ALU.vhd:1259:44 */
  assign n2178 = div_reg[63:31]; // extract
  /*# TG68K_ALU.vhd:1259:64 */
  assign n2180 = {1'b1, OP2out};
  /*# TG68K_ALU.vhd:1259:59 */
  assign n2181 = n2178 + n2180;
  /*# TG68K_ALU.vhd:1261:44 */
  assign n2182 = div_reg[63:31]; // extract
  /*# TG68K_ALU.vhd:1261:64 */
  assign n2184 = {1'b0, op2outext};
  /*# TG68K_ALU.vhd:1261:94 */
  assign n2185 = OP2out[15:0]; // extract
  /*# TG68K_ALU.vhd:1261:87 */
  assign n2186 = {n2184, n2185};
  /*# TG68K_ALU.vhd:1261:59 */
  assign n2187 = n2182 - n2186;
  /*# TG68K_ALU.vhd:1258:17 */
  assign n2188 = n2177 ? n2181 : n2187;
  /*# TG68K_ALU.vhd:1266:43 */
  assign n2189 = div_sub[32]; // extract
  /*# TG68K_ALU.vhd:1269:58 */
  assign n2190 = div_reg[62:31]; // extract
  /*# TG68K_ALU.vhd:1271:58 */
  assign n2191 = div_sub[31:0]; // extract
  /*# TG68K_ALU.vhd:1268:17 */
  assign n2192 = div_bit ? n2190 : n2191;
  /*# TG68K_ALU.vhd:1273:49 */
  assign n2193 = div_reg[30:0]; // extract
  /*# TG68K_ALU.vhd:1273:63 */
  assign n2194 = ~div_bit;
  /*# TG68K_ALU.vhd:1273:62 */
  assign n2195 = {n2193, n2194};
  /*# TG68K_ALU.vhd:1276:66 */
  assign n2196 = div_quot[31:0]; // extract
  /*# TG68K_ALU.vhd:1276:57 */
  assign n2198 = 32'b00000000000000000000000000000000 - n2196;
  /*# TG68K_ALU.vhd:1279:64 */
  assign n2199 = div_quot[31:0]; // extract
  /*# TG68K_ALU.vhd:1275:17 */
  assign n2200 = div_neg ? n2198 : n2199;
  /*# TG68K_ALU.vhd:1282:44 */
  assign n2201 = ~div_bit;
  /*# TG68K_ALU.vhd:1282:34 */
  assign n2202 = nozero | n2201;
  /*# TG68K_ALU.vhd:1282:50 */
  assign n2203 = signedop & n2202;
  /*# TG68K_ALU.vhd:1282:78 */
  assign n2204 = OP2out[31]; // extract
  /*# TG68K_ALU.vhd:1282:83 */
  assign n2205 = n2204 ^ op1_sign;
  /*# TG68K_ALU.vhd:1282:96 */
  assign n2206 = n2205 ^ div_qsign;
  /*# TG68K_ALU.vhd:1282:67 */
  assign n2207 = n2206 & n2203;
  /*# TG68K_ALU.vhd:1283:37 */
  assign n2208 = ~signedop;
  /*# TG68K_ALU.vhd:1283:54 */
  assign n2209 = div_over[32]; // extract
  /*# TG68K_ALU.vhd:1283:58 */
  assign n2210 = ~n2209;
  /*# TG68K_ALU.vhd:1283:42 */
  assign n2211 = n2210 & n2208;
  /*# TG68K_ALU.vhd:1283:25 */
  assign n2212 = n2207 | n2211;
  /*# TG68K_ALU.vhd:1283:65 */
  assign n2214 = 1'b1 & n2212;
  /*# TG68K_ALU.vhd:1282:17 */
  assign n2217 = n2214 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1294:47 */
  assign n2223 = micro_state != 7'b1011100;
  /*# TG68K_ALU.vhd:1298:47 */
  assign n2226 = micro_state == 7'b1010111;
  /*# TG68K_ALU.vhd:1300:65 */
  assign n2227 = dividend[63]; // extract
  /*# TG68K_ALU.vhd:1300:53 */
  assign n2228 = n2227 & divs;
  /*# TG68K_ALU.vhd:1302:61 */
  assign n2230 = 64'b0000000000000000000000000000000000000000000000000000000000000000 - dividend;
  /*# TG68K_ALU.vhd:1300:41 */
  assign n2231 = n2228 ? n2230 : dividend;
  /*# TG68K_ALU.vhd:1300:41 */
  assign n2234 = n2228 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1309:51 */
  assign n2235 = ~div_bit;
  /*# TG68K_ALU.vhd:1309:63 */
  assign n2236 = n2235 | nozero;
  /*# TG68K_ALU.vhd:1298:33 */
  assign n2237 = n2226 ? n2231 : div_quot;
  /*# TG68K_ALU.vhd:1298:33 */
  assign n2239 = n2226 ? 1'b0 : n2236;
  /*# TG68K_ALU.vhd:1311:47 */
  assign n2242 = micro_state == 7'b1011000;
  /*# TG68K_ALU.vhd:1312:72 */
  assign n2243 = OP2out[31]; // extract
  /*# TG68K_ALU.vhd:1312:77 */
  assign n2244 = n2243 ^ op1_sign;
  /*# TG68K_ALU.vhd:1312:61 */
  assign n2245 = signedop & n2244;
  /*# TG68K_ALU.vhd:1316:73 */
  assign n2246 = div_reg[63:32]; // extract
  /*# TG68K_ALU.vhd:1316:65 */
  assign n2248 = {1'b0, n2246};
  /*# TG68K_ALU.vhd:1316:93 */
  assign n2250 = {1'b0, op2outext};
  /*# TG68K_ALU.vhd:1316:123 */
  assign n2251 = OP2out[15:0]; // extract
  /*# TG68K_ALU.vhd:1316:116 */
  assign n2252 = {n2250, n2251};
  /*# TG68K_ALU.vhd:1316:88 */
  assign n2253 = n2248 - n2252;
  /*# TG68K_ALU.vhd:1319:40 */
  assign n2256 = exec[68]; // extract
  /*# TG68K_ALU.vhd:1319:56 */
  assign n2257 = ~n2256;
  /*# TG68K_ALU.vhd:1322:87 */
  assign n2258 = div_quot[63:32]; // extract
  /*# TG68K_ALU.vhd:1322:78 */
  assign n2260 = 32'b00000000000000000000000000000000 - n2258;
  /*# TG68K_ALU.vhd:1324:85 */
  assign n2261 = div_quot[63:32]; // extract
  /*# TG68K_ALU.vhd:1321:41 */
  assign n2262 = op1_sign ? n2260 : n2261;
  /*# TG68K_ALU.vhd:1319:33 */
  assign n2263 = {n2262, result_div_pre};
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2265 = n2257 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2266 = n2223 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2268 = n2242 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2269 = n2242 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2272 = n2226 & clkena_lw;
  /*# TG68K_ALU.vhd:86:16 */
  assign n2282 = {n104, n101};
  /*# TG68K_ALU.vhd:91:16 */
  assign n2283 = {n255, n248, n241};
  /*# TG68K_ALU.vhd:93:16 */
  assign n2284 = {n233, n232, n227, n185};
  /*# TG68K_ALU.vhd:101:16 */
  assign n2285 = {n277, n315};
  /*# TG68K_ALU.vhd:106:16 */
  assign n2287 = {64'bZ, n2038, n2039};
  /*# TG68K_ALU.vhd:129:16 */
  assign n2291 = {32'bZ, n2326};
  /*# TG68K_ALU.vhd:135:16 */
  assign n2294 = {n2192, n2195};
  /*# TG68K_ALU.vhd:143:16 */
  assign n2296 = {n2168, n2165, n2163};
  /*# TG68K_ALU.vhd:151:16 */
  assign n2299 = {n791, n781, n770, n759, n748, n737, n726, n715, n704, n693, n682, n671, n660, n649, n638, n627, n616, n605, n594, n583, n572, n561, n550, n539, n528, n517, n506, n495, n484, n473, n462, n450};
  /*# TG68K_ALU.vhd:154:16 */
  assign n2301 = {n1086, n1082, n1077, n1072, n1067, n1062, n1057, n1052, n1047, n1042, n1037, n1032, n1027, n1022, n1017, n1012, n1007, n1002, n997, n992, n987, n982, n977, n972, n967, n962, n957, n952, n947, n942, n937, n932, n927, n922, n917, n912, n907, n902, n897, n892};
  /*# TG68K_ALU.vhd:156:16 */
  assign n2302 = {n792, n784, n773, n762, n751, n740, n729, n718, n707, n696, n685, n674, n663, n652, n641, n630, n619, n608, n597, n586, n575, n564, n553, n542, n531, n520, n509, n498, n487, n476, n465, n453};
  /*# TG68K_ALU.vhd:168:16 */
  assign n2304 = {n848, n849};
  /*# TG68K_ALU.vhd:171:16 */
  assign n2305 = {n1170, n1199, n1196};
  /*# TG68K_ALU.vhd:188:16 */
  assign n2307 = {n1690, n1688, n1685, n1682, n1679, n1692};
  /*# TG68K_ALU.vhd:195:16 */
  assign n2308 = {n1371, n1368, n1372, n1366, n1370};
  /*# TG68K_ALU.vhd:196:16 */
  assign n2309 = {n1625, n1627};
  /*# TG68K_ALU.vhd:200:16 */
  assign n2310 = {n1702, n1699, n1704};
  /*# TG68K_ALU.vhd:446:17 */
  assign n2311 = clkena_lw ? n426 : n2312;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2312 <= n2311;
  /*# TG68K_ALU.vhd:996:17 */
  always @(posedge clk)
    n2313 <= n2007;
  /*# TG68K_ALU.vhd:996:17 */
  always @(posedge clk)
    n2314 <= n2003;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2315 = n2265 ? n2263 : result_div;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2316 <= n2315;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2317 = n2266 ? n2217 : v_flag;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2318 <= n2317;
  /*# TG68K_ALU.vhd:996:17 */
  always @(posedge clk)
    n2319 <= n2004;
  /*# TG68K_ALU.vhd:405:17 */
  assign n2320 = clkena_lw ? n336 : bchg;
  /*# TG68K_ALU.vhd:405:17 */
  always @(posedge clk)
    n2321 <= n2320;
  /*# TG68K_ALU.vhd:405:17 */
  assign n2322 = clkena_lw ? n340 : bset;
  /*# TG68K_ALU.vhd:405:17 */
  always @(posedge clk)
    n2323 <= n2322;
  /*# TG68K_ALU.vhd:1211:17 */
  assign n2324 = mulu_reg[31:0]; // extract
  /*# TG68K_ALU.vhd:1211:17 */
  assign n2325 = clkena_lw ? n2069 : n2324;
  /*# TG68K_ALU.vhd:1211:17 */
  always @(posedge clk)
    n2326 <= n2325;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2327 = clkena_lw ? n2237 : div_reg;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2328 <= n2327;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2329 = n2268 ? n2245 : div_neg;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2330 <= n2329;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2331 = n2269 ? n2253 : div_over;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2332 <= n2331;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2333 = clkena_lw ? n2239 : nozero;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2334 <= n2333;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2335 = clkena_lw ? divs : signedop;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2336 <= n2335;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2337 = n2272 ? n2234 : op1_sign;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2338 <= n2337;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2339 = clkena_lw ? n399 : bf_bset;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2340 <= n2339;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2341 = clkena_lw ? n403 : bf_bchg;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2342 <= n2341;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2343 = clkena_lw ? n407 : bf_ins;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2344 <= n2343;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2345 = clkena_lw ? n411 : bf_exts;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2346 <= n2345;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2347 = clkena_lw ? n415 : bf_fffo;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2348 <= n2347;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2349 = clkena_lw ? n424 : bf_d32;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2350 <= n2349;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2351 = clkena_lw ? n418 : bf_s32;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2352 <= n2351;
  /*# TG68K_ALU.vhd:433:38 */
  assign n2353 = OP1out[bit_number * 1 +: 1]; //(Bmux)
  /*# TG68K_ALU.vhd:435:17 */
  assign n2354 = bit_number[4]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2355 = ~n2354;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2356 = bit_number[3]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2357 = ~n2356;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2358 = n2355 & n2357;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2359 = n2355 & n2356;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2360 = n2354 & n2357;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2361 = n2354 & n2356;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2362 = bit_number[2]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2363 = ~n2362;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2364 = n2358 & n2363;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2365 = n2358 & n2362;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2366 = n2359 & n2363;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2367 = n2359 & n2362;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2368 = n2360 & n2363;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2369 = n2360 & n2362;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2370 = n2361 & n2363;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2371 = n2361 & n2362;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2372 = bit_number[1]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2373 = ~n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2374 = n2364 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2375 = n2364 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2376 = n2365 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2377 = n2365 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2378 = n2366 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2379 = n2366 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2380 = n2367 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2381 = n2367 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2382 = n2368 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2383 = n2368 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2384 = n2369 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2385 = n2369 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2386 = n2370 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2387 = n2370 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2388 = n2371 & n2373;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2389 = n2371 & n2372;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2390 = bit_number[0]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2391 = ~n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2392 = n2374 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2393 = n2374 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2394 = n2375 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2395 = n2375 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2396 = n2376 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2397 = n2376 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2398 = n2377 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2399 = n2377 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2400 = n2378 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2401 = n2378 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2402 = n2379 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2403 = n2379 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2404 = n2380 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2405 = n2380 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2406 = n2381 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2407 = n2381 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2408 = n2382 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2409 = n2382 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2410 = n2383 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2411 = n2383 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2412 = n2384 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2413 = n2384 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2414 = n2385 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2415 = n2385 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2416 = n2386 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2417 = n2386 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2418 = n2387 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2419 = n2387 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2420 = n2388 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2421 = n2388 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2422 = n2389 & n2391;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2423 = n2389 & n2390;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2424 = OP1out[0]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2425 = n2392 ? n372 : n2424;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2426 = OP1out[1]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2427 = n2393 ? n372 : n2426;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2428 = OP1out[2]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2429 = n2394 ? n372 : n2428;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2430 = OP1out[3]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2431 = n2395 ? n372 : n2430;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2432 = OP1out[4]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2433 = n2396 ? n372 : n2432;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2434 = OP1out[5]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2435 = n2397 ? n372 : n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2436 = OP1out[6]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2437 = n2398 ? n372 : n2436;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2438 = OP1out[7]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2439 = n2399 ? n372 : n2438;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2440 = OP1out[8]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2441 = n2400 ? n372 : n2440;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2442 = OP1out[9]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2443 = n2401 ? n372 : n2442;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2444 = OP1out[10]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2445 = n2402 ? n372 : n2444;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2446 = OP1out[11]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2447 = n2403 ? n372 : n2446;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2448 = OP1out[12]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2449 = n2404 ? n372 : n2448;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2450 = OP1out[13]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2451 = n2405 ? n372 : n2450;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2452 = OP1out[14]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2453 = n2406 ? n372 : n2452;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2454 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2455 = n2407 ? n372 : n2454;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2456 = OP1out[16]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2457 = n2408 ? n372 : n2456;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2458 = OP1out[17]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2459 = n2409 ? n372 : n2458;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2460 = OP1out[18]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2461 = n2410 ? n372 : n2460;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2462 = OP1out[19]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2463 = n2411 ? n372 : n2462;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2464 = OP1out[20]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2465 = n2412 ? n372 : n2464;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2466 = OP1out[21]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2467 = n2413 ? n372 : n2466;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2468 = OP1out[22]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2469 = n2414 ? n372 : n2468;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2470 = OP1out[23]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2471 = n2415 ? n372 : n2470;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2472 = OP1out[24]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2473 = n2416 ? n372 : n2472;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2474 = OP1out[25]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2475 = n2417 ? n372 : n2474;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2476 = OP1out[26]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2477 = n2418 ? n372 : n2476;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2478 = OP1out[27]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2479 = n2419 ? n372 : n2478;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2480 = OP1out[28]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2481 = n2420 ? n372 : n2480;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2482 = OP1out[29]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2483 = n2421 ? n372 : n2482;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2484 = OP1out[30]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2485 = n2422 ? n372 : n2484;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2486 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2487 = n2423 ? n372 : n2486;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2488 = {n2487, n2485, n2483, n2481, n2479, n2477, n2475, n2473, n2471, n2469, n2467, n2465, n2463, n2461, n2459, n2457, n2455, n2453, n2451, n2449, n2447, n2445, n2443, n2441, n2439, n2437, n2435, n2433, n2431, n2429, n2427, n2425};
  /*# TG68K_ALU.vhd:496:37 */
  assign n2489 = datareg[n794 * 1 +: 1]; //(Bmux)
  /*# TG68K_ALU.vhd:761:17 */
  assign n2490 = bit_msb[5]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2491 = ~n2490;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2492 = bit_msb[4]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2493 = ~n2492;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2494 = n2491 & n2493;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2495 = n2491 & n2492;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2496 = n2490 & n2493;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2497 = bit_msb[3]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2498 = ~n2497;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2499 = n2494 & n2498;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2500 = n2494 & n2497;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2501 = n2495 & n2498;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2502 = n2495 & n2497;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2503 = n2496 & n2498;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2504 = bit_msb[2]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2505 = ~n2504;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2506 = n2499 & n2505;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2507 = n2499 & n2504;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2508 = n2500 & n2505;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2509 = n2500 & n2504;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2510 = n2501 & n2505;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2511 = n2501 & n2504;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2512 = n2502 & n2505;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2513 = n2502 & n2504;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2514 = n2503 & n2505;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2515 = bit_msb[1]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2516 = ~n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2517 = n2506 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2518 = n2506 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2519 = n2507 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2520 = n2507 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2521 = n2508 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2522 = n2508 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2523 = n2509 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2524 = n2509 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2525 = n2510 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2526 = n2510 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2527 = n2511 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2528 = n2511 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2529 = n2512 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2530 = n2512 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2531 = n2513 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2532 = n2513 & n2515;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2533 = n2514 & n2516;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2534 = bit_msb[0]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2535 = ~n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2536 = n2517 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2537 = n2517 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2538 = n2518 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2539 = n2518 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2540 = n2519 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2541 = n2519 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2542 = n2520 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2543 = n2520 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2544 = n2521 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2545 = n2521 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2546 = n2522 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2547 = n2522 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2548 = n2523 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2549 = n2523 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2550 = n2524 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2551 = n2524 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2552 = n2525 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2553 = n2525 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2554 = n2526 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2555 = n2526 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2556 = n2527 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2557 = n2527 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2558 = n2528 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2559 = n2528 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2560 = n2529 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2561 = n2529 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2562 = n2530 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2563 = n2530 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2564 = n2531 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2565 = n2531 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2566 = n2532 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2567 = n2532 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2568 = n2533 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2569 = n2533 & n2534;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2570 = n1337[0]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2571 = n2536 ? 1'b1 : n2570;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2572 = n1337[1]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2573 = n2537 ? 1'b1 : n2572;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2574 = n1337[2]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2575 = n2538 ? 1'b1 : n2574;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2576 = n1337[3]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2577 = n2539 ? 1'b1 : n2576;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2578 = n1337[4]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2579 = n2540 ? 1'b1 : n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2580 = n1337[5]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2581 = n2541 ? 1'b1 : n2580;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2582 = n1337[6]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2583 = n2542 ? 1'b1 : n2582;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2584 = n1337[7]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2585 = n2543 ? 1'b1 : n2584;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2586 = n1337[8]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2587 = n2544 ? 1'b1 : n2586;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2588 = n1337[9]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2589 = n2545 ? 1'b1 : n2588;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2590 = n1337[10]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2591 = n2546 ? 1'b1 : n2590;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2592 = n1337[11]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2593 = n2547 ? 1'b1 : n2592;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2594 = n1337[12]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2595 = n2548 ? 1'b1 : n2594;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2596 = n1337[13]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2597 = n2549 ? 1'b1 : n2596;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2598 = n1337[14]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2599 = n2550 ? 1'b1 : n2598;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2600 = n1337[15]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2601 = n2551 ? 1'b1 : n2600;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2602 = n1337[16]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2603 = n2552 ? 1'b1 : n2602;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2604 = n1337[17]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2605 = n2553 ? 1'b1 : n2604;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2606 = n1337[18]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2607 = n2554 ? 1'b1 : n2606;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2608 = n1337[19]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2609 = n2555 ? 1'b1 : n2608;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2610 = n1337[20]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2611 = n2556 ? 1'b1 : n2610;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2612 = n1337[21]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2613 = n2557 ? 1'b1 : n2612;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2614 = n1337[22]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2615 = n2558 ? 1'b1 : n2614;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2616 = n1337[23]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2617 = n2559 ? 1'b1 : n2616;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2618 = n1337[24]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2619 = n2560 ? 1'b1 : n2618;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2620 = n1337[25]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2621 = n2561 ? 1'b1 : n2620;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2622 = n1337[26]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2623 = n2562 ? 1'b1 : n2622;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2624 = n1337[27]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2625 = n2563 ? 1'b1 : n2624;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2626 = n1337[28]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2627 = n2564 ? 1'b1 : n2626;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2628 = n1337[29]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2629 = n2565 ? 1'b1 : n2628;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2630 = n1337[30]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2631 = n2566 ? 1'b1 : n2630;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2632 = n1337[31]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2633 = n2567 ? 1'b1 : n2632;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2634 = n1337[32]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2635 = n2568 ? 1'b1 : n2634;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2636 = n1337[33]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2637 = n2569 ? 1'b1 : n2636;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2638 = {n2637, n2635, n2633, n2631, n2629, n2627, n2625, n2623, n2621, n2619, n2617, n2615, n2613, n2611, n2609, n2607, n2605, n2603, n2601, n2599, n2597, n2595, n2593, n2591, n2589, n2587, n2585, n2583, n2581, n2579, n2577, n2575, n2573, n2571};
endmodule

