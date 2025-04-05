"""Public definitions for D rules."""

load(
    "//d/private:defs.bzl",
    _d_binary = "d_binary",
    _d_library = "d_library",
    _d_test = "d_test",
)

d_binary = _d_binary
d_library = _d_library
d_test = _d_test
