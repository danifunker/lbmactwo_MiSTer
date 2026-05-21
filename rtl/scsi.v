/* verilator lint_off UNUSED */

// scsi.v
// implements a target only scsi device
  
module scsi
(
	input      clk,

	// scsi interface
	input 	  rst, // bus reset from initiator
	input 	  sel,
	input 	  atn, // initiator requests to send a message
	output 	  bsy, // target holds bus

	output 	  msg,
	output 	  cd,
	output 	  io,

	output 	  req,
	input 	  ack, // initiator acknowledges a request

	input   [7:0] din, // data from initiator to target
	output  [7:0] dout, // data from target to initiator
	output [15:0] dout_pair,
	output [15:0] dout_pair_next,

	// interface to io controller
	input         img_mounted,
	input  [31:0] img_blocks,
	output [31:0] io_lba,
	output reg 	  io_rd,
	output reg 	  io_wr,
	input         io_ack,

	input   [7:0] sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr,

	output        dbg_mounted   // JTAG debug: is a disk mounted on this target?
);

// SCSI device id
parameter [2:0] ID = 0;

assign dbg_mounted = mounted;

localparam PHASE_IDLE        = 3'd0;
localparam PHASE_CMD_IN      = 3'd1;
localparam PHASE_DATA_OUT    = 3'd2;
localparam PHASE_DATA_IN     = 3'd3;
localparam PHASE_STATUS_OUT  = 3'd4;
localparam PHASE_MESSAGE_OUT = 3'd5;
reg [2:0]  phase;

// ------------ sector buffer IO controller read/write -----------------------
// the buffer itself. Can hold two sectors
reg sd_buff_sel;

