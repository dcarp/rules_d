"""Implementation for D rules extensions."""

load(":common.bzl", "d_toolchain_attrs", "default_compiler", "default_versions")
load(":repositories.bzl", "d_toolchains_repo")

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
    if len(toolchains) > 1:
        fail("Multiple toolchains not supported yet")

    # register default toolchain if nothing specified
    if not toolchains:
        d_toolchains_repo(
            name = "d_toolchains",
            compiler = default_compiler,
            version = default_versions[default_compiler],
        )

    for toolchain in toolchains:
        if toolchain.compiler == "gdc":
            fail("gdc compiler not supported yet")
        if not toolchain.compiler:
            toolchain.compiler = default_compiler
        if not toolchain.version:
            toolchain.version = default_versions[toolchain.compiler]
        d_toolchains_repo(
            name = "d_toolchains",
            compiler = toolchain.compiler,
            version = toolchain.version,
        )

d = module_extension(
    implementation = _d_impl,
    tag_classes = {
        "toolchain": tag_class(attrs = d_toolchain_attrs),
    },
)
