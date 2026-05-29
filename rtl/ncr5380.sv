/* verilator lint_off UNUSED */

/* based on minimigmac by Benjamin Herrenschmidt */

/* Read registers */
`define RREG_CDR        3'h0    /* Current SCSI data */
`define RREG_ICR        3'h1    /* Initiator Command */
`define RREG_MR         3'h2    /* Mode register */
`define RREG_TCR        3'h3    /* Target Command */
`define RREG_CSR        3'h4    /* SCSI bus status */
`define RREG_BSR        3'h5    /* Bus and status */
`define RREG_IDR        3'h6    /* Input data */
`define RREG_RST        3'h7    /* Reset */

/* Write registers */
`define WREG_ODR        3'h0    /* Output data */
`define WREG_ICR        3'h1    /* Initiator Command */
`define WREG_MR         3'h2    /* Mode register */
`define WREG_TCR        3'h3    /* Target Command */
`define WREG_SER        3'h4    /* Select Enable */
`define WREG_DMAS       3'h5    /* Start DMA Send */
`define WREG_DMATR      3'h6    /* Start DMA Target receive */
`define WREG_IDMAR      3'h7    /* Start DMA Initiator receive */

/* MR bit numbers */
`define MR_DMA_MODE     1
`define MR_ARB          0

/* ICR bit numbers */
`define ICR_A_RST       7
`define ICR_TEST_MODE   6
`define ICR_DIFF_ENBL   5
`define ICR_A_ACK       4
`define ICR_A_BSY       3
`define ICR_A_SEL       2
`define ICR_A_ATN       1
`define ICR_A_DATA      0

/* TCR bit numbers */
`define TCR_A_REQ       3
`define TCR_A_MSG       2
`define TCR_A_CD        1
`define TCR_A_IO        0

