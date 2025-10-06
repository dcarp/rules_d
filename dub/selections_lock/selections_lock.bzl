"""Provides a macro to manage dub dependencies with a lock file.
"""

load("@bazel_skylib//rules:native_binary.bzl", "native_binary", "native_test")

def dub_lock_dependencies(
        name,
        src = None,
        dub_selections_lock = None,
        tags = [],
        visibility = None,
        **kwargs):
    """Generates targets for managing dub dependencies.

    It generates two targets:
    - `bazel test [name].test` to verify that the lock file is up to date.
    - `bazel run [name].update` to update the lock file.

    Args:
        name: The name of the target.
        src: file containing the dub dependencies. Supported inputs are:
            * dub.sdl
            * dub.json
            * dub.selections.json
        dub_selections_lock: The output lock file `dub.selections.lock.json`.
        tags: Optional list of tags to attach to both `.test` and `.update` targets.
        visibility: Optional list of visibility labels for both `.test` and `.update` targets.
        **kwargs: Additional keyword arguments passed to the `_test` rule.
    """
    if not src:
        fail("The 'src' attribute is required.")
    if not dub_selections_lock:
        fail("The 'dub_selections_lock' attribute is required.")

    test_target_name = name + ".test"
    update_target_name = name + ".update"
    update_target_full_name = "//{}:{}".format(native.package_name(), update_target_name)

    native_binary(
        name = update_target_name,
        src = "//dub/selections_lock",
        data = [
            src,
            dub_selections_lock,
        ],
        env = {
            "DC": "$(DC)",
            "DUB": "$(DUB)",
        },
        args = [
            "--generate",
            "--bazel_generating_target={}".format(update_target_full_name),
            "--input={}".format(src),
            "--output={}".format(dub_selections_lock),
        ],
        tags = tags + [
            "no-remote",
            "no-sandbox",
        ],
        visibility = visibility,
    )

    native_test(
        name = test_target_name,
        src = "//dub/selections_lock",
        data = [
            src,
            dub_selections_lock,
        ],
        args = [
            "--check",
            "--bazel_generating_target={}".format(update_target_full_name),
            "--input={}".format(src),
            "--output={}".format(dub_selections_lock),
        ],
        tags = tags + [
            "no-remote",
            "no-sandbox",
        ],
        visibility = visibility,
        **kwargs
    )

    native.genrule(
        name = name + ".bla",
        cmd = "echo DC=$(DC) DUB=$(DUB) $(location @rules_d//dub/selections_lock) > $@",
        executable = True,
        outs = [name + "bla.bat"],
        toolchains = ["@rules_d//d:resolved_toolchain"],
        tools = ["@rules_d//dub/selections_lock"],
    )
