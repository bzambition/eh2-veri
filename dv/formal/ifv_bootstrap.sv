// IFV Bootstrap — includes macro/type-definition files before RTL compilation.
// eh2_pdef.vh defines the eh2_param_t packed struct type at $unit scope,
// which all subsequent RTL modules need for their `#(include "eh2_param.vh")` blocks.
// DO NOT include eh2_param.vh here — parameter declarations at file scope
// (outside a module) cause ncvlog parser errors (SVNOTY, EXPSMC) that
// cascade to every downstream RTL module.
`include "common_defines.vh"
`include "eh2_pdef.vh"

// Bootstrap module provides a home for any $unit-scope items that must
// live inside a design element.  Currently it exists only so the
// compilation unit contains at least one module (IFV sometimes requires
// a top-level module during -elaborate, separate from the RTL top).
module ifv_bootstrap ();
endmodule
