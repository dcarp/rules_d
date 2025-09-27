"""Helper rule to export compiler and dub executables from the toolchain."""

def _d_tool_impl(ctx):
    toolchain = ctx.toolchains["//d:toolchain_type"].d_toolchain_info
    dc_tool = toolchain.d_compiler[DefaultInfo]
    dub_tool = toolchain.dub_tool[DefaultInfo]
    rdmd_tool = toolchain.rdmd_tool[DefaultInfo]
    if ctx.attr.which == "dc":
        tool = dc_tool.files_to_run.executable
        runfiles = dc_tool.data_runfiles
    elif ctx.attr.which == "dub":
        tool = dub_tool.files_to_run.executable
        runfiles = dub_tool.data_runfiles
    elif ctx.attr.which == "rdmd":
        tool = rdmd_tool.files_to_run.executable
        runfiles = rdmd_tool.data_runfiles
    else:
        fail("Unknown tool: %s" % ctx.attr.which)

    tool_exe = ctx.actions.declare_file(ctx.attr.which + ".exe")
    ctx.actions.symlink(
        output = tool_exe,
        target_file = tool,
        is_executable = True,
    )
    return [
        DefaultInfo(executable = tool_exe, runfiles = runfiles),
    ]

d_tool = rule(
    implementation = _d_tool_impl,
    attrs = {
        "which": attr.string(values = ["dc", "dub", "rdmd"], mandatory = True),
    },
    executable = True,
    toolchains = ["//d:toolchain_type"],
)
