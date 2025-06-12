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
    "import_srcs": attr.label_list(doc = "List of import expression source files."),
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

def binary_name(ctx, name):
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

def static_library_name(ctx, name):
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
