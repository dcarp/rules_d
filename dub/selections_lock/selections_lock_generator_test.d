module dub.selections_lock.selections_lock_generator_lib_test;

import std.algorithm : canFind;
import std.file : mkdirRecurse, tempDir, write;
import std.json : parseJSON;
import std.path : buildNormalizedPath;
import std.range : empty;
import std.uuid : randomUUID;

import build_file_generator : computeBuildFile, targetDefinition;
import model;
import selections_lock_generator;

string testPackagePath()
{
    auto path = buildNormalizedPath(tempDir, "rules_d_generate_selections_lock_test_" ~
            randomUUID.toString);
    path.mkdirRecurse;
    return path;
}

unittest
{
    // Builds one glob per source path and applies excludes only to the matching source path.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "extra/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");
    buildNormalizedPath(packagePath, "source/pkg/excluded.d").write("module pkg.excluded;");
    buildNormalizedPath(packagePath, "source/pkg/package.di").write("module pkg;");
    buildNormalizedPath(packagePath, "extra/pkg/extra.d").write("module pkg.extra;");

    auto groups = sourceGlobGroups(packagePath, ["source", "extra"],
        ["source/pkg/excluded.d"]);

    assert(groups.length == 2);
    assert(groups[0].patterns == ["source/**/*.d", "source/**/*.di"]);
    assert(groups[0].excludes == ["source/pkg/excluded.d"]);
    assert(groups[1].patterns == ["extra/**/*.d"]);
    assert(groups[1].excludes.empty);
}

unittest
{
    // Omits empty, current-directory, and parent-directory import paths from parsed targets.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": ["source"],
        "importPaths": ["", ".", "..", "source", "include/"]
    }`.parseJSON;

    auto target = parseRecipeTarget(recipe, packagePath, "pkg");

    assert(target.importPaths.valuesForCondition(genericPlatformCondition) == [
            "source", "include"
        ]);
}

unittest
{
    // Does not emit a default import when the package source path is the package root.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "pkg.d").write("module pkg;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": [""]
    }`.parseJSON;

    auto target = parseRecipeTarget(recipe, packagePath, "pkg");

    assert(target.importPaths.empty);
}

unittest
{
    // Does not add the package default source path when root sources are explicit.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");

    auto recipe = `{
        "name": "pkg",
        "sourceFiles": ["manual.d"]
    }`.parseJSON;

    string mainTargetName;
    auto targets = packageTargetsFromRecipe(recipe, packagePath, "pkg", mainTargetName);
    auto content = targetDefinition(targets[0]);

    assert(content.canFind(`srcs = ["manual.d"]`));
    assert(!content.canFind(`glob([`));
    assert(!content.canFind(`imports = [`));
}

unittest
{
    // Adds mainSourceFile to sources and treats it as an explicit source input.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");

    auto recipe = `{
        "name": "pkg",
        "mainSourceFile": "app.d"
    }`.parseJSON;

    string mainTargetName;
    auto targets = packageTargetsFromRecipe(recipe, packagePath, "pkg", mainTargetName);
    auto content = targetDefinition(targets[0]);

    assert(content.canFind(`srcs = ["app.d"]`));
    assert(!content.canFind(`glob([`));
    assert(!content.canFind(`imports = [`));
}

