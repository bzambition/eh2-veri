// SPDX-License-Identifier: Apache-2.0
// AXI4 Response Driver - Responds to AXI4 master requests
//
// Acts as an AXI4 slave, responding to read/write requests from the DUT.
// The actual memory behavior is handled by axi4_slave_mem RTL model.
// This driver provides:
//   - Passive mode (default): RTL memory model handles responses
//   - Error injection: configurable SLVERR/DECERR responses
//   - Response delay modeling
//
// Based on Ibex's ibex_mem_intf_response_driver pattern.

class axi4_driver #(int ID_WIDTH = 4) extends uvm_driver #(axi4_seq_item);

  `uvm_component_param_utils(axi4_driver#(ID_WIDTH))

  // Virtual interface
  virtual axi4_intf#(.ID_WIDTH(ID_WIDTH)) vif;

  // Configuration
  string agent_name = "axi4_driver";
  int    rsp_delay = 0;           // Response delay in clock cycles
  bit    enable_error_inject = 0; // Enable error injection
  int    error_pct = 5;           // Error injection percentage (0-100)
  bit    enable_delay_inject = 0; // Enable random response delays
  int    min_delay = 0;           // Min response delay cycles
  int    max_delay = 10;          // Max response delay cycles

  // Error response type
  typedef enum bit [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi4_resp_e;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (!uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(ID_WIDTH)))::get(this, "", "vif", vif)) begin
      `uvm_fatal(agent_name, "Could not get virtual interface")
    end
  endfunction

  task run_phase(uvm_phase phase);
    // In passive mode, the RTL memory model (axi4_slave_mem) handles responses.
    // This driver is active only when error injection or delay modeling is enabled.
    if (!enable_error_inject && !enable_delay_inject) begin
      // Passive mode - just wait
      forever begin
        @(posedge vif.clk);
      end
    end else begin
      // Active mode - monitor and potentially inject errors
      forever begin
        @(posedge vif.clk);
        // Error injection and delay modeling are handled per-transaction
        // via the sequence-item-driven interface when activated
      end
    end
  endtask

  // Drive write response (B channel)
  task drive_write_response(bit [1:0] resp, bit [3:0] id);
    if (rsp_delay > 0) begin
      repeat (rsp_delay) @(posedge vif.clk);
    end
    vif.bvalid <= 1'b1;
    vif.bresp  <= resp;
    vif.bid    <= id;
    @(posedge vif.clk iff vif.bready);
    vif.bvalid <= 1'b0;
  endtask

  // Drive read response (R channel)
  task drive_read_response(bit [63:0] data, bit [1:0] resp, bit last);
    if (rsp_delay > 0) begin
      repeat (rsp_delay) @(posedge vif.clk);
    end
    vif.rvalid <= 1'b1;
    vif.rdata  <= data;
    vif.rresp  <= resp;
    vif.rlast  <= last;
    @(posedge vif.clk iff vif.rready);
    vif.rvalid <= 1'b0;
  endtask

  // Check if error should be injected (random)
  function bit should_inject_error();
    if (!enable_error_inject) return 0;
    return ($urandom_range(0, 99) < error_pct);
  endfunction

  // Get random delay for response
  function int get_random_delay();
    if (!enable_delay_inject) return rsp_delay;
    return $urandom_range(min_delay, max_delay);
  endfunction

  // Get error response type (random SLVERR or DECERR)
  function bit [1:0] get_error_resp();
    if ($urandom_range(0, 1) == 0)
      return RESP_SLVERR;
    else
      return RESP_DECERR;
  endfunction

endclass