wire [7:0] buffer0_dout;
wire [7:0] buffer0_dout_next;
wire [7:0] buffer0_dout_next2;
scsi_dpram buffer0
(
	.clock(clk),

	.address_a({sd_buff_sel, sd_buff_addr}),
	.data_a(sd_buff_dout[15:8]),
	.wren_a(sd_buff_wr),
	.q_a(sd_buff_din[15:8]),

	.address_b(data_cnt[9:1]),
	.data_b(din),
	.wren_b(buffer0_wr),
	.q_b(buffer0_dout),

	.address_c(data_cnt[9:1] + 9'd1),
	.q_c(buffer0_dout_next),

	.address_d(data_cnt[9:1] + 9'd2),
	.q_d(buffer0_dout_next2)
);

wire [7:0] buffer1_dout;
wire [7:0] buffer1_dout_next;
wire [7:0] buffer1_dout_next2;
scsi_dpram buffer1
(
	.clock(clk),

	.address_a({sd_buff_sel, sd_buff_addr}),
	.data_a(sd_buff_dout[7:0]),
	.wren_a(sd_buff_wr),
	.q_a(sd_buff_din[7:0]),

	.address_b(data_cnt[9:1]),
	.data_b(din),
	.wren_b(buffer1_wr),
	.q_b(buffer1_dout),

	.address_c(data_cnt[9:1] + 9'd1),
	.q_c(buffer1_dout_next),

	.address_d(data_cnt[9:1] + 9'd2),
	.q_d(buffer1_dout_next2)
);

reg old_io_ack;
always @(posedge clk) begin
	old_io_ack <= io_ack;
	if (phase == PHASE_IDLE)
		sd_buff_sel <= 0;
	else
		if (old_io_ack & ~io_ack) sd_buff_sel <= !sd_buff_sel;
end

// -----------------------------------------------------------

// status replies
reg [7:0]  status;
`define STATUS_OK 8'h00
`define STATUS_CHECK_CONDITION 8'h02

// message codes
`define MSG_CMD_COMPLETE 8'h00
	
// drive scsi signals according to phase
assign msg = (phase == PHASE_MESSAGE_OUT);
assign cd = (phase == PHASE_CMD_IN) || (phase == PHASE_STATUS_OUT) || (phase == PHASE_MESSAGE_OUT);
assign io = (phase == PHASE_DATA_OUT) || (phase == PHASE_STATUS_OUT) || (phase == PHASE_MESSAGE_OUT);

wire   io_busy = (phase == PHASE_DATA_OUT && (io_rd | io_ack) && data_cnt[9] == sd_buff_sel) ||
                 (phase == PHASE_DATA_IN  && (io_wr | io_ack) && data_cnt[9] == sd_buff_sel) ||
                 (phase != PHASE_DATA_OUT && phase != PHASE_DATA_IN && (io_rd | io_wr | io_ack));
	wire data_phase_complete = ((phase == PHASE_DATA_OUT) || (phase == PHASE_DATA_IN)) && data_complete;
	assign req = (phase != PHASE_IDLE) && !ack && !io_busy && !data_phase_complete;

assign bsy = (phase != PHASE_IDLE);

assign dout = (phase == PHASE_STATUS_OUT)?status:
	 (phase == PHASE_MESSAGE_OUT)?`MSG_CMD_COMPLETE:
	 (phase == PHASE_DATA_OUT)?cmd_dout:
	 8'h00;
assign dout_pair = (phase == PHASE_STATUS_OUT)?{status, status}:
	 (phase == PHASE_MESSAGE_OUT)?{`MSG_CMD_COMPLETE, `MSG_CMD_COMPLETE}:
	 (phase == PHASE_DATA_OUT)?cmd_dout_pair:
	 16'h0000;
assign dout_pair_next = (phase == PHASE_STATUS_OUT)?{status, status}:
	 (phase == PHASE_MESSAGE_OUT)?{`MSG_CMD_COMPLETE, `MSG_CMD_COMPLETE}:
	 (phase == PHASE_DATA_OUT)?cmd_dout_pair_next:
	 16'h0000;

// de-multiplex different data sources
wire [7:0] cmd_dout =
		cmd_read?(data_cnt[0] ? buffer1_dout : buffer0_dout):
		cmd_inquiry?inquiry_dout:
		cmd_read_capacity?read_capacity_dout:
		cmd_mode_sense?mode_sense_dout:
		8'h00;
wire [15:0] cmd_dout_pair =
		cmd_read?(data_cnt[0] ? {buffer1_dout, buffer0_dout_next} : {buffer0_dout, buffer1_dout}):
		cmd_inquiry?{inquiry_dout, inquiry_dout_next}:
		cmd_read_capacity?{read_capacity_dout, read_capacity_dout_next}:
		cmd_mode_sense?{mode_sense_dout, mode_sense_dout_next}:
		16'h0000;
wire [15:0] cmd_dout_pair_next =
		cmd_read?(data_cnt[0] ? {buffer1_dout_next, buffer0_dout_next2} : {buffer0_dout_next, buffer1_dout_next}):
		cmd_inquiry?{inquiry_dout_next2, inquiry_dout_next3}:
		cmd_read_capacity?{read_capacity_dout_next2, read_capacity_dout_next3}:
		cmd_mode_sense?{mode_sense_dout_next2, mode_sense_dout_next3}:
		16'h0000;

// output of inquiry command, identify as "SEAGATE ST225N"
wire [7:0] inquiry_dout =
		(data_cnt == 32'd4 )?8'd32:  // length

		(data_cnt == 32'd8 )?" ":(data_cnt == 32'd9 )?"S":
		(data_cnt == 32'd10)?"E":(data_cnt == 32'd11)?"A":
		(data_cnt == 32'd12)?"G":(data_cnt == 32'd13)?"A":
		(data_cnt == 32'd14)?"T":(data_cnt == 32'd15)?"E":
		(data_cnt == 32'd16)?" ":(data_cnt == 32'd17)?" ":
		(data_cnt == 32'd18)?" ":(data_cnt == 32'd19)?" ":
		(data_cnt == 32'd20)?" ":(data_cnt == 32'd21)?" ":
		(data_cnt == 32'd22)?" ":(data_cnt == 32'd23)?" ":
		(data_cnt == 32'd24)?" ":(data_cnt == 32'd25)?" ":

		(data_cnt == 32'd26)?"S":(data_cnt == 32'd27)?"T":
		(data_cnt == 32'd28)?"2":(data_cnt == 32'd29)?"2":
		(data_cnt == 32'd30)?"5":(data_cnt == 32'd31)?"N" + {5'd0, ID}: // TESTING. ElectronAsh.
		8'h00;
wire [31:0] data_cnt_next = data_cnt + 32'd1;
wire [31:0] data_cnt_next2 = data_cnt + 32'd2;
wire [31:0] data_cnt_next3 = data_cnt + 32'd3;
wire [7:0] inquiry_dout_next =
		(data_cnt_next == 32'd4 )?8'd32:
		(data_cnt_next == 32'd8 )?" ":(data_cnt_next == 32'd9 )?"S":
		(data_cnt_next == 32'd10)?"E":(data_cnt_next == 32'd11)?"A":
		(data_cnt_next == 32'd12)?"G":(data_cnt_next == 32'd13)?"A":
		(data_cnt_next == 32'd14)?"T":(data_cnt_next == 32'd15)?"E":
		(data_cnt_next == 32'd16)?" ":(data_cnt_next == 32'd17)?" ":
		(data_cnt_next == 32'd18)?" ":(data_cnt_next == 32'd19)?" ":
		(data_cnt_next == 32'd20)?" ":(data_cnt_next == 32'd21)?" ":
		(data_cnt_next == 32'd22)?" ":(data_cnt_next == 32'd23)?" ":
		(data_cnt_next == 32'd24)?" ":(data_cnt_next == 32'd25)?" ":

		(data_cnt_next == 32'd26)?"S":(data_cnt_next == 32'd27)?"T":
		(data_cnt_next == 32'd28)?"2":(data_cnt_next == 32'd29)?"2":
		(data_cnt_next == 32'd30)?"5":(data_cnt_next == 32'd31)?"N" + {5'd0, ID}:
		8'h00;
wire [7:0] inquiry_dout_next2 =
		(data_cnt_next2 == 32'd4 )?8'd32:
		(data_cnt_next2 == 32'd8 )?" ":(data_cnt_next2 == 32'd9 )?"S":
		(data_cnt_next2 == 32'd10)?"E":(data_cnt_next2 == 32'd11)?"A":
		(data_cnt_next2 == 32'd12)?"G":(data_cnt_next2 == 32'd13)?"A":
		(data_cnt_next2 == 32'd14)?"T":(data_cnt_next2 == 32'd15)?"E":
		(data_cnt_next2 == 32'd16)?" ":(data_cnt_next2 == 32'd17)?" ":
		(data_cnt_next2 == 32'd18)?" ":(data_cnt_next2 == 32'd19)?" ":
		(data_cnt_next2 == 32'd20)?" ":(data_cnt_next2 == 32'd21)?" ":
		(data_cnt_next2 == 32'd22)?" ":(data_cnt_next2 == 32'd23)?" ":
		(data_cnt_next2 == 32'd24)?" ":(data_cnt_next2 == 32'd25)?" ":

		(data_cnt_next2 == 32'd26)?"S":(data_cnt_next2 == 32'd27)?"T":
		(data_cnt_next2 == 32'd28)?"2":(data_cnt_next2 == 32'd29)?"2":
		(data_cnt_next2 == 32'd30)?"5":(data_cnt_next2 == 32'd31)?"N" + {5'd0, ID}:
		8'h00;
wire [7:0] inquiry_dout_next3 =
		(data_cnt_next3 == 32'd4 )?8'd32:
		(data_cnt_next3 == 32'd8 )?" ":(data_cnt_next3 == 32'd9 )?"S":
		(data_cnt_next3 == 32'd10)?"E":(data_cnt_next3 == 32'd11)?"A":
		(data_cnt_next3 == 32'd12)?"G":(data_cnt_next3 == 32'd13)?"A":
		(data_cnt_next3 == 32'd14)?"T":(data_cnt_next3 == 32'd15)?"E":
		(data_cnt_next3 == 32'd16)?" ":(data_cnt_next3 == 32'd17)?" ":
		(data_cnt_next3 == 32'd18)?" ":(data_cnt_next3 == 32'd19)?" ":
		(data_cnt_next3 == 32'd20)?" ":(data_cnt_next3 == 32'd21)?" ":
		(data_cnt_next3 == 32'd22)?" ":(data_cnt_next3 == 32'd23)?" ":
		(data_cnt_next3 == 32'd24)?" ":(data_cnt_next3 == 32'd25)?" ":

		(data_cnt_next3 == 32'd26)?"S":(data_cnt_next3 == 32'd27)?"T":
		(data_cnt_next3 == 32'd28)?"2":(data_cnt_next3 == 32'd29)?"2":
		(data_cnt_next3 == 32'd30)?"5":(data_cnt_next3 == 32'd31)?"N" + {5'd0, ID}:
		8'h00;

// output of read capacity command
//wire [31:0] capacity = 32'd41056;   // 40960 + 96 blocks = 20MB
//wire [31:0] capacity = 32'd1024096;   // 1024000 + 96 blocks = 500MB
reg [31:0] capacity;
reg        mounted = 0;
always @(posedge clk) begin
	if (img_mounted) begin
		if (|img_blocks) begin
			capacity <= img_blocks - 1'd1;
			if (!mounted) $display("Image mounted on target %d, size: %d", ID, img_blocks);
			mounted <= 1;
		end else
			mounted <= 0;
	end
end

wire [7:0] read_capacity_dout =
		(data_cnt == 32'd0 )?capacity[31:24]:
		(data_cnt == 32'd1 )?capacity[23:16]:
		(data_cnt == 32'd2 )?capacity[15:8]:
		(data_cnt == 32'd3 )?capacity[7:0]:
		(data_cnt == 32'd6 )?8'd2:             // 512 bytes per sector
		8'h00;
wire [7:0] read_capacity_dout_next =
		(data_cnt_next == 32'd0 )?capacity[31:24]:
		(data_cnt_next == 32'd1 )?capacity[23:16]:
		(data_cnt_next == 32'd2 )?capacity[15:8]:
		(data_cnt_next == 32'd3 )?capacity[7:0]:
		(data_cnt_next == 32'd6 )?8'd2:
		8'h00;
wire [7:0] read_capacity_dout_next2 =
		(data_cnt_next2 == 32'd0 )?capacity[31:24]:
		(data_cnt_next2 == 32'd1 )?capacity[23:16]:
		(data_cnt_next2 == 32'd2 )?capacity[15:8]:
		(data_cnt_next2 == 32'd3 )?capacity[7:0]:
		(data_cnt_next2 == 32'd6 )?8'd2:
		8'h00;
wire [7:0] read_capacity_dout_next3 =
		(data_cnt_next3 == 32'd0 )?capacity[31:24]:
		(data_cnt_next3 == 32'd1 )?capacity[23:16]:
		(data_cnt_next3 == 32'd2 )?capacity[15:8]:
		(data_cnt_next3 == 32'd3 )?capacity[7:0]:
		(data_cnt_next3 == 32'd6 )?8'd2:
		8'h00;

wire [7:0] mode_sense_dout =
		(data_cnt == 32'd3 )?8'd8:
		(data_cnt == 32'd5 )?capacity[23:16]:
		(data_cnt == 32'd6 )?capacity[15:8]:
		(data_cnt == 32'd7 )?capacity[7:0]:
		(data_cnt == 32'd10 )?8'd2:
		8'h00;
wire [7:0] mode_sense_dout_next =
		(data_cnt_next == 32'd3 )?8'd8:
		(data_cnt_next == 32'd5 )?capacity[23:16]:
		(data_cnt_next == 32'd6 )?capacity[15:8]:
		(data_cnt_next == 32'd7 )?capacity[7:0]:
		(data_cnt_next == 32'd10 )?8'd2:
		8'h00;
wire [7:0] mode_sense_dout_next2 =
		(data_cnt_next2 == 32'd3 )?8'd8:
		(data_cnt_next2 == 32'd5 )?capacity[23:16]:
		(data_cnt_next2 == 32'd6 )?capacity[15:8]:
		(data_cnt_next2 == 32'd7 )?capacity[7:0]:
		(data_cnt_next2 == 32'd10 )?8'd2:
		8'h00;
wire [7:0] mode_sense_dout_next3 =
		(data_cnt_next3 == 32'd3 )?8'd8:
		(data_cnt_next3 == 32'd5 )?capacity[23:16]:
		(data_cnt_next3 == 32'd6 )?capacity[15:8]:
		(data_cnt_next3 == 32'd7 )?capacity[7:0]:
		(data_cnt_next3 == 32'd10 )?8'd2:
		8'h00;

// buffer to store incoming commands
reg [3:0]  cmd_cnt;
reg [7:0]  cmd [9:0];

/* ----------------------- request data from/to io controller ----------------------- */

assign io_lba = lba;

// generate an io_rd signal whenever the first byte of a 512 byte block is required
// start fetching the next sector when the 20th byte is read, and it's not the last sector
wire req_rd = ((phase == PHASE_DATA_OUT) && cmd_read && (data_cnt == 0 || (data_cnt[8:0] == 9'd20 && data_cnt[31:9] != ({7'd0, tlen} - 1'd1))) && !data_complete);

// generate an io_wr signal whenever a 512 byte block has been received or when the status
// phase of a write command has been reached
wire req_wr = ((((phase == PHASE_DATA_IN) && (data_cnt[8:0] == 0) && (data_cnt != 0)) || (phase == PHASE_STATUS_OUT)) && cmd_write);

always @(posedge clk) begin
	reg old_rd, old_wr;
	reg wr_pending, rd_pending;

	old_rd <= req_rd;
	old_wr <= req_wr;
	if(~old_rd & req_rd) rd_pending <= 1;
	if(~old_wr & req_wr) wr_pending <= 1;

	if(io_ack) begin
		io_rd <= 1'b0;
		io_wr <= 1'b0;
	end else begin
		if (rd_pending && !io_rd) begin
			io_rd <= 1;
			rd_pending <= 0;
		end

		if (wr_pending && !io_wr) begin
			io_wr <= 1;
			wr_pending <= 0;
		end
	end
end

reg  stb_ack;
reg  stb_adv;
always @(posedge clk) begin
	reg old_ack;
	
	old_ack <= ack;
	stb_ack <= (~old_ack & ack); // on rising edge
	stb_adv <= (old_ack & ~ack); // on falling edge
end

reg buffer0_wr, buffer1_wr;

// store data on rising edge of ack, ...
always @(posedge clk) begin
	buffer0_wr <= 0;
	buffer1_wr <= 0;
	if(stb_ack) begin
		if(phase == PHASE_CMD_IN)  cmd[cmd_cnt] <= din;
		if(phase == PHASE_DATA_IN) begin
			buffer0_wr <= ~data_cnt[0];
			buffer1_wr <=  data_cnt[0];
		end
	end
end

// ... advance counter on falling edge
always @(posedge clk) begin
	if(phase == PHASE_IDLE) cmd_cnt <= 4'd0;
	else if(stb_adv && (phase == PHASE_CMD_IN) && (cmd_cnt != 15)) cmd_cnt <= cmd_cnt + 4'd1;
end

// count data bytes. don't increase counter while we are waiting for data from
// the io controller
reg [31:0] data_cnt;
reg        data_complete;

// For block transfers tlen contains the number of 512 bytes blocks to transfer.
// Most other commands have the bytes length stored in the transfer length field.
// And some have a fixed length idependent from any header field.
// The data transfer has finished once the data counter reaches this
// number.
wire [31:0] data_len =
		 cmd_read_capacity?32'd8:
		 cmd_read?{ 7'd0, tlen, 9'd0 }:   // read command length is in 512 bytes blocks
		 cmd_write?{ 7'd0, tlen, 9'd0 }:  // write command length is in 512 bytes blocks
		 { 16'd0, tlen };                 // inquiry etc have length in bytes

always @(posedge clk) begin
	if((phase != PHASE_DATA_OUT) && (phase != PHASE_DATA_IN) && (phase != PHASE_STATUS_OUT) && (phase != PHASE_MESSAGE_OUT)) begin
		data_cnt <= 0;
		data_complete <= 0;
	end else begin	
		if(stb_adv)begin	
			if(!data_complete) data_cnt <= data_cnt + 1'd1;
			data_complete <= (data_len - 1'd1) == data_cnt;
		end
	end
end

// check whether status byte has been sent
reg status_sent;
always @(posedge clk) begin
	if(phase != PHASE_STATUS_OUT) status_sent <= 0;
	else if(stb_adv) status_sent <= 1;
end

// check whether message byte has been sent
reg message_sent;
always @(posedge clk) begin
	if(phase != PHASE_MESSAGE_OUT) message_sent <= 0;
	else if(stb_adv) message_sent <= 1;
end

/* ----------------------- command decoding ------------------------------- */


// parse commands
wire [7:0] op_code = cmd[0];
wire [2:0] cmd_group = op_code[7:5];

// check if a complete command has been received
wire       cmd_cpl = cmd6_cpl || cmd10_cpl;
wire       cmd6_cpl = (cmd_group == 3'b000) && (cmd_cnt == 6);
wire       cmd10_cpl = ((cmd_group == 3'b010) || (cmd_group == 3'b001)) && (cmd_cnt == 10);

// https://en.wikipedia.org/wiki/SCSI_command
wire       cmd_read = cmd_read6 || cmd_read10;
wire       cmd_read6 = (op_code == 8'h08);
wire       cmd_read10 = (op_code == 8'h28);
wire       cmd_write = cmd_write6 || cmd_write10;
wire       cmd_write6 = (op_code == 8'h0a);
wire       cmd_write10 = (op_code == 8'h2a);
wire       cmd_inquiry = (op_code == 8'h12);
wire       cmd_format = (op_code == 8'h04);
wire       cmd_mode_select = (op_code == 8'h15);
wire       cmd_mode_sense = (op_code == 8'h1a);
wire       cmd_test_unit_ready = (op_code == 8'h00);
wire       cmd_read_capacity = (op_code == 8'h25);
wire       cmd_read_buffer = (op_code == 8'h3b);  // fake
wire       cmd_write_buffer = (op_code == 8'h3c); // fake
wire       cmd_verify6 = (op_code == 8'h13); // fake
wire       cmd_verify10 = (op_code == 8'h2f); // fake

// valid command in buffer? TODO: check for valid command parameters
wire  cmd_ok = cmd_read || cmd_write || cmd_inquiry || cmd_test_unit_ready || 
		  cmd_read_capacity || cmd_mode_select || cmd_format || cmd_mode_sense ||
		  cmd_read_buffer || cmd_write_buffer || cmd_verify6 || cmd_verify10;

// latch parameters once command is complete
reg [31:0] lba;
reg [15:0] tlen;

always @(posedge clk) begin
	if (old_io_ack & ~io_ack) lba <= lba + 1'd1;
	if(cmd_cpl && (phase == PHASE_CMD_IN)) begin
		lba <= cmd6_cpl?{11'd0, lba6}:lba10;
		tlen <= cmd6_cpl?{7'd0, tlen6}:tlen10;
	end
end
   
// logical block address
wire [7:0] cmd1 = cmd[1];
wire [20:0] lba6 = { cmd1[4:0], cmd[2], cmd[3] };
wire [31:0] lba10 = { cmd[2], cmd[3], cmd[4], cmd[5] };

// transfer length
wire [8:0]  tlen6 = (cmd[4] == 0)?9'd256:{1'b0,cmd[4]};
wire [15:0] tlen10 = { cmd[7], cmd[8] };


// the 5380 changes phase in the falling edge, thus we monitor it
// on the rising edge
always @(posedge clk) begin
	if(rst) begin
		phase <= PHASE_IDLE;
	end else begin
		if(phase == PHASE_IDLE) begin
			if(sel && din[ID] && mounted)  // own id on bus during selection?
				phase <= PHASE_CMD_IN;
		end

		else if(phase == PHASE_CMD_IN) begin
			// check if a full command is in the buffer
			if(cmd_cpl) begin
				$display("New command on target %d: %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x", ID, cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9]);
				// is this a supported and valid command?
				if(cmd_ok) begin
					// yes, continue
					status <= `STATUS_OK;

					// continue according to command

					// these commands return data
					if(cmd_read || cmd_inquiry || cmd_read_capacity || cmd_mode_sense || cmd_read_buffer) phase <= PHASE_DATA_OUT;
					// these commands receive dataa
					else if(cmd_write || cmd_mode_select || cmd_write_buffer) phase <= PHASE_DATA_IN;
					// and all other valid commands are just "ok"
					else phase <= PHASE_STATUS_OUT;
				end else begin
					// no, report failure
					status <= `STATUS_CHECK_CONDITION;
					phase <= PHASE_STATUS_OUT;
				end
			end
		end

		else if(phase == PHASE_DATA_OUT) begin
			if(data_complete) phase <= PHASE_STATUS_OUT;
		end

		else if(phase == PHASE_DATA_IN) begin
			if(data_complete) phase <= PHASE_STATUS_OUT;
		end

		else if(phase == PHASE_STATUS_OUT) begin
			if(status_sent) phase <= PHASE_MESSAGE_OUT;
		end

		else if(phase == PHASE_MESSAGE_OUT) begin
			if(message_sent) phase <= PHASE_IDLE;
		end
		
		else
			phase <= PHASE_IDLE;  // should never happen
	end
end
   
   
endmodule

module scsi_empty_cd
(
	input      clk,
	input      rst,
	input      sel,
	input      ack,
	output     bsy,
	output     msg,
	output     cd,
	output     io,
	output     req,
	input  [7:0] din,
	output [7:0] dout,
	output [15:0] dout_pair,
	output [15:0] dout_pair_next
);

parameter [2:0] ID = 3;

localparam PHASE_IDLE        = 3'd0;
localparam PHASE_CMD_IN      = 3'd1;
localparam PHASE_DATA_OUT    = 3'd2;
localparam PHASE_STATUS_OUT  = 3'd4;
localparam PHASE_MESSAGE_OUT = 3'd5;

localparam STATUS_OK              = 8'h00;
localparam STATUS_CHECK_CONDITION = 8'h02;
localparam MSG_CMD_COMPLETE       = 8'h00;

reg [2:0]  phase;
reg [3:0]  cmd_cnt;
reg [7:0]  cmd [9:0];
reg [31:0] data_cnt;
reg [7:0]  status;
reg        status_sent;
reg        message_sent;
reg        data_complete;

assign msg = (phase == PHASE_MESSAGE_OUT);
assign cd = (phase == PHASE_CMD_IN) || (phase == PHASE_STATUS_OUT) || (phase == PHASE_MESSAGE_OUT);
assign io = (phase == PHASE_DATA_OUT) || (phase == PHASE_STATUS_OUT) || (phase == PHASE_MESSAGE_OUT);
	wire data_phase_complete = (phase == PHASE_DATA_OUT) && data_complete;
	assign req = (phase != PHASE_IDLE) && !ack && !data_phase_complete;
assign bsy = (phase != PHASE_IDLE);

wire [7:0] op_code = cmd[0];
wire [2:0] cmd_group = op_code[7:5];
wire       cmd6_cpl = (cmd_group == 3'b000) && (cmd_cnt == 6);
wire       cmd10_cpl = ((cmd_group == 3'b010) || (cmd_group == 3'b001)) && (cmd_cnt == 10);
wire       cmd_cpl = cmd6_cpl || cmd10_cpl;
wire       cmd_inquiry = (op_code == 8'h12);
wire       cmd_request_sense = (op_code == 8'h03);
wire [31:0] cmd6_len = (cmd[4] == 8'h00) ? 32'd256 : {24'd0, cmd[4]};
wire [31:0] data_len = cmd_inquiry ? cmd6_len :
                       cmd_request_sense ? cmd6_len :
                       32'd0;

	wire [7:0] inquiry_dout =
			(data_cnt == 32'd0 ) ? 8'h05 : // CD/DVD device
			(data_cnt == 32'd1 ) ? 8'h80 : // removable
			(data_cnt == 32'd2 ) ? 8'h01 :
			(data_cnt == 32'd3 ) ? 8'h01 :
			(data_cnt == 32'd4 ) ? 8'h31 :
			(data_cnt == 32'd8 ) ? "S" :
			(data_cnt == 32'd9 ) ? "O" :
			(data_cnt == 32'd10) ? "N" :
			(data_cnt == 32'd11) ? "Y" :
			(data_cnt == 32'd16) ? "C" :
			(data_cnt == 32'd17) ? "D" :
			(data_cnt == 32'd18) ? "-" :
			(data_cnt == 32'd19) ? "R" :
			(data_cnt == 32'd20) ? "O" :
			(data_cnt == 32'd21) ? "M" :
			(data_cnt == 32'd22) ? " " :
			(data_cnt == 32'd23) ? "C" :
			(data_cnt == 32'd24) ? "D" :
			(data_cnt == 32'd25) ? "U" :
			(data_cnt == 32'd26) ? "-" :
			(data_cnt == 32'd27) ? "8" :
			(data_cnt == 32'd28) ? "0" :
			(data_cnt == 32'd29) ? "0" :
			(data_cnt == 32'd30) ? "2" :
			(data_cnt == 32'd32) ? "1" :
			(data_cnt == 32'd33) ? "." :
			(data_cnt == 32'd34) ? "8" :
			(data_cnt == 32'd35) ? "g" :
			(data_cnt == 32'd39) ? 8'hd0 :
			(data_cnt == 32'd40) ? 8'h90 :
			(data_cnt == 32'd41) ? 8'h27 :
			(data_cnt == 32'd42) ? 8'h3e :
			(data_cnt == 32'd43) ? 8'h01 :
			(data_cnt == 32'd44) ? 8'h04 :
			(data_cnt == 32'd45) ? 8'h91 :
			(data_cnt == 32'd47) ? 8'h18 :
			(data_cnt == 32'd48) ? 8'h06 :
			(data_cnt == 32'd49) ? 8'hf0 :
			(data_cnt == 32'd50) ? 8'hfe :
			8'h00;

wire [7:0] sense_dout =
			(data_cnt == 32'd0 ) ? 8'h70 :
			(data_cnt == 32'd2 ) ? 8'h02 : // not ready
			(data_cnt == 32'd7 ) ? 8'h0a :
			(data_cnt == 32'd12) ? 8'hb0 : // AppleCD no-disc vendor ASC
			8'h00;
wire [31:0] empty_cd_data_cnt_next = data_cnt + 32'd1;
wire [7:0] inquiry_dout_next =
			(empty_cd_data_cnt_next == 32'd0 ) ? 8'h05 :
			(empty_cd_data_cnt_next == 32'd1 ) ? 8'h80 :
			(empty_cd_data_cnt_next == 32'd2 ) ? 8'h01 :
			(empty_cd_data_cnt_next == 32'd3 ) ? 8'h01 :
			(empty_cd_data_cnt_next == 32'd4 ) ? 8'h31 :
			(empty_cd_data_cnt_next == 32'd8 ) ? "S" :
			(empty_cd_data_cnt_next == 32'd9 ) ? "O" :
			(empty_cd_data_cnt_next == 32'd10) ? "N" :
			(empty_cd_data_cnt_next == 32'd11) ? "Y" :
			(empty_cd_data_cnt_next == 32'd16) ? "C" :
			(empty_cd_data_cnt_next == 32'd17) ? "D" :
			(empty_cd_data_cnt_next == 32'd18) ? "-" :
			(empty_cd_data_cnt_next == 32'd19) ? "R" :
			(empty_cd_data_cnt_next == 32'd20) ? "O" :
			(empty_cd_data_cnt_next == 32'd21) ? "M" :
			(empty_cd_data_cnt_next == 32'd22) ? " " :
			(empty_cd_data_cnt_next == 32'd23) ? "C" :
			(empty_cd_data_cnt_next == 32'd24) ? "D" :
			(empty_cd_data_cnt_next == 32'd25) ? "U" :
			(empty_cd_data_cnt_next == 32'd26) ? "-" :
			(empty_cd_data_cnt_next == 32'd27) ? "8" :
			(empty_cd_data_cnt_next == 32'd28) ? "0" :
			(empty_cd_data_cnt_next == 32'd29) ? "0" :
			(empty_cd_data_cnt_next == 32'd30) ? "2" :
			(empty_cd_data_cnt_next == 32'd32) ? "1" :
			(empty_cd_data_cnt_next == 32'd33) ? "." :
			(empty_cd_data_cnt_next == 32'd34) ? "8" :
			(empty_cd_data_cnt_next == 32'd35) ? "g" :
			(empty_cd_data_cnt_next == 32'd39) ? 8'hd0 :
			(empty_cd_data_cnt_next == 32'd40) ? 8'h90 :
			(empty_cd_data_cnt_next == 32'd41) ? 8'h27 :
			(empty_cd_data_cnt_next == 32'd42) ? 8'h3e :
			(empty_cd_data_cnt_next == 32'd43) ? 8'h01 :
			(empty_cd_data_cnt_next == 32'd44) ? 8'h04 :
			(empty_cd_data_cnt_next == 32'd45) ? 8'h91 :
			(empty_cd_data_cnt_next == 32'd47) ? 8'h18 :
			(empty_cd_data_cnt_next == 32'd48) ? 8'h06 :
			(empty_cd_data_cnt_next == 32'd49) ? 8'hf0 :
			(empty_cd_data_cnt_next == 32'd50) ? 8'hfe :
			8'h00;
wire [7:0] sense_dout_next =
			(empty_cd_data_cnt_next == 32'd0 ) ? 8'h70 :
			(empty_cd_data_cnt_next == 32'd2 ) ? 8'h02 :
			(empty_cd_data_cnt_next == 32'd7 ) ? 8'h0a :
			(empty_cd_data_cnt_next == 32'd12) ? 8'hb0 :
			8'h00;
wire [7:0] inquiry_dout_next2 = inquiry_dout_next;
wire [7:0] inquiry_dout_next3 = inquiry_dout_next;
wire [7:0] sense_dout_next2 = sense_dout_next;
wire [7:0] sense_dout_next3 = sense_dout_next;

assign dout = (phase == PHASE_STATUS_OUT)  ? status :
              (phase == PHASE_MESSAGE_OUT) ? MSG_CMD_COMPLETE :
              (phase == PHASE_DATA_OUT)    ? (cmd_request_sense ? sense_dout : inquiry_dout) :
              8'h00;
assign dout_pair = (phase == PHASE_STATUS_OUT)  ? {status, status} :
                   (phase == PHASE_MESSAGE_OUT) ? {MSG_CMD_COMPLETE, MSG_CMD_COMPLETE} :
                   (phase == PHASE_DATA_OUT)    ? (cmd_request_sense ? {sense_dout, sense_dout_next} : {inquiry_dout, inquiry_dout_next}) :
                   16'h0000;
assign dout_pair_next = (phase == PHASE_STATUS_OUT)  ? {status, status} :
                        (phase == PHASE_MESSAGE_OUT) ? {MSG_CMD_COMPLETE, MSG_CMD_COMPLETE} :
                        (phase == PHASE_DATA_OUT)    ? (cmd_request_sense ? {sense_dout_next2, sense_dout_next3} : {inquiry_dout_next2, inquiry_dout_next3}) :
                        16'h0000;

reg old_ack;
reg stb_ack;
reg stb_adv;
always @(posedge clk) begin
	old_ack <= ack;
	stb_ack <= ~old_ack & ack;
	stb_adv <= old_ack & ~ack;
end

always @(posedge clk) begin
	if (stb_ack && phase == PHASE_CMD_IN)
		cmd[cmd_cnt] <= din;
end

always @(posedge clk) begin
	if (phase == PHASE_IDLE)
		cmd_cnt <= 4'd0;
	else if (stb_adv && phase == PHASE_CMD_IN && cmd_cnt != 4'd15)
		cmd_cnt <= cmd_cnt + 4'd1;
end

always @(posedge clk) begin
	if (phase != PHASE_DATA_OUT && phase != PHASE_STATUS_OUT && phase != PHASE_MESSAGE_OUT) begin
		data_cnt <= 32'd0;
		data_complete <= 1'b0;
	end else if (phase == PHASE_DATA_OUT && stb_adv) begin
		if (!data_complete)
			data_cnt <= data_cnt + 32'd1;
		data_complete <= (data_len == 32'd0) || ((data_len - 32'd1) == data_cnt);
	end
end

always @(posedge clk) begin
	if (phase != PHASE_STATUS_OUT)
		status_sent <= 1'b0;
	else if (stb_adv)
		status_sent <= 1'b1;
end

always @(posedge clk) begin
	if (phase != PHASE_MESSAGE_OUT)
		message_sent <= 1'b0;
	else if (stb_adv)
		message_sent <= 1'b1;
end

always @(posedge clk) begin
	if (rst) begin
		phase <= PHASE_IDLE;
	end else begin
		if (phase == PHASE_IDLE) begin
			if (sel && din[ID])
				phase <= PHASE_CMD_IN;
		end else if (phase == PHASE_CMD_IN) begin
			if (cmd_cpl) begin
				if (cmd_inquiry || cmd_request_sense) begin
					status <= STATUS_OK;
					phase <= PHASE_DATA_OUT;
				end else begin
					status <= STATUS_CHECK_CONDITION;
					phase <= PHASE_STATUS_OUT;
				end
			end
		end else if (phase == PHASE_DATA_OUT) begin
			if (data_complete)
				phase <= PHASE_STATUS_OUT;
		end else if (phase == PHASE_STATUS_OUT) begin
			if (status_sent)
				phase <= PHASE_MESSAGE_OUT;
		end else if (phase == PHASE_MESSAGE_OUT) begin
			if (message_sent)
				phase <= PHASE_IDLE;
		end else begin
			phase <= PHASE_IDLE;
		end
	end
end

endmodule

module scsi_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=9)
(
	input	                clock,

	input	[ADDRWIDTH-1:0] address_a,
	input	[DATAWIDTH-1:0] data_a,
	input	                wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	[ADDRWIDTH-1:0] address_b,
	input	[DATAWIDTH-1:0] data_b,
	input	                wren_b,
	output reg [DATAWIDTH-1:0] q_b,

	input	[ADDRWIDTH-1:0] address_c,
	output reg [DATAWIDTH-1:0] q_c,

	input	[ADDRWIDTH-1:0] address_d,
	output reg [DATAWIDTH-1:0] q_d
);

// ram_ab is a true dual-port RAM serving the existing q_a/q_b read paths
// (each read at its port's write address). ram_c and ram_d are simple
// dual-port mirrors used for the look-ahead read ports q_c/q_d.
//
// wren_a and wren_b are mutually exclusive in this design (wren_a is
// driven by the SD->buffer path during PHASE_DATA_OUT, wren_b by the
// SCSI->buffer path during PHASE_DATA_IN), so muxing them into a single
// SDP write port keeps the mirrors coherent without needing two write
// ports on those arrays. Using a single ram array with >2 reads fails
// Quartus's TDP inference and produces "multiple constant drivers"
// errors on the ram net.
reg [DATAWIDTH-1:0] ram_ab[0:(1<<ADDRWIDTH)-1];
reg [DATAWIDTH-1:0] ram_c [0:(1<<ADDRWIDTH)-1];
reg [DATAWIDTH-1:0] ram_d [0:(1<<ADDRWIDTH)-1];

wire                  mirror_we    = wren_a | wren_b;
wire [ADDRWIDTH-1:0]  mirror_waddr = wren_a ? address_a : address_b;
wire [DATAWIDTH-1:0]  mirror_wdata = wren_a ? data_a    : data_b;

always @(posedge clock) begin
	if(wren_a) begin
		ram_ab[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram_ab[address_a];
	end
end

always @(posedge clock) begin
	if(wren_b) begin
		ram_ab[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram_ab[address_b];
	end
end

always @(posedge clock) begin
	if(mirror_we) ram_c[mirror_waddr] <= mirror_wdata;
	q_c <= ram_c[address_c];
end

always @(posedge clock) begin
	if(mirror_we) ram_d[mirror_waddr] <= mirror_wdata;
	q_d <= ram_d[address_d];
end

endmodule
