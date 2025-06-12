"""D test rule for compiling and running D unit tests."""

load("//d/private/rules:common.bzl", "TARGET_TYPE", "common_attrs", "compilation_action")

def _d_test_impl(ctx):
    """Implementation of d_test rule."""
    return compilation_action(ctx, target_type = TARGET_TYPE.TEST)

d_test = rule(
    implementation = _d_test_impl,
    attrs = common_attrs,
    toolchains = ["//d:toolchain_type"],
    test = True,
)
