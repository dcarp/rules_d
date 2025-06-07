"""Rule for compiling D libraries."""

load("//d/private:providers.bzl", "DInfo")
load("//d/private/rules:common.bzl", "COMPILATION_MODE_FLAGS", "common_attrs")

def _static_library_name(ctx, name):
    """Generate the name of the static library."""
    if ctx.target_platform_has_constraint(ctx.attr._linux_constraint[platform_common.ConstraintValueInfo]):
        return "lib" + name + ".a"
    elif ctx.target_platform_has_constraint(ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]):
        return "lib" + name + ".a"
    elif ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]):
        return name + ".lib"
    else:
        fail("Unsupported OS for static library: %s" % ctx.label)

def _d_library_impl(ctx):
    """Implementation of d_library rule."""
    toolchain = ctx.toolchains["//d:toolchain_type"].d_toolchain_info
    output = ctx.actions.declare_file(_static_library_name(ctx, ctx.label.name))
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add("-lib")
    args.add_all(ctx.files.srcs)
    args.add_all(toolchain.compiler_flags)
    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [output],
        executable = toolchain.d_compiler[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "Dcompile",
        progress_message = "Compiling D library " + ctx.label.name,
        env = ctx.var,
    )
    return [DefaultInfo(files = depset([output])), DInfo()]

d_library = rule(
    implementation = _d_library_impl,
    attrs = dict(
        common_attrs.items() +
        {
            "module_paths": attr.string_list(doc = "List of module paths."),
            "source_only": attr.bool(
                doc = "If true, the source files are compiled, but not library is produced.",
            ),
        }.items(),
    ),
    toolchains = ["//d:toolchain_type"],
    provides = [DInfo],
)