module ncr5380
(
	input    		clk,
	input 	     	reset,

	/* Bus interface. 3-bit address, to be wired
	 * appropriately upstream (to A4..A6) plus one
	 * more bit (A9) wired as dack.
	 */
	input         bus_cs,
	input   [2:0] bus_rs,
	input         ior,
	input         iow,
	input         dack,
	input         dma_word,
	input         dma_longword,
	input         dma_second_word,
	output        dreq,
	input  [15:0] wdata,
	output [15:0] rdata,

	// connections to io controller
	input  [DEVS-1:0] img_mounted,
	input      [31:0] img_size,
	
	output reg [31:0] io_lba[DEVS],
	output [DEVS-1:0] io_rd,
	output [DEVS-1:0] io_wr,
	input  [DEVS-1:0] io_ack,

	input        [7:0] sd_buff_addr,
	input       [15:0] sd_buff_dout,
	output      [15:0] sd_buff_din[DEVS],
	input              sd_buff_wr,

	// JTAG debug: selection/arbitration state for the hardware hang
	output      [15:0] dbg_scsi,
	// JTAG debug: post-selection phase + HPS disk handshake
	//   [13:11] target_phase[1]  [10:8] target_phase[0]
	//   [5:4] io_rd  [3:2] io_wr  [1:0] io_ack
	output      [15:0] dbg_scsi2,
	// JTAG debug: per-target REQ/ACK handshake observations
	//   [15:8] target1 dbg_hs   [7:0] target0 dbg_hs
	output      [15:0] dbg_scsi3,
	// JTAG debug: bus-reset count + per-target completion flags
	//   [15:8] scsi_rst assertion count (saturating)
	//   [7:4]  target1 dbg_hs2   [3:0] target0 dbg_hs2
	output      [15:0] dbg_scsi4,
	// JTAG debug: per-target command-type bitmap
	//   [15:8] target1 dbg_cmd   [7:0] target0 dbg_cmd
	output      [15:0] dbg_scsi5
);
	parameter DEVS = 2;
	parameter ENABLE_EMPTY_CD = 0;

	reg  [7:0] mr;        /* Mode Register */
	reg  [7:0] icr;       /* Initiator Command Register */
	reg  [3:0] tcr;       /* Target Command Register */
	wire [7:0] csr;       /* SCSI bus status register */
	reg        arb_active;
	reg  [7:0] arb_count;

	/* Data in and out latches and associated
	* control logic for DMA
	*/
	reg  [7:0] din;
	reg  [7:0] dout;
	reg        dma_en;

	/* --- Main host-side interface --- */

	/* Register & DMA accesses decodes */
	reg dma_wr;
	reg reg_wr;
	reg dma_ack;
	reg [2:0] dma_ack_holdoff;
	reg dma_word_latched;
	reg dma_longword_latched;
	reg dma_second_word_latched;
	reg dma_suppress_ack_latched;
	reg dma_longword_second_pending;
	reg [15:0] dma_second_word_data;
	reg [7:0] dma_write_low_byte;
	reg old_dma_rd;
	reg old_dma_wr;
	reg old_reg_wr;

	wire dma_ack_busy = dma_ack | (dma_ack_holdoff != 3'd0);
	assign dreq = scsi_req & dma_en & !dma_ack_busy;

	wire i_dma_rd = bus_cs &  dack & ior;
	wire i_dma_wr = bus_cs &  dack & iow;
	wire i_reg_wr = bus_cs & ~dack & iow;
	// Host read of the Current SCSI Bus Status register (REQ poll) — used by the
	// target's block-boundary REQ pulse to know the host has observed REQ=0.
	wire csr_rd = bus_cs & ~dack & ior & (bus_rs == `RREG_CSR);

	always @(posedge clk or posedge reset) begin
		if (reset) begin
			old_dma_rd <= 0;
			old_dma_wr <= 0;
			old_reg_wr <= 0;
			dma_wr <= 0;
			dma_ack <= 0;
			dma_ack_holdoff <= 0;
			reg_wr <= 0;
			dma_word_latched <= 0;
			dma_longword_latched <= 0;
			dma_second_word_latched <= 0;
			dma_suppress_ack_latched <= 0;
			dma_longword_second_pending <= 0;
			dma_second_word_data <= 16'h0000;
			dma_write_low_byte <= 8'h00;
		end else begin
			old_dma_rd <= i_dma_rd;
			old_dma_wr <= i_dma_wr;
			old_reg_wr <= i_reg_wr;

			dma_wr <= 0;
			dma_ack <= 0;
			reg_wr <= 0;

			if(~old_dma_rd & i_dma_rd) begin
				dma_word_latched <= dma_word;
				dma_longword_latched <= dma_longword;
				dma_second_word_latched <= dma_second_word;
				dma_suppress_ack_latched <= dma_longword_second_pending & dma_second_word;
				dma_longword_second_pending <= (dma_longword_second_pending & dma_second_word) ? 1'b0 :
				                               (dma_word & dma_longword & !dma_second_word);
				if (dma_word & dma_longword & !dma_second_word)
					dma_second_word_data <= din_pair_next;
			end
			if(~old_dma_wr & i_dma_wr) begin
				dma_word_latched <= dma_word;
				dma_longword_latched <= dma_longword;
				dma_second_word_latched <= dma_second_word;
				dma_write_low_byte <= wdata[7:0];
				dma_wr <= 1;
			end
			if(~old_reg_wr & i_reg_wr) reg_wr <= 1;
			if (dma_ack_holdoff != 3'd0) begin
				/* Keep DREQ dropped while the target observes the ACK low edge.
				 * A 68020 longword pseudo-DMA read is two 16-bit bus cycles;
				 * only the first cycle should consume the four SCSI bytes.
				 */
				dma_ack <= dma_ack_holdoff[0];
				dma_ack_holdoff <= dma_ack_holdoff - 3'd1;
			end else if((old_dma_wr & ~i_dma_wr) |
			            (old_dma_rd & ~i_dma_rd &
			             !dma_suppress_ack_latched)) begin
				dma_ack <= dma_en & bsr_pmatch;
				if (dma_en & bsr_pmatch)
					dma_ack_holdoff <= (old_dma_rd & ~i_dma_rd) ?
						(dma_longword_latched ? 3'd6 : (dma_word_latched ? 3'd2 : 3'd0)) :
						(dma_word_latched ? 3'd2 : 3'd0);
			end
		end
	end

	/* System bus reads */
	wire [7:0] rdata8 =
	               dack                ? cur_data         :
	               bus_rs == `RREG_CDR ? cur_data         :
	               bus_rs == `RREG_ICR ? icr_read         :
	               bus_rs == `RREG_MR  ? mr               :
	               bus_rs == `RREG_TCR ? { 4'h0, tcr }    :
	               bus_rs == `RREG_CSR ? csr              :
	               bus_rs == `RREG_BSR ? bsr              :
	               bus_rs == `RREG_IDR ? cur_data         :
	               bus_rs == `RREG_RST ? 8'h00            :
	               8'hff;
	assign rdata = (dack && dma_word) ? cur_data_pair : { rdata8, rdata8 };

	/* Data out latch (in DMA mode, this is one cycle after we've
	* asserted ACK)
	*/
	always@(posedge clk) if(reg_wr && bus_rs == `WREG_ODR) dout <= wdata[15:8];
	else if(dma_wr) dout <= wdata[15:8];

	/* Current data register. Approximate MAME's nscsi bus: reads see the
	 * wired-OR of active initiator and target data drivers.
	 */
	wire       out_en = icr[`ICR_A_DATA] | mr[`MR_ARB];
	wire [7:0] dma_write_data = (dma_ack_holdoff == 3'd1 && dma_word_latched) ? dma_write_low_byte : dout;
	wire [7:0] scsi_bus_data = (out_en ? dma_write_data : 8'h00) | din;
	wire [7:0] cur_data = scsi_bus_data;
	wire [15:0] cur_data_pair = out_en ? { dout, dout } : (dma_suppress_ack_latched ? dma_second_word_data : din_pair);

	/* ICR read wires */
	wire [7:0] icr_read = { icr[`ICR_A_RST],
	                        icr_aip,
	                        icr_la,
	                        icr[`ICR_A_ACK],
	                        icr[`ICR_A_BSY],
	                        icr[`ICR_A_SEL],
	                        icr[`ICR_A_ATN],
	                        icr[`ICR_A_DATA] };

	/* ICR write */
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			icr <= 0;
		end else if (reg_wr && (bus_rs == `WREG_ICR)) begin
			icr <= wdata;
		end else if (arb_active && arb_count == 8'd0) begin
			icr[`ICR_A_BSY] <= 1'b1;
		end
	end
   
	/* MR write */
	always@(posedge clk or posedge reset) begin
		if (reset) mr <= 8'b0;
		else if (reg_wr && (bus_rs == `WREG_MR)) mr <= wdata;
	end

	/* Minimal initiator arbitration. The Mac II ROM writes MR.ARB and then
	 * polls ICR.AIP until arbitration completes. Treat a free bus as won
	 * after a short delay and assert BSY for the initiator.
	 */
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			arb_active <= 1'b0;
			arb_count <= 8'd0;
		end else begin
			if (reg_wr && (bus_rs == `WREG_MR)) begin
				if (wdata[`MR_ARB] && !mr[`MR_ARB]) begin
					arb_active <= 1'b1;
					arb_count <= 8'd64;
				end else if (!wdata[`MR_ARB]) begin
					arb_active <= 1'b0;
					arb_count <= 8'd0;
				end
			end else if (arb_active) begin
				if (arb_count != 8'd0) begin
					arb_count <= arb_count - 8'd1;
				end else begin
					arb_active <= 1'b0;
				end
			end
		end
	end
   
	/* TCR write */
	always@(posedge clk or posedge reset) begin
		if (reset) tcr <= 4'b0;
		else if (reg_wr && (bus_rs == `WREG_TCR)) tcr <= wdata[3:0];
	end
   
	/* DMA start send & receive registers. We currently ignore
	* the direction.
	*/
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			dma_en <= 0;
		end else begin
			if (!mr[`MR_DMA_MODE]) begin
				dma_en <= 0;
			end else if (reg_wr && (bus_rs == `WREG_DMAS)) begin
				dma_en <= 1;
			end else if (reg_wr && (bus_rs == `WREG_IDMAR)) begin
				dma_en <= 1;
			end
		end
	end

	/* CSR (read only). We don't do parity */
	assign csr = { scsi_rst, scsi_bsy, scsi_req, scsi_msg,
	               scsi_cd, scsi_io, scsi_sel, 1'b0 };	

	/* Bus and Status register */
	/* BSR (read only). We don't do a few things... */
	wire bsr_eodma = 1'b0;	/* We don't do EOP */
	wire bsr_dmarq = scsi_req & dma_en;
	wire bsr_perr = 1'b0;	/* We don't do parity */
	wire bsr_irq = scsi_req & dma_en & ~bsr_pmatch;
	wire bsr_pmatch = 
	         tcr[`TCR_A_MSG] == scsi_msg &&
	         tcr[`TCR_A_CD ] == scsi_cd  &&
	         tcr[`TCR_A_IO ] == scsi_io;

	wire bsr_berr = 1'b0;	/* XXX ? Does MacOS use this ? */
	wire [7:0] bsr = { bsr_eodma, bsr_dmarq, bsr_perr, bsr_irq,
	                   bsr_pmatch, bsr_berr, scsi_atn, scsi_ack };

   /* --- Simulated SCSI Signals --- */

   /* BSY logic (simplified arbitration, see notes) */
	wire scsi_bsy = 
	    icr[`ICR_A_BSY] |
	    |target_bsy |
	    empty_cd_active |
	    //scsi2_bsy |
	    //scsi6_bsy |
	    mr[`MR_ARB];

	/* Keep AIP visible while the ROM is requesting arbitration. */
	wire icr_aip = mr[`MR_ARB];
	wire icr_la = 0;

	/* Other ORed SCSI signals */
	wire scsi_sel = icr[`ICR_A_SEL];
	wire scsi_rst = icr[`ICR_A_RST];
	wire scsi_ack = icr[`ICR_A_ACK] | dma_ack;
	wire scsi_atn = icr[`ICR_A_ATN];

	/* Mux target signals */
	reg scsi_cd, scsi_io, scsi_msg, scsi_req;

	always begin
		integer i;
		scsi_cd = 0;
		scsi_io = 0;
		scsi_msg = 0;
		scsi_req = 0;
		din = 8'h00;
		din_pair = 16'h0000;
		din_pair_next = 16'h0000;

		for (i = 0; i < DEVS; i = i + 1) begin
			if (target_bsy[i]) begin
				scsi_cd = target_cd[i];
				scsi_io = target_io[i];
				scsi_msg = target_msg[i];
				scsi_req = target_req[i];
				din = target_dout[i];
				din_pair = target_dout_pair[i];
				din_pair_next = target_dout_pair_next[i];
			end
		end

		if (empty_cd_active) begin
			scsi_cd = empty_cd_cd;
			scsi_io = empty_cd_io;
			scsi_msg = empty_cd_msg;
			scsi_req = empty_cd_req;
			din = empty_cd_dout;
			din_pair = empty_cd_dout_pair;
			din_pair_next = empty_cd_dout_pair_next;
		end
	end

	// input signals from targets
	wire [DEVS-1:0] target_mounted;
	wire [2:0]      target_phase[DEVS];
	wire [7:0]      target_hs[DEVS];
	wire [3:0]      target_hs2[DEVS];
	wire [7:0]      target_cmd[DEVS];
	wire [31:0]     target_wrsnap[DEVS];   // JTAG debug: first-word-write capture
	wire [DEVS-1:0] target_bsy;

	// Count SCSI bus resets (Mac asserting ICR.RST) -- the abort/retry signal.
	// Resets only on the global module reset, so it survives scsi_rst.
	reg [7:0] dbg_rst_count;
	reg       dbg_rst_d;
	always @(posedge clk or posedge reset) begin
		if (reset) begin
			dbg_rst_count <= 8'd0;
			dbg_rst_d     <= 1'b0;
		end else begin
			dbg_rst_d <= scsi_rst;
			if (scsi_rst && !dbg_rst_d && dbg_rst_count != 8'hFF)
				dbg_rst_count <= dbg_rst_count + 8'd1;
		end
	end
	wire [DEVS-1:0] target_msg;
	wire [DEVS-1:0] target_io;
	wire [DEVS-1:0] target_cd;
	wire [DEVS-1:0] target_req;
	wire      [7:0] target_dout[DEVS];
	wire     [15:0] target_dout_pair[DEVS];
	wire     [15:0] target_dout_pair_next[DEVS];
	reg      [15:0] din_pair;
	reg      [15:0] din_pair_next;

	wire empty_cd_bsy;
	wire empty_cd_msg;
	wire empty_cd_io;
	wire empty_cd_cd;
	wire empty_cd_req;
	wire [7:0] empty_cd_dout;
	wire [15:0] empty_cd_dout_pair;
	wire [15:0] empty_cd_dout_pair_next;
	wire empty_cd_active = ENABLE_EMPTY_CD && empty_cd_bsy;

	scsi_empty_cd #(.ID(3'd3)) empty_cd
	(
		.clk    ( clk ),
		.rst    ( scsi_rst ),
		.sel    ( ENABLE_EMPTY_CD ? scsi_sel : 1'b0 ),
		.ack    ( scsi_ack ),
		.bsy    ( empty_cd_bsy  ),
		.msg    ( empty_cd_msg  ),
		.cd     ( empty_cd_cd   ),
		.io     ( empty_cd_io   ),
		.req    ( empty_cd_req  ),
		.dout   ( empty_cd_dout ),
		.dout_pair ( empty_cd_dout_pair ),
		.dout_pair_next ( empty_cd_dout_pair_next ),
		.din    ( scsi_bus_data )
	);

	generate
		genvar i;
		for (i = 0; i < DEVS; i = i + 1) begin : target
			// connect a target
			scsi #(.ID(3'd6 - i[2:0])) target
			(
				.clk    ( clk ),
				.rst    ( scsi_rst ),
				.sel    ( scsi_sel ),
				.atn    ( scsi_atn ),

				.ack    ( scsi_ack ),
				.host_csr_rd ( csr_rd ),
				.host_data_rd ( i_dma_rd ),

				.bsy    ( target_bsy[i]  ),
				.msg    ( target_msg[i]  ),
				.cd     ( target_cd[i]   ),
				.io     ( target_io[i]   ),
				.req    ( target_req[i]  ),
				.dout   ( target_dout[i] ),
				.dout_pair ( target_dout_pair[i] ),
				.dout_pair_next ( target_dout_pair_next[i] ),

				.din    ( scsi_bus_data ),

				// connection to io controller to read and write sectors
				// to sd card
				.img_mounted(img_mounted[i]),
				.img_blocks(img_size),
				.io_lba ( io_lba[i] ),
				.io_rd  ( io_rd[i] ),
				.io_wr  ( io_wr[i] ),
				.io_ack ( io_ack[i] & target_bsy[i] ),

				.sd_buff_addr( sd_buff_addr ),
				.sd_buff_dout( sd_buff_dout ),
				.sd_buff_din( sd_buff_din[i] ),
				.sd_buff_wr( sd_buff_wr & target_bsy[i] ),
				.dbg_mounted( target_mounted[i] ),
				.dbg_phase( target_phase[i] ),
				.dbg_hs( target_hs[i] ),
				.dbg_hs2( target_hs2[i] ),
				.dbg_cmd( target_cmd[i] ),
				.dbg_dma_word( dma_word_latched ),
				.dbg_dma_long( dma_longword_latched ),
				.dbg_dma_lowbyte( dma_write_low_byte ),
				.dbg_wrsnap( target_wrsnap[i] )
			);
		end
	endgenerate

	// JTAG debug: capture the selection/arbitration handshake state.
	//  [15]    out_en       (initiator driving the data bus?)
	//  [14]    scsi_sel     (SEL asserted)
	//  [13]    scsi_bsy     (any BSY on the bus)
	//  [12:11] target_bsy   (which target asserted BSY)
	//  [10:9]  target_mounted (per-target disk-present state)
	//  [8]     icr[ICR_A_DATA]
	//  [7:0]   scsi_bus_data (ID bits driven during selection)
	assign dbg_scsi = { out_en, scsi_sel, scsi_bsy, target_bsy[1:0],
	                    target_mounted[1:0], icr[`ICR_A_DATA],
	                    scsi_bus_data };

	assign dbg_scsi2 = { 2'b0, target_phase[1], target_phase[0],
	                     io_rd[1:0], io_wr[1:0], io_ack[1:0] };

	assign dbg_scsi3 = { target_hs[1], target_hs[0] };

	assign dbg_scsi4 = { dbg_rst_count, target_hs2[1], target_hs2[0] };

	assign dbg_scsi5 = { target_cmd[1], target_cmd[0] };

	// JTAG ISSP: first-word-write capture for target 0 (ID 6, the boot disk).
	// Read with quartus_stp via instance_id "PWR".
	//   [7:0]   byte0 the target latched   [15:8]  byte1 the target latched
	//   [23:16] ncr5380 intended odd byte  [24] dma_word_latched
	//   [25] dma_longword_latched          [26] b0_seen [27] b1_seen
	// byte1==byte0 (and != intended odd byte) => low byte dropped in serialization.
	altsource_probe #(
		.instance_id ("PWR2"),
		.probe_width (32),
		.source_width(1),
		.sld_auto_instance_index ("YES")
	) cp_pwr (.probe(target_wrsnap[0]), .source(), .source_clk(clk), .source_ena(1'b1));

`ifdef SIMULATION
	// Host-side stall watchdog: when a target holds REQ but the host stops
	// ACKing for a long time, dump the pseudo-DMA state so we can see whether
	// the host is starved of DREQ (dma_en cleared, holdoff stuck, pmatch lost).
	reg [31:0] hstall;
	reg        old_scsi_ack_w;
	always @(posedge clk) begin
		old_scsi_ack_w <= scsi_ack;
		if (scsi_req && !scsi_ack) begin
			hstall <= hstall + 1'd1;
			if (hstall == 32'd320000 && $test$plusargs("scsi_stall_debug"))
				$display("NCR_STALL req=%b ack=%b dreq=%b dma_en=%b dma_ack=%b ack_busy=%b holdoff=%0d mr_dma=%b icr=%02h tcr=%01h pmatch=%b io=%b cd=%b msg=%b",
				         scsi_req, scsi_ack, dreq, dma_en, dma_ack, dma_ack_busy, dma_ack_holdoff,
				         mr[`MR_DMA_MODE], icr, tcr, bsr_pmatch, scsi_io, scsi_cd, scsi_msg);
		end else
			hstall <= 0;
	end
`endif

endmodule
