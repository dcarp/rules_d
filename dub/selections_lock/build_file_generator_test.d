module dub.selections_lock.build_file_generator_test;

import std.algorithm : canFind;

import build_file_generator : computeBuildFile, targetDefinition;
import model;

unittest
{
    // Renders a library target with explicit sources, source globs, and supported D rule attrs.
    Target target;
    target.targetName = "pkg";
    target.targetType = TargetType.library;
    target.sourceFiles = [
        PlatformValues(genericPlatformCondition, ["manual.d"])
    ];
    target.sourceGlobGroups = [
        PlatformSourceGlobGroups(genericPlatformCondition, [
                SourceGlobGroup(["source/**/*.d"], []),
                SourceGlobGroup(["extra/**/*.d"], ["extra/generated.d"]),
            ]),
    ];
    target.importPaths = [
        PlatformValues(genericPlatformCondition, ["source", "extra"])
    ];
    target.dflags = [PlatformValues(genericPlatformCondition, ["-preview=in"])];
    target.debugVersions = [PlatformValues(genericPlatformCondition, ["Trace"])];
    target.lflags = [PlatformValues(genericPlatformCondition, ["-L/foo"])];
    target.libs = [PlatformValues(genericPlatformCondition, ["ssl"])];
    target.versions = [PlatformValues(genericPlatformCondition, ["HavePkg"])];
    target.stringImportPaths = [
        PlatformValues(genericPlatformCondition, ["views"])
    ];
    target.stringSrcs = [
        PlatformValues(genericPlatformCondition, ["views/template.txt"])
    ];
    target.dependencies = [
        PlatformValues(genericPlatformCondition, [":helper", "external:target"])
    ];

    auto content = targetDefinition(target);

    assert(content.canFind(`d_library(`));
    assert(content.canFind(
            `srcs = ["manual.d"] + glob(["source/**/*.d"]) + glob(["extra/**/*.d"], exclude = ["extra/generated.d"])`));
    assert(content.canFind(`imports = ["source", "extra"]`));
    assert(content.canFind(`dopts = ["-preview=in", "-debug=Trace"]`));
    assert(content.canFind(`linkopts = ["-L/foo", "-lssl"]`));
    assert(content.canFind(`versions = ["HavePkg"]`));
    assert(content.canFind(`string_imports = ["views"]`));
    assert(content.canFind(`string_srcs = ["views/template.txt"]`));
    assert(content.canFind(`deps = [":helper", "@%DUB_REPOSITORY_NAME%//external:target"]`));
}

unittest
{
    // Emits config settings for compound platform conditions.
    Target target;
    target.targetName = "pkg";
    target.targetType = TargetType.library;
    target.sourceFiles = [
        PlatformValues(genericPlatformCondition, ["pkg.d"]),
        PlatformValues(
            PlatformCondition("_dub_platform_windows_x86_64",
                ["@platforms//os:windows", "@platforms//cpu:x86_64"]),
            ["win/pkg/windows.d"]),
    ];

    Package package_;
    package_.name = "pkg";
    package_.version_ = "1.0.0";
    package_.targets = [target];

    auto content = computeBuildFile(package_);

    assert(content.canFind(`config_setting(`));
    assert(content.canFind(`name = "_dub_platform_windows_x86_64"`));
    assert(content.canFind(
            `constraint_values = ["@platforms//os:windows", "@platforms//cpu:x86_64"]`));
    assert(content.canFind(`":_dub_platform_windows_x86_64": ["win/pkg/windows.d"]`));
}

unittest
{
    // Renders executable-only attrs such as data files and merged runtime environment values.
    Target target;
    target.targetName = "tool";
    target.targetType = TargetType.executable;
    target.sourceFiles = [PlatformValues(genericPlatformCondition, ["tool.d"])];
    target.copyFiles = [
        PlatformValues(genericPlatformCondition, ["config.json"])
    ];
    target.environments = ["BASE": "1"];
    target.runEnvironments = ["RUN": "2"];

    auto content = targetDefinition(target);

    assert(content.canFind(`d_binary(`));
    assert(content.canFind(`data = ["config.json"]`));
    assert(content.canFind(`env = {"BASE": "1", "RUN": "2"}`));
}
