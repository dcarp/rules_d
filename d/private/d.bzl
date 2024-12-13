"""D rule implementations."""

D_FILE_EXTENSIONS = [".d", ".di"]

def _d_library_impl(ctx):
    """Implementation of d_library rule."""
    print("d_library_impl")

d_library = rule(
    implementation = _d_library_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "List of D '.d' or '.di' source files.",
            allow_files = D_FILE_EXTENSIONS,
        ),
    },
    toolchains = ["//d:toolchain_type"],
)
