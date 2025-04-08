"""D rule implementations."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//d/private:common.bzl", "D_TOOLCHAIN")
load("//d/private:providers.bzl", "DInfo")

D_FILE_EXTENSIONS = [".d", ".di"]

COMPILATION_MODE_FLAGS = {
    "dbg": ["-debug", "-g"],
    "fastbuild": ["-g"],
    "opt": ["-O", "-release", "-inline"],
}

common_attrs = {
    "srcs": attr.label_list(
        doc = "List of D '.d' or '.di' source files.",
        allow_files = D_FILE_EXTENSIONS,
        allow_empty = False,
    ),
    "deps": attr.label_list(doc = "List of dependencies.", providers = [[CcInfo], [DInfo]]),
    "import_files": attr.label_list(doc = "List of import files."),
    "import_paths": attr.string_list(doc = "List of import paths."),
    "versions": attr.string_list(doc = "List of version identifiers."),
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
    args.add_all(toolchain.compiler_flags)
    args.add_all(toolchain.linker_flags)
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
    attrs = common_attrs,
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
    args.add_all(toolchain.compiler_flags)
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
    attrs = dict(
        common_attrs.items() +
        {
            "module_paths": attr.string_list(doc = "List of module paths."),
            "source_only": attr.bool(
                doc = "If true, the source files are compiled, but not library is produced.",
            ),
        }.items(),
    ),
    toolchains = [D_TOOLCHAIN],
    provides = [DInfo],
)

def _d_test_impl(ctx):
    """Implementation of d_binary rule."""
    toolchain = ctx.toolchains[D_TOOLCHAIN].d_toolchain_info
    output = ctx.actions.declare_file(_d_binary_name(ctx.label.name, toolchain.os))
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add(output, format = "-of=%s")
    args.add_all(["-main", "-unittest"])
    args.add_all(ctx.files.srcs)
    args.add_all(toolchain.compiler_flags)
    args.add_all(toolchain.linker_flags)
    ctx.actions.run(
        inputs = ctx.files.srcs,
        outputs = [output],
        tools = [toolchain.compiler[DefaultInfo].default_runfiles.files],
        executable = toolchain.compiler[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "Dcompile",
        progress_message = "Compiling D binary " + ctx.label.name,
        use_default_shell_env = True,
    )
    return [DefaultInfo(executable = output)]

d_test = rule(
    implementation = _d_test_impl,
    attrs = common_attrs,
    toolchains = [D_TOOLCHAIN],
    test = True,
)
