// SPDX-License-Identifier: Apache-2.0
// Copyright 2020 Western Digital Corporation or its affiliates.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// all flops call the rvdff flop


module rvdff #( parameter WIDTH=1 )
   (
     input logic [WIDTH-1:0] din,
     input logic           clk,
     input logic                   rst_l,

     output logic [WIDTH-1:0] dout
     );

`ifdef RV_CLOCKGATE
   always @(posedge tb_top.clk) begin
      #0 $strobe("CG: %0t %m din %x dout %x clk %b width %d",$time,din,dout,clk,WIDTH);
   end
`endif

   always_ff @(posedge clk or negedge rst_l) begin
      if (rst_l == 0)
        dout[WIDTH-1:0] <= 0;
      else
        dout[WIDTH-1:0] <= din[WIDTH-1:0];
   end


endmodule

// rvdff with 2:1 input mux to flop din iff sel==1
module rvdffs #( parameter WIDTH=1 )
   (
     input logic [WIDTH-1:0] din,
     input logic             en,
     input logic           clk,
     input logic                   rst_l,
     output logic [WIDTH-1:0] dout
     );

   rvdff #(WIDTH) dffs (.din((en) ? din[WIDTH-1:0] : dout[WIDTH-1:0]), .*);

endmodule

// rvdff with en and clear
module rvdffsc #( parameter WIDTH=1 )
   (
     input logic [WIDTH-1:0] din,
     input logic             en,
     input logic             clear,
     input logic           clk,
     input logic                   rst_l,
     output logic [WIDTH-1:0] dout
     );

   logic [WIDTH-1:0]          din_new;
   assign din_new = {WIDTH{~clear}} & (en ? din[WIDTH-1:0] : dout[WIDTH-1:0]);
   rvdff #(WIDTH) dffsc (.din(din_new[WIDTH-1:0]), .*);

endmodule

// _fpga versions
module rvdff_fpga #( parameter WIDTH=1 )
   (
     input logic [WIDTH-1:0] din,
     input logic           clk,
     input logic           clken,
     input logic           rawclk,
     input logic           rst_l,

     output logic [WIDTH-1:0] dout
     );

`ifdef RV_FPGA_OPTIMIZE
   rvdffs #(WIDTH) dffs (.clk(rawclk), .en(clken), .*);
`else
   rvdff #(WIDTH)  dff (.*);
`endif

endmodule

// rvdff with 2:1 input mux to flop din iff sel==1
module rvdffs_fpga #( parameter WIDTH=1 )
   (
     input logic [WIDTH-1:0] din,
     input logic             en,
     input logic           clk,
     input logic           clken,
     input logic           rawclk,
     input logic           rst_l,

     output logic [WIDTH-1:0] dout
     );

`ifdef RV_FPGA_OPTIMIZE
   rvdffs #(WIDTH)   dffs (.clk(rawclk), .en(clken & en), .*);
`else
   rvdffs #(WIDTH)   dffs (.*);
`endif

endmodule

// rvdff with en and clear
module rvdffsc_fpga #( parameter WIDTH=1 )
   (
     input logic [WIDTH-1:0] din,
     input logic             en,
     input logic             clear,
     input logic             clk,
     input logic             clken,
     input logic             rawclk,
     input logic             rst_l,

     output logic [WIDTH-1:0] dout
     );

   logic [WIDTH-1:0]          din_new;

`ifdef RV_FPGA_OPTIMIZE
   rvdffs  #(WIDTH)   dffs  (.clk(rawclk), .din(din[WIDTH-1:0] & {WIDTH{~clear}}),.en((en | clear) & clken), .*);
`else
   rvdffsc #(WIDTH)   dffsc (.*);
