"""D test rule for compiling and running D unit tests."""

load("//d/private/rules:common.bzl", "COMPILATION_MODE_FLAGS", "binary_name", "common_attrs")

def _d_test_impl(ctx):
    """Implementation of d_test rule."""
    toolchain = ctx.toolchains["//d:toolchain_type"].d_toolchain_info
    output = ctx.actions.declare_file(binary_name(ctx, ctx.label.name))
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add_all(["-main", "-unittest"])
    args.add_all(ctx.files.srcs)
    args.add_all(toolchain.compiler_flags)
    args.add_all(toolchain.linker_flags)

    # for dep in ctx.attr.deps:
    #     print(dep[DInfo].imports)
    #     print(dep[DInfo].static_libraries)
    ctx.actions.run(
        inputs = depset(
            direct = ctx.files.srcs,
            transitive = [toolchain.d_compiler[DefaultInfo].default_runfiles.files],
        ),
        outputs = [output],
        executable = toolchain.d_compiler[DefaultInfo].files_to_run,
        arguments = [args],
        env = ctx.var,
        mnemonic = "Dcompile",
        progress_message = "Compiling D binary " + ctx.label.name,
    )
    return [DefaultInfo(executable = output)]

d_test = rule(
    implementation = _d_test_impl,
    attrs = common_attrs,
    toolchains = ["//d:toolchain_type"],
    test = True,
)
