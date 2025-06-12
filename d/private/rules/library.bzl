"""Rule for compiling D libraries."""

load("//d/private:providers.bzl", "DInfo")
load("//d/private/rules:common.bzl", "TARGET_TYPE", "common_attrs", "compilation_action")

def _d_library_impl(ctx):
    """Implementation of d_library rule."""
    return compilation_action(ctx, target_type = TARGET_TYPE.LIBRARY)

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