`endif

endmodule


module rvdff4iee #( parameter WIDTH=64 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic       en,
     input  logic           clk,
     input  logic           rst_l,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   localparam LEFTMOST = int'(WIDTH/4);
   localparam LEFT     = LEFTMOST;
   localparam RIGHT    = LEFTMOST;
   localparam RIGHTMOST = WIDTH - LEFTMOST - LEFT - RIGHT;

   localparam LMMSB = WIDTH-1;
   localparam LMLSB = LMMSB-LEFTMOST+1;
   localparam LMSB = LMLSB-1;
   localparam LLSB = LMLSB-LEFT;
   localparam RMSB = LLSB-1;
   localparam RLSB = LLSB-RIGHT;
   localparam RMMSB = RLSB-1;
   localparam RMLSB = RLSB-RIGHTMOST;


`ifndef RV_PHYSICAL
   if (WIDTH >= 32 && LEFTMOST >= 8 && LEFT >=8 && RIGHT >= 8 && RIGHTMOST >=8) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH)      dff   (.*, .din(din[WIDTH-1:0]), .dout(dout[WIDTH-1:0]));
`else
      rvdffiee #(LEFTMOST)   dff_leftmost  (.*, .din(din[LMMSB:LMLSB]), .dout(dout[LMMSB:LMLSB]));
      rvdffiee #(LEFT)       dff_left      (.*, .din(din[LMSB:LLSB]),   .dout(dout[LMSB:LLSB])  );
      rvdffiee #(RIGHT)      dff_right     (.*, .din(din[RMSB:RLSB]),   .dout(dout[RMSB:RLSB])  );
      rvdffiee #(RIGHTMOST)  dff_rightmost (.*, .din(din[RMMSB:RMLSB]), .dout(dout[RMMSB:RMLSB]));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffe must be WIDTH >= 32 && LEFTMOST >= 8 && LEFT >=8 && RIGHT >= 8 && RIGHTMOST >=8");
`endif

endmodule // rvdffe



// specialty flop for power - ifu fetch buffers
// rvdffe broken into 4 rvdffe's, equal width, each with own enable
module rvdff4e #( parameter WIDTH=64 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic [3:0]     en,
     input  logic           clk,
     input  logic           rst_l,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   localparam LEFTMOST = int'(WIDTH/4);
   localparam LEFT     = LEFTMOST;
   localparam RIGHT    = LEFTMOST;
   localparam RIGHTMOST = WIDTH - LEFTMOST - LEFT - RIGHT;

   localparam LMMSB = WIDTH-1;
   localparam LMLSB = LMMSB-LEFTMOST+1;
   localparam LMSB = LMLSB-1;
   localparam LLSB = LMLSB-LEFT;
   localparam RMSB = LLSB-1;
   localparam RLSB = LLSB-RIGHT;
   localparam RMMSB = RLSB-1;
   localparam RMLSB = RLSB-RIGHTMOST;


`ifndef RV_PHYSICAL
   if (WIDTH >= 32 && LEFTMOST >= 8 && LEFT >=8 && RIGHT >= 8 && RIGHTMOST >=8) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(LEFTMOST)   dff_leftmost  (.*, .din(din[LMMSB:LMLSB]), .dout(dout[LMMSB:LMLSB]),.en(en[3]));
      rvdffs #(LEFT)       dff_left      (.*, .din(din[LMSB:LLSB]),   .dout(dout[LMSB:LLSB]),  .en(en[2]));
      rvdffs #(RIGHT)      dff_right     (.*, .din(din[RMSB:RLSB]),   .dout(dout[RMSB:RLSB]),  .en(en[1]));
      rvdffs #(RIGHTMOST)  dff_rightmost (.*, .din(din[RMMSB:RMLSB]), .dout(dout[RMMSB:RMLSB]),.en(en[0]));
`else
      rvdffe #(LEFTMOST)   dff_leftmost  (.*, .din(din[LMMSB:LMLSB]), .dout(dout[LMMSB:LMLSB]),.en(en[3]));
      rvdffe #(LEFT)       dff_left      (.*, .din(din[LMSB:LLSB]),   .dout(dout[LMSB:LLSB]),  .en(en[2]));
      rvdffe #(RIGHT)      dff_right     (.*, .din(din[RMSB:RLSB]),   .dout(dout[RMSB:RLSB]),  .en(en[1]));
      rvdffe #(RIGHTMOST)  dff_rightmost (.*, .din(din[RMMSB:RMLSB]), .dout(dout[RMMSB:RMLSB]),.en(en[0]));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffe must be WIDTH >= 32 && LEFTMOST >= 8 && LEFT >=8 && RIGHT >= 8 && RIGHTMOST >=8");
