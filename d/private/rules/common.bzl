"""Common definitions for D rules."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
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
    "string_srcs": attr.label_list(doc = "List of string import source files."),
    "versions": attr.string_list(doc = "List of version identifiers."),
    "_linux_constraint": attr.label(default = "@platforms//os:linux", doc = "Linux platform constraint"),
    "_macos_constraint": attr.label(default = "@platforms//os:macos", doc = "macOS platform constraint"),
    "_windows_constraint": attr.label(default = "@platforms//os:windows", doc = "Windows platform constraint"),
}

def _get_os(ctx):
    if ctx.target_platform_has_constraint(ctx.attr._linux_constraint[platform_common.ConstraintValueInfo]):
        return "linux"
    elif ctx.target_platform_has_constraint(ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]):
        return "macos"
    elif ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]):
        return "windows"
    else:
        fail("Unsupported OS: %s" % ctx.label)

def _binary_name(ctx, name):
    """Returns the name of the binary based on the OS.

    Args:
        ctx: The rule context.
        name: The base name of the binary.
    Returns:
        The name of the binary file.
    """
    os = _get_os(ctx)
    if os == "linux" or os == "macos":
        return name
    elif os == "windows":
        return name + ".exe"
    else:
        fail("Unsupported os %s for binary: %s" % (os, name))

def _static_library_name(ctx, name):
    """Returns the name of the static library based on the OS.

    Args:
        ctx: The rule context.
        name: The base name of the library.
    Returns:
        The name of the static library file.
    """
    os = _get_os(ctx)
    if os == "linux" or os == "macos":
        return "lib" + name + ".a"
    elif os == "windows":
        return name + ".lib"
    else:
        fail("Unsupported os %s for static library: %s" % (os, name))

TARGET_TYPE = struct(
    BINARY = "binary",
    LIBRARY = "library",
    TEST = "test",
)

def compilation_action(ctx, target_type = TARGET_TYPE.LIBRARY):
    """Defines a compilation action for D source files.

    Args:
        ctx: The rule context.
        target_type: The type of the target, either 'binary', 'library', or 'test'.
    Returns:
        The provider containing the compilation information.
    """
    toolchain = ctx.toolchains["//d:toolchain_type"].d_toolchain_info
    d_deps = [d[DInfo] for d in ctx.attr.deps if DInfo in d]
    import_paths = depset(transitive = [d.import_paths for d in d_deps])
    string_import_paths = depset(
        ["."] if ctx.files.string_srcs else [],
        transitive = [d.string_import_paths for d in d_deps],
    )
    args = ctx.actions.args()
    args.add_all(COMPILATION_MODE_FLAGS[ctx.var["COMPILATION_MODE"]])
    args.add_all(ctx.files.srcs)
    args.add_all(import_paths.to_list(), format_each = "-I=%s")
    args.add_all(string_import_paths.to_list(), format_each = "-J=%s")
    args.add_all(toolchain.compiler_flags)
    output = None
    if target_type in [TARGET_TYPE.BINARY, TARGET_TYPE.TEST]:
        if target_type == TARGET_TYPE.TEST:
            args.add_all(["-main", "-unittest"])
        args.add_all(toolchain.linker_flags)
        for dep in d_deps:
            args.add_all(dep.libraries)
        output = ctx.actions.declare_file(_binary_name(ctx, ctx.label.name))
        args.add(output, format = "-of=%s")
    elif target_type == TARGET_TYPE.LIBRARY:
        args.add("-lib")
        if ctx.attr.source_only:
            args.add("-c")
        else:
            output = ctx.actions.declare_file(_static_library_name(ctx, ctx.label.name))
            args.add(output, format = "-of=%s")
    else:
        fail("Unsupported target type: %s" % target_type)

    ctx.actions.run(
        inputs = depset(
            ctx.files.srcs + ctx.files.string_srcs,
            transitive = [toolchain.d_compiler[DefaultInfo].default_runfiles.files] +
                         [d.imports for d in d_deps] +
                         [d.libraries for d in d_deps],
        ),
        outputs = [output] if output else [],
        executable = toolchain.d_compiler[DefaultInfo].files_to_run,
        arguments = [args],
        env = ctx.var,
        use_default_shell_env = target_type != TARGET_TYPE.LIBRARY,  # True to make the linker work properly
        mnemonic = "Dcompile",
        progress_message = "Compiling D %s %s" % (target_type, ctx.label.name),
    )
    if target_type == TARGET_TYPE.LIBRARY:
        return [
            DefaultInfo(files = depset([output])),
            DInfo(
                import_paths = depset(
                    [ctx.label.package],
                    transitive = [d.import_paths for d in d_deps],
                ),
                imports = depset(
                    ctx.files.srcs + ctx.files.string_srcs,
                    transitive = [d.imports for d in d_deps],
                ),
                libraries = depset(
                    [output] if target_type == TARGET_TYPE.LIBRARY and output else [],
                    transitive = [d.libraries for d in d_deps],
                ),
                string_import_paths = depset(
                    [ctx.label.package] if ctx.files.string_srcs else [],
                    transitive = [d.string_import_paths for d in d_deps],
                ),
            ),
        ]
    else:
        return [DefaultInfo(executable = output)]
