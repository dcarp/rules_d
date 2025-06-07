"""This module implements the D toolchain rule.
"""

DToolchainInfo = provider(
    doc = "D compiler information.",
    fields = {
        "all_files": "All files in the toolchain.",
        "d_compiler": "The D compiler executable.",
        "compiler_flags": "Default compiler flags.",
        "dub_tool": "The dub package manager executable.",
        "linker_flags": "Default linker flags.",
        "rdmd_tool": "The rdmd compile and execute utility.",
    },
)

# Avoid using non-normalized paths (workspace/../other_workspace/path)
def _to_manifest_path(ctx, file):
    if file.short_path.startswith("../"):
        return "external/" + file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _d_toolchain_impl(ctx):
    d_toolchain_files = depset(
        direct = [
            ctx.attr.d_compiler.files.to_list()[0],
            ctx.attr.dub_tool.files.to_list()[0],
            ctx.attr.rdmd_tool.files.to_list()[0],
        ],
        transitive = [
            ctx.attr.d_compiler.files,
            ctx.attr.dub_tool.files,
            ctx.attr.rdmd_tool.files,
        ],
    )

    # Make the $(tool_BIN) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "DC": _to_manifest_path(ctx, ctx.attr.d_compiler.files.to_list()[0]),
        "DUB": _to_manifest_path(ctx, ctx.attr.dub_tool.files.to_list()[0]),
    })
    default = DefaultInfo(
        files = d_toolchain_files,
        runfiles = ctx.runfiles(files = d_toolchain_files.to_list()),
    )
    d_toolchain_info = DToolchainInfo(
        all_files = d_toolchain_files,
        d_compiler = ctx.attr.d_compiler,
        compiler_flags = ctx.attr.compiler_flags,
        dub_tool = ctx.attr.dub_tool,
        linker_flags = ctx.attr.linker_flags,
        rdmd_tool = ctx.attr.rdmd_tool,
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        default = default,
        d_toolchain_info = d_toolchain_info,
        template_variables = template_variables,
    )
    return [
        default,
        toolchain_info,
        template_variables,
    ]

d_toolchain = rule(
    implementation = _d_toolchain_impl,
    attrs = {
        "d_compiler": attr.label(
            doc = "The D compiler.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
        "compiler_flags": attr.string_list(
            doc = "Compiler flags.",
        ),
        "dub_tool": attr.label(
            doc = "The dub package manager.",
            executable = True,
            cfg = "exec",
        ),
        "linker_flags": attr.string_list(
            doc = "Linker flags.",
        ),
        "rdmd_tool": attr.label(
            doc = "The rdmd compile and execute utility.",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = """Defines a d compiler/runtime toolchain.

For usage see https://docs.bazel.build/versions/main/toolchains.html#defining-toolchains.
""",
)