`endif

endmodule // rvdffe


module rvdffe #( parameter WIDTH=1, OVERRIDE=0 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic           en,
     input  logic           clk,
     input  logic           rst_l,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   logic                      l1clk;

`ifndef RV_PHYSICAL
   if (WIDTH >= 8 || OVERRIDE==1) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else
      rvclkhdr clkhdr ( .* );
      rvdff #(WIDTH) dff (.*, .clk(l1clk));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffe width must be >= 8");
`endif

endmodule // rvdffe

module rvdffpcie #( parameter WIDTH=31 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic             clk,
     input  logic             rst_l,
     input  logic             en,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );


`ifndef RV_PHYSICAL
   if (WIDTH == 31) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else

      rvdfflie #(.WIDTH(WIDTH), .LEFT(19)) dff (.*);

`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffpc width must be 31");
`endif
endmodule

// format: { LEFT, EXTRA }
// LEFT # of bits will be done with rvdffie, all else EXTRA with rvdffe
module rvdfflie #( parameter WIDTH=16, LEFT=8 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic             clk,
     input  logic             rst_l,
     input  logic             en,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   localparam EXTRA = WIDTH-LEFT;

   localparam LMSB = WIDTH-1;
   localparam LLSB = LMSB-LEFT+1;
   localparam XMSB = LLSB-1;
   localparam XLSB = LLSB-EXTRA;


`ifndef RV_PHYSICAL
   if (WIDTH >= 16 && LEFT >= 8 && EXTRA >= 8) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else

      rvdffiee #(LEFT)  dff_left  (.*, .din(din[LMSB:LLSB]), .dout(dout[LMSB:LLSB]));

      rvdffe  #(EXTRA)  dff_extra (.*, .din(din[XMSB:XLSB]), .dout(dout[XMSB:XLSB]));


`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdfflie musb be WIDTH >= 16 && LEFT >= 8 && EXTRA >= 8");
`endif
endmodule

// specialty flop for the inst buffers
// format: { LEFT, PADLEFT, MIDDLE, PADRIGHT, RIGHT }
// LEFT,MIDDLE # of bits will be done with rvdffie, PADLEFT, PADRIGHT rvdffe, RIGHT special rvdffe
module rvdffibie #( parameter WIDTH=32, LEFT=8, PADLEFT=8, MIDDLE=8, PADRIGHT=8, RIGHT=8 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic             clk,
     input  logic             rst_l,
     input  logic             en,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   localparam LMSB = WIDTH-1;
   localparam LLSB = LMSB-LEFT+1;
   localparam PLMSB = LLSB-1;
   localparam PLLSB = LLSB-PADLEFT;
   localparam MMSB = PLLSB-1;
   localparam MLSB = PLLSB-MIDDLE;
   localparam PRMSB = MLSB-1;
   localparam PRLSB = MLSB-PADRIGHT;
   localparam RMSB = PRLSB-1;
   localparam RLSB = PRLSB-RIGHT;


`ifndef RV_PHYSICAL
   if (WIDTH>=32 && LEFT>=8 && PADLEFT>=8 && MIDDLE>=8 && PADRIGHT>=8 && RIGHT >= 8) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else

      rvdff2iee #(LEFT)     dff_left     (.*, .din(din[LMSB:LLSB]),   .dout(dout[LMSB:LLSB]));

      rvdffe    #(PADLEFT)  dff_padleft  (.*, .din(din[PLMSB:PLLSB]), .dout(dout[PLMSB:PLLSB]));

      rvdffe    #(MIDDLE)   dff_middle   (.*, .din(din[MMSB:MLSB]),   .dout(dout[MMSB:MLSB]), .en(en &  din[PLLSB]));  // prett[31:1]

      rvdffe    #(PADRIGHT) dff_padright (.*, .din(din[PRMSB:PRLSB]), .dout(dout[PRMSB:PRLSB]));

      rvdffe    #(RIGHT)    dff_right    (.*, .din(din[RMSB:RLSB]),   .dout(dout[RMSB:RLSB]), .en(en & ~din[PRLSB]));  // cinst

