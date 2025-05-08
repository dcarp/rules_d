"""This module implements the language-specific toolchain rule.
"""

DInfo = provider(
    doc = "Information about how to invoke the tool executable.",
    fields = {
        "target_tool_path": "Path to the tool executable for the target platform.",
        "tool_files": """Files required in runfiles to make the tool executable available.

May be empty if the target_tool_path points to a locally installed tool binary.""",
    },
)

# Avoid using non-normalized paths (workspace/../other_workspace/path)
def _to_manifest_path(ctx, file):
    if file.short_path.startswith("../"):
        return "external/" + file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _d_toolchain_impl(ctx):
    if ctx.attr.target_tool and ctx.attr.target_tool_path:
        fail("Can only set one of target_tool or target_tool_path but both were set.")
    if not ctx.attr.target_tool and not ctx.attr.target_tool_path:
        fail("Must set one of target_tool or target_tool_path.")

    tool_files = []
    target_tool_path = ctx.attr.target_tool_path

    if ctx.attr.target_tool:
        tool_files = ctx.attr.target_tool.files.to_list()
        target_tool_path = _to_manifest_path(ctx, tool_files[0])

    # Make the $(tool_BIN) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "DC": ctx.attr.compiler.path,
        "DUB": ctx.attr.dub.path,
    })
    default = DefaultInfo(
        files = depset(tool_files),
        runfiles = ctx.runfiles(files = tool_files),
    )
    dinfo = DInfo(
        target_tool_path = target_tool_path,
        tool_files = tool_files,
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        default = default,
        dinfo = dinfo,
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
        "all_files": attr.label(
            doc = "All files in the toolchain.",
            allow_files = True,
        ),
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
