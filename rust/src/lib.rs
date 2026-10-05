// The futures of the matrix-sdk-ui timeline are deeper than the default limit allows
// the compiler to lay out.
#![recursion_limit = "256"]

pub mod api;
mod frb_generated;
mod matrix;
