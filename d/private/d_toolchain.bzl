"""D toolchain rules."""

DToolchainInfo = provider(
    doc = "D compiler information.",
    fields = {
        "all_files": "All files in the toolchain.",
        "compiler": "The D compiler executable.",
        "compiler_flags": "Compiler flags.",
        "cpu": "Target CPU of the D toolchain.",
        "dub": "The dub executable.",
        "linker_flags": "Linker flags.",
        "os": "Target OS of the D toolchain.",
    },
)

def _expand_toolchain_variables(input, ctx):
    """Expand toolchain variables in the input string."""
    d_toolchain_root = ctx.attr.compiler[DefaultInfo].files_to_run.executable.dirname
    return input.format(D_TOOLCHAIN_ROOT = d_toolchain_root)

def _d_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            d_toolchain_info = DToolchainInfo(
                all_files = ctx.attr.all_files,
                compiler = ctx.attr.compiler,
                compiler_flags = [_expand_toolchain_variables(cf, ctx) for cf in ctx.attr.compiler_flags],
                cpu = ctx.attr.cpu,
                dub = ctx.attr.dub,
                linker_flags = [_expand_toolchain_variables(lf, ctx) for lf in ctx.attr.linker_flags],
                os = ctx.attr.os,
            ),
        ),
    ]

d_toolchain = rule(
    doc = "Defines a D toolchain",
    implementation = _d_toolchain_impl,
    attrs = {
        "all_files": attr.label(
            doc = "All files in the toolchain.",
            allow_files = True,
        ),
        "compiler": attr.label(
            doc = "The D compiler.",
            executable = True,
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
        ),
        "compiler_flags": attr.string_list(
            doc = "Compiler flags.",
        ),
        "cpu": attr.string(
            doc = "Target CPU for the toolchain.",
            mandatory = True,
        ),
        "dub": attr.label(
            doc = "The dub executable.",
            executable = True,
            cfg = "exec",
        ),
        "linker_flags": attr.string_list(
            doc = "Linker flags.",
        ),
        "os": attr.string(
            doc = "Target OS for the toolchain.",
            mandatory = True,
        ),
    },
    provides = [platform_common.ToolchainInfo],
)