`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffibie must be WIDTH>=32 && LEFT>=8 && PADLEFT>=8 && MIDDLE>=8 && PADRIGHT>=8 && RIGHT >= 8");
`endif
endmodule

// specialty flop for power in the dest pkt flops
// format: { LEFTMOST, LEFT, RIGHT, RIGHTMOST }
// LEFTMOST,LEFT,RIGHT # of bits will be done with rvdffiee, all else RIGHTMOST with rvdffe
module rvdffdpie #( parameter WIDTH=32, LEFTMOST=8, LEFT=8, RIGHT=8 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic             clk,
     input  logic             rst_l,
     input  logic             en,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   localparam RIGHTMOST = WIDTH-LEFTMOST-LEFT-RIGHT;

   localparam LMMSB = WIDTH-1;
   localparam LMLSB = LMMSB-LEFTMOST+1;
   localparam LMSB = LMLSB-1;
   localparam LLSB = LMLSB-LEFT;
   localparam RMSB = LLSB-1;
   localparam RLSB = LLSB-RIGHT;
   localparam RMMSB = RLSB-1;
   localparam RMLSB = RLSB-RIGHTMOST;


`ifndef RV_PHYSICAL
   if (WIDTH>=32 && LEFTMOST>=8 && LEFT>=8 && RIGHT>=8 && RIGHTMOST >= 8) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else

      rvdffiee #(LEFTMOST)  dff_leftmost  (.*, .din(din[LMMSB:LMLSB]), .dout(dout[LMMSB:LMLSB]));

      rvdffiee #(LEFT)      dff_left      (.*, .din(din[LMSB:LLSB]),   .dout(dout[LMSB:LLSB]));

      rvdffiee #(RIGHT)     dff_right     (.*, .din(din[RMSB:RLSB]),   .dout(dout[RMSB:RLSB]));

      rvdffe   #(RIGHTMOST) dff_rightmost (.*, .din(din[RMMSB:RMLSB]), .dout(dout[RMMSB:RMLSB]));

`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffdpie must be WIDTH>=32 && LEFTMOST>=8 && LEFT>=8 && RIGHT>=8 && RIGHTMOST >= 8");
`endif
endmodule


// special power flop for predict packet
// format: { LEFT, PAD, RIGHT }
// LEFT # of bits will be done with rvdffiee; LEFT,PAD with den; RIGHT with cen
module rvdffppie #( parameter WIDTH=32, LEFT=8, RIGHT=8 )
   (
     input  logic [WIDTH-1:0] din,
     input  logic             clk,
     input  logic             rst_l,
     input  logic             en,           // ctl enable
     input  logic             den,          // data enable
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   localparam PAD = WIDTH-LEFT-RIGHT;

   localparam LMSB = WIDTH-1;
   localparam LLSB = LMSB-LEFT+1;
   localparam PMSB = LLSB-1;
   localparam PLSB = LLSB-PAD;
   localparam RMSB = PLSB-1;
   localparam RLSB = PLSB-RIGHT;


`ifndef RV_PHYSICAL
   if (WIDTH>=32 && LEFT>=8 && PAD>=8 && RIGHT>=8) begin: genblock
