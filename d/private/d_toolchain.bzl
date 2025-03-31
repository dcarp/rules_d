"""D toolchain rules."""

load("//d/private:dc.bzl", "DcInfo")

def _d_toolchain_impl(ctx):
    return platform_common.ToolchainInfo(
        compiler = ctx.attr.compiler[DcInfo],
    )

d_toolchain = rule(
    doc = "Defines a D toolchain",
    implementation = _d_toolchain_impl,
    attrs = {
        "compiler": attr.label(
            manatory = True,
            providers = [DcInfo],
            cfg = "exec",
            doc = "The D compiler.",
        ),
    },
    provides = [platform_common.ToolchainInfo],
)