unittest
{
    // Keeps inline subpackages with explicit source files from receiving the generic package glob.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");
    buildNormalizedPath(packagePath, "utils").mkdirRecurse;
    buildNormalizedPath(packagePath, "utils/zlib.d").write("module zlib;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": ["source"],
        "subPackages": [
            {
                "name": "zlib",
                "sourceFiles": ["utils/zlib.d"],
                "targetType": "library"
            }
        ]
    }`.parseJSON;

    string mainTargetName;
    auto targets = packageTargetsFromRecipe(recipe, packagePath, "pkg", mainTargetName);
    auto content = targetDefinition(targets[1]);

    assert(content.canFind(`srcs = ["utils/zlib.d"]`));
    assert(!content.canFind(`glob([`));
    assert(!content.canFind(`imports = [`));
}

unittest
{
    // Renders OS, CPU, and non-Windows DUB settings as platform-specific selects.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": ["source"],
        "libs-windows": ["ws2_32"],
        "dflags-x86_64": ["-m64"],
        "dflags-posix": ["-fPIC"],
        "versions-linux": ["LinuxOnly"]
    }`.parseJSON;

    auto target = parseRecipeTarget(recipe, packagePath, "pkg");
    auto content = targetDefinition(target);

    assert(content.canFind(
            `linkopts = select({"@platforms//os:windows": ["-lws2_32"], "//conditions:default": []})`));
    assert(content.canFind(
            `select({"@platforms//cpu:x86_64": ["-m64"], "//conditions:default": []})`));
    assert(content.canFind(
            `select({"@platforms//os:windows": [], "//conditions:default": ["-fPIC"]})`));
    assert(content.canFind(
            `versions = select({"@platforms//os:linux": ["LinuxOnly"], "//conditions:default": []})`));
}

unittest
{
    // Emits compound OS+CPU config settings and platform-specific source selections.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");
    buildNormalizedPath(packagePath, "win/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "win/pkg/windows.d").write("module pkg.windows;");
    buildNormalizedPath(packagePath, "posix/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "posix/pkg/posix.d").write("module pkg.posix;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": ["source"],
        "sourceFiles-windows-x86_64-dmd": ["win/pkg/windows.d"],
        "sourcePaths-posix": ["posix"]
    }`.parseJSON;

    Package package_;
    package_.name = "pkg";
    package_.version_ = "1.0.0";
    package_.targets = [parseRecipeTarget(recipe, packagePath, "pkg")];
    package_.mainTargetName = package_.targets[0].targetName;

    auto content = computeBuildFile(package_);

    assert(content.canFind(`config_setting(`));
    assert(content.canFind(`name = "_dub_platform_windows_x86_64"`));
    assert(content.canFind(
            `constraint_values = ["@platforms//os:windows", "@platforms//cpu:x86_64"]`));
    assert(content.canFind(`":_dub_platform_windows_x86_64": ["win/pkg/windows.d"]`));
    assert(content.canFind(`"@platforms//os:windows": []`));
    assert(content.canFind(`"//conditions:default": glob(["posix/**/*.d"])`));
}

unittest
{
    // Ignores platform-specific source attributes with unsupported suffix tokens.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");
    buildNormalizedPath(packagePath, "win/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "win/pkg/windows.d").write("module pkg.windows;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": ["source"],
        "sourceFiles-windows-x86-dmd": ["win/pkg/windows.d"]
    }`.parseJSON;

    auto target = parseRecipeTarget(recipe, packagePath, "pkg");
    auto content = targetDefinition(target);

    assert(!content.canFind(`win/pkg/windows.d`));
    assert(!content.canFind(`"@platforms//os:windows"`));
}

unittest
{
    // Resolves path-backed dependencies locally and version-backed dependencies externally.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "source/pkg").mkdirRecurse;
    buildNormalizedPath(packagePath, "source/pkg/package.d").write("module pkg;");
    buildNormalizedPath(packagePath, "utils").mkdirRecurse;
    buildNormalizedPath(packagePath, "utils/sub.d").write("module sub;");

    auto recipe = `{
        "name": "pkg",
        "sourcePaths": ["source"],
        "subPackages": [
            {
                "name": "sub",
                "sourceFiles": ["utils/sub.d"],
                "dependencies": {
                    "pkg": {"path": "."},
                    "pkg:helper": {"path": "."},
                    "other": "~>1.0.0",
                    "unknown": "~>1.0.0"
                },
                "dependencies-windows-x86_64": {
                    "pkg:helper": {"path": "."},
                    "other": "~>1.0.0"
                },
                "targetType": "library"
            },
            {
                "name": "helper",
                "sourceFiles": ["utils/sub.d"],
                "targetType": "library"
            }
        ]
    }`.parseJSON;

    string mainTargetName;
    Package package_;
    package_.name = "pkg";
    package_.mainTargetName = "pkg";
    package_.targets = packageTargetsFromRecipe(recipe, packagePath, "pkg", mainTargetName);

    expandDependencyTargetNames(package_, ["other": "other_lib"]);

    auto dependencies = package_.targets[1].dependencies.valuesForCondition(
        genericPlatformCondition);
    assert(dependencies.canFind(":pkg"));
    assert(dependencies.canFind(":helper"));
    assert(dependencies.canFind("other:other_lib"));
    assert(dependencies.canFind("unknown"));
    assert(package_.targets[1].pathDependencies.empty);

    auto content = targetDefinition(package_.targets[1]);
    assert(content.canFind(`":pkg"`));
    assert(content.canFind(`":helper"`));
    assert(content.canFind(`"@%DUB_REPOSITORY_NAME%//other:other_lib"`));
    assert(content.canFind(`"@%DUB_REPOSITORY_NAME%//unknown"`));
    assert(content.canFind(`":_dub_platform_windows_x86_64"`));
    assert(content.canFind(`":helper"`));
    assert(content.canFind(`"@%DUB_REPOSITORY_NAME%//other:other_lib"`));
}

unittest
{
    // Converts DUB test configurations into canonical d_test targets.
    auto packagePath = testPackagePath;
    buildNormalizedPath(packagePath, "test").mkdirRecurse;
    buildNormalizedPath(packagePath, "test/main.d").write("module main;");

    auto recipe = `{
        "name": "pkg",
        "targetName": "pkg",
        "configurations": [
            {
                "name": "unittest",
                "targetType": "executable",
                "sourcePaths": ["test"]
            }
        ]
    }`.parseJSON;
    auto configuration = recipe["configurations"].array[0];

    auto target = parseTestConfigurationTarget(recipe, configuration, packagePath, "pkg");

    assert(target.targetType == TargetType.test);
    assert(target.targetName == "pkg_test");
    assert(target.sourceGlobGroups.length == 1);
    assert(target.sourceGlobGroups[0].groups[0].patterns == ["test/**/*.d"]);
}
