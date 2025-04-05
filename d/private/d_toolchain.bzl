"""D toolchain rules."""

DToolchainInfo = provider(
    doc = "D compiler information.",
    fields = {
        "all_files": "All files in the toolchain.",
        "compiler": "The D compiler executable.",
        "cpu": "Target CPU of the D toolchain.",
        "druntime_import_path": "The path to the D runtime library.",
        "dub": "The dub executable.",
        "dynamic_stdlib": "The dynamic runtime library.",
        "os": "Target OS of the D toolchain.",
        "static_stdlib": "The static runtime library.",
        "stdlib_import_path": "The path to the standard library.",
    },
)

def _d_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            d_toolchain_info = DToolchainInfo(
                all_files = ctx.attr.all_files,
                compiler = ctx.attr.compiler,
                cpu = ctx.attr.cpu,
                druntime_import_path = ctx.attr.druntime_import_path,
                dub = ctx.attr.dub,
                dynamic_stdlib = ctx.attr.dynamic_stdlib,
                os = ctx.attr.os,
                static_stdlib = ctx.attr.static_stdlib,
                stdlib_import_path = ctx.attr.stdlib_import_path,
            ),
        ),
    ]

d_toolchain = rule(
    doc = "Defines a D toolchain",
    implementation = _d_toolchain_impl,
    attrs = {
        "all_files": attr.label(
            allow_files = True,
            doc = "All files in the toolchain.",
        ),
        "compiler": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "The D compiler.",
        ),
        "cpu": attr.string(
            doc = "Target CPU for the toolchain.",
        ),
        "druntime_import_path": attr.string(
            doc = "Path to the D runtime library.",
        ),
        "dub": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The dub executable.",
        ),
        "dynamic_stdlib": attr.label(
            doc = "The dynamic runtime library.",
        ),
        "os": attr.string(
            mandatory = True,
            doc = "Target OS for the toolchain.",
        ),
        "static_stdlib": attr.label(
            doc = "The static runtime library.",
        ),
        "stdlib_import_path": attr.string(
            doc = "Path to the standard library.",
        ),
    },
    provides = [platform_common.ToolchainInfo],
)
