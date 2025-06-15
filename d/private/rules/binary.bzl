"""D test rule for compiling binaries."""

load("//d/private/rules:common.bzl", "TARGET_TYPE", "common_attrs", "compilation_action")

def _d_binary_impl(ctx):
    """Implementation of d_binary rule."""
    return compilation_action(ctx, target_type = TARGET_TYPE.BINARY)

d_binary = rule(
    implementation = _d_binary_impl,
    attrs = common_attrs,
    toolchains = ["//d:toolchain_type"],
    executable = True,
)
