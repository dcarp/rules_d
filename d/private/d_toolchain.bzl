"""D toolchain rules."""

load("//d/private:dc.bzl", "DcInfo")

def _d_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        dcinfo = DcInfo(
            compiler_path = ctx.attr.compiler_path,
            import_paths = ctx.attr.import_paths,
            link_paths = ctx.attr.link_paths,
        ),
    )
    return [toolchain_info]

d_toolchain = rule(
    doc = "Defines a D toolchain",
    implementation = _d_toolchain_impl,
    attrs = {
        "compiler_path": attr.label(),
        "import_paths": attr.string_list(),
        "link_paths": attr.string_list(),
    },
    provides = [platform_common.ToolchainInfo],
)
