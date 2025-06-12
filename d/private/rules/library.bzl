"""Rule for compiling D libraries."""

load("//d/private:providers.bzl", "DInfo")
load("//d/private/rules:common.bzl", "COMPILATION_MODE_FLAGS", "common_attrs", "static_library_name")

def _d_library_impl(ctx):
    """Implementation of d_library rule."""
    toolchain = ctx.toolchains["//d:toolchain_type"].d_toolchain_info
    output = ctx.actions.declare_file(static_library_name(ctx, ctx.label.name))
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add("-lib")
    args.add_all(ctx.files.srcs)
    args.add_all(toolchain.compiler_flags)
    ctx.actions.run(
        inputs = depset(
            direct = ctx.files.srcs + ctx.files.import_srcs,
            transitive = [toolchain.d_compiler[DefaultInfo].default_runfiles.files],
        ),
        outputs = [output],
        executable = toolchain.d_compiler[DefaultInfo].files_to_run,
        arguments = [args],
        env = ctx.var,
        mnemonic = "Dcompile",
        progress_message = "Compiling D library " + ctx.label.name,
    )

    # print(ctx.files.srcs + ctx.files.import_srcs)
    # print(output)
    return [DefaultInfo(files = depset([output])), DInfo(static_libraries = [output])]

d_library = rule(
    implementation = _d_library_impl,
    attrs = dict(
        common_attrs.items() +
        {
            "source_only": attr.bool(
                doc = "If true, the source files are compiled, but not library is produced.",
            ),
        }.items(),
    ),
    toolchains = ["//d:toolchain_type"],
    provides = [DInfo],
)
