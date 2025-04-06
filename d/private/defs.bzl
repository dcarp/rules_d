"""D rule implementations."""

load("//d/private:common.bzl", "D_TOOLCHAIN")
load("//d/private:providers.bzl", "DInfo")

D_FILE_EXTENSIONS = [".d", ".di"]

COMPILATION_MODE_FLAGS = {
    "dbg": ["-debug", "-g"],
    "fastbuild": ["-g"],
    "opt": ["-O", "-release", "-inline"],
}

def _d_binary_name(name, os):
    """Generate the name of the binary."""
    if os == "linux":
        return name
    elif os == "macos":
        return name
    elif os == "windows":
        return name + ".exe"
    else:
        fail("Unsupported OS: %s" % os)

def _d_binary_impl(ctx):
    """Implementation of d_binary rule."""
    toolchain = ctx.toolchains[D_TOOLCHAIN].d_toolchain_info
    output = ctx.actions.declare_file(_d_binary_name(ctx.label.name, toolchain.os))
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add_all(ctx.files.srcs)
    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [output],
        executable = toolchain.compiler[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "Dcompile",
        progress_message = "Compiling D binary " + ctx.label.name,
        use_default_shell_env = True,
    )
    return [DefaultInfo(executable = output)]

d_binary = rule(
    implementation = _d_binary_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "List of D '.d' or '.di' source files.",
            allow_files = D_FILE_EXTENSIONS,
        ),
    },
    toolchains = [D_TOOLCHAIN],
    executable = True,
)

def _static_library_name(name, os):
    """Generate the name of the static library."""
    if os == "linux":
        return "lib" + name + ".a"
    elif os == "macos":
        return "lib" + name + ".a"
    elif os == "windows":
        return name + ".lib"
    else:
        fail("Unsupported OS: %s" % os)

def _d_library_impl(ctx):
    """Implementation of d_library rule."""
    toolchain = ctx.toolchains[D_TOOLCHAIN].d_toolchain_info
    output = ctx.actions.declare_file(
        _static_library_name(ctx.label.name, toolchain.os),
    )
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add("-lib")
    args.add_all(ctx.files.srcs)
    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [output],
        executable = toolchain.compiler[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "Dcompile",
        progress_message = "Compiling D library " + ctx.label.name,
    )

    return [DefaultInfo(files = depset([output])), DInfo()]

d_library = rule(
    implementation = _d_library_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "List of D '.d' or '.di' source files.",
            allow_files = D_FILE_EXTENSIONS,
        ),
    },
    fragments = ["platform"],
    toolchains = [D_TOOLCHAIN],
)

def _d_test_impl(ctx):
    """Implementation of d_binary rule."""
    toolchain = ctx.toolchains[D_TOOLCHAIN].d_toolchain_info
    output = ctx.actions.declare_file(_d_binary_name(ctx.label.name, toolchain.os))
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add("-main")
    args.add("-unittest")
    args.add_all(ctx.files.srcs)
    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [output],
        executable = toolchain.compiler[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "Dcompile",
        progress_message = "Compiling D binary " + ctx.label.name,
        use_default_shell_env = True,
    )
    return [DefaultInfo(executable = output)]

d_test = rule(
    implementation = _d_test_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "List of D '.d' or '.di' source files.",
            allow_files = D_FILE_EXTENSIONS,
        ),
    },
    toolchains = [D_TOOLCHAIN],
    test = True,
)