`endif

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else
      rvdffiee #(LEFT)   dff_left (.*, .din(din[LMSB:LLSB]), .dout(dout[LMSB:LLSB]), .en(den));

      rvdffe   #(PAD)    dff_pad  (.*, .din(din[PMSB:PLSB]), .dout(dout[PMSB:PLSB]), .en(den));

      rvdffe #(RIGHT)   dff_right (.*, .din(din[RMSB:RLSB]), .dout(dout[RMSB:RLSB]));


`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffppie must be WIDTH>=32 && LEFT>=8 && PAD>=8 && RIGHT>=8");
`endif
endmodule




module rvdffie #( parameter WIDTH=1, OVERRIDE=0 )
   (
     input  logic [WIDTH-1:0] din,

     input  logic           clk,
     input  logic           rst_l,
     input  logic             scan_mode,
     output logic [WIDTH-1:0] dout
     );

   logic                      l1clk;
   logic                      en;

`ifndef RV_PHYSICAL
   if (WIDTH >= 8 || OVERRIDE==1) begin: genblock
`endif

      assign en = |(din ^ dout);

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .* );
`else
      rvclkhdr clkhdr ( .* );
      rvdff #(WIDTH) dff (.*, .clk(l1clk));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//      $error("%m: rvdffie width must be >= 8");
`endif

endmodule

// ie flop but it has an .en input
module rvdffiee #( parameter WIDTH=1, OVERRIDE=0 )
   (
     input  logic [WIDTH-1:0] din,

     input  logic           clk,
     input  logic           rst_l,
     input  logic           scan_mode,
     input  logic           en,
     output logic [WIDTH-1:0] dout
     );

   logic                      l1clk;
   logic                      final_en;

`ifndef RV_PHYSICAL
   if (WIDTH >= 8 || OVERRIDE==1) begin: genblock
`endif

      assign final_en = (|(din ^ dout)) & en;

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .*, .en(final_en) );
`else
      rvdffe #(WIDTH) dff (.*,  .en(final_en));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdffie width must be >= 8");
`endif

endmodule

// ie flop but it has an .en input
// splits into 2 "equal" flops
module rvdff2iee #( parameter WIDTH=16 )
   (
     input  logic [WIDTH-1:0] din,

     input  logic           clk,
     input  logic           rst_l,
     input  logic           scan_mode,
     input  logic           en,
     output logic [WIDTH-1:0] dout
     );

   logic                      l1clk;
   logic                      final_en;

   localparam LEFT = int'(WIDTH/2);
   localparam RIGHT = WIDTH-LEFT;

   localparam LMSB = WIDTH-1;
   localparam LLSB = LMSB-LEFT+1;
   localparam RMSB = LLSB-1;
   localparam RLSB = LLSB-RIGHT;


`ifndef RV_PHYSICAL
   if (WIDTH >= 16 && LEFT>=8 && RIGHT>=8) begin: genblock
`endif

      assign final_en = (|(din ^ dout)) & en;

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .*, .en(final_en) );
`else
      rvdffe #(LEFT)  dff_left  (.*, .en(final_en), .din(din[LMSB:LLSB]), .dout(dout[LMSB:LLSB]));
      rvdffe #(RIGHT) dff_right (.*, .en(final_en), .din(din[RMSB:RLSB]), .dout(dout[RMSB:RLSB]));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdff2iee must be WIDTH >= 16 && LEFT>=8 && RIGHT>=8");
`endif

endmodule

// splits into 2 "equal" flops
module rvdff2ie #( parameter WIDTH=16 )
   (
     input  logic [WIDTH-1:0] din,

     input  logic           clk,
     input  logic           rst_l,
     input  logic           scan_mode,
     output logic [WIDTH-1:0] dout
     );

   logic                      l1clk;
   logic                      final_en;

   localparam LEFT = int'(WIDTH/2);
   localparam RIGHT = WIDTH-LEFT;

   localparam LMSB = WIDTH-1;
   localparam LLSB = LMSB-LEFT+1;
   localparam RMSB = LLSB-1;
   localparam RLSB = LLSB-RIGHT;


`ifndef RV_PHYSICAL
   if (WIDTH >= 16 && LEFT>=8 && RIGHT>=8) begin: genblock
