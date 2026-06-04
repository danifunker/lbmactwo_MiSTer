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
   input  [7:0] micro_state,
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
  wire [31:0] n446;
  wire n447;
  wire n450;
  wire n451;
  wire n454;
  localparam [31:0] n455 = 32'b00000000000000000000000000000000;
  wire [4:0] n457;
  wire [31:0] n459;
  wire n460;
  wire n463;
  wire n464;
  wire n466;
  wire n467;
  wire [4:0] n469;
  wire [31:0] n471;
  wire n472;
  wire n475;
  wire n476;
  wire n478;
  wire n479;
  wire [4:0] n481;
  wire [31:0] n483;
  wire n484;
  wire n487;
  wire n488;
  wire n490;
  wire n491;
  wire [4:0] n493;
  wire [31:0] n495;
  wire n496;
  wire n499;
  wire n500;
  wire n502;
  wire n503;
  wire [4:0] n505;
  wire [31:0] n507;
  wire n508;
  wire n511;
  wire n512;
  wire n514;
  wire n515;
  wire [4:0] n517;
  wire [31:0] n519;
  wire n520;
  wire n523;
  wire n524;
  wire n526;
  wire n527;
  wire [4:0] n529;
  wire [31:0] n531;
  wire n532;
  wire n535;
  wire n536;
  wire n538;
  wire n539;
  wire [4:0] n541;
  wire [31:0] n543;
  wire n544;
  wire n547;
  wire n548;
  wire n550;
  wire n551;
  wire [4:0] n553;
  wire [31:0] n555;
  wire n556;
  wire n559;
  wire n560;
  wire n562;
  wire n563;
  wire [4:0] n565;
  wire [31:0] n567;
  wire n568;
  wire n571;
  wire n572;
  wire n574;
  wire n575;
  wire [4:0] n577;
  wire [31:0] n579;
  wire n580;
  wire n583;
  wire n584;
  wire n586;
  wire n587;
  wire [4:0] n589;
  wire [31:0] n591;
  wire n592;
  wire n595;
  wire n596;
  wire n598;
  wire n599;
  wire [4:0] n601;
  wire [31:0] n603;
  wire n604;
  wire n607;
  wire n608;
  wire n610;
  wire n611;
  wire [4:0] n613;
  wire [31:0] n615;
  wire n616;
  wire n619;
  wire n620;
  wire n622;
  wire n623;
  wire [4:0] n625;
  wire [31:0] n627;
  wire n628;
  wire n631;
  wire n632;
  wire n634;
  wire n635;
  wire [4:0] n637;
  wire [31:0] n639;
  wire n640;
  wire n643;
  wire n644;
  wire n646;
  wire n647;
  wire [4:0] n649;
  wire [31:0] n651;
  wire n652;
  wire n655;
  wire n656;
  wire n658;
  wire n659;
  wire [4:0] n661;
  wire [31:0] n663;
  wire n664;
  wire n667;
  wire n668;
  wire n670;
  wire n671;
  wire [4:0] n673;
  wire [31:0] n675;
  wire n676;
  wire n679;
  wire n680;
  wire n682;
  wire n683;
  wire [4:0] n685;
  wire [31:0] n687;
  wire n688;
  wire n691;
  wire n692;
  wire n694;
  wire n695;
  wire [4:0] n697;
  wire [31:0] n699;
  wire n700;
  wire n703;
  wire n704;
  wire n706;
  wire n707;
  wire [4:0] n709;
  wire [31:0] n711;
  wire n712;
  wire n715;
  wire n716;
  wire n718;
  wire n719;
  wire [4:0] n721;
  wire [31:0] n723;
  wire n724;
  wire n727;
  wire n728;
  wire n730;
  wire n731;
  wire [4:0] n733;
  wire [31:0] n735;
  wire n736;
  wire n739;
  wire n740;
  wire n742;
  wire n743;
  wire [4:0] n745;
  wire [31:0] n747;
  wire n748;
  wire n751;
  wire n752;
  wire n754;
  wire n755;
  wire [4:0] n757;
  wire [31:0] n759;
  wire n760;
  wire n763;
  wire n764;
  wire n766;
  wire n767;
  wire [4:0] n769;
  wire [31:0] n771;
  wire n772;
  wire n775;
  wire n776;
  wire n778;
  wire n779;
  wire [4:0] n781;
  wire [31:0] n783;
  wire n784;
  wire n787;
  wire n788;
  wire n790;
  wire n791;
  wire [4:0] n793;
  wire [31:0] n795;
  wire n796;
  wire n799;
  wire n800;
  wire n802;
  wire n803;
  wire [4:0] n805;
  wire [31:0] n807;
  wire n808;
  wire n811;
  wire n812;
  wire n813;
  wire n814;
  wire n815;
  wire n816;
  wire [4:0] n817;
  wire [31:0] n819;
  wire n820;
  wire n823;
  wire n824;
  wire [4:0] n826;
  wire n829;
  wire [31:0] n830;
  wire [31:0] n831;
  wire n832;
  wire [15:0] n833;
  wire [15:0] n834;
  wire [31:0] n835;
  wire [31:0] n836;
  wire n837;
  wire [23:0] n838;
  wire [7:0] n839;
  wire [31:0] n840;
  wire [31:0] n841;
  wire n842;
  wire [35:0] n844;
  wire [3:0] n845;
  wire [3:0] n846;
  wire [3:0] n847;
  wire [31:0] n848;
  wire [35:0] n850;
  wire [35:0] n851;
  wire [35:0] n852;
  wire n853;
  wire [37:0] n855;
  wire [1:0] n856;
  wire [1:0] n857;
  wire [1:0] n858;
  wire [35:0] n859;
  wire [37:0] n861;
  wire [37:0] n862;
  wire [37:0] n863;
  wire n864;
  wire [38:0] n866;
  wire [39:0] n868;
  wire n869;
  wire n870;
  wire n871;
  wire [38:0] n872;
  wire [39:0] n874;
  wire [39:0] n875;
  wire [39:0] n876;
  wire [39:0] n877;
  wire [7:0] n878;
  wire [7:0] n879;
  wire [7:0] n880;
  wire [31:0] n881;
  wire n882;
  wire n883;
  wire [38:0] n884;
  wire [39:0] n885;
  wire [39:0] n886;
  wire n887;
  wire [1:0] n888;
  wire [37:0] n889;
  wire [39:0] n890;
  wire [39:0] n891;
  wire n892;
  wire [3:0] n893;
  wire [35:0] n894;
  wire [39:0] n895;
  wire [39:0] n896;
  wire n897;
  wire [7:0] n898;
  wire [23:0] n899;
  wire [31:0] n900;
  wire [31:0] n901;
  wire [31:0] n902;
  wire n903;
  wire [15:0] n904;
  wire [15:0] n905;
  wire [31:0] n906;
  wire [31:0] n907;
  wire [7:0] n908;
  wire [31:0] n909;
  wire [7:0] n910;
  wire [39:0] n911;
  wire [39:0] n913;
  wire [39:0] n914;
  wire [39:0] n915;
  wire [39:0] n917;
  wire [39:0] n918;
  wire [39:0] n919;
  wire [39:0] n920;
  wire n921;
  wire n922;
  wire n923;
  wire n924;
  wire n926;
  wire n927;
  wire n928;
  wire n929;
  wire n931;
  wire n932;
  wire n933;
  wire n934;
  wire n936;
  wire n937;
  wire n938;
  wire n939;
  wire n941;
  wire n942;
  wire n943;
  wire n944;
  wire n946;
  wire n947;
  wire n948;
  wire n949;
  wire n951;
  wire n952;
  wire n953;
  wire n954;
  wire n956;
  wire n957;
  wire n958;
  wire n959;
  wire n961;
  wire n962;
  wire n963;
  wire n964;
  wire n966;
  wire n967;
  wire n968;
  wire n969;
  wire n971;
  wire n972;
  wire n973;
  wire n974;
  wire n976;
  wire n977;
  wire n978;
  wire n979;
  wire n981;
  wire n982;
  wire n983;
  wire n984;
  wire n986;
  wire n987;
  wire n988;
  wire n989;
  wire n991;
  wire n992;
  wire n993;
  wire n994;
  wire n996;
  wire n997;
  wire n998;
  wire n999;
  wire n1001;
  wire n1002;
  wire n1003;
  wire n1004;
  wire n1006;
  wire n1007;
  wire n1008;
  wire n1009;
  wire n1011;
  wire n1012;
  wire n1013;
  wire n1014;
  wire n1016;
  wire n1017;
  wire n1018;
  wire n1019;
  wire n1021;
  wire n1022;
  wire n1023;
  wire n1024;
  wire n1026;
  wire n1027;
  wire n1028;
  wire n1029;
  wire n1031;
  wire n1032;
  wire n1033;
  wire n1034;
  wire n1036;
  wire n1037;
  wire n1038;
  wire n1039;
  wire n1041;
  wire n1042;
  wire n1043;
  wire n1044;
  wire n1046;
  wire n1047;
  wire n1048;
  wire n1049;
  wire n1051;
  wire n1052;
  wire n1053;
  wire n1054;
  wire n1056;
  wire n1057;
  wire n1058;
  wire n1059;
  wire n1061;
  wire n1062;
  wire n1063;
  wire n1064;
  wire n1066;
  wire n1067;
  wire n1068;
  wire n1069;
  wire n1071;
  wire n1072;
  wire n1073;
  wire n1074;
  wire n1076;
  wire n1077;
  wire n1078;
  wire n1079;
  wire n1081;
  wire n1082;
  wire n1083;
  wire n1084;
  wire n1086;
  wire n1087;
  wire n1088;
  wire n1089;
  wire n1091;
  wire n1092;
  wire n1093;
  wire n1094;
  wire n1096;
  wire n1097;
  wire n1098;
  wire n1099;
  wire n1101;
  wire n1102;
  wire n1103;
  wire n1104;
  wire n1106;
  wire n1107;
  wire n1108;
  wire n1109;
  wire n1111;
  wire n1112;
  wire n1113;
  wire n1114;
  wire n1115;
  wire n1116;
  wire n1117;
  wire n1118;
  wire [5:0] n1120;
  wire [5:0] n1121;
  wire [5:0] n1122;
  wire [3:0] n1123;
  wire n1125;
  wire [3:0] n1126;
  wire n1128;
  wire [3:0] n1129;
  wire n1131;
  wire [3:0] n1132;
  wire n1134;
  wire [3:0] n1136;
  wire n1138;
  wire [3:0] n1139;
  wire n1141;
  wire [3:0] n1143;
  wire n1145;
  wire [3:0] n1147;
  wire [3:0] n1148;
  wire [3:0] n1149;
  wire n1151;
  wire [3:0] n1152;
  wire [3:0] n1154;
  wire [1:0] n1155;
  wire n1156;
  wire n1157;
  wire n1158;
  wire n1160;
  wire [3:0] n1161;
  wire [3:0] n1162;
  wire [1:0] n1163;
  wire [1:0] n1165;
  wire [3:0] n1166;
  wire [3:0] n1169;
  wire [1:0] n1170;
  wire [2:0] n1171;
  wire [1:0] n1172;
  wire [1:0] n1173;
  wire n1174;
  wire n1176;
  wire [3:0] n1177;
  wire [3:0] n1179;
  wire [2:0] n1180;
  wire n1181;
  wire n1183;
  wire n1184;
  wire n1185;
  wire n1186;
  wire n1188;
  wire [3:0] n1189;
  wire [3:0] n1191;
  wire [2:0] n1192;
  wire n1193;
  wire n1194;
  wire [1:0] n1195;
  wire [1:0] n1197;
  wire [3:0] n1198;
  wire [3:0] n1199;
  wire [2:0] n1200;
  wire [2:0] n1202;
  localparam [4:0] n1203 = 5'b11111;
  wire [1:0] n1205;
  wire n1207;
  wire n1209;
  wire n1210;
  wire n1212;
  wire n1213;
  wire n1216;
  wire n1217;
  wire n1218;
  wire n1220;
  wire n1221;
  wire n1222;
  wire n1224;
  wire n1225;
  wire [1:0] n1226;
  wire n1227;
  wire n1228;
  wire n1229;
  wire n1230;
  wire n1231;
  wire n1234;
  wire [1:0] n1239;
  wire n1240;
  wire n1242;
  wire n1243;
  wire n1245;
  wire n1247;
  wire n1248;
  wire n1249;
  wire n1251;
  wire [2:0] n1252;
  reg n1253;
  wire n1271;
  wire n1272;
  wire n1274;
  wire n1275;
  wire n1277;
  wire n1278;
  wire n1281;
  wire n1282;
  wire n1302;
  wire n1303;
  wire n1306;
  wire n1307;
  wire [31:0] n1308;
  wire n1313;
  wire [1:0] n1314;
  wire n1316;
  wire n1318;
  wire n1320;
  wire n1321;
  wire n1323;
  wire [2:0] n1324;
  reg [5:0] n1329;
  wire [1:0] n1330;
  wire n1332;
  wire n1334;
  wire n1336;
  wire n1337;
  wire n1339;
  wire [2:0] n1340;
  reg [5:0] n1345;
  wire [5:0] n1346;
  wire [1:0] n1348;
  wire n1350;
  wire n1351;
  wire n1352;
  wire n1353;
  wire n1354;
  wire [5:0] n1355;
  wire [2:0] n1356;
  wire [2:0] n1357;
  wire n1359;
  wire [2:0] n1362;
  wire [5:0] n1363;
  wire [5:0] n1364;
  wire [5:0] n1366;
  localparam [33:0] n1369 = 34'b0000000000000000000000000000000000;
  wire n1373;
  wire [5:0] n1374;
  wire [5:0] n1376;
  wire [30:0] n1378;
  wire [31:0] n1380;
  wire [30:0] n1381;
  wire [31:0] n1383;
  wire [31:0] n1384;
  wire [32:0] n1385;
  wire [1:0] n1386;
  wire n1389;
  wire n1392;
  wire n1394;
  wire n1395;
  wire [1:0] n1396;
  wire n1397;
  reg n1398;
  wire n1399;
  reg n1400;
  wire [7:0] n1402;
  wire [15:0] n1403;
  wire [6:0] n1404;
  wire [31:0] n1405;
  wire [32:0] n1407;
  wire [32:0] n1408;
  wire n1410;
  wire n1411;
  wire n1412;
  wire n1413;
  wire n1414;
  wire n1416;
  wire n1418;
  wire n1419;
  wire n1420;
  wire [1:0] n1421;
  wire n1422;
  wire n1424;
  wire n1425;
  wire n1427;
  wire n1429;
  wire n1430;
  wire n1431;
  wire n1433;
  wire [2:0] n1434;
  reg n1435;
  wire n1436;
  wire n1438;
  wire n1439;
  wire [1:0] n1440;
  wire [7:0] n1441;
  wire [7:0] n1442;
  wire [7:0] n1443;
  wire n1444;
  wire n1446;
  wire [15:0] n1447;
  wire [15:0] n1448;
  wire [15:0] n1449;
  wire n1450;
  wire n1452;
  wire n1454;
  wire n1455;
  wire [31:0] n1456;
  wire [31:0] n1457;
  wire [31:0] n1458;
  wire n1459;
  wire n1461;
  wire [2:0] n1462;
  wire [7:0] n1463;
  wire [7:0] n1464;
  reg [7:0] n1466;
  wire [7:0] n1467;
  wire [7:0] n1468;
  reg [7:0] n1470;
  wire [15:0] n1471;
  reg [15:0] n1473;
  reg n1474;
  wire n1475;
  wire n1476;
  wire n1477;
  wire n1479;
  wire [1:0] n1480;
  wire [7:0] n1481;
  wire [7:0] n1482;
  wire [7:0] n1483;
  wire n1484;
  wire n1485;
  wire n1486;
  wire n1488;
  wire [15:0] n1489;
  wire [15:0] n1490;
  wire [15:0] n1491;
  wire n1492;
  wire n1493;
  wire n1494;
  wire n1496;
  wire n1498;
  wire n1499;
  wire [31:0] n1500;
  wire [31:0] n1501;
  wire [31:0] n1502;
  wire n1503;
  wire n1504;
  wire n1505;
  wire n1507;
  wire [2:0] n1508;
  wire [7:0] n1509;
  wire [7:0] n1510;
  reg [7:0] n1512;
  wire [7:0] n1513;
  wire [7:0] n1514;
  reg [7:0] n1516;
  wire [15:0] n1517;
  reg [15:0] n1519;
  reg n1520;
  wire n1521;
  wire n1522;
  wire [31:0] n1523;
  wire [31:0] n1524;
  wire [31:0] n1525;
  wire [31:0] n1526;
  wire [31:0] n1527;
  wire n1528;
  wire [31:0] n1529;
  wire [31:0] n1530;
  wire n1532;
  wire n1533;
  wire n1535;
  wire n1537;
  wire n1538;
  wire n1540;
  wire n1541;
  wire n1543;
  wire n1544;
  wire n1545;
  wire [31:0] n1546;
  wire n1548;
  wire [31:0] n1549;
  wire n1551;
  wire [5:0] n1553;
  wire [31:0] n1554;
  wire n1556;
  wire [5:0] n1558;
  wire [31:0] n1559;
  wire n1561;
  wire [5:0] n1563;
  wire [31:0] n1564;
  wire n1566;
  wire [5:0] n1568;
  wire [31:0] n1569;
  wire n1571;
  wire [5:0] n1573;
  wire [31:0] n1574;
  wire n1576;
  wire [5:0] n1578;
  wire [5:0] n1579;
  wire [5:0] n1580;
  wire [5:0] n1581;
  wire [5:0] n1582;
  wire [5:0] n1583;
  wire [5:0] n1584;
  wire [5:0] n1586;
  wire n1588;
  wire [31:0] n1589;
  wire n1591;
  wire [5:0] n1593;
  wire [31:0] n1594;
  wire n1596;
  wire [5:0] n1598;
  wire [31:0] n1599;
  wire n1601;
  wire [5:0] n1603;
  wire [5:0] n1604;
  wire [5:0] n1605;
  wire [5:0] n1606;
  wire n1608;
  wire [31:0] n1609;
  wire n1611;
  wire [5:0] n1613;
  wire [5:0] n1614;
  wire n1616;
  wire [2:0] n1617;
  wire [5:0] n1619;
  wire n1621;
  wire [3:0] n1622;
  wire [5:0] n1624;
  wire n1626;
  wire [4:0] n1627;
  wire [5:0] n1629;
  wire n1631;
  wire [5:0] n1632;
  reg [5:0] n1634;
  wire n1635;
  wire n1636;
  wire [5:0] n1637;
  wire [5:0] n1638;
  wire n1639;
  wire n1640;
  wire n1641;
  wire n1642;
  wire [5:0] n1644;
  wire [5:0] n1645;
  wire n1646;
  wire n1647;
  wire n1648;
  wire [5:0] n1650;
  wire [5:0] n1651;
  wire [5:0] n1652;
  wire n1653;
  wire n1654;
  wire n1655;
  wire [5:0] n1657;
  wire [5:0] n1659;
  wire n1661;
  wire [5:0] n1662;
  wire n1663;
  wire [5:0] n1664;
  wire n1665;
  wire [31:0] n1666;
  wire [31:0] n1667;
  wire [31:0] n1668;
  localparam [32:0] n1669 = 33'b000000000000000000000000000000000;
  wire n1670;
  wire n1672;
  wire n1673;
  wire n1674;
  wire n1675;
  wire n1676;
  wire [31:0] n1677;
  wire [31:0] n1678;
  wire n1679;
  wire n1681;
  wire [31:0] n1682;
  wire n1683;
  wire [32:0] n1685;
  wire [1:0] n1686;
  wire n1687;
  localparam [23:0] n1688 = 24'b000000000000000000000000;
  localparam [23:0] n1689 = 24'b000000000000000000000000;
  wire n1691;
  wire n1692;
  wire n1693;
  wire n1694;
  wire [22:0] n1695;
  wire n1697;
  wire n1698;
  localparam [15:0] n1699 = 16'b0000000000000000;
  wire n1702;
  wire n1703;
  wire n1704;
  wire n1705;
  wire [14:0] n1706;
  wire n1708;
  wire n1710;
  wire n1711;
  wire n1712;
  wire n1714;
  wire n1715;
  wire n1716;
  wire n1717;
  wire n1719;
  wire [2:0] n1720;
  wire n1721;
  reg n1722;
  wire [6:0] n1723;
  wire [6:0] n1724;
  reg [6:0] n1725;
  wire n1726;
  wire n1727;
  reg n1728;
  wire [14:0] n1729;
  wire [14:0] n1730;
  reg [14:0] n1731;
  wire n1732;
  reg n1733;
  wire [7:0] n1735;
  reg n1739;
  wire [7:0] n1740;
  wire [7:0] n1741;
  reg [7:0] n1742;
  wire [15:0] n1743;
  wire [15:0] n1744;
  reg [15:0] n1745;
  wire [7:0] n1747;
  wire [65:0] n1749;
  wire [30:0] n1750;
  wire [31:0] n1751;
  wire [65:0] n1752;
  wire n1756;
  wire [7:0] n1757;
  wire [7:0] n1758;
  wire n1759;
  wire [7:0] n1760;
  wire [7:0] n1761;
  wire n1762;
  wire [7:0] n1763;
  wire [7:0] n1764;
  wire [7:0] n1765;
  wire [7:0] n1766;
  wire [7:0] n1767;
  wire [7:0] n1768;
  wire n1769;
  wire n1770;
  wire n1771;
  wire n1772;
  wire [7:0] n1773;
  wire n1775;
  wire [7:0] n1777;
  wire n1779;
  wire [15:0] n1781;
  wire n1783;
  wire n1786;
  wire [1:0] n1787;
  wire [1:0] n1789;
  wire [2:0] n1790;
  wire [2:0] n1792;
  wire [2:0] n1794;
  wire n1797;
  wire n1798;
  wire n1799;
  wire [1:0] n1800;
  wire n1801;
  wire [2:0] n1802;
  wire n1803;
  wire [3:0] n1804;
  wire n1805;
  wire n1806;
  wire n1807;
  wire [1:0] n1808;
  wire [1:0] n1809;
  wire [1:0] n1810;
  wire [1:0] n1811;
  wire n1813;
  wire n1814;
  wire n1815;
  wire n1816;
  wire n1817;
  wire [1:0] n1818;
  wire n1819;
  wire [2:0] n1820;
  wire n1821;
  wire [3:0] n1822;
  wire n1823;
  wire n1824;
  wire [1:0] n1825;
  wire n1826;
  wire [2:0] n1827;
  wire n1828;
  wire [3:0] n1829;
  wire [3:0] n1830;
  wire [3:0] n1831;
  wire [3:0] n1832;
  wire n1834;
  wire n1835;
  wire [7:0] n1836;
  wire [7:0] n1837;
  wire n1838;
  wire [7:0] n1839;
  wire [7:0] n1840;
  wire n1841;
  wire n1842;
  wire n1843;
  wire n1844;
  wire n1845;
  wire n1846;
  wire n1848;
  wire n1849;
  wire n1851;
  wire n1852;
  wire n1853;
  wire n1854;
  wire n1855;
  wire [1:0] n1857;
  wire [3:0] n1859;
  wire [3:0] n1861;
  wire [3:0] n1862;
  wire [3:0] n1863;
  wire n1864;
  wire n1865;
  wire [3:0] n1866;
  wire n1867;
  wire n1868;
  wire n1869;
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
  wire n1884;
  wire n1886;
  wire n1888;
  wire n1890;
  wire n1891;
  wire n1892;
  wire [1:0] n1893;
  wire [3:0] n1895;
  wire n1896;
  wire n1897;
  wire [1:0] n1898;
  wire [3:0] n1900;
  wire [3:0] n1901;
  wire [3:0] n1902;
  wire n1903;
  wire n1905;
  wire n1906;
  wire n1907;
  wire n1908;
  wire n1909;
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
  wire n1928;
  wire n1929;
  wire n1932;
  wire n1933;
  wire n1934;
  wire n1935;
  wire n1936;
  wire [1:0] n1937;
  wire n1939;
  wire n1940;
  wire n1941;
  wire n1942;
  wire n1943;
  wire n1946;
  wire n1947;
  wire [1:0] n1948;
  wire n1949;
  wire n1950;
  wire n1951;
  wire n1952;
  wire n1953;
  wire n1954;
  wire n1955;
  wire n1956;
  wire n1957;
  wire n1958;
  wire n1959;
  wire n1960;
  wire n1961;
  wire n1962;
  wire n1963;
  wire n1964;
  wire n1965;
  wire n1966;
  wire n1967;
  wire n1968;
  wire n1969;
  wire n1970;
  wire n1972;
  wire n1973;
  wire n1974;
  wire n1975;
  wire n1976;
  wire n1977;
  wire n1979;
  wire n1980;
  wire n1981;
  wire n1982;
  wire [15:0] n1983;
  wire n1985;
  wire n1987;
  wire [15:0] n1988;
  wire n1990;
  wire n1991;
  wire n1992;
  wire n1995;
  wire [3:0] n1998;
  wire [3:0] n1999;
  wire [3:0] n2000;
  wire [3:0] n2001;
  wire [3:0] n2002;
  wire [1:0] n2003;
  wire [1:0] n2004;
  wire [1:0] n2005;
  wire n2006;
  wire n2007;
  wire n2008;
  wire n2009;
  wire n2010;
  wire [3:0] n2011;
  wire [3:0] n2012;
  wire [3:0] n2013;
  wire [3:0] n2014;
  wire [3:0] n2015;
  wire [3:0] n2016;
  wire [3:0] n2017;
  wire [3:0] n2018;
  wire [3:0] n2019;
  wire [3:0] n2020;
  wire [3:0] n2021;
  wire [4:0] n2022;
  wire [4:0] n2023;
  wire [4:0] n2024;
  wire [3:0] n2025;
  wire [3:0] n2026;
  wire [3:0] n2027;
  wire n2028;
  wire n2029;
  wire n2030;
  wire [3:0] n2031;
  wire [4:0] n2032;
  wire [4:0] n2033;
  wire [4:0] n2034;
  wire [2:0] n2035;
  wire [2:0] n2036;
  wire [2:0] n2037;
  wire [3:0] n2039;
  wire [7:0] n2040;
  wire [7:0] n2041;
  wire [3:0] n2042;
  wire n2043;
  wire [7:0] n2045;
  wire [3:0] n2046;
  wire n2047;
  wire [4:0] n2049;
  wire [7:0] n2050;
  wire n2057;
  wire n2058;
  wire n2059;
  wire n2060;
  wire n2062;
  wire n2063;
  wire n2064;
  wire n2067;
  wire [62:0] n2068;
  wire [63:0] n2069;
  wire n2070;
  wire [31:0] n2071;
  wire [32:0] n2072;
  wire [32:0] n2073;
  wire [32:0] n2074;
  wire [31:0] n2075;
  wire [32:0] n2076;
  wire [32:0] n2077;
  wire [32:0] n2078;
  wire [32:0] n2079;
  wire [32:0] n2080;
  wire [32:0] n2081;
  wire [30:0] n2082;
  wire n2083;
  wire n2085;
  wire [15:0] n2086;
  wire [31:0] n2088;
  wire [31:0] n2089;
  wire [31:0] n2112;
  wire n2120;
  wire n2121;
  wire n2122;
  wire n2123;
  wire n2124;
  wire n2125;
  wire n2126;
  wire n2127;
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
  wire n2150;
  wire n2151;
  wire n2152;
  wire n2153;
  wire n2154;
  wire n2155;
  wire n2156;
  wire n2157;
  wire n2158;
  wire n2159;
  wire n2160;
  wire n2161;
  wire n2162;
  wire n2163;
  wire n2164;
  wire n2165;
  wire n2166;
  wire n2167;
  wire n2168;
  wire n2169;
  wire n2170;
  wire n2171;
  wire n2172;
  wire n2173;
  wire n2174;
  wire n2175;
  wire n2176;
  wire n2177;
  wire n2178;
  wire n2179;
  wire n2180;
  wire n2181;
  wire n2182;
  wire n2183;
  wire n2184;
  wire n2185;
  wire n2186;
  wire n2187;
  wire n2188;
  wire n2189;
  wire n2190;
  wire n2191;
  wire n2192;
  wire [31:0] n2193;
  wire n2194;
  wire n2196;
  wire n2197;
  wire n2198;
  wire n2199;
  wire n2200;
  wire [31:0] n2201;
  wire n2202;
  wire n2203;
  wire [63:0] n2204;
  wire [15:0] n2205;
  wire [15:0] n2206;
  wire [31:0] n2207;
  wire [31:0] n2208;
  wire [15:0] n2209;
  wire [15:0] n2210;
  wire [15:0] n2211;
  wire n2213;
  wire n2214;
  wire n2215;
  wire [15:0] n2216;
  wire [15:0] n2218;
  wire n2219;
  wire n2220;
  wire [32:0] n2221;
  wire [32:0] n2223;
  wire [32:0] n2224;
  wire [32:0] n2225;
  wire [16:0] n2227;
  wire [15:0] n2228;
  wire [32:0] n2229;
  wire [32:0] n2230;
  wire [32:0] n2231;
  wire n2232;
  wire [31:0] n2233;
  wire [31:0] n2234;
  wire [31:0] n2235;
  wire [30:0] n2236;
  wire n2237;
  wire [31:0] n2238;
  wire [31:0] n2239;
  wire [31:0] n2241;
  wire [31:0] n2242;
  wire [31:0] n2243;
  wire n2244;
  wire n2245;
  wire n2246;
  wire n2247;
  wire n2248;
  wire n2249;
  wire n2250;
  wire n2251;
  wire n2252;
  wire n2253;
  wire n2254;
  wire n2255;
  wire n2257;
  wire n2260;
  wire n2266;
  wire n2269;
  wire n2270;
  wire n2271;
  wire [63:0] n2273;
  wire [63:0] n2274;
  wire n2277;
  wire n2278;
  wire n2279;
  wire [63:0] n2280;
  wire n2282;
  wire n2285;
  wire n2286;
  wire n2287;
  wire n2288;
  wire [31:0] n2289;
  wire [32:0] n2291;
  wire [16:0] n2293;
  wire [15:0] n2294;
  wire [32:0] n2295;
  wire [32:0] n2296;
  wire n2299;
  wire n2300;
  wire [31:0] n2301;
  wire [31:0] n2303;
  wire [31:0] n2304;
  wire [31:0] n2305;
  wire [63:0] n2306;
  wire n2308;
  wire n2309;
  wire n2311;
  wire n2312;
  wire n2315;
  wire [31:0] n2325;
  wire [2:0] n2326;
  wire [3:0] n2327;
  wire [8:0] n2328;
  wire [127:0] n2330;
  wire [63:0] n2334;
  wire [63:0] n2337;
  wire [63:0] n2339;
  wire [31:0] n2342;
  wire [39:0] n2344;
  wire [31:0] n2345;
  wire [39:0] n2347;
  wire [4:0] n2348;
  wire [32:0] n2350;
  wire [32:0] n2351;
  wire [32:0] n2352;
  wire [31:0] n2353;
  wire [7:0] n2354;
  reg [7:0] n2355;
  reg [7:0] n2356;
  reg [3:0] n2357;
  wire [63:0] n2358;
  reg [63:0] n2359;
  wire n2360;
  reg n2361;
  reg n2362;
  wire n2363;
  reg n2364;
  wire n2365;
  reg n2366;
  wire [31:0] n2367;
  wire [31:0] n2368;
  reg [31:0] n2369;
  wire [63:0] n2370;
  reg [63:0] n2371;
  wire n2372;
  reg n2373;
  wire [32:0] n2374;
  reg [32:0] n2375;
  wire n2376;
  reg n2377;
  wire n2378;
  reg n2379;
  wire n2380;
  reg n2381;
  wire n2382;
  reg n2383;
  wire n2384;
  reg n2385;
  wire n2386;
  reg n2387;
  wire n2388;
  reg n2389;
  wire n2390;
  reg n2391;
  wire n2392;
  reg n2393;
  wire n2394;
  reg n2395;
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
  wire n2488;
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
  wire [31:0] n2531;
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
  wire n2638;
  wire n2639;
  wire n2640;
  wire n2641;
  wire n2642;
  wire n2643;
  wire n2644;
  wire n2645;
  wire n2646;
  wire n2647;
  wire n2648;
  wire n2649;
  wire n2650;
  wire n2651;
  wire n2652;
  wire n2653;
  wire n2654;
  wire n2655;
  wire n2656;
  wire n2657;
  wire n2658;
  wire n2659;
  wire n2660;
  wire n2661;
  wire n2662;
  wire n2663;
  wire n2664;
  wire n2665;
  wire n2666;
  wire n2667;
  wire n2668;
  wire n2669;
  wire n2670;
  wire n2671;
  wire n2672;
  wire n2673;
  wire n2674;
  wire n2675;
  wire n2676;
  wire n2677;
  wire n2678;
  wire n2679;
  wire n2680;
  wire [33:0] n2681;
  assign bf_ext_out = n2355; //(module output)
  assign set_V_Flag = n2260; //(module output)
  assign Flags = n2356; //(module output)
  assign c_out = n256; //(module output)
  assign addsub_q = n234; //(module output)
  assign ALUout = n18; //(module output)
  /*# TG68K_ALU.vhd:86:16 */
  assign op1in = n2325; // (signal)
  /*# TG68K_ALU.vhd:87:16 */
  assign addsub_a = n122; // (signal)
  /*# TG68K_ALU.vhd:88:16 */
  assign addsub_b = n205; // (signal)
  /*# TG68K_ALU.vhd:89:16 */
  assign notaddsub_b = n217; // (signal)
  /*# TG68K_ALU.vhd:90:16 */
  assign add_result = n222; // (signal)
  /*# TG68K_ALU.vhd:91:16 */
  assign addsub_ofl = n2326; // (signal)
  /*# TG68K_ALU.vhd:92:16 */
  assign opaddsub = n184; // (signal)
  /*# TG68K_ALU.vhd:93:16 */
  assign c_in = n2327; // (signal)
  /*# TG68K_ALU.vhd:94:16 */
  assign flag_z = n1794; // (signal)
  /*# TG68K_ALU.vhd:95:16 */
  assign set_flags = n1832; // (signal)
  /*# TG68K_ALU.vhd:96:16 */
  assign ccrin = n1768; // (signal)
  /*# TG68K_ALU.vhd:97:16 */
  assign last_flags1 = n2357; // (signal)
  /*# TG68K_ALU.vhd:100:16 */
  assign bcd_pur = n262; // (signal)
  /*# TG68K_ALU.vhd:101:16 */
  assign bcd_kor = n2328; // (signal)
  /*# TG68K_ALU.vhd:102:16 */
  assign halve_carry = n267; // (signal)
  /*# TG68K_ALU.vhd:103:16 */
  assign vflag_a = n320; // (signal)
  /*# TG68K_ALU.vhd:104:16 */
  assign bcd_a_carry = n323; // (signal)
  /*# TG68K_ALU.vhd:105:16 */
  assign bcd_a = n317; // (signal)
  /*# TG68K_ALU.vhd:106:16 */
  assign result_mulu = n2330; // (signal)
  /*# TG68K_ALU.vhd:107:16 */
  assign result_div = n2359; // (signal)
  /*# TG68K_ALU.vhd:108:16 */
  assign result_div_pre = n2243; // (signal)
  /*# TG68K_ALU.vhd:110:16 */
  assign v_flag = n2361; // (signal)
  /*# TG68K_ALU.vhd:112:16 */
  assign rot_rot = n1253; // (signal)
  /*# TG68K_ALU.vhd:115:16 */
  assign rot_x = n1306; // (signal)
  /*# TG68K_ALU.vhd:116:16 */
  assign rot_c = n1307; // (signal)
  /*# TG68K_ALU.vhd:117:16 */
  assign rot_out = n1308; // (signal)
  /*# TG68K_ALU.vhd:118:16 */
  assign asl_vflag = n2362; // (signal)
  /*# TG68K_ALU.vhd:120:16 */
  assign bit_number = n364; // (signal)
  /*# TG68K_ALU.vhd:121:16 */
  assign bits_out = n2531; // (signal)
  /*# TG68K_ALU.vhd:122:16 */
  assign one_bit_in = n2396; // (signal)
  /*# TG68K_ALU.vhd:123:16 */
  assign bchg = n2364; // (signal)
  /*# TG68K_ALU.vhd:124:16 */
  assign bset = n2366; // (signal)
  /*# TG68K_ALU.vhd:126:16 */
  assign mulu_sign = n2067; // (signal)
  /*# TG68K_ALU.vhd:128:16 */
  assign muls_msb = n2062; // (signal)
  /*# TG68K_ALU.vhd:129:16 */
  assign mulu_reg = n2334; // (signal)
  /*# TG68K_ALU.vhd:130:16 */
  assign fasign = 1'bX; // (signal)
  /*# TG68K_ALU.vhd:132:16 */
  assign faktorb = n2089; // (signal)
  /*# TG68K_ALU.vhd:134:16 */
  assign div_reg = n2371; // (signal)
  /*# TG68K_ALU.vhd:135:16 */
  assign div_quot = n2337; // (signal)
  /*# TG68K_ALU.vhd:137:16 */
  assign div_neg = n2373; // (signal)
  /*# TG68K_ALU.vhd:138:16 */
  assign div_bit = n2232; // (signal)
  /*# TG68K_ALU.vhd:139:16 */
  assign div_sub = n2231; // (signal)
  /*# TG68K_ALU.vhd:140:16 */
  assign div_over = n2375; // (signal)
  /*# TG68K_ALU.vhd:141:16 */
  assign nozero = n2377; // (signal)
  /*# TG68K_ALU.vhd:142:16 */
  assign div_qsign = n2203; // (signal)
  /*# TG68K_ALU.vhd:143:16 */
  assign dividend = n2339; // (signal)
  /*# TG68K_ALU.vhd:144:16 */
  assign divs = n2127; // (signal)
  /*# TG68K_ALU.vhd:145:16 */
  assign signedop = n2379; // (signal)
  /*# TG68K_ALU.vhd:146:16 */
  assign op1_sign = n2381; // (signal)
  /*# TG68K_ALU.vhd:148:16 */
  assign op2outext = n2218; // (signal)
  /*# TG68K_ALU.vhd:151:16 */
  assign datareg = n2342; // (signal)
  /*# TG68K_ALU.vhd:153:16 */
  assign bf_datareg = n831; // (signal)
  /*# TG68K_ALU.vhd:154:16 */
  assign result = n2344; // (signal)
  /*# TG68K_ALU.vhd:155:16 */
  assign result_tmp = n920; // (signal)
  /*# TG68K_ALU.vhd:156:16 */
  assign unshifted_bitmask = n2345; // (signal)
  /*# TG68K_ALU.vhd:158:16 */
  assign inmux0 = n886; // (signal)
  /*# TG68K_ALU.vhd:159:16 */
  assign inmux1 = n891; // (signal)
  /*# TG68K_ALU.vhd:160:16 */
  assign inmux2 = n896; // (signal)
  /*# TG68K_ALU.vhd:161:16 */
  assign inmux3 = n902; // (signal)
  /*# TG68K_ALU.vhd:162:16 */
  assign shifted_bitmask = n876; // (signal)
  /*# TG68K_ALU.vhd:163:16 */
  assign bitmaskmux0 = n863; // (signal)
  /*# TG68K_ALU.vhd:164:16 */
  assign bitmaskmux1 = n852; // (signal)
  /*# TG68K_ALU.vhd:165:16 */
  assign bitmaskmux2 = n841; // (signal)
  /*# TG68K_ALU.vhd:166:16 */
  assign bitmaskmux3 = n836; // (signal)
  /*# TG68K_ALU.vhd:167:16 */
  assign bf_set2 = n907; // (signal)
  /*# TG68K_ALU.vhd:168:16 */
  assign shift = n2347; // (signal)
  /*# TG68K_ALU.vhd:169:16 */
  assign bf_firstbit = n1122; // (signal)
  /*# TG68K_ALU.vhd:170:16 */
  assign mux = n1199; // (signal)
  /*# TG68K_ALU.vhd:171:16 */
  assign bitnr = n2348; // (signal)
  /*# TG68K_ALU.vhd:172:16 */
  assign mask = datareg; // (signal)
  /*# TG68K_ALU.vhd:173:16 */
  assign mask_not_zero = n1234; // (signal)
  /*# TG68K_ALU.vhd:174:16 */
  assign bf_bset = n2383; // (signal)
  /*# TG68K_ALU.vhd:175:16 */
  assign bf_nflag = n2532; // (signal)
  /*# TG68K_ALU.vhd:176:16 */
  assign bf_bchg = n2385; // (signal)
  /*# TG68K_ALU.vhd:177:16 */
  assign bf_ins = n2387; // (signal)
  /*# TG68K_ALU.vhd:178:16 */
  assign bf_exts = n2389; // (signal)
  /*# TG68K_ALU.vhd:179:16 */
  assign bf_fffo = n2391; // (signal)
  /*# TG68K_ALU.vhd:180:16 */
  assign bf_d32 = n2393; // (signal)
  /*# TG68K_ALU.vhd:181:16 */
  assign bf_s32 = n2395; // (signal)
  /*# TG68K_ALU.vhd:187:16 */
  assign hot_msb = n2681; // (signal)
  /*# TG68K_ALU.vhd:188:16 */
  assign vector = n2350; // (signal)
  /*# TG68K_ALU.vhd:189:16 */
  assign result_bs = n1752; // (signal)
  /*# TG68K_ALU.vhd:190:16 */
  assign bit_nr = n1664; // (signal)
  /*# TG68K_ALU.vhd:191:16 */
  assign bit_msb = n1376; // (signal)
  /*# TG68K_ALU.vhd:192:16 */
  assign bs_shift = n1366; // (signal)
  /*# TG68K_ALU.vhd:193:16 */
  assign bs_shift_mod = n1634; // (signal)
  /*# TG68K_ALU.vhd:194:16 */
  assign asl_over = n1408; // (signal)
  /*# TG68K_ALU.vhd:195:16 */
  assign asl_over_xor = n2351; // (signal)
  /*# TG68K_ALU.vhd:196:16 */
  assign asr_sign = n2352; // (signal)
  /*# TG68K_ALU.vhd:197:16 */
  assign msb = n1739; // (signal)
  /*# TG68K_ALU.vhd:198:16 */
  assign ring = n1346; // (signal)
  /*# TG68K_ALU.vhd:199:16 */
  assign alu = n1530; // (signal)
  /*# TG68K_ALU.vhd:200:16 */
  assign bsout = n2353; // (signal)
  /*# TG68K_ALU.vhd:201:16 */
  assign bs_v = n1543; // (signal)
  /*# TG68K_ALU.vhd:202:16 */
  assign bs_c = n1681; // (signal)
  /*# TG68K_ALU.vhd:203:16 */
  assign bs_x = n1545; // (signal)
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
  assign n71 = {n64, n2356};
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
  assign n168 = n2356[4]; // extract
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
  assign n446 = {27'b0, n444};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n447 = $unsigned(32'b00000000000000000000000000000000) > $unsigned(n446);
  /*# TG68K_ALU.vhd:151:16 */
  assign n450 = n443[0]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n451 = n447 ? 1'b0 : n450;
  /*# TG68K_ALU.vhd:490:25 */
  assign n454 = n447 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:490:38 */
  assign n457 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n459 = {27'b0, n457};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n460 = $unsigned(32'b00000000000000000000000000000001) > $unsigned(n459);
  /*# TG68K_ALU.vhd:151:16 */
  assign n463 = n443[1]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n464 = n460 ? 1'b0 : n463;
  /*# TG68K_ALU.vhd:156:16 */
  assign n466 = n455[1]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n467 = n460 ? 1'b1 : n466;
  /*# TG68K_ALU.vhd:490:38 */
  assign n469 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n471 = {27'b0, n469};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n472 = $unsigned(32'b00000000000000000000000000000010) > $unsigned(n471);
  /*# TG68K_ALU.vhd:151:16 */
  assign n475 = n443[2]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n476 = n472 ? 1'b0 : n475;
  /*# TG68K_ALU.vhd:156:16 */
  assign n478 = n455[2]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n479 = n472 ? 1'b1 : n478;
  /*# TG68K_ALU.vhd:490:38 */
  assign n481 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n483 = {27'b0, n481};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n484 = $unsigned(32'b00000000000000000000000000000011) > $unsigned(n483);
  /*# TG68K_ALU.vhd:151:16 */
  assign n487 = n443[3]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n488 = n484 ? 1'b0 : n487;
  /*# TG68K_ALU.vhd:156:16 */
  assign n490 = n455[3]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n491 = n484 ? 1'b1 : n490;
  /*# TG68K_ALU.vhd:490:38 */
  assign n493 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n495 = {27'b0, n493};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n496 = $unsigned(32'b00000000000000000000000000000100) > $unsigned(n495);
  /*# TG68K_ALU.vhd:151:16 */
  assign n499 = n443[4]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n500 = n496 ? 1'b0 : n499;
  /*# TG68K_ALU.vhd:156:16 */
  assign n502 = n455[4]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n503 = n496 ? 1'b1 : n502;
  /*# TG68K_ALU.vhd:490:38 */
  assign n505 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n507 = {27'b0, n505};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n508 = $unsigned(32'b00000000000000000000000000000101) > $unsigned(n507);
  /*# TG68K_ALU.vhd:151:16 */
  assign n511 = n443[5]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n512 = n508 ? 1'b0 : n511;
  /*# TG68K_ALU.vhd:156:16 */
  assign n514 = n455[5]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n515 = n508 ? 1'b1 : n514;
  /*# TG68K_ALU.vhd:490:38 */
  assign n517 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n519 = {27'b0, n517};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n520 = $unsigned(32'b00000000000000000000000000000110) > $unsigned(n519);
  /*# TG68K_ALU.vhd:151:16 */
  assign n523 = n443[6]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n524 = n520 ? 1'b0 : n523;
  /*# TG68K_ALU.vhd:156:16 */
  assign n526 = n455[6]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n527 = n520 ? 1'b1 : n526;
  /*# TG68K_ALU.vhd:490:38 */
  assign n529 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n531 = {27'b0, n529};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n532 = $unsigned(32'b00000000000000000000000000000111) > $unsigned(n531);
  /*# TG68K_ALU.vhd:151:16 */
  assign n535 = n443[7]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n536 = n532 ? 1'b0 : n535;
  /*# TG68K_ALU.vhd:156:16 */
  assign n538 = n455[7]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n539 = n532 ? 1'b1 : n538;
  /*# TG68K_ALU.vhd:490:38 */
  assign n541 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n543 = {27'b0, n541};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n544 = $unsigned(32'b00000000000000000000000000001000) > $unsigned(n543);
  /*# TG68K_ALU.vhd:151:16 */
  assign n547 = n443[8]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n548 = n544 ? 1'b0 : n547;
  /*# TG68K_ALU.vhd:156:16 */
  assign n550 = n455[8]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n551 = n544 ? 1'b1 : n550;
  /*# TG68K_ALU.vhd:490:38 */
  assign n553 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n555 = {27'b0, n553};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n556 = $unsigned(32'b00000000000000000000000000001001) > $unsigned(n555);
  /*# TG68K_ALU.vhd:151:16 */
  assign n559 = n443[9]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n560 = n556 ? 1'b0 : n559;
  /*# TG68K_ALU.vhd:156:16 */
  assign n562 = n455[9]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n563 = n556 ? 1'b1 : n562;
  /*# TG68K_ALU.vhd:490:38 */
  assign n565 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n567 = {27'b0, n565};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n568 = $unsigned(32'b00000000000000000000000000001010) > $unsigned(n567);
  /*# TG68K_ALU.vhd:151:16 */
  assign n571 = n443[10]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n572 = n568 ? 1'b0 : n571;
  /*# TG68K_ALU.vhd:156:16 */
  assign n574 = n455[10]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n575 = n568 ? 1'b1 : n574;
  /*# TG68K_ALU.vhd:490:38 */
  assign n577 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n579 = {27'b0, n577};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n580 = $unsigned(32'b00000000000000000000000000001011) > $unsigned(n579);
  /*# TG68K_ALU.vhd:151:16 */
  assign n583 = n443[11]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n584 = n580 ? 1'b0 : n583;
  /*# TG68K_ALU.vhd:156:16 */
  assign n586 = n455[11]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n587 = n580 ? 1'b1 : n586;
  /*# TG68K_ALU.vhd:490:38 */
  assign n589 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n591 = {27'b0, n589};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n592 = $unsigned(32'b00000000000000000000000000001100) > $unsigned(n591);
  /*# TG68K_ALU.vhd:151:16 */
  assign n595 = n443[12]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n596 = n592 ? 1'b0 : n595;
  /*# TG68K_ALU.vhd:156:16 */
  assign n598 = n455[12]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n599 = n592 ? 1'b1 : n598;
  /*# TG68K_ALU.vhd:490:38 */
  assign n601 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n603 = {27'b0, n601};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n604 = $unsigned(32'b00000000000000000000000000001101) > $unsigned(n603);
  /*# TG68K_ALU.vhd:151:16 */
  assign n607 = n443[13]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n608 = n604 ? 1'b0 : n607;
  /*# TG68K_ALU.vhd:156:16 */
  assign n610 = n455[13]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n611 = n604 ? 1'b1 : n610;
  /*# TG68K_ALU.vhd:490:38 */
  assign n613 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n615 = {27'b0, n613};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n616 = $unsigned(32'b00000000000000000000000000001110) > $unsigned(n615);
  /*# TG68K_ALU.vhd:151:16 */
  assign n619 = n443[14]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n620 = n616 ? 1'b0 : n619;
  /*# TG68K_ALU.vhd:156:16 */
  assign n622 = n455[14]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n623 = n616 ? 1'b1 : n622;
  /*# TG68K_ALU.vhd:490:38 */
  assign n625 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n627 = {27'b0, n625};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n628 = $unsigned(32'b00000000000000000000000000001111) > $unsigned(n627);
  /*# TG68K_ALU.vhd:151:16 */
  assign n631 = n443[15]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n632 = n628 ? 1'b0 : n631;
  /*# TG68K_ALU.vhd:156:16 */
  assign n634 = n455[15]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n635 = n628 ? 1'b1 : n634;
  /*# TG68K_ALU.vhd:490:38 */
  assign n637 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n639 = {27'b0, n637};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n640 = $unsigned(32'b00000000000000000000000000010000) > $unsigned(n639);
  /*# TG68K_ALU.vhd:151:16 */
  assign n643 = n443[16]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n644 = n640 ? 1'b0 : n643;
  /*# TG68K_ALU.vhd:156:16 */
  assign n646 = n455[16]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n647 = n640 ? 1'b1 : n646;
  /*# TG68K_ALU.vhd:490:38 */
  assign n649 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n651 = {27'b0, n649};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n652 = $unsigned(32'b00000000000000000000000000010001) > $unsigned(n651);
  /*# TG68K_ALU.vhd:151:16 */
  assign n655 = n443[17]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n656 = n652 ? 1'b0 : n655;
  /*# TG68K_ALU.vhd:156:16 */
  assign n658 = n455[17]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n659 = n652 ? 1'b1 : n658;
  /*# TG68K_ALU.vhd:490:38 */
  assign n661 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n663 = {27'b0, n661};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n664 = $unsigned(32'b00000000000000000000000000010010) > $unsigned(n663);
  /*# TG68K_ALU.vhd:151:16 */
  assign n667 = n443[18]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n668 = n664 ? 1'b0 : n667;
  /*# TG68K_ALU.vhd:156:16 */
  assign n670 = n455[18]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n671 = n664 ? 1'b1 : n670;
  /*# TG68K_ALU.vhd:490:38 */
  assign n673 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n675 = {27'b0, n673};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n676 = $unsigned(32'b00000000000000000000000000010011) > $unsigned(n675);
  /*# TG68K_ALU.vhd:151:16 */
  assign n679 = n443[19]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n680 = n676 ? 1'b0 : n679;
  /*# TG68K_ALU.vhd:156:16 */
  assign n682 = n455[19]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n683 = n676 ? 1'b1 : n682;
  /*# TG68K_ALU.vhd:490:38 */
  assign n685 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n687 = {27'b0, n685};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n688 = $unsigned(32'b00000000000000000000000000010100) > $unsigned(n687);
  /*# TG68K_ALU.vhd:151:16 */
  assign n691 = n443[20]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n692 = n688 ? 1'b0 : n691;
  /*# TG68K_ALU.vhd:156:16 */
  assign n694 = n455[20]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n695 = n688 ? 1'b1 : n694;
  /*# TG68K_ALU.vhd:490:38 */
  assign n697 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n699 = {27'b0, n697};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n700 = $unsigned(32'b00000000000000000000000000010101) > $unsigned(n699);
  /*# TG68K_ALU.vhd:151:16 */
  assign n703 = n443[21]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n704 = n700 ? 1'b0 : n703;
  /*# TG68K_ALU.vhd:156:16 */
  assign n706 = n455[21]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n707 = n700 ? 1'b1 : n706;
  /*# TG68K_ALU.vhd:490:38 */
  assign n709 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n711 = {27'b0, n709};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n712 = $unsigned(32'b00000000000000000000000000010110) > $unsigned(n711);
  /*# TG68K_ALU.vhd:151:16 */
  assign n715 = n443[22]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n716 = n712 ? 1'b0 : n715;
  /*# TG68K_ALU.vhd:156:16 */
  assign n718 = n455[22]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n719 = n712 ? 1'b1 : n718;
  /*# TG68K_ALU.vhd:490:38 */
  assign n721 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n723 = {27'b0, n721};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n724 = $unsigned(32'b00000000000000000000000000010111) > $unsigned(n723);
  /*# TG68K_ALU.vhd:151:16 */
  assign n727 = n443[23]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n728 = n724 ? 1'b0 : n727;
  /*# TG68K_ALU.vhd:156:16 */
  assign n730 = n455[23]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n731 = n724 ? 1'b1 : n730;
  /*# TG68K_ALU.vhd:490:38 */
  assign n733 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n735 = {27'b0, n733};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n736 = $unsigned(32'b00000000000000000000000000011000) > $unsigned(n735);
  /*# TG68K_ALU.vhd:151:16 */
  assign n739 = n443[24]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n740 = n736 ? 1'b0 : n739;
  /*# TG68K_ALU.vhd:156:16 */
  assign n742 = n455[24]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n743 = n736 ? 1'b1 : n742;
  /*# TG68K_ALU.vhd:490:38 */
  assign n745 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n747 = {27'b0, n745};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n748 = $unsigned(32'b00000000000000000000000000011001) > $unsigned(n747);
  /*# TG68K_ALU.vhd:151:16 */
  assign n751 = n443[25]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n752 = n748 ? 1'b0 : n751;
  /*# TG68K_ALU.vhd:156:16 */
  assign n754 = n455[25]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n755 = n748 ? 1'b1 : n754;
  /*# TG68K_ALU.vhd:490:38 */
  assign n757 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n759 = {27'b0, n757};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n760 = $unsigned(32'b00000000000000000000000000011010) > $unsigned(n759);
  /*# TG68K_ALU.vhd:151:16 */
  assign n763 = n443[26]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n764 = n760 ? 1'b0 : n763;
  /*# TG68K_ALU.vhd:156:16 */
  assign n766 = n455[26]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n767 = n760 ? 1'b1 : n766;
  /*# TG68K_ALU.vhd:490:38 */
  assign n769 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n771 = {27'b0, n769};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n772 = $unsigned(32'b00000000000000000000000000011011) > $unsigned(n771);
  /*# TG68K_ALU.vhd:151:16 */
  assign n775 = n443[27]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n776 = n772 ? 1'b0 : n775;
  /*# TG68K_ALU.vhd:156:16 */
  assign n778 = n455[27]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n779 = n772 ? 1'b1 : n778;
  /*# TG68K_ALU.vhd:490:38 */
  assign n781 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n783 = {27'b0, n781};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n784 = $unsigned(32'b00000000000000000000000000011100) > $unsigned(n783);
  /*# TG68K_ALU.vhd:151:16 */
  assign n787 = n443[28]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n788 = n784 ? 1'b0 : n787;
  /*# TG68K_ALU.vhd:156:16 */
  assign n790 = n455[28]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n791 = n784 ? 1'b1 : n790;
  /*# TG68K_ALU.vhd:490:38 */
  assign n793 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n795 = {27'b0, n793};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n796 = $unsigned(32'b00000000000000000000000000011101) > $unsigned(n795);
  /*# TG68K_ALU.vhd:151:16 */
  assign n799 = n443[29]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n800 = n796 ? 1'b0 : n799;
  /*# TG68K_ALU.vhd:156:16 */
  assign n802 = n455[29]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n803 = n796 ? 1'b1 : n802;
  /*# TG68K_ALU.vhd:490:38 */
  assign n805 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n807 = {27'b0, n805};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n808 = $unsigned(32'b00000000000000000000000000011110) > $unsigned(n807);
  /*# TG68K_ALU.vhd:151:16 */
  assign n811 = n443[30]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n812 = n808 ? 1'b0 : n811;
  /*# TG68K_ALU.vhd:151:16 */
  assign n813 = n443[31]; // extract
  /*# TG68K_ALU.vhd:156:16 */
  assign n814 = n455[30]; // extract
  /*# TG68K_ALU.vhd:490:25 */
  assign n815 = n808 ? 1'b1 : n814;
  /*# TG68K_ALU.vhd:156:16 */
  assign n816 = n455[31]; // extract
  /*# TG68K_ALU.vhd:490:38 */
  assign n817 = bf_width[4:0]; // extract
  /*# TG68K_ALU.vhd:490:29 */
  assign n819 = {27'b0, n817};  // uext
  /*# TG68K_ALU.vhd:490:29 */
  assign n820 = $unsigned(32'b00000000000000000000000000011111) > $unsigned(n819);
  /*# TG68K_ALU.vhd:490:25 */
  assign n823 = n820 ? 1'b0 : n813;
  /*# TG68K_ALU.vhd:490:25 */
  assign n824 = n820 ? 1'b1 : n816;
  /*# TG68K_ALU.vhd:496:37 */
  assign n826 = bf_width[4:0];  // trunc
  /*# TG68K_ALU.vhd:497:32 */
  assign n829 = bf_nflag & bf_exts;
  /*# TG68K_ALU.vhd:498:47 */
  assign n830 = datareg | unshifted_bitmask;
  /*# TG68K_ALU.vhd:497:17 */
  assign n831 = n829 ? n830 : datareg;
  /*# TG68K_ALU.vhd:504:30 */
  assign n832 = bf_loffset[4]; // extract
  /*# TG68K_ALU.vhd:505:57 */
  assign n833 = unshifted_bitmask[15:0]; // extract
  /*# TG68K_ALU.vhd:505:88 */
  assign n834 = unshifted_bitmask[31:16]; // extract
  /*# TG68K_ALU.vhd:505:70 */
  assign n835 = {n833, n834};
  /*# TG68K_ALU.vhd:504:17 */
  assign n836 = n832 ? n835 : unshifted_bitmask;
  /*# TG68K_ALU.vhd:509:30 */
  assign n837 = bf_loffset[3]; // extract
  /*# TG68K_ALU.vhd:510:64 */
  assign n838 = bitmaskmux3[23:0]; // extract
  /*# TG68K_ALU.vhd:510:89 */
  assign n839 = bitmaskmux3[31:24]; // extract
  /*# TG68K_ALU.vhd:510:77 */
  assign n840 = {n838, n839};
  /*# TG68K_ALU.vhd:509:17 */
  assign n841 = n837 ? n840 : bitmaskmux3;
  /*# TG68K_ALU.vhd:514:30 */
  assign n842 = bf_loffset[2]; // extract
  /*# TG68K_ALU.vhd:515:51 */
  assign n844 = {bitmaskmux2, 4'b1111};
  /*# TG68K_ALU.vhd:517:71 */
  assign n845 = bitmaskmux2[31:28]; // extract
  /*# TG68K_ALU.vhd:164:16 */
  assign n846 = n844[3:0]; // extract
  /*# TG68K_ALU.vhd:516:25 */
  assign n847 = bf_d32 ? n845 : n846;
  /*# TG68K_ALU.vhd:164:16 */
  assign n848 = n844[35:4]; // extract
  /*# TG68K_ALU.vhd:520:46 */
  assign n850 = {4'b1111, bitmaskmux2};
  /*# TG68K_ALU.vhd:514:17 */
  assign n851 = {n848, n847};
  /*# TG68K_ALU.vhd:514:17 */
  assign n852 = n842 ? n851 : n850;
  /*# TG68K_ALU.vhd:522:30 */
  assign n853 = bf_loffset[1]; // extract
  /*# TG68K_ALU.vhd:523:51 */
  assign n855 = {bitmaskmux1, 2'b11};
  /*# TG68K_ALU.vhd:525:71 */
  assign n856 = bitmaskmux1[31:30]; // extract
  /*# TG68K_ALU.vhd:163:16 */
  assign n857 = n855[1:0]; // extract
  /*# TG68K_ALU.vhd:524:25 */
  assign n858 = bf_d32 ? n856 : n857;
  /*# TG68K_ALU.vhd:163:16 */
  assign n859 = n855[37:2]; // extract
  /*# TG68K_ALU.vhd:528:44 */
  assign n861 = {2'b11, bitmaskmux1};
  /*# TG68K_ALU.vhd:522:17 */
  assign n862 = {n859, n858};
  /*# TG68K_ALU.vhd:522:17 */
  assign n863 = n853 ? n862 : n861;
  /*# TG68K_ALU.vhd:530:30 */
  assign n864 = bf_loffset[0]; // extract
  /*# TG68K_ALU.vhd:531:47 */
  assign n866 = {1'b1, bitmaskmux0};
  /*# TG68K_ALU.vhd:531:59 */
  assign n868 = {n866, 1'b1};
  /*# TG68K_ALU.vhd:533:66 */
  assign n869 = bitmaskmux0[31]; // extract
  /*# TG68K_ALU.vhd:162:16 */
  assign n870 = n868[0]; // extract
  /*# TG68K_ALU.vhd:532:25 */
  assign n871 = bf_d32 ? n869 : n870;
  /*# TG68K_ALU.vhd:162:16 */
  assign n872 = n868[39:1]; // extract
  /*# TG68K_ALU.vhd:536:48 */
  assign n874 = {2'b11, bitmaskmux0};
  /*# TG68K_ALU.vhd:530:17 */
  assign n875 = {n872, n871};
  /*# TG68K_ALU.vhd:530:17 */
  assign n876 = n864 ? n875 : n874;
  /*# TG68K_ALU.vhd:541:35 */
  assign n877 = {bf_ext_in, OP2out};
  /*# TG68K_ALU.vhd:543:54 */
  assign n878 = OP2out[7:0]; // extract
  /*# TG68K_ALU.vhd:168:16 */
  assign n879 = n877[39:32]; // extract
  /*# TG68K_ALU.vhd:542:17 */
  assign n880 = bf_s32 ? n878 : n879;
  /*# TG68K_ALU.vhd:168:16 */
  assign n881 = n877[31:0]; // extract
  /*# TG68K_ALU.vhd:546:28 */
  assign n882 = bf_shift[0]; // extract
  /*# TG68K_ALU.vhd:547:40 */
  assign n883 = shift[0]; // extract
  /*# TG68K_ALU.vhd:547:49 */
  assign n884 = shift[39:1]; // extract
  /*# TG68K_ALU.vhd:547:43 */
  assign n885 = {n883, n884};
  /*# TG68K_ALU.vhd:546:17 */
  assign n886 = n882 ? n885 : shift;
  /*# TG68K_ALU.vhd:551:28 */
  assign n887 = bf_shift[1]; // extract
  /*# TG68K_ALU.vhd:552:41 */
  assign n888 = inmux0[1:0]; // extract
  /*# TG68K_ALU.vhd:552:60 */
  assign n889 = inmux0[39:2]; // extract
  /*# TG68K_ALU.vhd:552:53 */
  assign n890 = {n888, n889};
  /*# TG68K_ALU.vhd:551:17 */
  assign n891 = n887 ? n890 : inmux0;
  /*# TG68K_ALU.vhd:556:28 */
  assign n892 = bf_shift[2]; // extract
  /*# TG68K_ALU.vhd:557:41 */
  assign n893 = inmux1[3:0]; // extract
  /*# TG68K_ALU.vhd:557:60 */
  assign n894 = inmux1[39:4]; // extract
  /*# TG68K_ALU.vhd:557:53 */
  assign n895 = {n893, n894};
  /*# TG68K_ALU.vhd:556:17 */
  assign n896 = n892 ? n895 : inmux1;
  /*# TG68K_ALU.vhd:561:28 */
  assign n897 = bf_shift[3]; // extract
  /*# TG68K_ALU.vhd:562:41 */
  assign n898 = inmux2[7:0]; // extract
  /*# TG68K_ALU.vhd:562:60 */
  assign n899 = inmux2[31:8]; // extract
  /*# TG68K_ALU.vhd:562:53 */
  assign n900 = {n898, n899};
  /*# TG68K_ALU.vhd:564:41 */
  assign n901 = inmux2[31:0]; // extract
  /*# TG68K_ALU.vhd:561:17 */
  assign n902 = n897 ? n900 : n901;
  /*# TG68K_ALU.vhd:566:28 */
  assign n903 = bf_shift[4]; // extract
  /*# TG68K_ALU.vhd:567:55 */
  assign n904 = inmux3[15:0]; // extract
  /*# TG68K_ALU.vhd:567:75 */
  assign n905 = inmux3[31:16]; // extract
  /*# TG68K_ALU.vhd:567:68 */
  assign n906 = {n904, n905};
  /*# TG68K_ALU.vhd:566:17 */
  assign n907 = n903 ? n906 : inmux3;
  /*# TG68K_ALU.vhd:574:56 */
  assign n908 = bf_set2[7:0]; // extract
  /*# TG68K_ALU.vhd:576:48 */
  assign n909 = ~OP2out;
  /*# TG68K_ALU.vhd:577:49 */
  assign n910 = ~bf_ext_in;
  /*# TG68K_ALU.vhd:575:17 */
  assign n911 = {n910, n909};
  /*# TG68K_ALU.vhd:575:17 */
  assign n913 = bf_bchg ? n911 : 40'b0000000000000000000000000000000000000000;
  /*# TG68K_ALU.vhd:572:17 */
  assign n914 = {n908, bf_set2};
  /*# TG68K_ALU.vhd:572:17 */
  assign n915 = bf_ins ? n914 : n913;
  /*# TG68K_ALU.vhd:581:17 */
  assign n917 = bf_bset ? 40'b1111111111111111111111111111111111111111 : n915;
  /*# TG68K_ALU.vhd:586:48 */
  assign n918 = {bf_ext_in, OP1out};
  /*# TG68K_ALU.vhd:588:48 */
  assign n919 = {bf_ext_in, OP2out};
  /*# TG68K_ALU.vhd:585:17 */
  assign n920 = bf_ins ? n918 : n919;
  /*# TG68K_ALU.vhd:591:43 */
  assign n921 = shifted_bitmask[0]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n922 = result_tmp[0]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n923 = n917[0]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n924 = n921 ? n922 : n923;
  /*# TG68K_ALU.vhd:591:43 */
  assign n926 = shifted_bitmask[1]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n927 = result_tmp[1]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n928 = n917[1]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n929 = n926 ? n927 : n928;
  /*# TG68K_ALU.vhd:591:43 */
  assign n931 = shifted_bitmask[2]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n932 = result_tmp[2]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n933 = n917[2]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n934 = n931 ? n932 : n933;
  /*# TG68K_ALU.vhd:591:43 */
  assign n936 = shifted_bitmask[3]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n937 = result_tmp[3]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n938 = n917[3]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n939 = n936 ? n937 : n938;
  /*# TG68K_ALU.vhd:591:43 */
  assign n941 = shifted_bitmask[4]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n942 = result_tmp[4]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n943 = n917[4]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n944 = n941 ? n942 : n943;
  /*# TG68K_ALU.vhd:591:43 */
  assign n946 = shifted_bitmask[5]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n947 = result_tmp[5]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n948 = n917[5]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n949 = n946 ? n947 : n948;
  /*# TG68K_ALU.vhd:591:43 */
  assign n951 = shifted_bitmask[6]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n952 = result_tmp[6]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n953 = n917[6]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n954 = n951 ? n952 : n953;
  /*# TG68K_ALU.vhd:591:43 */
  assign n956 = shifted_bitmask[7]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n957 = result_tmp[7]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n958 = n917[7]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n959 = n956 ? n957 : n958;
  /*# TG68K_ALU.vhd:591:43 */
  assign n961 = shifted_bitmask[8]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n962 = result_tmp[8]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n963 = n917[8]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n964 = n961 ? n962 : n963;
  /*# TG68K_ALU.vhd:591:43 */
  assign n966 = shifted_bitmask[9]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n967 = result_tmp[9]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n968 = n917[9]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n969 = n966 ? n967 : n968;
  /*# TG68K_ALU.vhd:591:43 */
  assign n971 = shifted_bitmask[10]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n972 = result_tmp[10]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n973 = n917[10]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n974 = n971 ? n972 : n973;
  /*# TG68K_ALU.vhd:591:43 */
  assign n976 = shifted_bitmask[11]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n977 = result_tmp[11]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n978 = n917[11]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n979 = n976 ? n977 : n978;
  /*# TG68K_ALU.vhd:591:43 */
  assign n981 = shifted_bitmask[12]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n982 = result_tmp[12]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n983 = n917[12]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n984 = n981 ? n982 : n983;
  /*# TG68K_ALU.vhd:591:43 */
  assign n986 = shifted_bitmask[13]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n987 = result_tmp[13]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n988 = n917[13]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n989 = n986 ? n987 : n988;
  /*# TG68K_ALU.vhd:591:43 */
  assign n991 = shifted_bitmask[14]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n992 = result_tmp[14]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n993 = n917[14]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n994 = n991 ? n992 : n993;
  /*# TG68K_ALU.vhd:591:43 */
  assign n996 = shifted_bitmask[15]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n997 = result_tmp[15]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n998 = n917[15]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n999 = n996 ? n997 : n998;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1001 = shifted_bitmask[16]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1002 = result_tmp[16]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1003 = n917[16]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1004 = n1001 ? n1002 : n1003;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1006 = shifted_bitmask[17]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1007 = result_tmp[17]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1008 = n917[17]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1009 = n1006 ? n1007 : n1008;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1011 = shifted_bitmask[18]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1012 = result_tmp[18]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1013 = n917[18]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1014 = n1011 ? n1012 : n1013;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1016 = shifted_bitmask[19]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1017 = result_tmp[19]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1018 = n917[19]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1019 = n1016 ? n1017 : n1018;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1021 = shifted_bitmask[20]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1022 = result_tmp[20]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1023 = n917[20]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1024 = n1021 ? n1022 : n1023;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1026 = shifted_bitmask[21]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1027 = result_tmp[21]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1028 = n917[21]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1029 = n1026 ? n1027 : n1028;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1031 = shifted_bitmask[22]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1032 = result_tmp[22]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1033 = n917[22]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1034 = n1031 ? n1032 : n1033;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1036 = shifted_bitmask[23]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1037 = result_tmp[23]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1038 = n917[23]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1039 = n1036 ? n1037 : n1038;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1041 = shifted_bitmask[24]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1042 = result_tmp[24]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1043 = n917[24]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1044 = n1041 ? n1042 : n1043;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1046 = shifted_bitmask[25]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1047 = result_tmp[25]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1048 = n917[25]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1049 = n1046 ? n1047 : n1048;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1051 = shifted_bitmask[26]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1052 = result_tmp[26]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1053 = n917[26]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1054 = n1051 ? n1052 : n1053;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1056 = shifted_bitmask[27]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1057 = result_tmp[27]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1058 = n917[27]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1059 = n1056 ? n1057 : n1058;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1061 = shifted_bitmask[28]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1062 = result_tmp[28]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1063 = n917[28]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1064 = n1061 ? n1062 : n1063;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1066 = shifted_bitmask[29]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1067 = result_tmp[29]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1068 = n917[29]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1069 = n1066 ? n1067 : n1068;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1071 = shifted_bitmask[30]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1072 = result_tmp[30]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1073 = n917[30]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1074 = n1071 ? n1072 : n1073;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1076 = shifted_bitmask[31]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1077 = result_tmp[31]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1078 = n917[31]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1079 = n1076 ? n1077 : n1078;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1081 = shifted_bitmask[32]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1082 = result_tmp[32]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1083 = n917[32]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1084 = n1081 ? n1082 : n1083;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1086 = shifted_bitmask[33]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1087 = result_tmp[33]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1088 = n917[33]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1089 = n1086 ? n1087 : n1088;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1091 = shifted_bitmask[34]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1092 = result_tmp[34]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1093 = n917[34]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1094 = n1091 ? n1092 : n1093;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1096 = shifted_bitmask[35]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1097 = result_tmp[35]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1098 = n917[35]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1099 = n1096 ? n1097 : n1098;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1101 = shifted_bitmask[36]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1102 = result_tmp[36]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1103 = n917[36]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1104 = n1101 ? n1102 : n1103;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1106 = shifted_bitmask[37]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1107 = result_tmp[37]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1108 = n917[37]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1109 = n1106 ? n1107 : n1108;
  /*# TG68K_ALU.vhd:591:43 */
  assign n1111 = shifted_bitmask[38]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1112 = result_tmp[38]; // extract
  /*# TG68K_ALU.vhd:154:16 */
  assign n1113 = n917[38]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1114 = n1111 ? n1112 : n1113;
  /*# TG68K_ALU.vhd:154:16 */
  assign n1115 = n917[39]; // extract
  /*# TG68K_ALU.vhd:591:43 */
  assign n1116 = shifted_bitmask[39]; // extract
  /*# TG68K_ALU.vhd:592:56 */
  assign n1117 = result_tmp[39]; // extract
  /*# TG68K_ALU.vhd:591:25 */
  assign n1118 = n1116 ? n1117 : n1115;
  /*# TG68K_ALU.vhd:598:36 */
  assign n1120 = {1'b0, bitnr};
  /*# TG68K_ALU.vhd:598:43 */
  assign n1121 = {5'b0, mask_not_zero};  // uext
  /*# TG68K_ALU.vhd:598:43 */
  assign n1122 = n1120 + n1121;
  /*# TG68K_ALU.vhd:601:24 */
  assign n1123 = mask[31:28]; // extract
  /*# TG68K_ALU.vhd:601:38 */
  assign n1125 = n1123 == 4'b0000;
  /*# TG68K_ALU.vhd:602:32 */
  assign n1126 = mask[27:24]; // extract
  /*# TG68K_ALU.vhd:602:46 */
  assign n1128 = n1126 == 4'b0000;
  /*# TG68K_ALU.vhd:603:40 */
  assign n1129 = mask[23:20]; // extract
  /*# TG68K_ALU.vhd:603:54 */
  assign n1131 = n1129 == 4'b0000;
  /*# TG68K_ALU.vhd:604:48 */
  assign n1132 = mask[19:16]; // extract
  /*# TG68K_ALU.vhd:604:62 */
  assign n1134 = n1132 == 4'b0000;
  /*# TG68K_ALU.vhd:606:56 */
  assign n1136 = mask[15:12]; // extract
  /*# TG68K_ALU.vhd:606:70 */
  assign n1138 = n1136 == 4'b0000;
  /*# TG68K_ALU.vhd:607:64 */
  assign n1139 = mask[11:8]; // extract
  /*# TG68K_ALU.vhd:607:77 */
  assign n1141 = n1139 == 4'b0000;
  /*# TG68K_ALU.vhd:609:72 */
  assign n1143 = mask[7:4]; // extract
  /*# TG68K_ALU.vhd:609:84 */
  assign n1145 = n1143 == 4'b0000;
  /*# TG68K_ALU.vhd:611:84 */
  assign n1147 = mask[3:0]; // extract
  /*# TG68K_ALU.vhd:613:84 */
  assign n1148 = mask[7:4]; // extract
  /*# TG68K_ALU.vhd:609:65 */
  assign n1149 = n1145 ? n1147 : n1148;
  /*# TG68K_ALU.vhd:609:65 */
  assign n1151 = n1145 ? 1'b0 : 1'b1;
  /*# TG68K_ALU.vhd:616:76 */
  assign n1152 = mask[11:8]; // extract
  /*# TG68K_ALU.vhd:607:57 */
  assign n1154 = n1141 ? n1149 : n1152;
  /*# TG68K_ALU.vhd:607:57 */
  assign n1155 = {1'b0, n1151};
  /*# TG68K_ALU.vhd:607:57 */
  assign n1156 = n1155[0]; // extract
  /*# TG68K_ALU.vhd:607:57 */
  assign n1157 = n1141 ? n1156 : 1'b0;
  /*# TG68K_ALU.vhd:607:57 */
  assign n1158 = n1155[1]; // extract
  /*# TG68K_ALU.vhd:607:57 */
  assign n1160 = n1141 ? n1158 : 1'b1;
  /*# TG68K_ALU.vhd:620:68 */
  assign n1161 = mask[15:12]; // extract
  /*# TG68K_ALU.vhd:606:49 */
  assign n1162 = n1138 ? n1154 : n1161;
  /*# TG68K_ALU.vhd:606:49 */
  assign n1163 = {n1160, n1157};
  /*# TG68K_ALU.vhd:606:49 */
  assign n1165 = n1138 ? n1163 : 2'b11;
  /*# TG68K_ALU.vhd:623:60 */
  assign n1166 = mask[19:16]; // extract
  /*# TG68K_ALU.vhd:604:41 */
  assign n1169 = n1134 ? n1162 : n1166;
  /*# TG68K_ALU.vhd:604:41 */
  assign n1170 = {1'b0, 1'b0};
  /*# TG68K_ALU.vhd:604:41 */
  assign n1171 = {1'b0, n1165};
  /*# TG68K_ALU.vhd:604:41 */
  assign n1172 = n1171[1:0]; // extract
  /*# TG68K_ALU.vhd:604:41 */
  assign n1173 = n1134 ? n1172 : n1170;
  /*# TG68K_ALU.vhd:604:41 */
  assign n1174 = n1171[2]; // extract
  /*# TG68K_ALU.vhd:604:41 */
  assign n1176 = n1134 ? n1174 : 1'b1;
  /*# TG68K_ALU.vhd:628:52 */
  assign n1177 = mask[23:20]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1179 = n1131 ? n1169 : n1177;
  /*# TG68K_ALU.vhd:603:33 */
  assign n1180 = {n1176, n1173};
  /*# TG68K_ALU.vhd:603:33 */
  assign n1181 = n1180[0]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1183 = n1131 ? n1181 : 1'b1;
  /*# TG68K_ALU.vhd:603:33 */
  assign n1184 = n1180[1]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1185 = n1131 ? n1184 : 1'b0;
  /*# TG68K_ALU.vhd:603:33 */
  assign n1186 = n1180[2]; // extract
  /*# TG68K_ALU.vhd:603:33 */
  assign n1188 = n1131 ? n1186 : 1'b1;
  /*# TG68K_ALU.vhd:632:44 */
  assign n1189 = mask[27:24]; // extract
  /*# TG68K_ALU.vhd:602:25 */
  assign n1191 = n1128 ? n1179 : n1189;
  /*# TG68K_ALU.vhd:602:25 */
  assign n1192 = {n1188, n1185, n1183};
  /*# TG68K_ALU.vhd:602:25 */
  assign n1193 = n1192[0]; // extract
  /*# TG68K_ALU.vhd:602:25 */
  assign n1194 = n1128 ? n1193 : 1'b0;
  /*# TG68K_ALU.vhd:602:25 */
  assign n1195 = n1192[2:1]; // extract
  /*# TG68K_ALU.vhd:602:25 */
  assign n1197 = n1128 ? n1195 : 2'b11;
  /*# TG68K_ALU.vhd:636:36 */
  assign n1198 = mask[31:28]; // extract
  /*# TG68K_ALU.vhd:601:17 */
  assign n1199 = n1125 ? n1191 : n1198;
  /*# TG68K_ALU.vhd:601:17 */
  assign n1200 = {n1197, n1194};
  /*# TG68K_ALU.vhd:601:17 */
  assign n1202 = n1125 ? n1200 : 3'b111;
  /*# TG68K_ALU.vhd:639:23 */
  assign n1205 = mux[3:2]; // extract
  /*# TG68K_ALU.vhd:639:35 */
  assign n1207 = n1205 == 2'b00;
  /*# TG68K_ALU.vhd:641:31 */
  assign n1209 = mux[1]; // extract
  /*# TG68K_ALU.vhd:641:34 */
  assign n1210 = ~n1209;
  /*# TG68K_ALU.vhd:643:39 */
  assign n1212 = mux[0]; // extract
  /*# TG68K_ALU.vhd:643:42 */
  assign n1213 = ~n1212;
  /*# TG68K_ALU.vhd:643:33 */
  assign n1216 = n1213 ? 1'b0 : 1'b1;
  /*# TG68K_ALU.vhd:171:16 */
  assign n1217 = n1203[0]; // extract
  /*# TG68K_ALU.vhd:641:25 */
  assign n1218 = n1210 ? 1'b0 : n1217;
  /*# TG68K_ALU.vhd:641:25 */
  assign n1220 = n1210 ? n1216 : 1'b1;
  /*# TG68K_ALU.vhd:648:31 */
  assign n1221 = mux[3]; // extract
  /*# TG68K_ALU.vhd:648:34 */
  assign n1222 = ~n1221;
  /*# TG68K_ALU.vhd:171:16 */
  assign n1224 = n1203[0]; // extract
  /*# TG68K_ALU.vhd:648:25 */
  assign n1225 = n1222 ? 1'b0 : n1224;
  /*# TG68K_ALU.vhd:639:17 */
  assign n1226 = {1'b0, n1218};
  /*# TG68K_ALU.vhd:639:17 */
  assign n1227 = n1226[0]; // extract
  /*# TG68K_ALU.vhd:639:17 */
  assign n1228 = n1207 ? n1227 : n1225;
  /*# TG68K_ALU.vhd:639:17 */
  assign n1229 = n1226[1]; // extract
  /*# TG68K_ALU.vhd:171:16 */
  assign n1230 = n1203[1]; // extract
  /*# TG68K_ALU.vhd:639:17 */
  assign n1231 = n1207 ? n1229 : n1230;
  /*# TG68K_ALU.vhd:639:17 */
  assign n1234 = n1207 ? n1220 : 1'b1;
  /*# TG68K_ALU.vhd:659:32 */
  assign n1239 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:661:66 */
  assign n1240 = OP1out[7]; // extract
  /*# TG68K_ALU.vhd:660:25 */
  assign n1242 = n1239 == 2'b00;
  /*# TG68K_ALU.vhd:663:66 */
  assign n1243 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:662:25 */
  assign n1245 = n1239 == 2'b01;
  /*# TG68K_ALU.vhd:662:34 */
  assign n1247 = n1239 == 2'b11;
  /*# TG68K_ALU.vhd:662:34 */
  assign n1248 = n1245 | n1247;
  /*# TG68K_ALU.vhd:665:66 */
  assign n1249 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:664:25 */
  assign n1251 = n1239 == 2'b10;
  /*# TG68K_ALU.vhd:659:17 */
  assign n1252 = {n1251, n1248, n1242};
  /*# TG68K_ALU.vhd:659:17 */
  always @*
    case (n1252)
      3'b100: n1253 = n1249;
      3'b010: n1253 = n1243;
      3'b001: n1253 = n1240;
      default: n1253 = rot_rot;
    endcase
  /*# TG68K_ALU.vhd:685:24 */
  assign n1271 = exec[23]; // extract
  /*# TG68K_ALU.vhd:687:39 */
  assign n1272 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:688:36 */
  assign n1274 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:689:47 */
  assign n1275 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:688:25 */
  assign n1277 = n1274 ? n1275 : 1'b0;
  /*# TG68K_ALU.vhd:694:38 */
  assign n1278 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:699:48 */
  assign n1281 = OP1out[0]; // extract
  /*# TG68K_ALU.vhd:700:48 */
  assign n1282 = OP1out[0]; // extract
  /*# TG68K_ALU.vhd:694:25 */
  assign n1302 = n1278 ? rot_rot : n1281;
  /*# TG68K_ALU.vhd:694:25 */
  assign n1303 = n1278 ? rot_rot : n1282;
  /*# TG68K_ALU.vhd:685:17 */
  assign n1306 = n1271 ? n1272 : n1302;
  /*# TG68K_ALU.vhd:685:17 */
  assign n1307 = n1271 ? n1277 : n1303;
  /*# TG68K_ALU.vhd:685:17 */
  assign n1308 = n1271 ? OP1out : bsout;
  /*# TG68K_ALU.vhd:723:28 */
  assign n1313 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:724:40 */
  assign n1314 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:725:33 */
  assign n1316 = n1314 == 2'b00;
  /*# TG68K_ALU.vhd:727:33 */
  assign n1318 = n1314 == 2'b01;
  /*# TG68K_ALU.vhd:727:42 */
  assign n1320 = n1314 == 2'b11;
  /*# TG68K_ALU.vhd:727:42 */
  assign n1321 = n1318 | n1320;
  /*# TG68K_ALU.vhd:729:33 */
  assign n1323 = n1314 == 2'b10;
  /*# TG68K_ALU.vhd:724:25 */
  assign n1324 = {n1323, n1321, n1316};
  /*# TG68K_ALU.vhd:724:25 */
  always @*
    case (n1324)
      3'b100: n1329 = 6'b100001;
      3'b010: n1329 = 6'b010001;
      3'b001: n1329 = 6'b001001;
      default: n1329 = 6'b100000;
    endcase
  /*# TG68K_ALU.vhd:734:40 */
  assign n1330 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:735:33 */
  assign n1332 = n1330 == 2'b00;
  /*# TG68K_ALU.vhd:737:33 */
  assign n1334 = n1330 == 2'b01;
  /*# TG68K_ALU.vhd:737:42 */
  assign n1336 = n1330 == 2'b11;
  /*# TG68K_ALU.vhd:737:42 */
  assign n1337 = n1334 | n1336;
  /*# TG68K_ALU.vhd:739:33 */
  assign n1339 = n1330 == 2'b10;
  /*# TG68K_ALU.vhd:734:25 */
  assign n1340 = {n1339, n1337, n1332};
  /*# TG68K_ALU.vhd:734:25 */
  always @*
    case (n1340)
      3'b100: n1345 = 6'b100000;
      3'b010: n1345 = 6'b010000;
      3'b001: n1345 = 6'b001000;
      default: n1345 = 6'b100000;
    endcase
  /*# TG68K_ALU.vhd:723:17 */
  assign n1346 = n1313 ? n1329 : n1345;
  /*# TG68K_ALU.vhd:745:30 */
  assign n1348 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:745:42 */
  assign n1350 = n1348 == 2'b11;
  /*# TG68K_ALU.vhd:745:55 */
  assign n1351 = exec[81]; // extract
  /*# TG68K_ALU.vhd:745:64 */
  assign n1352 = ~n1351;
  /*# TG68K_ALU.vhd:745:48 */
  assign n1353 = n1350 | n1352;
  /*# TG68K_ALU.vhd:747:33 */
  assign n1354 = exe_opcode[5]; // extract
  /*# TG68K_ALU.vhd:748:43 */
  assign n1355 = OP2out[5:0]; // extract
  /*# TG68K_ALU.vhd:750:59 */
  assign n1356 = exe_opcode[11:9]; // extract
  /*# TG68K_ALU.vhd:751:38 */
  assign n1357 = exe_opcode[11:9]; // extract
  /*# TG68K_ALU.vhd:751:51 */
  assign n1359 = n1357 == 3'b000;
  /*# TG68K_ALU.vhd:751:25 */
  assign n1362 = n1359 ? 3'b001 : 3'b000;
  /*# TG68K_ALU.vhd:747:17 */
  assign n1363 = {n1362, n1356};
  /*# TG68K_ALU.vhd:747:17 */
  assign n1364 = n1354 ? n1355 : n1363;
  /*# TG68K_ALU.vhd:745:17 */
  assign n1366 = n1353 ? 6'b000001 : n1364;
  /*# TG68K_ALU.vhd:762:29 */
  assign n1373 = $unsigned(bs_shift) < $unsigned(ring);
  /*# TG68K_ALU.vhd:763:40 */
  assign n1374 = ring - bs_shift;
  /*# TG68K_ALU.vhd:762:17 */
  assign n1376 = n1373 ? n1374 : 6'b000000;
  /*# TG68K_ALU.vhd:765:45 */
  assign n1378 = vector[30:0]; // extract
  /*# TG68K_ALU.vhd:765:38 */
  assign n1380 = {1'b0, n1378};
  /*# TG68K_ALU.vhd:765:75 */
  assign n1381 = vector[31:1]; // extract
  /*# TG68K_ALU.vhd:765:68 */
  assign n1383 = {1'b0, n1381};
  /*# TG68K_ALU.vhd:765:60 */
  assign n1384 = n1380 ^ n1383;
  /*# TG68K_ALU.vhd:765:90 */
  assign n1385 = {n1384, msb};
  /*# TG68K_ALU.vhd:766:32 */
  assign n1386 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:767:25 */
  assign n1389 = n1386 == 2'b00;
  /*# TG68K_ALU.vhd:769:25 */
  assign n1392 = n1386 == 2'b01;
  /*# TG68K_ALU.vhd:769:34 */
  assign n1394 = n1386 == 2'b11;
  /*# TG68K_ALU.vhd:769:34 */
  assign n1395 = n1392 | n1394;
  /*# TG68K_ALU.vhd:766:17 */
  assign n1396 = {n1395, n1389};
  /*# TG68K_ALU.vhd:195:16 */
  assign n1397 = n1385[8]; // extract
  /*# TG68K_ALU.vhd:766:17 */
  always @*
    case (n1396)
      2'b10: n1398 = n1397;
      2'b01: n1398 = 1'b0;
      default: n1398 = n1397;
    endcase
  /*# TG68K_ALU.vhd:195:16 */
  assign n1399 = n1385[16]; // extract
  /*# TG68K_ALU.vhd:766:17 */
  always @*
    case (n1396)
      2'b10: n1400 = 1'b0;
      2'b01: n1400 = n1399;
      default: n1400 = n1399;
    endcase
  /*# TG68K_ALU.vhd:195:16 */
  assign n1402 = n1385[7:0]; // extract
  /*# TG68K_ALU.vhd:195:16 */
  assign n1403 = n1385[32:17]; // extract
  /*# TG68K_ALU.vhd:195:16 */
  assign n1404 = n1385[15:9]; // extract
  /*# TG68K_ALU.vhd:773:56 */
  assign n1405 = hot_msb[31:0]; // extract
  /*# TG68K_ALU.vhd:773:48 */
  assign n1407 = {1'b0, n1405};
  /*# TG68K_ALU.vhd:773:42 */
  assign n1408 = asl_over_xor - n1407;
  /*# TG68K_ALU.vhd:775:28 */
  assign n1410 = rot_bits == 2'b00;
  /*# TG68K_ALU.vhd:775:48 */
  assign n1411 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:775:34 */
  assign n1412 = n1411 & n1410;
  /*# TG68K_ALU.vhd:776:45 */
  assign n1413 = asl_over[32]; // extract
  /*# TG68K_ALU.vhd:776:33 */
  assign n1414 = ~n1413;
  /*# TG68K_ALU.vhd:775:17 */
  assign n1416 = n1412 ? n1414 : 1'b0;
  /*# TG68K_ALU.vhd:780:30 */
  assign n1418 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:780:33 */
  assign n1419 = ~n1418;
  /*# TG68K_ALU.vhd:781:42 */
  assign n1420 = result_bs[31]; // extract
  /*# TG68K_ALU.vhd:783:40 */
  assign n1421 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:785:58 */
  assign n1422 = result_bs[8]; // extract
  /*# TG68K_ALU.vhd:784:33 */
  assign n1424 = n1421 == 2'b00;
  /*# TG68K_ALU.vhd:787:58 */
  assign n1425 = result_bs[16]; // extract
  /*# TG68K_ALU.vhd:786:33 */
  assign n1427 = n1421 == 2'b01;
  /*# TG68K_ALU.vhd:786:42 */
  assign n1429 = n1421 == 2'b11;
  /*# TG68K_ALU.vhd:786:42 */
  assign n1430 = n1427 | n1429;
  /*# TG68K_ALU.vhd:789:58 */
  assign n1431 = result_bs[32]; // extract
  /*# TG68K_ALU.vhd:788:33 */
  assign n1433 = n1421 == 2'b10;
  /*# TG68K_ALU.vhd:783:25 */
  assign n1434 = {n1433, n1430, n1424};
  /*# TG68K_ALU.vhd:783:25 */
  always @*
    case (n1434)
      3'b100: n1435 = n1431;
      3'b010: n1435 = n1425;
      3'b001: n1435 = n1422;
      default: n1435 = bs_c;
    endcase
  /*# TG68K_ALU.vhd:780:17 */
  assign n1436 = n1419 ? n1420 : n1435;
  /*# TG68K_ALU.vhd:795:28 */
  assign n1438 = rot_bits == 2'b11;
  /*# TG68K_ALU.vhd:796:38 */
  assign n1439 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:797:40 */
  assign n1440 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:799:69 */
  assign n1441 = result_bs[7:0]; // extract
  /*# TG68K_ALU.vhd:799:94 */
  assign n1442 = result_bs[15:8]; // extract
  /*# TG68K_ALU.vhd:799:82 */
  assign n1443 = n1441 | n1442;
  /*# TG68K_ALU.vhd:800:52 */
  assign n1444 = alu[7]; // extract
  /*# TG68K_ALU.vhd:798:33 */
  assign n1446 = n1440 == 2'b00;
  /*# TG68K_ALU.vhd:802:70 */
  assign n1447 = result_bs[15:0]; // extract
  /*# TG68K_ALU.vhd:802:96 */
  assign n1448 = result_bs[31:16]; // extract
  /*# TG68K_ALU.vhd:802:84 */
  assign n1449 = n1447 | n1448;
  /*# TG68K_ALU.vhd:803:52 */
  assign n1450 = alu[15]; // extract
  /*# TG68K_ALU.vhd:801:33 */
  assign n1452 = n1440 == 2'b01;
  /*# TG68K_ALU.vhd:801:42 */
  assign n1454 = n1440 == 2'b11;
  /*# TG68K_ALU.vhd:801:42 */
  assign n1455 = n1452 | n1454;
  /*# TG68K_ALU.vhd:805:57 */
  assign n1456 = result_bs[31:0]; // extract
  /*# TG68K_ALU.vhd:805:83 */
  assign n1457 = result_bs[63:32]; // extract
  /*# TG68K_ALU.vhd:805:71 */
  assign n1458 = n1456 | n1457;
  /*# TG68K_ALU.vhd:806:52 */
  assign n1459 = alu[31]; // extract
  /*# TG68K_ALU.vhd:804:33 */
  assign n1461 = n1440 == 2'b10;
  /*# TG68K_ALU.vhd:797:25 */
  assign n1462 = {n1461, n1455, n1446};
  /*# TG68K_ALU.vhd:802:84 */
  assign n1463 = n1449[7:0]; // extract
  /*# TG68K_ALU.vhd:805:71 */
  assign n1464 = n1458[7:0]; // extract
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1462)
      3'b100: n1466 = n1464;
      3'b010: n1466 = n1463;
      3'b001: n1466 = n1443;
      default: n1466 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:802:84 */
  assign n1467 = n1449[15:8]; // extract
  /*# TG68K_ALU.vhd:805:71 */
  assign n1468 = n1458[15:8]; // extract
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1462)
      3'b100: n1470 = n1468;
      3'b010: n1470 = n1467;
      3'b001: n1470 = 8'bX;
      default: n1470 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:805:71 */
  assign n1471 = n1458[31:16]; // extract
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1462)
      3'b100: n1473 = n1471;
      3'b010: n1473 = 16'bX;
      3'b001: n1473 = 16'bX;
      default: n1473 = 16'bX;
    endcase
  /*# TG68K_ALU.vhd:797:25 */
  always @*
    case (n1462)
      3'b100: n1474 = n1459;
      3'b010: n1474 = n1450;
      3'b001: n1474 = n1444;
      default: n1474 = n1436;
    endcase
  /*# TG68K_ALU.vhd:809:38 */
  assign n1475 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:810:44 */
  assign n1476 = alu[0]; // extract
  /*# TG68K_ALU.vhd:809:25 */
  assign n1477 = n1475 ? n1476 : n1474;
  /*# TG68K_ALU.vhd:812:31 */
  assign n1479 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:813:40 */
  assign n1480 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:815:69 */
  assign n1481 = result_bs[7:0]; // extract
  /*# TG68K_ALU.vhd:815:94 */
  assign n1482 = result_bs[16:9]; // extract
  /*# TG68K_ALU.vhd:815:82 */
  assign n1483 = n1481 | n1482;
  /*# TG68K_ALU.vhd:816:58 */
  assign n1484 = result_bs[8]; // extract
  /*# TG68K_ALU.vhd:816:74 */
  assign n1485 = result_bs[17]; // extract
  /*# TG68K_ALU.vhd:816:62 */
  assign n1486 = n1484 | n1485;
  /*# TG68K_ALU.vhd:814:33 */
  assign n1488 = n1480 == 2'b00;
  /*# TG68K_ALU.vhd:818:70 */
  assign n1489 = result_bs[15:0]; // extract
  /*# TG68K_ALU.vhd:818:96 */
  assign n1490 = result_bs[32:17]; // extract
  /*# TG68K_ALU.vhd:818:84 */
  assign n1491 = n1489 | n1490;
  /*# TG68K_ALU.vhd:819:58 */
  assign n1492 = result_bs[16]; // extract
  /*# TG68K_ALU.vhd:819:75 */
  assign n1493 = result_bs[33]; // extract
  /*# TG68K_ALU.vhd:819:63 */
  assign n1494 = n1492 | n1493;
  /*# TG68K_ALU.vhd:817:33 */
  assign n1496 = n1480 == 2'b01;
  /*# TG68K_ALU.vhd:817:42 */
  assign n1498 = n1480 == 2'b11;
  /*# TG68K_ALU.vhd:817:42 */
  assign n1499 = n1496 | n1498;
  /*# TG68K_ALU.vhd:821:57 */
  assign n1500 = result_bs[31:0]; // extract
  /*# TG68K_ALU.vhd:821:83 */
  assign n1501 = result_bs[64:33]; // extract
  /*# TG68K_ALU.vhd:821:71 */
  assign n1502 = n1500 | n1501;
  /*# TG68K_ALU.vhd:822:58 */
  assign n1503 = result_bs[32]; // extract
  /*# TG68K_ALU.vhd:822:75 */
  assign n1504 = result_bs[65]; // extract
  /*# TG68K_ALU.vhd:822:63 */
  assign n1505 = n1503 | n1504;
  /*# TG68K_ALU.vhd:820:33 */
  assign n1507 = n1480 == 2'b10;
  /*# TG68K_ALU.vhd:813:25 */
  assign n1508 = {n1507, n1499, n1488};
  /*# TG68K_ALU.vhd:818:84 */
  assign n1509 = n1491[7:0]; // extract
  /*# TG68K_ALU.vhd:821:71 */
  assign n1510 = n1502[7:0]; // extract
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1508)
      3'b100: n1512 = n1510;
      3'b010: n1512 = n1509;
      3'b001: n1512 = n1483;
      default: n1512 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:818:84 */
  assign n1513 = n1491[15:8]; // extract
  /*# TG68K_ALU.vhd:821:71 */
  assign n1514 = n1502[15:8]; // extract
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1508)
      3'b100: n1516 = n1514;
      3'b010: n1516 = n1513;
      3'b001: n1516 = 8'bX;
      default: n1516 = 8'bX;
    endcase
  /*# TG68K_ALU.vhd:821:71 */
  assign n1517 = n1502[31:16]; // extract
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1508)
      3'b100: n1519 = n1517;
      3'b010: n1519 = 16'bX;
      3'b001: n1519 = 16'bX;
      default: n1519 = 16'bX;
    endcase
  /*# TG68K_ALU.vhd:813:25 */
  always @*
    case (n1508)
      3'b100: n1520 = n1505;
      3'b010: n1520 = n1494;
      3'b001: n1520 = n1486;
      default: n1520 = n1436;
    endcase
  /*# TG68K_ALU.vhd:826:38 */
  assign n1521 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:826:41 */
  assign n1522 = ~n1521;
  /*# TG68K_ALU.vhd:827:49 */
  assign n1523 = result_bs[63:32]; // extract
  /*# TG68K_ALU.vhd:829:49 */
  assign n1524 = result_bs[31:0]; // extract
  /*# TG68K_ALU.vhd:826:25 */
  assign n1525 = n1522 ? n1523 : n1524;
  /*# TG68K_ALU.vhd:812:17 */
  assign n1526 = {n1519, n1516, n1512};
  /*# TG68K_ALU.vhd:812:17 */
  assign n1527 = n1479 ? n1526 : n1525;
  /*# TG68K_ALU.vhd:812:17 */
  assign n1528 = n1479 ? n1520 : n1436;
  /*# TG68K_ALU.vhd:795:17 */
  assign n1529 = {n1473, n1470, n1466};
  /*# TG68K_ALU.vhd:795:17 */
  assign n1530 = n1438 ? n1529 : n1527;
  /*# TG68K_ALU.vhd:795:17 */
  assign n1532 = n1438 ? n1477 : n1528;
  /*# TG68K_ALU.vhd:795:17 */
  assign n1533 = n1438 ? n1439 : bs_c;
  /*# TG68K_ALU.vhd:833:29 */
  assign n1535 = bs_shift == 6'b000000;
  /*# TG68K_ALU.vhd:834:36 */
  assign n1537 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:835:46 */
  assign n1538 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:834:25 */
  assign n1540 = n1537 ? n1538 : 1'b0;
  /*# TG68K_ALU.vhd:839:38 */
  assign n1541 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:833:17 */
  assign n1543 = n1535 ? 1'b0 : n1416;
  /*# TG68K_ALU.vhd:833:17 */
  assign n1544 = n1535 ? n1540 : n1532;
  /*# TG68K_ALU.vhd:833:17 */
  assign n1545 = n1535 ? n1541 : n1533;
  /*# TG68K_ALU.vhd:848:45 */
  assign n1546 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:848:45 */
  assign n1548 = n1546 == 32'b00000000000000000000000000111111;
  /*# TG68K_ALU.vhd:850:48 */
  assign n1549 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:850:48 */
  assign n1551 = $unsigned(n1549) > $unsigned(32'b00000000000000000000000000110101);
  /*# TG68K_ALU.vhd:851:66 */
  assign n1553 = bs_shift - 6'b110110;
  /*# TG68K_ALU.vhd:852:48 */
  assign n1554 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:852:48 */
  assign n1556 = $unsigned(n1554) > $unsigned(32'b00000000000000000000000000101100);
  /*# TG68K_ALU.vhd:853:66 */
  assign n1558 = bs_shift - 6'b101101;
  /*# TG68K_ALU.vhd:854:48 */
  assign n1559 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:854:48 */
  assign n1561 = $unsigned(n1559) > $unsigned(32'b00000000000000000000000000100011);
  /*# TG68K_ALU.vhd:855:66 */
  assign n1563 = bs_shift - 6'b100100;
  /*# TG68K_ALU.vhd:856:48 */
  assign n1564 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:856:48 */
  assign n1566 = $unsigned(n1564) > $unsigned(32'b00000000000000000000000000011010);
  /*# TG68K_ALU.vhd:857:66 */
  assign n1568 = bs_shift - 6'b011011;
  /*# TG68K_ALU.vhd:858:48 */
  assign n1569 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:858:48 */
  assign n1571 = $unsigned(n1569) > $unsigned(32'b00000000000000000000000000010001);
  /*# TG68K_ALU.vhd:859:66 */
  assign n1573 = bs_shift - 6'b010010;
  /*# TG68K_ALU.vhd:860:48 */
  assign n1574 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:860:48 */
  assign n1576 = $unsigned(n1574) > $unsigned(32'b00000000000000000000000000001000);
  /*# TG68K_ALU.vhd:861:66 */
  assign n1578 = bs_shift - 6'b001001;
  /*# TG68K_ALU.vhd:860:33 */
  assign n1579 = n1576 ? n1578 : bs_shift;
  /*# TG68K_ALU.vhd:858:33 */
  assign n1580 = n1571 ? n1573 : n1579;
  /*# TG68K_ALU.vhd:856:33 */
  assign n1581 = n1566 ? n1568 : n1580;
  /*# TG68K_ALU.vhd:854:33 */
  assign n1582 = n1561 ? n1563 : n1581;
  /*# TG68K_ALU.vhd:852:33 */
  assign n1583 = n1556 ? n1558 : n1582;
  /*# TG68K_ALU.vhd:850:33 */
  assign n1584 = n1551 ? n1553 : n1583;
  /*# TG68K_ALU.vhd:848:33 */
  assign n1586 = n1548 ? 6'b000000 : n1584;
  /*# TG68K_ALU.vhd:847:25 */
  assign n1588 = ring == 6'b001001;
  /*# TG68K_ALU.vhd:866:45 */
  assign n1589 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:866:45 */
  assign n1591 = $unsigned(n1589) > $unsigned(32'b00000000000000000000000000110010);
  /*# TG68K_ALU.vhd:867:66 */
  assign n1593 = bs_shift - 6'b110011;
  /*# TG68K_ALU.vhd:868:48 */
  assign n1594 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:868:48 */
  assign n1596 = $unsigned(n1594) > $unsigned(32'b00000000000000000000000000100001);
  /*# TG68K_ALU.vhd:869:66 */
  assign n1598 = bs_shift - 6'b100010;
  /*# TG68K_ALU.vhd:870:48 */
  assign n1599 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:870:48 */
  assign n1601 = $unsigned(n1599) > $unsigned(32'b00000000000000000000000000010000);
  /*# TG68K_ALU.vhd:871:66 */
  assign n1603 = bs_shift - 6'b010001;
  /*# TG68K_ALU.vhd:870:33 */
  assign n1604 = n1601 ? n1603 : bs_shift;
  /*# TG68K_ALU.vhd:868:33 */
  assign n1605 = n1596 ? n1598 : n1604;
  /*# TG68K_ALU.vhd:866:33 */
  assign n1606 = n1591 ? n1593 : n1605;
  /*# TG68K_ALU.vhd:865:25 */
  assign n1608 = ring == 6'b010001;
  /*# TG68K_ALU.vhd:876:45 */
  assign n1609 = {26'b0, bs_shift};  // uext
  /*# TG68K_ALU.vhd:876:45 */
  assign n1611 = $unsigned(n1609) > $unsigned(32'b00000000000000000000000000100000);
  /*# TG68K_ALU.vhd:877:66 */
  assign n1613 = bs_shift - 6'b100001;
  /*# TG68K_ALU.vhd:876:33 */
  assign n1614 = n1611 ? n1613 : bs_shift;
  /*# TG68K_ALU.vhd:875:25 */
  assign n1616 = ring == 6'b100001;
  /*# TG68K_ALU.vhd:881:74 */
  assign n1617 = bs_shift[2:0]; // extract
  /*# TG68K_ALU.vhd:881:64 */
  assign n1619 = {3'b000, n1617};
  /*# TG68K_ALU.vhd:881:25 */
  assign n1621 = ring == 6'b001000;
  /*# TG68K_ALU.vhd:882:74 */
  assign n1622 = bs_shift[3:0]; // extract
  /*# TG68K_ALU.vhd:882:64 */
  assign n1624 = {2'b00, n1622};
  /*# TG68K_ALU.vhd:882:25 */
  assign n1626 = ring == 6'b010000;
  /*# TG68K_ALU.vhd:883:74 */
  assign n1627 = bs_shift[4:0]; // extract
  /*# TG68K_ALU.vhd:883:64 */
  assign n1629 = {1'b0, n1627};
  /*# TG68K_ALU.vhd:883:25 */
  assign n1631 = ring == 6'b100000;
  /*# TG68K_ALU.vhd:846:17 */
  assign n1632 = {n1631, n1626, n1621, n1616, n1608, n1588};
  /*# TG68K_ALU.vhd:846:17 */
  always @*
    case (n1632)
      6'b100000: n1634 = n1629;
      6'b010000: n1634 = n1624;
      6'b001000: n1634 = n1619;
      6'b000100: n1634 = n1614;
      6'b000010: n1634 = n1606;
      6'b000001: n1634 = n1586;
      default: n1634 = 6'b000000;
    endcase
  /*# TG68K_ALU.vhd:888:30 */
  assign n1635 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:888:33 */
  assign n1636 = ~n1635;
  /*# TG68K_ALU.vhd:889:39 */
  assign n1637 = ring - bs_shift_mod;
  /*# TG68K_ALU.vhd:888:17 */
  assign n1638 = n1636 ? n1637 : bs_shift_mod;
  /*# TG68K_ALU.vhd:891:28 */
  assign n1639 = rot_bits[1]; // extract
  /*# TG68K_ALU.vhd:891:31 */
  assign n1640 = ~n1639;
  /*# TG68K_ALU.vhd:892:38 */
  assign n1641 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:892:41 */
  assign n1642 = ~n1641;
  /*# TG68K_ALU.vhd:893:45 */
  assign n1644 = 6'b100000 - bs_shift_mod;
  /*# TG68K_ALU.vhd:892:25 */
  assign n1645 = n1642 ? n1644 : n1638;
  /*# TG68K_ALU.vhd:895:37 */
  assign n1646 = bs_shift == ring;
  /*# TG68K_ALU.vhd:896:46 */
  assign n1647 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:896:49 */
  assign n1648 = ~n1647;
  /*# TG68K_ALU.vhd:897:53 */
  assign n1650 = 6'b100000 - ring;
  /*# TG68K_ALU.vhd:896:33 */
  assign n1651 = n1648 ? n1650 : ring;
  /*# TG68K_ALU.vhd:895:25 */
  assign n1652 = n1646 ? n1651 : n1645;
  /*# TG68K_ALU.vhd:902:37 */
  assign n1653 = $unsigned(bs_shift) > $unsigned(ring);
  /*# TG68K_ALU.vhd:903:46 */
  assign n1654 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:903:49 */
  assign n1655 = ~n1654;
  /*# TG68K_ALU.vhd:907:55 */
  assign n1657 = ring + 6'b000001;
  /*# TG68K_ALU.vhd:903:33 */
  assign n1659 = n1655 ? 6'b000000 : n1657;
  /*# TG68K_ALU.vhd:891:17 */
  assign n1661 = n1665 ? 1'b0 : n1544;
  /*# TG68K_ALU.vhd:902:25 */
  assign n1662 = n1653 ? n1659 : n1652;
  /*# TG68K_ALU.vhd:902:25 */
  assign n1663 = n1655 & n1653;
  /*# TG68K_ALU.vhd:891:17 */
  assign n1664 = n1640 ? n1662 : n1638;
  /*# TG68K_ALU.vhd:891:17 */
  assign n1665 = n1663 & n1640;
  /*# TG68K_ALU.vhd:915:50 */
  assign n1666 = asr_sign[31:0]; // extract
  /*# TG68K_ALU.vhd:915:74 */
  assign n1667 = hot_msb[31:0]; // extract
  /*# TG68K_ALU.vhd:915:64 */
  assign n1668 = n1666 | n1667;
  /*# TG68K_ALU.vhd:196:16 */
  assign n1670 = n1669[0]; // extract
  /*# TG68K_ALU.vhd:916:28 */
  assign n1672 = rot_bits == 2'b00;
  /*# TG68K_ALU.vhd:916:48 */
  assign n1673 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:916:51 */
  assign n1674 = ~n1673;
  /*# TG68K_ALU.vhd:916:34 */
  assign n1675 = n1674 & n1672;
  /*# TG68K_ALU.vhd:916:56 */
  assign n1676 = msb & n1675;
  /*# TG68K_ALU.vhd:917:49 */
  assign n1677 = asr_sign[32:1]; // extract
  /*# TG68K_ALU.vhd:917:38 */
  assign n1678 = alu | n1677;
  /*# TG68K_ALU.vhd:918:37 */
  assign n1679 = $unsigned(bs_shift) > $unsigned(ring);
  /*# TG68K_ALU.vhd:916:17 */
  assign n1681 = n1683 ? 1'b1 : n1661;
  /*# TG68K_ALU.vhd:916:17 */
  assign n1682 = n1676 ? n1678 : alu;
  /*# TG68K_ALU.vhd:916:17 */
  assign n1683 = n1679 & n1676;
  /*# TG68K_ALU.vhd:923:43 */
  assign n1685 = {1'b0, OP1out};
  /*# TG68K_ALU.vhd:924:32 */
  assign n1686 = exe_opcode[7:6]; // extract
  /*# TG68K_ALU.vhd:926:46 */
  assign n1687 = OP1out[7]; // extract
  /*# TG68K_ALU.vhd:929:44 */
  assign n1691 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:930:59 */
  assign n1692 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1693 = n1688[0]; // extract
  /*# TG68K_ALU.vhd:929:33 */
  assign n1694 = n1691 ? n1692 : n1693;
  /*# TG68K_ALU.vhd:188:16 */
  assign n1695 = n1688[23:1]; // extract
  /*# TG68K_ALU.vhd:925:25 */
  assign n1697 = n1686 == 2'b00;
  /*# TG68K_ALU.vhd:933:46 */
  assign n1698 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:936:44 */
  assign n1702 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:937:60 */
  assign n1703 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1704 = n1699[0]; // extract
  /*# TG68K_ALU.vhd:936:33 */
  assign n1705 = n1702 ? n1703 : n1704;
  /*# TG68K_ALU.vhd:188:16 */
  assign n1706 = n1699[15:1]; // extract
  /*# TG68K_ALU.vhd:932:25 */
  assign n1708 = n1686 == 2'b01;
  /*# TG68K_ALU.vhd:932:34 */
  assign n1710 = n1686 == 2'b11;
  /*# TG68K_ALU.vhd:932:34 */
  assign n1711 = n1708 | n1710;
  /*# TG68K_ALU.vhd:940:46 */
  assign n1712 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:941:44 */
  assign n1714 = rot_bits == 2'b10;
  /*# TG68K_ALU.vhd:942:60 */
  assign n1715 = n2356[4]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1716 = n1685[32]; // extract
  /*# TG68K_ALU.vhd:941:33 */
  assign n1717 = n1714 ? n1715 : n1716;
  /*# TG68K_ALU.vhd:939:25 */
  assign n1719 = n1686 == 2'b10;
  /*# TG68K_ALU.vhd:924:17 */
  assign n1720 = {n1719, n1711, n1697};
  /*# TG68K_ALU.vhd:188:16 */
  assign n1721 = n1685[8]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1722 = n1721;
      3'b010: n1722 = n1721;
      3'b001: n1722 = n1694;
      default: n1722 = n1721;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1723 = n1695[6:0]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1724 = n1685[15:9]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1725 = n1724;
      3'b010: n1725 = n1724;
      3'b001: n1725 = n1723;
      default: n1725 = n1724;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1726 = n1695[7]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1727 = n1685[16]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1728 = n1727;
      3'b010: n1728 = n1705;
      3'b001: n1728 = n1726;
      default: n1728 = n1727;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1729 = n1695[22:8]; // extract
  /*# TG68K_ALU.vhd:188:16 */
  assign n1730 = n1685[31:17]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1731 = n1730;
      3'b010: n1731 = n1706;
      3'b001: n1731 = n1729;
      default: n1731 = n1730;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1732 = n1685[32]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1733 = n1717;
      3'b010: n1733 = n1732;
      3'b001: n1733 = n1732;
      default: n1733 = n1732;
    endcase
  /*# TG68K_ALU.vhd:188:16 */
  assign n1735 = n1685[7:0]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1739 = n1712;
      3'b010: n1739 = n1698;
      3'b001: n1739 = n1687;
      default: n1739 = msb;
    endcase
  assign n1740 = n1689[7:0]; // extract
  /*# TG68K_ALU.vhd:200:16 */
  assign n1741 = n1682[15:8]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1742 = n1741;
      3'b010: n1742 = n1741;
      3'b001: n1742 = n1740;
      default: n1742 = n1741;
    endcase
  assign n1743 = n1689[23:8]; // extract
  /*# TG68K_ALU.vhd:200:16 */
  assign n1744 = n1682[31:16]; // extract
  /*# TG68K_ALU.vhd:924:17 */
  always @*
    case (n1720)
      3'b100: n1745 = n1744;
      3'b010: n1745 = 16'b0000000000000000;
      3'b001: n1745 = n1743;
      default: n1745 = n1744;
    endcase
  /*# TG68K_ALU.vhd:200:16 */
  assign n1747 = n1682[7:0]; // extract
  /*# TG68K_ALU.vhd:946:71 */
  assign n1749 = {33'b000000000000000000000000000000000, vector};
  /*# TG68K_ALU.vhd:946:84 */
  assign n1750 = {25'b0, bit_nr};  // uext
  /*# TG68K_ALU.vhd:946:80 */
  assign n1751 = {1'b0, n1750};  // uext
  /*# TG68K_ALU.vhd:946:80 */
  assign n1752 = n1749 << n1751;
  /*# TG68K_ALU.vhd:957:24 */
  assign n1756 = exec[17]; // extract
  /*# TG68K_ALU.vhd:958:58 */
  assign n1757 = last_data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:958:40 */
  assign n1758 = n2356 & n1757;
  /*# TG68K_ALU.vhd:959:27 */
  assign n1759 = exec[18]; // extract
  /*# TG68K_ALU.vhd:960:58 */
  assign n1760 = last_data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:960:40 */
  assign n1761 = n2356 ^ n1760;
  /*# TG68K_ALU.vhd:961:27 */
  assign n1762 = exec[19]; // extract
  /*# TG68K_ALU.vhd:962:57 */
  assign n1763 = last_data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:962:40 */
  assign n1764 = n2356 | n1763;
  /*# TG68K_ALU.vhd:964:40 */
  assign n1765 = OP2out[7:0]; // extract
  /*# TG68K_ALU.vhd:961:17 */
  assign n1766 = n1762 ? n1764 : n1765;
  /*# TG68K_ALU.vhd:959:17 */
  assign n1767 = n1759 ? n1761 : n1766;
  /*# TG68K_ALU.vhd:957:17 */
  assign n1768 = n1756 ? n1758 : n1767;
  /*# TG68K_ALU.vhd:971:24 */
  assign n1769 = exec[28]; // extract
  /*# TG68K_ALU.vhd:971:50 */
  assign n1770 = n2356[2]; // extract
  /*# TG68K_ALU.vhd:971:53 */
  assign n1771 = ~n1770;
  /*# TG68K_ALU.vhd:971:41 */
  assign n1772 = n1771 & n1769;
  /*# TG68K_ALU.vhd:973:28 */
  assign n1773 = op1in[7:0]; // extract
  /*# TG68K_ALU.vhd:973:40 */
  assign n1775 = n1773 == 8'b00000000;
  /*# TG68K_ALU.vhd:975:33 */
  assign n1777 = op1in[15:8]; // extract
  /*# TG68K_ALU.vhd:975:46 */
  assign n1779 = n1777 == 8'b00000000;
  /*# TG68K_ALU.vhd:977:41 */
  assign n1781 = op1in[31:16]; // extract
  /*# TG68K_ALU.vhd:977:55 */
  assign n1783 = n1781 == 16'b0000000000000000;
  /*# TG68K_ALU.vhd:977:33 */
  assign n1786 = n1783 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:975:25 */
  assign n1787 = {n1786, 1'b1};
  /*# TG68K_ALU.vhd:975:25 */
  assign n1789 = n1779 ? n1787 : 2'b00;
  /*# TG68K_ALU.vhd:973:17 */
  assign n1790 = {n1789, 1'b1};
  /*# TG68K_ALU.vhd:973:17 */
  assign n1792 = n1775 ? n1790 : 3'b000;
  /*# TG68K_ALU.vhd:971:17 */
  assign n1794 = n1772 ? 3'b000 : n1792;
  /*# TG68K_ALU.vhd:984:32 */
  assign n1797 = exe_datatype == 2'b00;
  /*# TG68K_ALU.vhd:985:43 */
  assign n1798 = op1in[7]; // extract
  /*# TG68K_ALU.vhd:985:53 */
  assign n1799 = flag_z[0]; // extract
  /*# TG68K_ALU.vhd:985:46 */
  assign n1800 = {n1798, n1799};
  /*# TG68K_ALU.vhd:985:67 */
  assign n1801 = addsub_ofl[0]; // extract
  /*# TG68K_ALU.vhd:985:56 */
  assign n1802 = {n1800, n1801};
  /*# TG68K_ALU.vhd:985:76 */
  assign n1803 = n256[0]; // extract
  /*# TG68K_ALU.vhd:985:70 */
  assign n1804 = {n1802, n1803};
  /*# TG68K_ALU.vhd:986:32 */
  assign n1805 = exec[12]; // extract
  /*# TG68K_ALU.vhd:986:53 */
  assign n1806 = exec[13]; // extract
  /*# TG68K_ALU.vhd:986:46 */
  assign n1807 = n1805 | n1806;
  /*# TG68K_ALU.vhd:986:25 */
  assign n1808 = {vflag_a, bcd_a_carry};
  /*# TG68K_ALU.vhd:95:16 */
  assign n1809 = n1804[1:0]; // extract
  /*# TG68K_ALU.vhd:986:25 */
  assign n1810 = n1807 ? n1808 : n1809;
  /*# TG68K_ALU.vhd:95:16 */
  assign n1811 = n1804[3:2]; // extract
  /*# TG68K_ALU.vhd:990:35 */
  assign n1813 = exe_datatype == 2'b10;
  /*# TG68K_ALU.vhd:990:48 */
  assign n1814 = exec[10]; // extract
  /*# TG68K_ALU.vhd:990:41 */
  assign n1815 = n1813 | n1814;
  /*# TG68K_ALU.vhd:991:43 */
  assign n1816 = op1in[31]; // extract
  /*# TG68K_ALU.vhd:991:54 */
  assign n1817 = flag_z[2]; // extract
  /*# TG68K_ALU.vhd:991:47 */
  assign n1818 = {n1816, n1817};
  /*# TG68K_ALU.vhd:991:68 */
  assign n1819 = addsub_ofl[2]; // extract
  /*# TG68K_ALU.vhd:991:57 */
  assign n1820 = {n1818, n1819};
  /*# TG68K_ALU.vhd:991:77 */
  assign n1821 = n256[2]; // extract
  /*# TG68K_ALU.vhd:991:71 */
  assign n1822 = {n1820, n1821};
  /*# TG68K_ALU.vhd:993:43 */
  assign n1823 = op1in[15]; // extract
  /*# TG68K_ALU.vhd:993:54 */
  assign n1824 = flag_z[1]; // extract
  /*# TG68K_ALU.vhd:993:47 */
  assign n1825 = {n1823, n1824};
  /*# TG68K_ALU.vhd:993:68 */
  assign n1826 = addsub_ofl[1]; // extract
  /*# TG68K_ALU.vhd:993:57 */
  assign n1827 = {n1825, n1826};
  /*# TG68K_ALU.vhd:993:77 */
  assign n1828 = n256[1]; // extract
  /*# TG68K_ALU.vhd:993:71 */
  assign n1829 = {n1827, n1828};
  /*# TG68K_ALU.vhd:990:17 */
  assign n1830 = n1815 ? n1822 : n1829;
  /*# TG68K_ALU.vhd:984:17 */
  assign n1831 = {n1811, n1810};
  /*# TG68K_ALU.vhd:984:17 */
  assign n1832 = n1797 ? n1831 : n1830;
  /*# TG68K_ALU.vhd:1000:40 */
  assign n1834 = exec[59]; // extract
  /*# TG68K_ALU.vhd:1000:55 */
  assign n1835 = n1834 | set_stop;
  /*# TG68K_ALU.vhd:1001:71 */
  assign n1836 = data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:1000:33 */
  assign n1837 = n1835 ? n1836 : n2356;
  /*# TG68K_ALU.vhd:1003:40 */
  assign n1838 = exec[60]; // extract
  /*# TG68K_ALU.vhd:1004:71 */
  assign n1839 = data_read[7:0]; // extract
  /*# TG68K_ALU.vhd:1003:33 */
  assign n1840 = n1838 ? n1839 : n1837;
  /*# TG68K_ALU.vhd:1007:40 */
  assign n1841 = exec[9]; // extract
  /*# TG68K_ALU.vhd:1007:66 */
  assign n1842 = ~decodeOPC;
  /*# TG68K_ALU.vhd:1007:53 */
  assign n1843 = n1842 & n1841;
  /*# TG68K_ALU.vhd:1008:65 */
  assign n1844 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1008:69 */
  assign n1845 = n1844 ^ rot_rot;
  /*# TG68K_ALU.vhd:1008:82 */
  assign n1846 = n1845 | asl_vflag;
  /*# TG68K_ALU.vhd:1007:33 */
  assign n1848 = n1843 ? n1846 : 1'b0;
  /*# TG68K_ALU.vhd:1012:40 */
  assign n1849 = exec[51]; // extract
  /*# TG68K_ALU.vhd:1015:56 */
  assign n1851 = micro_state == 8'b00110011;
  /*# TG68K_ALU.vhd:1017:62 */
  assign n1852 = exe_opcode[8]; // extract
  /*# TG68K_ALU.vhd:1017:65 */
  assign n1853 = ~n1852;
  /*# TG68K_ALU.vhd:1019:92 */
  assign n1854 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1019:82 */
  assign n1855 = ~n1854;
  /*# TG68K_ALU.vhd:1019:81 */
  assign n1857 = {1'b0, n1855};
  /*# TG68K_ALU.vhd:1019:96 */
  assign n1859 = {n1857, 2'b00};
  /*# TG68K_ALU.vhd:1017:49 */
  assign n1861 = n1853 ? n1859 : 4'b0100;
  /*# TG68K_ALU.vhd:73:17 */
  assign n1862 = n1840[3:0]; // extract
  /*# TG68K_ALU.vhd:1015:41 */
  assign n1863 = n1851 ? n1861 : n1862;
  /*# TG68K_ALU.vhd:1024:43 */
  assign n1864 = exec[49]; // extract
  /*# TG68K_ALU.vhd:1024:53 */
  assign n1865 = ~n1864;
  /*# TG68K_ALU.vhd:1025:61 */
  assign n1866 = n2356[3:0]; // extract
  /*# TG68K_ALU.vhd:1026:48 */
  assign n1867 = exec[3]; // extract
  /*# TG68K_ALU.vhd:1027:70 */
  assign n1868 = set_flags[0]; // extract
  /*# TG68K_ALU.vhd:1028:51 */
  assign n1869 = exec[9]; // extract
  /*# TG68K_ALU.vhd:1028:76 */
  assign n1871 = rot_bits != 2'b11;
  /*# TG68K_ALU.vhd:1028:64 */
  assign n1872 = n1871 & n1869;
  /*# TG68K_ALU.vhd:1028:91 */
  assign n1873 = exec[23]; // extract
  /*# TG68K_ALU.vhd:1028:100 */
  assign n1874 = ~n1873;
  /*# TG68K_ALU.vhd:1028:83 */
  assign n1875 = n1874 & n1872;
  /*# TG68K_ALU.vhd:1030:51 */
  assign n1876 = exec[81]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1877 = n1840[4]; // extract
  /*# TG68K_ALU.vhd:1030:41 */
  assign n1878 = n1876 ? bs_x : n1877;
  /*# TG68K_ALU.vhd:1028:41 */
  assign n1879 = n1875 ? rot_x : n1878;
  /*# TG68K_ALU.vhd:1026:41 */
  assign n1880 = n1867 ? n1868 : n1879;
  /*# TG68K_ALU.vhd:1034:49 */
  assign n1881 = exec[8]; // extract
  /*# TG68K_ALU.vhd:1034:65 */
  assign n1882 = exec[86]; // extract
  /*# TG68K_ALU.vhd:1034:58 */
  assign n1883 = n1881 | n1882;
  /*# TG68K_ALU.vhd:1036:51 */
  assign n1884 = exec[21]; // extract
  /*# TG68K_ALU.vhd:1036:65 */
  assign n1886 = 1'b1 & n1884;
  /*# TG68K_ALU.vhd:1039:65 */
  assign n1888 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:1039:74 */
  assign n1890 = n1888 | 1'b0;
  /*# TG68K_ALU.vhd:1040:83 */
  assign n1891 = op1in[15]; // extract
  /*# TG68K_ALU.vhd:1040:94 */
  assign n1892 = flag_z[1]; // extract
  /*# TG68K_ALU.vhd:1040:87 */
  assign n1893 = {n1891, n1892};
  /*# TG68K_ALU.vhd:1040:97 */
  assign n1895 = {n1893, 2'b00};
  /*# TG68K_ALU.vhd:1042:83 */
  assign n1896 = op1in[31]; // extract
  /*# TG68K_ALU.vhd:1042:94 */
  assign n1897 = flag_z[2]; // extract
  /*# TG68K_ALU.vhd:1042:87 */
  assign n1898 = {n1896, n1897};
  /*# TG68K_ALU.vhd:1042:97 */
  assign n1900 = {n1898, 2'b00};
  /*# TG68K_ALU.vhd:1039:49 */
  assign n1901 = n1890 ? n1895 : n1900;
  /*# TG68K_ALU.vhd:1037:49 */
  assign n1902 = v_flag ? 4'b1010 : n1901;
  /*# TG68K_ALU.vhd:1044:51 */
  assign n1903 = exec[68]; // extract
  /*# TG68K_ALU.vhd:1044:72 */
  assign n1905 = 1'b1 & n1903;
  /*# TG68K_ALU.vhd:1045:70 */
  assign n1906 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1046:70 */
  assign n1907 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1046:83 */
  assign n1908 = n2356[2]; // extract
  /*# TG68K_ALU.vhd:1046:74 */
  assign n1909 = n1907 & n1908;
  /*# TG68K_ALU.vhd:1054:51 */
  assign n1913 = exec[5]; // extract
  /*# TG68K_ALU.vhd:1054:70 */
  assign n1914 = exec[6]; // extract
  /*# TG68K_ALU.vhd:1054:63 */
  assign n1915 = n1913 | n1914;
  /*# TG68K_ALU.vhd:1054:90 */
  assign n1916 = exec[7]; // extract
  /*# TG68K_ALU.vhd:1054:83 */
  assign n1917 = n1915 | n1916;
  /*# TG68K_ALU.vhd:1054:110 */
  assign n1918 = exec[0]; // extract
  /*# TG68K_ALU.vhd:1054:103 */
  assign n1919 = n1917 | n1918;
  /*# TG68K_ALU.vhd:1054:131 */
  assign n1920 = exec[1]; // extract
  /*# TG68K_ALU.vhd:1054:124 */
  assign n1921 = n1919 | n1920;
  /*# TG68K_ALU.vhd:1054:153 */
  assign n1922 = exec[15]; // extract
  /*# TG68K_ALU.vhd:1054:146 */
  assign n1923 = n1921 | n1922;
  /*# TG68K_ALU.vhd:1054:174 */
  assign n1924 = exec[75]; // extract
  /*# TG68K_ALU.vhd:1054:167 */
  assign n1925 = n1923 | n1924;
  /*# TG68K_ALU.vhd:1054:194 */
  assign n1926 = exec[20]; // extract
  /*# TG68K_ALU.vhd:1054:208 */
  assign n1928 = 1'b1 & n1926;
  /*# TG68K_ALU.vhd:1054:186 */
  assign n1929 = n1925 | n1928;
  /*# TG68K_ALU.vhd:1057:56 */
  assign n1932 = exec[75]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n1933 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1057:49 */
  assign n1934 = n1932 ? bf_nflag : n1933;
  /*# TG68K_ALU.vhd:73:17 */
  assign n1935 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1060:51 */
  assign n1936 = exec[9]; // extract
  /*# TG68K_ALU.vhd:1061:79 */
  assign n1937 = set_flags[3:2]; // extract
  /*# TG68K_ALU.vhd:1063:60 */
  assign n1939 = rot_bits == 2'b00;
  /*# TG68K_ALU.vhd:1063:81 */
  assign n1940 = set_flags[3]; // extract
  /*# TG68K_ALU.vhd:1063:85 */
  assign n1941 = n1940 ^ rot_rot;
  /*# TG68K_ALU.vhd:1063:98 */
  assign n1942 = n1941 | asl_vflag;
  /*# TG68K_ALU.vhd:1063:66 */
  assign n1943 = n1942 & n1939;
  /*# TG68K_ALU.vhd:1063:49 */
  assign n1946 = n1943 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1068:51 */
  assign n1947 = exec[81]; // extract
  /*# TG68K_ALU.vhd:1069:79 */
  assign n1948 = set_flags[3:2]; // extract
  /*# TG68K_ALU.vhd:1072:51 */
  assign n1949 = exec[14]; // extract
  /*# TG68K_ALU.vhd:1073:61 */
  assign n1950 = ~one_bit_in;
  /*# TG68K_ALU.vhd:1074:51 */
  assign n1951 = exec[87]; // extract
  /*# TG68K_ALU.vhd:1079:63 */
  assign n1952 = last_flags1[0]; // extract
  /*# TG68K_ALU.vhd:1079:66 */
  assign n1953 = ~n1952;
  /*# TG68K_ALU.vhd:1080:74 */
  assign n1954 = n2356[0]; // extract
  /*# TG68K_ALU.vhd:1080:95 */
  assign n1955 = set_flags[0]; // extract
  /*# TG68K_ALU.vhd:1080:82 */
  assign n1956 = ~n1955;
  /*# TG68K_ALU.vhd:1080:116 */
  assign n1957 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1080:103 */
  assign n1958 = ~n1957;
  /*# TG68K_ALU.vhd:1080:99 */
  assign n1959 = n1956 & n1958;
  /*# TG68K_ALU.vhd:1080:78 */
  assign n1960 = n1954 | n1959;
  /*# TG68K_ALU.vhd:1082:75 */
  assign n1961 = n2356[0]; // extract
  /*# TG68K_ALU.vhd:1082:92 */
  assign n1962 = set_flags[0]; // extract
  /*# TG68K_ALU.vhd:1082:79 */
  assign n1963 = n1961 ^ n1962;
  /*# TG68K_ALU.vhd:1082:111 */
  assign n1964 = n2356[2]; // extract
  /*# TG68K_ALU.vhd:1082:102 */
  assign n1965 = ~n1964;
  /*# TG68K_ALU.vhd:1082:97 */
  assign n1966 = n1963 & n1965;
  /*# TG68K_ALU.vhd:1082:132 */
  assign n1967 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1082:119 */
  assign n1968 = ~n1967;
  /*# TG68K_ALU.vhd:1082:115 */
  assign n1969 = n1966 & n1968;
  /*# TG68K_ALU.vhd:1079:49 */
  assign n1970 = n1953 ? n1960 : n1969;
  /*# TG68K_ALU.vhd:1085:66 */
  assign n1972 = n2356[2]; // extract
  /*# TG68K_ALU.vhd:1085:82 */
  assign n1973 = set_flags[2]; // extract
  /*# TG68K_ALU.vhd:1085:70 */
  assign n1974 = n1972 | n1973;
  /*# TG68K_ALU.vhd:1086:76 */
  assign n1975 = last_flags1[0]; // extract
  /*# TG68K_ALU.vhd:1086:61 */
  assign n1976 = ~n1975;
  /*# TG68K_ALU.vhd:1087:51 */
  assign n1977 = exec[31]; // extract
  /*# TG68K_ALU.vhd:1088:64 */
  assign n1979 = exe_datatype == 2'b01;
  /*# TG68K_ALU.vhd:1089:75 */
  assign n1980 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:1091:75 */
  assign n1981 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:1088:49 */
  assign n1982 = n1979 ? n1980 : n1981;
  /*# TG68K_ALU.vhd:1093:58 */
  assign n1983 = OP1out[15:0]; // extract
  /*# TG68K_ALU.vhd:1093:71 */
  assign n1985 = n1983 == 16'b0000000000000000;
  /*# TG68K_ALU.vhd:1093:97 */
  assign n1987 = exe_datatype == 2'b01;
  /*# TG68K_ALU.vhd:1093:112 */
  assign n1988 = OP1out[31:16]; // extract
  /*# TG68K_ALU.vhd:1093:126 */
  assign n1990 = n1988 == 16'b0000000000000000;
  /*# TG68K_ALU.vhd:1093:103 */
  assign n1991 = n1987 | n1990;
  /*# TG68K_ALU.vhd:1093:80 */
  assign n1992 = n1991 & n1985;
  /*# TG68K_ALU.vhd:1093:49 */
  assign n1995 = n1992 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1087:41 */
  assign n1998 = {n1982, n1995, 1'b0, 1'b0};
  /*# TG68K_ALU.vhd:73:17 */
  assign n1999 = n1840[3:0]; // extract
  /*# TG68K_ALU.vhd:1087:41 */
  assign n2000 = n1977 ? n1998 : n1999;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n2001 = {n1976, n1974, 1'b0, n1970};
  /*# TG68K_ALU.vhd:1074:41 */
  assign n2002 = n1951 ? n2001 : n2000;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n2003 = n2002[1:0]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n2004 = n1840[1:0]; // extract
  /*# TG68K_ALU.vhd:1072:41 */
  assign n2005 = n1949 ? n2004 : n2003;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n2006 = n2002[2]; // extract
  /*# TG68K_ALU.vhd:1072:41 */
  assign n2007 = n1949 ? n1950 : n2006;
  /*# TG68K_ALU.vhd:1074:41 */
  assign n2008 = n2002[3]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n2009 = n1840[3]; // extract
  /*# TG68K_ALU.vhd:1072:41 */
  assign n2010 = n1949 ? n2009 : n2008;
  /*# TG68K_ALU.vhd:1068:41 */
  assign n2011 = {n2010, n2007, n2005};
  /*# TG68K_ALU.vhd:1068:41 */
  assign n2012 = {n1948, bs_v, bs_c};
  /*# TG68K_ALU.vhd:1068:41 */
  assign n2013 = n1947 ? n2012 : n2011;
  /*# TG68K_ALU.vhd:1060:41 */
  assign n2014 = {n1937, n1946, rot_c};
  /*# TG68K_ALU.vhd:1060:41 */
  assign n2015 = n1936 ? n2014 : n2013;
  /*# TG68K_ALU.vhd:1054:41 */
  assign n2016 = {n1934, n1935, 2'b00};
  /*# TG68K_ALU.vhd:1054:41 */
  assign n2017 = n1929 ? n2016 : n2015;
  /*# TG68K_ALU.vhd:1044:41 */
  assign n2018 = {n1906, n1909, 1'b0, 1'b0};
  /*# TG68K_ALU.vhd:1044:41 */
  assign n2019 = n1905 ? n2018 : n2017;
  /*# TG68K_ALU.vhd:1036:41 */
  assign n2020 = n1886 ? n1902 : n2019;
  /*# TG68K_ALU.vhd:1034:41 */
  assign n2021 = n1883 ? set_flags : n2020;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n2022 = {n1880, n2021};
  /*# TG68K_ALU.vhd:73:17 */
  assign n2023 = n1840[4:0]; // extract
  /*# TG68K_ALU.vhd:1024:33 */
  assign n2024 = n1865 ? n2022 : n2023;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n2025 = n1865 ? n1866 : last_flags1;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n2026 = n2024[3:0]; // extract
  /*# TG68K_ALU.vhd:1014:33 */
  assign n2027 = Z_error ? n1863 : n2026;
  /*# TG68K_ALU.vhd:1024:33 */
  assign n2028 = n2024[4]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n2029 = n1840[4]; // extract
  /*# TG68K_ALU.vhd:1014:33 */
  assign n2030 = Z_error ? n2029 : n2028;
  /*# TG68K_ALU.vhd:1014:33 */
  assign n2031 = Z_error ? last_flags1 : n2025;
  /*# TG68K_ALU.vhd:1012:33 */
  assign n2032 = {n2030, n2027};
  /*# TG68K_ALU.vhd:96:16 */
  assign n2033 = ccrin[4:0]; // extract
  /*# TG68K_ALU.vhd:1012:33 */
  assign n2034 = n1849 ? n2033 : n2032;
  /*# TG68K_ALU.vhd:96:16 */
  assign n2035 = ccrin[7:5]; // extract
  /*# TG68K_ALU.vhd:73:17 */
  assign n2036 = n1840[7:5]; // extract
  /*# TG68K_ALU.vhd:1012:33 */
  assign n2037 = n1849 ? n2035 : n2036;
  /*# TG68K_ALU.vhd:1012:33 */
  assign n2039 = n1849 ? last_flags1 : n2031;
  /*# TG68K_ALU.vhd:999:25 */
  assign n2040 = {n2037, n2034};
  /*# TG68K_ALU.vhd:999:25 */
  assign n2041 = clkena_lw ? n2040 : n2356;
  /*# TG68K_ALU.vhd:999:25 */
  assign n2042 = clkena_lw ? n2039 : last_flags1;
  /*# TG68K_ALU.vhd:999:25 */
  assign n2043 = clkena_lw ? n1848 : asl_vflag;
  /*# TG68K_ALU.vhd:997:25 */
  assign n2045 = Reset ? 8'b00000000 : n2041;
  /*# TG68K_ALU.vhd:997:25 */
  assign n2046 = Reset ? last_flags1 : n2042;
  /*# TG68K_ALU.vhd:997:25 */
  assign n2047 = Reset ? asl_vflag : n2043;
  /*# TG68K_ALU.vhd:73:17 */
  assign n2049 = n2045[4:0]; // extract
  /*# TG68K_ALU.vhd:996:17 */
  assign n2050 = {3'b000, n2049};
  /*# TG68K_ALU.vhd:1162:45 */
  assign n2057 = faktorb[31]; // extract
  /*# TG68K_ALU.vhd:1162:34 */
  assign n2058 = n2057 & signedop;
  /*# TG68K_ALU.vhd:1162:55 */
  assign n2059 = n2058 | fasign;
  /*# TG68K_ALU.vhd:1163:45 */
  assign n2060 = mulu_reg[63]; // extract
  /*# TG68K_ALU.vhd:1162:17 */
  assign n2062 = n2059 ? n2060 : 1'b0;
  /*# TG68K_ALU.vhd:1168:44 */
  assign n2063 = faktorb[31]; // extract
  /*# TG68K_ALU.vhd:1168:33 */
  assign n2064 = n2063 & signedop;
  /*# TG68K_ALU.vhd:1168:17 */
  assign n2067 = n2064 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1185:70 */
  assign n2068 = mulu_reg[63:1]; // extract
  /*# TG68K_ALU.vhd:1185:61 */
  assign n2069 = {muls_msb, n2068};
  /*# TG68K_ALU.vhd:1186:36 */
  assign n2070 = mulu_reg[0]; // extract
  /*# TG68K_ALU.vhd:1188:88 */
  assign n2071 = mulu_reg[63:32]; // extract
  /*# TG68K_ALU.vhd:1188:79 */
  assign n2072 = {muls_msb, n2071};
  /*# TG68K_ALU.vhd:1188:113 */
  assign n2073 = {mulu_sign, faktorb};
  /*# TG68K_ALU.vhd:1188:102 */
  assign n2074 = n2072 - n2073;
  /*# TG68K_ALU.vhd:1190:88 */
  assign n2075 = mulu_reg[63:32]; // extract
  /*# TG68K_ALU.vhd:1190:79 */
  assign n2076 = {muls_msb, n2075};
  /*# TG68K_ALU.vhd:1190:113 */
  assign n2077 = {mulu_sign, faktorb};
  /*# TG68K_ALU.vhd:1190:102 */
  assign n2078 = n2076 + n2077;
  /*# TG68K_ALU.vhd:1187:33 */
  assign n2079 = fasign ? n2074 : n2078;
  /*# TG68K_ALU.vhd:106:16 */
  assign n2080 = n2069[63:31]; // extract
  /*# TG68K_ALU.vhd:1186:25 */
  assign n2081 = n2070 ? n2079 : n2080;
  /*# TG68K_ALU.vhd:106:16 */
  assign n2082 = n2069[30:0]; // extract
  /*# TG68K_ALU.vhd:1194:30 */
  assign n2083 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:1194:39 */
  assign n2085 = n2083 | 1'b0;
  /*# TG68K_ALU.vhd:1195:56 */
  assign n2086 = OP2out[15:0]; // extract
  /*# TG68K_ALU.vhd:1194:17 */
  assign n2088 = {n2086, 16'b0000000000000000};
  /*# TG68K_ALU.vhd:1194:17 */
  assign n2089 = n2085 ? n2088 : OP2out;
  /*# TG68K_ALU.vhd:1227:77 */
  assign n2112 = result_mulu[63:32]; // extract
  /*# TG68K_ALU.vhd:1240:32 */
  assign n2120 = opcode[15]; // extract
  /*# TG68K_ALU.vhd:1240:47 */
  assign n2121 = opcode[8]; // extract
  /*# TG68K_ALU.vhd:1240:37 */
  assign n2122 = n2120 & n2121;
  /*# TG68K_ALU.vhd:1240:66 */
  assign n2123 = opcode[15]; // extract
  /*# TG68K_ALU.vhd:1240:56 */
  assign n2124 = ~n2123;
  /*# TG68K_ALU.vhd:1240:81 */
  assign n2125 = sndOPC[11]; // extract
  /*# TG68K_ALU.vhd:1240:71 */
  assign n2126 = n2124 & n2125;
  /*# TG68K_ALU.vhd:1240:52 */
  assign n2127 = n2122 | n2126;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2129 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2130 = divs & n2129;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2131 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2132 = divs & n2131;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2133 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2134 = divs & n2133;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2135 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2136 = divs & n2135;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2137 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2138 = divs & n2137;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2139 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2140 = divs & n2139;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2141 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2142 = divs & n2141;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2143 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2144 = divs & n2143;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2145 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2146 = divs & n2145;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2147 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2148 = divs & n2147;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2149 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2150 = divs & n2149;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2151 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2152 = divs & n2151;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2153 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2154 = divs & n2153;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2155 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2156 = divs & n2155;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2157 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2158 = divs & n2157;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2159 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2160 = divs & n2159;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2161 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2162 = divs & n2161;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2163 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2164 = divs & n2163;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2165 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2166 = divs & n2165;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2167 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2168 = divs & n2167;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2169 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2170 = divs & n2169;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2171 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2172 = divs & n2171;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2173 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2174 = divs & n2173;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2175 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2176 = divs & n2175;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2177 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2178 = divs & n2177;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2179 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2180 = divs & n2179;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2181 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2182 = divs & n2181;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2183 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2184 = divs & n2183;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2185 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2186 = divs & n2185;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2187 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2188 = divs & n2187;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2189 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2190 = divs & n2189;
  /*# TG68K_ALU.vhd:1242:68 */
  assign n2191 = reg_QA[31]; // extract
  /*# TG68K_ALU.vhd:1242:58 */
  assign n2192 = divs & n2191;
  /*# TG68K_ALU.vhd:1242:43 */
  assign n2193 = {n2130, n2132, n2134, n2136, n2138, n2140, n2142, n2144, n2146, n2148, n2150, n2152, n2154, n2156, n2158, n2160, n2162, n2164, n2166, n2168, n2170, n2172, n2174, n2176, n2178, n2180, n2182, n2184, n2186, n2188, n2190, n2192};
  /*# TG68K_ALU.vhd:1243:30 */
  assign n2194 = exe_opcode[15]; // extract
  /*# TG68K_ALU.vhd:1243:39 */
  assign n2196 = n2194 | 1'b0;
  /*# TG68K_ALU.vhd:1245:52 */
  assign n2197 = result_div_pre[15]; // extract
  /*# TG68K_ALU.vhd:1248:38 */
  assign n2198 = exe_opcode[14]; // extract
  /*# TG68K_ALU.vhd:1248:57 */
  assign n2199 = sndOPC[10]; // extract
  /*# TG68K_ALU.vhd:1248:47 */
  assign n2200 = n2199 & n2198;
  /*# TG68K_ALU.vhd:1248:25 */
  assign n2201 = n2200 ? reg_QB : n2193;
  /*# TG68K_ALU.vhd:1251:52 */
  assign n2202 = result_div_pre[31]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2203 = n2196 ? n2197 : n2202;
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2204 = {n2201, reg_QA};
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2205 = n2204[15:0]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2206 = n2196 ? 16'b0000000000000000 : n2205;
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2207 = n2204[47:16]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2208 = n2196 ? reg_QA : n2207;
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2209 = n2204[63:48]; // extract
  /*# TG68K_ALU.vhd:143:16 */
  assign n2210 = n2193[31:16]; // extract
  /*# TG68K_ALU.vhd:1243:17 */
  assign n2211 = n2196 ? n2210 : n2209;
  /*# TG68K_ALU.vhd:1253:42 */
  assign n2213 = opcode[15]; // extract
  /*# TG68K_ALU.vhd:1253:46 */
  assign n2214 = ~n2213;
  /*# TG68K_ALU.vhd:1253:33 */
  assign n2215 = signedop | n2214;
  /*# TG68K_ALU.vhd:1254:44 */
  assign n2216 = OP2out[31:16]; // extract
  /*# TG68K_ALU.vhd:1253:17 */
  assign n2218 = n2215 ? n2216 : 16'b0000000000000000;
  /*# TG68K_ALU.vhd:1258:43 */
  assign n2219 = OP2out[31]; // extract
  /*# TG68K_ALU.vhd:1258:33 */
  assign n2220 = n2219 & signedop;
  /*# TG68K_ALU.vhd:1259:44 */
  assign n2221 = div_reg[63:31]; // extract
  /*# TG68K_ALU.vhd:1259:64 */
  assign n2223 = {1'b1, OP2out};
  /*# TG68K_ALU.vhd:1259:59 */
  assign n2224 = n2221 + n2223;
  /*# TG68K_ALU.vhd:1261:44 */
  assign n2225 = div_reg[63:31]; // extract
  /*# TG68K_ALU.vhd:1261:64 */
  assign n2227 = {1'b0, op2outext};
  /*# TG68K_ALU.vhd:1261:94 */
  assign n2228 = OP2out[15:0]; // extract
  /*# TG68K_ALU.vhd:1261:87 */
  assign n2229 = {n2227, n2228};
  /*# TG68K_ALU.vhd:1261:59 */
  assign n2230 = n2225 - n2229;
  /*# TG68K_ALU.vhd:1258:17 */
  assign n2231 = n2220 ? n2224 : n2230;
  /*# TG68K_ALU.vhd:1266:43 */
  assign n2232 = div_sub[32]; // extract
  /*# TG68K_ALU.vhd:1269:58 */
  assign n2233 = div_reg[62:31]; // extract
  /*# TG68K_ALU.vhd:1271:58 */
  assign n2234 = div_sub[31:0]; // extract
  /*# TG68K_ALU.vhd:1268:17 */
  assign n2235 = div_bit ? n2233 : n2234;
  /*# TG68K_ALU.vhd:1273:49 */
  assign n2236 = div_reg[30:0]; // extract
  /*# TG68K_ALU.vhd:1273:63 */
  assign n2237 = ~div_bit;
  /*# TG68K_ALU.vhd:1273:62 */
  assign n2238 = {n2236, n2237};
  /*# TG68K_ALU.vhd:1276:66 */
  assign n2239 = div_quot[31:0]; // extract
  /*# TG68K_ALU.vhd:1276:57 */
  assign n2241 = 32'b00000000000000000000000000000000 - n2239;
  /*# TG68K_ALU.vhd:1279:64 */
  assign n2242 = div_quot[31:0]; // extract
  /*# TG68K_ALU.vhd:1275:17 */
  assign n2243 = div_neg ? n2241 : n2242;
  /*# TG68K_ALU.vhd:1282:44 */
  assign n2244 = ~div_bit;
  /*# TG68K_ALU.vhd:1282:34 */
  assign n2245 = nozero | n2244;
  /*# TG68K_ALU.vhd:1282:50 */
  assign n2246 = signedop & n2245;
  /*# TG68K_ALU.vhd:1282:78 */
  assign n2247 = OP2out[31]; // extract
  /*# TG68K_ALU.vhd:1282:83 */
  assign n2248 = n2247 ^ op1_sign;
  /*# TG68K_ALU.vhd:1282:96 */
  assign n2249 = n2248 ^ div_qsign;
  /*# TG68K_ALU.vhd:1282:67 */
  assign n2250 = n2249 & n2246;
  /*# TG68K_ALU.vhd:1283:37 */
  assign n2251 = ~signedop;
  /*# TG68K_ALU.vhd:1283:54 */
  assign n2252 = div_over[32]; // extract
  /*# TG68K_ALU.vhd:1283:58 */
  assign n2253 = ~n2252;
  /*# TG68K_ALU.vhd:1283:42 */
  assign n2254 = n2253 & n2251;
  /*# TG68K_ALU.vhd:1283:25 */
  assign n2255 = n2250 | n2254;
  /*# TG68K_ALU.vhd:1283:65 */
  assign n2257 = 1'b1 & n2255;
  /*# TG68K_ALU.vhd:1282:17 */
  assign n2260 = n2257 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1294:47 */
  assign n2266 = micro_state != 8'b01011100;
  /*# TG68K_ALU.vhd:1298:47 */
  assign n2269 = micro_state == 8'b01010111;
  /*# TG68K_ALU.vhd:1300:65 */
  assign n2270 = dividend[63]; // extract
  /*# TG68K_ALU.vhd:1300:53 */
  assign n2271 = n2270 & divs;
  /*# TG68K_ALU.vhd:1302:61 */
  assign n2273 = 64'b0000000000000000000000000000000000000000000000000000000000000000 - dividend;
  /*# TG68K_ALU.vhd:1300:41 */
  assign n2274 = n2271 ? n2273 : dividend;
  /*# TG68K_ALU.vhd:1300:41 */
  assign n2277 = n2271 ? 1'b1 : 1'b0;
  /*# TG68K_ALU.vhd:1309:51 */
  assign n2278 = ~div_bit;
  /*# TG68K_ALU.vhd:1309:63 */
  assign n2279 = n2278 | nozero;
  /*# TG68K_ALU.vhd:1298:33 */
  assign n2280 = n2269 ? n2274 : div_quot;
  /*# TG68K_ALU.vhd:1298:33 */
  assign n2282 = n2269 ? 1'b0 : n2279;
  /*# TG68K_ALU.vhd:1311:47 */
  assign n2285 = micro_state == 8'b01011000;
  /*# TG68K_ALU.vhd:1312:72 */
  assign n2286 = OP2out[31]; // extract
  /*# TG68K_ALU.vhd:1312:77 */
  assign n2287 = n2286 ^ op1_sign;
  /*# TG68K_ALU.vhd:1312:61 */
  assign n2288 = signedop & n2287;
  /*# TG68K_ALU.vhd:1316:73 */
  assign n2289 = div_reg[63:32]; // extract
  /*# TG68K_ALU.vhd:1316:65 */
  assign n2291 = {1'b0, n2289};
  /*# TG68K_ALU.vhd:1316:93 */
  assign n2293 = {1'b0, op2outext};
  /*# TG68K_ALU.vhd:1316:123 */
  assign n2294 = OP2out[15:0]; // extract
  /*# TG68K_ALU.vhd:1316:116 */
  assign n2295 = {n2293, n2294};
  /*# TG68K_ALU.vhd:1316:88 */
  assign n2296 = n2291 - n2295;
  /*# TG68K_ALU.vhd:1319:40 */
  assign n2299 = exec[68]; // extract
  /*# TG68K_ALU.vhd:1319:56 */
  assign n2300 = ~n2299;
  /*# TG68K_ALU.vhd:1322:87 */
  assign n2301 = div_quot[63:32]; // extract
  /*# TG68K_ALU.vhd:1322:78 */
  assign n2303 = 32'b00000000000000000000000000000000 - n2301;
  /*# TG68K_ALU.vhd:1324:85 */
  assign n2304 = div_quot[63:32]; // extract
  /*# TG68K_ALU.vhd:1321:41 */
  assign n2305 = op1_sign ? n2303 : n2304;
  /*# TG68K_ALU.vhd:1319:33 */
  assign n2306 = {n2305, result_div_pre};
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2308 = n2300 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2309 = n2266 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2311 = n2285 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2312 = n2285 & clkena_lw;
  /*# TG68K_ALU.vhd:1293:25 */
  assign n2315 = n2269 & clkena_lw;
  /*# TG68K_ALU.vhd:86:16 */
  assign n2325 = {n104, n101};
  /*# TG68K_ALU.vhd:91:16 */
  assign n2326 = {n255, n248, n241};
  /*# TG68K_ALU.vhd:93:16 */
  assign n2327 = {n233, n232, n227, n185};
  /*# TG68K_ALU.vhd:101:16 */
  assign n2328 = {n277, n315};
  /*# TG68K_ALU.vhd:106:16 */
  assign n2330 = {64'bZ, n2081, n2082};
  /*# TG68K_ALU.vhd:129:16 */
  assign n2334 = {32'bZ, n2369};
  /*# TG68K_ALU.vhd:135:16 */
  assign n2337 = {n2235, n2238};
  /*# TG68K_ALU.vhd:143:16 */
  assign n2339 = {n2211, n2208, n2206};
  /*# TG68K_ALU.vhd:151:16 */
  assign n2342 = {n823, n812, n800, n788, n776, n764, n752, n740, n728, n716, n704, n692, n680, n668, n656, n644, n632, n620, n608, n596, n584, n572, n560, n548, n536, n524, n512, n500, n488, n476, n464, n451};
  /*# TG68K_ALU.vhd:154:16 */
  assign n2344 = {n1118, n1114, n1109, n1104, n1099, n1094, n1089, n1084, n1079, n1074, n1069, n1064, n1059, n1054, n1049, n1044, n1039, n1034, n1029, n1024, n1019, n1014, n1009, n1004, n999, n994, n989, n984, n979, n974, n969, n964, n959, n954, n949, n944, n939, n934, n929, n924};
  /*# TG68K_ALU.vhd:156:16 */
  assign n2345 = {n824, n815, n803, n791, n779, n767, n755, n743, n731, n719, n707, n695, n683, n671, n659, n647, n635, n623, n611, n599, n587, n575, n563, n551, n539, n527, n515, n503, n491, n479, n467, n454};
  /*# TG68K_ALU.vhd:168:16 */
  assign n2347 = {n880, n881};
  /*# TG68K_ALU.vhd:171:16 */
  assign n2348 = {n1202, n1231, n1228};
  /*# TG68K_ALU.vhd:188:16 */
  assign n2350 = {n1733, n1731, n1728, n1725, n1722, n1735};
  /*# TG68K_ALU.vhd:195:16 */
  assign n2351 = {n1403, n1400, n1404, n1398, n1402};
  /*# TG68K_ALU.vhd:196:16 */
  assign n2352 = {n1668, n1670};
  /*# TG68K_ALU.vhd:200:16 */
  assign n2353 = {n1745, n1742, n1747};
  /*# TG68K_ALU.vhd:446:17 */
  assign n2354 = clkena_lw ? n426 : n2355;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2355 <= n2354;
  /*# TG68K_ALU.vhd:996:17 */
  always @(posedge clk)
    n2356 <= n2050;
  /*# TG68K_ALU.vhd:996:17 */
  always @(posedge clk)
    n2357 <= n2046;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2358 = n2308 ? n2306 : result_div;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2359 <= n2358;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2360 = n2309 ? n2260 : v_flag;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2361 <= n2360;
  /*# TG68K_ALU.vhd:996:17 */
  always @(posedge clk)
    n2362 <= n2047;
  /*# TG68K_ALU.vhd:405:17 */
  assign n2363 = clkena_lw ? n336 : bchg;
  /*# TG68K_ALU.vhd:405:17 */
  always @(posedge clk)
    n2364 <= n2363;
  /*# TG68K_ALU.vhd:405:17 */
  assign n2365 = clkena_lw ? n340 : bset;
  /*# TG68K_ALU.vhd:405:17 */
  always @(posedge clk)
    n2366 <= n2365;
  /*# TG68K_ALU.vhd:1211:17 */
  assign n2367 = mulu_reg[31:0]; // extract
  /*# TG68K_ALU.vhd:1211:17 */
  assign n2368 = clkena_lw ? n2112 : n2367;
  /*# TG68K_ALU.vhd:1211:17 */
  always @(posedge clk)
    n2369 <= n2368;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2370 = clkena_lw ? n2280 : div_reg;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2371 <= n2370;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2372 = n2311 ? n2288 : div_neg;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2373 <= n2372;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2374 = n2312 ? n2296 : div_over;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2375 <= n2374;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2376 = clkena_lw ? n2282 : nozero;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2377 <= n2376;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2378 = clkena_lw ? divs : signedop;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2379 <= n2378;
  /*# TG68K_ALU.vhd:1292:17 */
  assign n2380 = n2315 ? n2277 : op1_sign;
  /*# TG68K_ALU.vhd:1292:17 */
  always @(posedge clk)
    n2381 <= n2380;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2382 = clkena_lw ? n399 : bf_bset;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2383 <= n2382;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2384 = clkena_lw ? n403 : bf_bchg;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2385 <= n2384;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2386 = clkena_lw ? n407 : bf_ins;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2387 <= n2386;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2388 = clkena_lw ? n411 : bf_exts;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2389 <= n2388;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2390 = clkena_lw ? n415 : bf_fffo;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2391 <= n2390;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2392 = clkena_lw ? n424 : bf_d32;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2393 <= n2392;
  /*# TG68K_ALU.vhd:446:17 */
  assign n2394 = clkena_lw ? n418 : bf_s32;
  /*# TG68K_ALU.vhd:446:17 */
  always @(posedge clk)
    n2395 <= n2394;
  /*# TG68K_ALU.vhd:433:38 */
  assign n2396 = OP1out[bit_number * 1 +: 1]; //(Bmux)
  /*# TG68K_ALU.vhd:435:17 */
  assign n2397 = bit_number[4]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2398 = ~n2397;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2399 = bit_number[3]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2400 = ~n2399;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2401 = n2398 & n2400;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2402 = n2398 & n2399;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2403 = n2397 & n2400;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2404 = n2397 & n2399;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2405 = bit_number[2]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2406 = ~n2405;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2407 = n2401 & n2406;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2408 = n2401 & n2405;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2409 = n2402 & n2406;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2410 = n2402 & n2405;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2411 = n2403 & n2406;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2412 = n2403 & n2405;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2413 = n2404 & n2406;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2414 = n2404 & n2405;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2415 = bit_number[1]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2416 = ~n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2417 = n2407 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2418 = n2407 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2419 = n2408 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2420 = n2408 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2421 = n2409 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2422 = n2409 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2423 = n2410 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2424 = n2410 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2425 = n2411 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2426 = n2411 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2427 = n2412 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2428 = n2412 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2429 = n2413 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2430 = n2413 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2431 = n2414 & n2416;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2432 = n2414 & n2415;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2433 = bit_number[0]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2434 = ~n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2435 = n2417 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2436 = n2417 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2437 = n2418 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2438 = n2418 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2439 = n2419 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2440 = n2419 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2441 = n2420 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2442 = n2420 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2443 = n2421 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2444 = n2421 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2445 = n2422 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2446 = n2422 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2447 = n2423 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2448 = n2423 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2449 = n2424 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2450 = n2424 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2451 = n2425 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2452 = n2425 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2453 = n2426 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2454 = n2426 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2455 = n2427 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2456 = n2427 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2457 = n2428 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2458 = n2428 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2459 = n2429 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2460 = n2429 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2461 = n2430 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2462 = n2430 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2463 = n2431 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2464 = n2431 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2465 = n2432 & n2434;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2466 = n2432 & n2433;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2467 = OP1out[0]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2468 = n2435 ? n372 : n2467;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2469 = OP1out[1]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2470 = n2436 ? n372 : n2469;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2471 = OP1out[2]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2472 = n2437 ? n372 : n2471;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2473 = OP1out[3]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2474 = n2438 ? n372 : n2473;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2475 = OP1out[4]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2476 = n2439 ? n372 : n2475;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2477 = OP1out[5]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2478 = n2440 ? n372 : n2477;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2479 = OP1out[6]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2480 = n2441 ? n372 : n2479;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2481 = OP1out[7]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2482 = n2442 ? n372 : n2481;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2483 = OP1out[8]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2484 = n2443 ? n372 : n2483;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2485 = OP1out[9]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2486 = n2444 ? n372 : n2485;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2487 = OP1out[10]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2488 = n2445 ? n372 : n2487;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2489 = OP1out[11]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2490 = n2446 ? n372 : n2489;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2491 = OP1out[12]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2492 = n2447 ? n372 : n2491;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2493 = OP1out[13]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2494 = n2448 ? n372 : n2493;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2495 = OP1out[14]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2496 = n2449 ? n372 : n2495;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2497 = OP1out[15]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2498 = n2450 ? n372 : n2497;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2499 = OP1out[16]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2500 = n2451 ? n372 : n2499;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2501 = OP1out[17]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2502 = n2452 ? n372 : n2501;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2503 = OP1out[18]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2504 = n2453 ? n372 : n2503;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2505 = OP1out[19]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2506 = n2454 ? n372 : n2505;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2507 = OP1out[20]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2508 = n2455 ? n372 : n2507;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2509 = OP1out[21]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2510 = n2456 ? n372 : n2509;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2511 = OP1out[22]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2512 = n2457 ? n372 : n2511;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2513 = OP1out[23]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2514 = n2458 ? n372 : n2513;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2515 = OP1out[24]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2516 = n2459 ? n372 : n2515;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2517 = OP1out[25]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2518 = n2460 ? n372 : n2517;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2519 = OP1out[26]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2520 = n2461 ? n372 : n2519;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2521 = OP1out[27]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2522 = n2462 ? n372 : n2521;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2523 = OP1out[28]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2524 = n2463 ? n372 : n2523;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2525 = OP1out[29]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2526 = n2464 ? n372 : n2525;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2527 = OP1out[30]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2528 = n2465 ? n372 : n2527;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2529 = OP1out[31]; // extract
  /*# TG68K_ALU.vhd:435:17 */
  assign n2530 = n2466 ? n372 : n2529;
  /*# TG68K_ALU.vhd:435:17 */
  assign n2531 = {n2530, n2528, n2526, n2524, n2522, n2520, n2518, n2516, n2514, n2512, n2510, n2508, n2506, n2504, n2502, n2500, n2498, n2496, n2494, n2492, n2490, n2488, n2486, n2484, n2482, n2480, n2478, n2476, n2474, n2472, n2470, n2468};
  /*# TG68K_ALU.vhd:496:37 */
  assign n2532 = datareg[n826 * 1 +: 1]; //(Bmux)
  /*# TG68K_ALU.vhd:761:17 */
  assign n2533 = bit_msb[5]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2534 = ~n2533;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2535 = bit_msb[4]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2536 = ~n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2537 = n2534 & n2536;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2538 = n2534 & n2535;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2539 = n2533 & n2536;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2540 = bit_msb[3]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2541 = ~n2540;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2542 = n2537 & n2541;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2543 = n2537 & n2540;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2544 = n2538 & n2541;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2545 = n2538 & n2540;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2546 = n2539 & n2541;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2547 = bit_msb[2]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2548 = ~n2547;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2549 = n2542 & n2548;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2550 = n2542 & n2547;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2551 = n2543 & n2548;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2552 = n2543 & n2547;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2553 = n2544 & n2548;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2554 = n2544 & n2547;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2555 = n2545 & n2548;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2556 = n2545 & n2547;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2557 = n2546 & n2548;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2558 = bit_msb[1]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2559 = ~n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2560 = n2549 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2561 = n2549 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2562 = n2550 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2563 = n2550 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2564 = n2551 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2565 = n2551 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2566 = n2552 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2567 = n2552 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2568 = n2553 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2569 = n2553 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2570 = n2554 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2571 = n2554 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2572 = n2555 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2573 = n2555 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2574 = n2556 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2575 = n2556 & n2558;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2576 = n2557 & n2559;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2577 = bit_msb[0]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2578 = ~n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2579 = n2560 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2580 = n2560 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2581 = n2561 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2582 = n2561 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2583 = n2562 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2584 = n2562 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2585 = n2563 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2586 = n2563 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2587 = n2564 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2588 = n2564 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2589 = n2565 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2590 = n2565 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2591 = n2566 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2592 = n2566 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2593 = n2567 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2594 = n2567 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2595 = n2568 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2596 = n2568 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2597 = n2569 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2598 = n2569 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2599 = n2570 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2600 = n2570 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2601 = n2571 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2602 = n2571 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2603 = n2572 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2604 = n2572 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2605 = n2573 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2606 = n2573 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2607 = n2574 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2608 = n2574 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2609 = n2575 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2610 = n2575 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2611 = n2576 & n2578;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2612 = n2576 & n2577;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2613 = n1369[0]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2614 = n2579 ? 1'b1 : n2613;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2615 = n1369[1]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2616 = n2580 ? 1'b1 : n2615;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2617 = n1369[2]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2618 = n2581 ? 1'b1 : n2617;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2619 = n1369[3]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2620 = n2582 ? 1'b1 : n2619;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2621 = n1369[4]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2622 = n2583 ? 1'b1 : n2621;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2623 = n1369[5]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2624 = n2584 ? 1'b1 : n2623;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2625 = n1369[6]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2626 = n2585 ? 1'b1 : n2625;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2627 = n1369[7]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2628 = n2586 ? 1'b1 : n2627;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2629 = n1369[8]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2630 = n2587 ? 1'b1 : n2629;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2631 = n1369[9]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2632 = n2588 ? 1'b1 : n2631;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2633 = n1369[10]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2634 = n2589 ? 1'b1 : n2633;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2635 = n1369[11]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2636 = n2590 ? 1'b1 : n2635;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2637 = n1369[12]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2638 = n2591 ? 1'b1 : n2637;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2639 = n1369[13]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2640 = n2592 ? 1'b1 : n2639;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2641 = n1369[14]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2642 = n2593 ? 1'b1 : n2641;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2643 = n1369[15]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2644 = n2594 ? 1'b1 : n2643;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2645 = n1369[16]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2646 = n2595 ? 1'b1 : n2645;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2647 = n1369[17]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2648 = n2596 ? 1'b1 : n2647;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2649 = n1369[18]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2650 = n2597 ? 1'b1 : n2649;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2651 = n1369[19]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2652 = n2598 ? 1'b1 : n2651;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2653 = n1369[20]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2654 = n2599 ? 1'b1 : n2653;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2655 = n1369[21]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2656 = n2600 ? 1'b1 : n2655;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2657 = n1369[22]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2658 = n2601 ? 1'b1 : n2657;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2659 = n1369[23]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2660 = n2602 ? 1'b1 : n2659;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2661 = n1369[24]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2662 = n2603 ? 1'b1 : n2661;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2663 = n1369[25]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2664 = n2604 ? 1'b1 : n2663;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2665 = n1369[26]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2666 = n2605 ? 1'b1 : n2665;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2667 = n1369[27]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2668 = n2606 ? 1'b1 : n2667;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2669 = n1369[28]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2670 = n2607 ? 1'b1 : n2669;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2671 = n1369[29]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2672 = n2608 ? 1'b1 : n2671;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2673 = n1369[30]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2674 = n2609 ? 1'b1 : n2673;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2675 = n1369[31]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2676 = n2610 ? 1'b1 : n2675;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2677 = n1369[32]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2678 = n2611 ? 1'b1 : n2677;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2679 = n1369[33]; // extract
  /*# TG68K_ALU.vhd:761:17 */
  assign n2680 = n2612 ? 1'b1 : n2679;
  /*# TG68K_ALU.vhd:761:17 */
  assign n2681 = {n2680, n2678, n2676, n2674, n2672, n2670, n2668, n2666, n2664, n2662, n2660, n2658, n2656, n2654, n2652, n2650, n2648, n2646, n2644, n2642, n2640, n2638, n2636, n2634, n2632, n2630, n2628, n2626, n2624, n2622, n2620, n2618, n2616, n2614};
endmodule

