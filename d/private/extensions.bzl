"""Implementation for D rules extensions."""

load("//d/private:repositories.bzl", "d_register_toolchain")

_D_COMPILERS = ["dmd", "gdc", "ldc"]

_D_TOOLCHAIN_TAG = tag_class(
    attrs = dict(
        compiler = attr.string(
            default = _D_COMPILERS[0],
            doc = "Compiler type. One of: dmd, gdc, ldc",
            values = _D_COMPILERS,
        ),
        version = attr.string(doc = "Compiler version."),
    ),
)

def _find_modules(module_ctx):
    root = None
    our_module = None
    for mod in module_ctx.modules:
        if mod.is_root:
            root = mod
        if mod.name == "rules_d":
            our_module = mod
    if root == None:
        root = our_module
    if our_module == None:
        fail("Unable to find rules_d module")

    return root, our_module

def _d_impl(module_ctx):
    root, rules_d = _find_modules(module_ctx)

    toolchains = root.tags.toolchain or rules_d.tags.toolchain

    for toolchain in toolchains:
        d_register_toolchain(toolchain.compiler, toolchain.version)

d = module_extension(
    implementation = _d_impl,
    tag_classes = {
        "toolchain": _D_TOOLCHAIN_TAG,
    },
)