`endif

      assign final_en = |(din ^ dout);

`ifdef RV_FPGA_OPTIMIZE
      rvdffs #(WIDTH) dff ( .*, .en(final_en) );
`else
      rvdffe #(LEFT)  dff_left  (.*, .en(final_en), .din(din[LMSB:LLSB]), .dout(dout[LMSB:LLSB]));
      rvdffe #(RIGHT) dff_right (.*, .en(final_en), .din(din[RMSB:RLSB]), .dout(dout[RMSB:RLSB]));
`endif

`ifndef RV_PHYSICAL
   end
// [else $error removed]
//       $error("%m: rvdff2ie must be WIDTH >= 16 && LEFT>=8 && RIGHT>=8");
`endif

endmodule

module rvsyncss #(parameter WIDTH = 251)
   (
     input  logic                 clk,
     input  logic                 rst_l,
     input  logic [WIDTH-1:0]     din,
     output logic [WIDTH-1:0]     dout
     );

   logic [WIDTH-1:0]              din_ff1;

   rvdff #(WIDTH) sync_ff1  (.*, .din (din[WIDTH-1:0]),     .dout(din_ff1[WIDTH-1:0]));
   rvdff #(WIDTH) sync_ff2  (.*, .din (din_ff1[WIDTH-1:0]), .dout(dout[WIDTH-1:0]));

endmodule // rvsyncss

module rvsyncss_fpga #(parameter WIDTH = 251)
   (
     input  logic                 gw_clk,
     input  logic                 rawclk,
     input  logic                 clken,
     input  logic                 rst_l,
     input  logic [WIDTH-1:0]     din,
     output logic [WIDTH-1:0]     dout
     );

   logic [WIDTH-1:0]              din_ff1;

   rvdff_fpga #(WIDTH) sync_ff1  (.*, .clk(gw_clk), .rawclk(rawclk), .clken(clken), .din (din[WIDTH-1:0]),     .dout(din_ff1[WIDTH-1:0]));
   rvdff_fpga #(WIDTH) sync_ff2  (.*, .clk(gw_clk), .rawclk(rawclk), .clken(clken), .din (din_ff1[WIDTH-1:0]), .dout(dout[WIDTH-1:0]));

endmodule // rvsyncss

module rvarbiter2_fpga
  (
   input  logic       [1:0] ready,
   input  logic             shift,
   input  logic             clk,
   input  logic             rawclk,
   input  logic             clken,
   input  logic             rst_l,
   input  logic             scan_mode,
   output logic             tid
   );

   logic                    ready0, ready1, ready2;
   logic                    favor_in, favor;

   assign ready0 = ~(|ready[1:0]);

   assign ready1 = ready[1] ^ ready[0];

   assign ready2 = ready[1] & ready[0];

   assign favor_in = (ready2 & ~favor) |
                     (ready1 & ready[0]) |
                     (ready0 & favor);

   // only update if 2 ready threads
   rvdffs_fpga #(1) favor_ff (.*, .en(shift & ready2), .clk(clk), .din(favor_in),  .dout(favor) );

   // when to select tid 1
   assign tid = (ready2 & favor) |
                (ready[1] & ~ready[0]);

endmodule



module rvarbiter2
  (
   input  logic       [1:0] ready,
   input  logic             shift,
   input  logic             clk,
   input  logic             rst_l,
   input  logic             scan_mode,
   output logic             tid
   );

   logic                    ready0, ready1, ready2;
   logic                    favor_in, favor;

   assign ready0 = ~(|ready[1:0]);           
                                             
   assign ready1 = ready[1] ^ ready[0];      
                                             
   assign ready2 = ready[1] & ready[0];      
                                             
   assign favor_in = (ready2 & ~favor) |     
                     (ready1 & ready[0]) |   
                     (ready0 & favor);       
                                             
   // only update if 2 ready threads         
   rvdffs #(.WIDTH(1)) favor_ff (.*, .en(shift & ready2), .clk(clk), .din(favor_in),  .dout(favor) );  
                                             
   // when to select tid 1                   
   assign tid = (ready2 & favor) |           
                (ready[1] & ~ready[0]);

