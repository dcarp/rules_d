"""Helper rule to export compiler and dub executables from the toolchain."""

def _tool_runner_impl(ctx):
    toolchain = ctx.toolchains["//d:toolchain_type"].d_toolchain_info
    dc_tool = toolchain.d_compiler[DefaultInfo]
    dub_tool = toolchain.dub_tool[DefaultInfo]
    if ctx.attr.which == "dc":
        tool = dc_tool.files_to_run.executable
        runfiles = dc_tool.data_runfiles
    elif ctx.attr.which == "dub":
        tool = dub_tool.files_to_run.executable
        runfiles = dub_tool.data_runfiles
    else:
        fail("Unknown tool: %s" % ctx.attr.which)

    tool_exe = ctx.actions.declare_file(ctx.attr.which + ".exe")
    ctx.actions.symlink(
        output = tool_exe,
        target_file = tool,
        is_executable = True,
    )
    print(dub_tool.data_runfiles.files)
    return [
        DefaultInfo(executable = tool_exe, runfiles = runfiles),
        # RunEnvironmentInfo(environment = {
        #     "DC": dc_tool.files_to_run.executable.path,
        #     "DUB": dub_tool.files_to_run.executable.path,
        # }),
    ]

tool_runner = rule(
    implementation = _tool_runner_impl,
    attrs = {
        "which": attr.string(values = ["dc", "dub"], mandatory = True),
    },
    executable = True,
    toolchains = ["//d:toolchain_type"],
)