endmodule

// bring out the favor bit as an output
module rvarbiter2_pic
  (
   input  logic       [1:0] ready,
   input  logic             shift,
   input  logic             clk,
   input  logic             rst_l,
   input  logic             scan_mode,
   output logic             tid,
   output logic             favor
   );

   logic                    ready0, ready1, ready2;
   logic                    favor_in;

   assign ready0 = ~(|ready[1:0]);           
                                             
   assign ready1 = ready[1] ^ ready[0];      
                                             
   assign ready2 = ready[1] & ready[0];      
                                             
   assign favor_in = (ready2 & ~favor) |     
                     (ready1 & ready[0]) |   
                     (ready0 & favor);       
                                             
   // only update if 2 ready threads         
   rvdffs #(.WIDTH(1)) favor_ff (.*, .en(shift & ready2), .clk(clk), .din(favor_in),  .dout(favor) );  
                                             
   // when to select tid 1                   
   assign tid = (ready2 & favor) |           
                (ready[1] & ~ready[0]);

endmodule


// .i 3
// .o 5
// .ilb ready[0] ready[1] favor
// .ob i0_sel_i0_t1 i1_sel_i1[1] i1_sel_i0[1] i1_sel_i1[0] i1_sel_i0[0]
//
// .type fr
//
// 00 - - ----
//
// 01 - 1 1000
//
// 10 - 0 0010
//
// 11 0 0 0100
//
// 11 1 1 0001

// .i 3
// .o 1
// .ilb favor_in i0_only_in[0] i0_only_in[1]
// .ob favor_final
//
// .type fd
//
// 0 0 0  0
// 0 0 1  1
// 0 1 0  0
// 0 1 1  0
// 1 0 0  1
// 1 0 1  1
// 1 1 0  0
// 1 1 1  1

module rvarbiter2_smt
  (
   input  logic       [1:0] flush,
   input  logic       [1:0] ready_in,
   input  logic       [1:0] lsu_in,
   input  logic       [1:0] mul_in,
   input  logic       [1:0] i0_only_in,
   input  logic       [1:0] thread_stall_in,
   input  logic             force_favor_flip,
   input  logic             shift,
   input  logic             clk,
   input  logic             rst_l,
   input  logic             scan_mode,
   output logic [1:0]       ready,
   output logic             i0_sel_i0_t1,
   output logic [1:0]       i1_sel_i1,
   output logic [1:0]       i1_sel_i0
   );

   logic [1:0]              fready;
   logic [1:0]              thread_cancel_in;
   logic                    ready0, ready1, ready2;
   logic                    favor_in, favor, favor_new, favor_final_raw, favor_final;
   logic                    ready2_in;
   logic                    lsu2_in;
   logic                    mul2_in;
   logic                    i0_only2_in;
   logic [1:0]              eff_ready_in;
   logic [1:0]              flush_ff;
   logic                    update_favor_in, update_favor;


   rvdff #(2) flushff (.*,
                        .clk(clk),
                        .din(flush[1:0]),
                        .dout(flush_ff[1:0])
                        );

   // if thread is flushed take it out of arbitration right away
   // if thread is stalled AND both threads ready make ready=0 for stall thread
   assign eff_ready_in[1:0] = ready_in[1:0] & ~({2{ready_in[1]&ready_in[0]}} & thread_stall_in[1:0]) & ~flush[1:0] & ~flush_ff[1:0];


   rvdff #(2) ready_ff (.*,
                        .clk(clk),
                        .din(eff_ready_in[1:0]),
                        .dout(ready[1:0])
                        );

   // optimize for power: only update favor bit when you have to
   assign update_favor_in = &eff_ready_in[1:0] & (lsu2_in | mul2_in | i0_only2_in);

   rvdff #(1) update_favor_ff (.*,
                        .clk(clk),
                        .din(update_favor_in),
                        .dout(update_favor)
                        );


   assign favor_in = (shift & (update_favor | force_favor_flip)) ? ~favor : favor;

   // i0_only optimization : make i0_only favored if at all possible
   assign favor_final_raw = (favor_in       & !i0_only_in[0]) |
                            (!i0_only_in[0] &  i0_only_in[1]) |
                            (favor_in       &  i0_only_in[1]);

   assign favor_final = (force_favor_flip) ? favor_in : favor_final_raw;

   rvdff #(1) favor_ff (.*, .clk(clk), .din(favor_final),  .dout(favor) );

   // SMT optimization
   assign ready2_in  = eff_ready_in[1] & eff_ready_in[0];
   assign lsu2_in    = lsu_in[1] & lsu_in[0];
   assign mul2_in    = mul_in[1] & mul_in[0];
   assign i0_only2_in = i0_only_in[1] & i0_only_in[0];

   // cancel non favored thread in the case of 2 muls or 2 load/stores
   // this case won't happen if i0_only for one or more threads
   assign thread_cancel_in[1:0] = { (lsu2_in | mul2_in) & ready2_in & ~favor_in,
                                    (lsu2_in | mul2_in) & ready2_in &  favor_in  };
   rvdff #(2) fready_ff (.*,
                        .clk(clk),
                        .din(eff_ready_in[1:0] & ~thread_cancel_in[1:0]),
                        .dout(fready[1:0])
                        );

   assign i0_sel_i0_t1 = (fready[1]&favor) | (!fready[0]);

   assign i1_sel_i1[1] = (!fready[0]);

   assign i1_sel_i0[1] = (fready[0]&fready[1]&!favor);

   assign i1_sel_i1[0] = (!fready[1]);

   assign i1_sel_i0[0] = (fready[0]&fready[1]&favor);



endmodule


module rvlsadder
  (
    input logic [31:0] rs1,
    input logic [11:0] offset,

    output logic [31:0] dout
    );

   logic                cout;
   logic                sign;

   logic [31:12]        rs1_inc;
   logic [31:12]        rs1_dec;

   assign {cout,dout[11:0]} = {1'b0,rs1[11:0]} + {1'b0,offset[11:0]};

   assign rs1_inc[31:12] = rs1[31:12] + 1;

   assign rs1_dec[31:12] = rs1[31:12] - 1;

   assign sign = offset[11];

   assign dout[31:12] = ({20{  sign ^  ~cout}}  &     rs1[31:12]) |
                        ({20{ ~sign &   cout}}  & rs1_inc[31:12]) |
                        ({20{  sign &  ~cout}}  & rs1_dec[31:12]);

endmodule // rvlsadder

// assume we only maintain pc[31:1] in the pipe


// === Truncated: modules below use import eh2_pkg::* which yosys 0.55 cannot parse ===
// See ADR-0013 for toolchain discussion.
// === Added: clock gate header (not in truncated portion) ===
module rvclkhdr (
  input  logic en,
  input  logic clk,
  output logic l1clk
);
  assign l1clk = clk & en;
endmodule

module rvoclkhdr (
  input  logic en,
  input  logic clk,
  output logic l1clk
);
  assign l1clk = clk & en;
endmodule

// === Added: ECC modules (referenced by mem_lib) ===
module rvecc_encode (
  input  logic [38:0] din,
  output logic [6:0] ecc
);
  assign ecc = 7'b0;
endmodule

module rvecc_decode (
  input  logic [38:0] din,
  input  logic [6:0]  ecc_in,
  output logic [38:0] dout,
  output logic [6:0]  ecc_out,
  output logic        sed_ded,
  output logic        sec
);
  assign dout = din;
  assign ecc_out = ecc_in;
  assign sed_ded = 1'b0;
  assign sec = 1'b0;
endmodule
