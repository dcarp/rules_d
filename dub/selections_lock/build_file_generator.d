module build_file_generator;

import std.algorithm : canFind, filter, map, sort, startsWith;
import std.array : array, replace;
import std.exception : enforce;
import std.format : format;
import std.range : chain, empty, join;

import model;

string headerDefinition(bool hasBinary, bool hasLibrary, bool hasTest)
{
    string[] rules;
    if (hasBinary)
        rules ~= "d_binary";
    if (hasLibrary)
        rules ~= "d_library";
    if (hasTest)
        rules ~= "d_test";
    if (rules.empty)
        return "";
    return "load(\"@rules_d//d:defs.bzl\", %s)".format(
        rules
            .map!(rule => rule.bzlStringLiteral)
            .join(", "));
}

bool needsConfigSetting(PlatformCondition condition)
{
    return !condition.posix && condition.constraintValues.length > 1;
}

void addConfigSetting(ref PlatformCondition[string] settings, PlatformCondition condition)
{
    if (condition.needsConfigSetting)
        settings[condition.name] = condition;
}

PlatformCondition[string] configSettings(Target[] targets)
{
    PlatformCondition[string] settings;
    foreach (target; targets)
    {
        foreach (values; target.dflags)
            settings.addConfigSetting(values.condition);
        foreach (values; target.debugVersions)
            settings.addConfigSetting(values.condition);
        foreach (values; target.lflags)
            settings.addConfigSetting(values.condition);
        foreach (values; target.libs)
            settings.addConfigSetting(values.condition);
        foreach (values; target.copyFiles)
            settings.addConfigSetting(values.condition);
        foreach (values; target.sourceFiles)
            settings.addConfigSetting(values.condition);
        foreach (values; target.sourceGlobGroups)
            settings.addConfigSetting(values.condition);
        foreach (values; target.versions)
            settings.addConfigSetting(values.condition);
        foreach (values; target.importPaths)
            settings.addConfigSetting(values.condition);
        foreach (values; target.stringImportPaths)
            settings.addConfigSetting(values.condition);
        foreach (values; target.stringSrcs)
            settings.addConfigSetting(values.condition);
        foreach (values; target.dependencies)
            settings.addConfigSetting(values.condition);
    }
    return settings;
}

string configSettingDefinition(PlatformCondition condition)
{
    return "config_setting(\n" ~
        "    name = \"%s\",\n".format(condition.name) ~
        "    constraint_values = %s,\n".format(condition.constraintValues.bzlListExpression) ~
        ")\n";
}

string bzlStringLiteral(string value)
{
    return "\"" ~ value.replace("\\", "\\\\").replace("\"", "\\\"") ~ "\"";
}

string bzlListExpression(string[] values)
{
    return "[" ~ values.map!(value => value.bzlStringLiteral).join(", ") ~ "]";
}

string bzlSelectKey(PlatformCondition condition)
{
    if (!condition.posix && condition.constraintValues.length == 1)
        return condition.constraintValues[0];
    return ":" ~ condition.name;
}

bool isOsLabel(string label)
{
    return label.startsWith("@platforms//os:");
}

string[] osSelectKeys(PlatformCondition condition)
{
    if (condition.posix && condition.constraintValues.empty)
        return ["@platforms//os:linux", "@platforms//os:osx"];
    if (!condition.posix && condition.constraintValues.length == 1 &&
        condition.constraintValues[0].isOsLabel)
        return [condition.constraintValues[0]];
    return [];
}

string bzlSelectExpression(string[string] values)
{
    return "select({" ~ values.byKeyValue
        .array
        .sort!((a, b) => a.key < b.key)
        .map!(item => "%s: %s".format(item.key.bzlStringLiteral, item.value))
        .chain(["%s: []".format("//conditions:default".bzlStringLiteral)])
        .join(", ") ~ "})";
}

string bzlSelectExpression(PlatformCondition condition, string valueExpression)
{
    if (condition.isGeneric)
        return valueExpression;
    if (condition.posix && condition.constraintValues.empty)
        return "select({" ~
            "%s: [], ".format("@platforms//os:windows".bzlStringLiteral) ~
            "%s: %s".format(
                "//conditions:default".bzlStringLiteral, valueExpression) ~
            "})";
    string[string] values;
    auto osKeys = condition.osSelectKeys;
    if (osKeys.empty)
        values[condition.bzlSelectKey] = valueExpression;
    else
        foreach (key; osKeys)
            values[key] = valueExpression;
    return values.bzlSelectExpression;
}

string minimizedOsSelectExpression(string[] keys, string valueExpression)
{
    keys = keys.sort.array;
    if (keys == ["@platforms//os:linux", "@platforms//os:osx"])
        return "select({" ~
            "%s: [], ".format("@platforms//os:windows".bzlStringLiteral) ~
            "%s: %s".format(
                "//conditions:default".bzlStringLiteral, valueExpression) ~
            "})";
    string[string] values;
    foreach (key; keys)
        values[key] = valueExpression;
    return values.bzlSelectExpression;
}

string bzlListOrSelectExpression(PlatformValues[] platformValues)
{
    string[] expressions;
    string[][string] osKeysByValue;
    foreach (platformValue; platformValues)
    {
        if (platformValue.values.empty)
            continue;
        auto valueExpression = platformValue.values.bzlListExpression;
        if (platformValue.condition.isGeneric)
            expressions ~= valueExpression;
        else
        {
            auto osKeys = platformValue.condition.osSelectKeys;
            if (osKeys.empty)
                expressions ~= platformValue.condition.bzlSelectExpression(valueExpression);
            else
                osKeysByValue[valueExpression] ~= osKeys;
        }
    }
    foreach (item; osKeysByValue.byKeyValue.array.sort!((a, b) => a.key < b.key))
    {
        string[] keys;
        foreach (key; item.value)
        {
            if (!keys.canFind(key))
                keys ~= key;
        }
        if (!keys.empty)
            expressions ~= keys.minimizedOsSelectExpression(item.key);
    }
    return expressions.join(" + ");
}

PlatformValues[] mapPlatformValues(PlatformValues[] values, string function(string) transform)
{
    return values
        .map!(value => PlatformValues(value.condition, value.values
                .map!(item => transform(item)).array))
        .array;
}

string debugVersionOption(string debugVersion)
{
    return "-debug=" ~ debugVersion;
}

string libraryOption(string library)
{
    return "-l" ~ library;
}

string dependencyLabel(string dependency)
{
    return dependency.startsWith(":") ? dependency : "@%DUB_REPOSITORY_NAME%//" ~ dependency;
}

string bzlDictExpression(string[string] values)
{
    return "{" ~ values.byKeyValue
        .array
        .sort!((a, b) => a.key < b.key)
        .map!(item => "%s: %s".format(item.key.bzlStringLiteral, item.value.bzlStringLiteral))
        .join(", ") ~ "}";
}

string sourceGlobExpression(Target target)
{
    return target.sourceGlobGroups
        .filter!(group => !group.groups.empty)
        .map!(group => group.condition.bzlSelectExpression(group.groups.sourceGlobExpression))
        .filter!(expression => !expression.empty)
        .join(" + ");
}

string sourceGlobExpression(SourceGlobGroup[] groups)
{
    string[] globs;
    foreach (group; groups)
    {
        auto glob = "glob(" ~ group.patterns.bzlListExpression;
        if (!group.excludes.empty)
            glob ~= ", exclude = " ~ group.excludes.bzlListExpression;
        globs ~= glob ~ ")";
    }
    return globs.join(" + ");
}

string sourceExpression(Target target)
{
    string[] expressions;
    foreach (sourceFiles; target.sourceFiles)
    {
        if (!sourceFiles.values.empty)
            expressions ~= sourceFiles.condition.bzlSelectExpression(
                sourceFiles.values.bzlListExpression);
    }
    if (!target.sourceGlobGroups.empty)
        expressions ~= target.sourceGlobExpression;
    enforce(!expressions.empty, "Target %s has no D source files.".format(target.targetName));
    return expressions.join(" + ");
}

string[string] runEnvironment(Target target)
{
    auto env = target.environments;
    foreach (item; target.runEnvironments.byKeyValue)
        env[item.key] = item.value;
    return env;
}

string targetDefinition(Target target)
{
    string[] result;
    switch (target.targetType)
    {
    case TargetType.library:
    case TargetType.sourceLibrary:
    case TargetType.dynamicLibrary:
    case TargetType.staticLibrary:
        result ~= "d_library(";
        break;
    case TargetType.executable:
        result ~= "d_binary(";
        break;
    case TargetType.test:
        result ~= "d_test(";
        break;
    default:
        enforce(false, "Unsupported target type %s.".format(target.targetType));
        return "";
    }
    result ~= "    name = \"%s\",".format(target.targetName);
    result ~= "    srcs = %s,".format(target.sourceExpression);
    auto imports = target.importPaths.bzlListOrSelectExpression;
    if (!imports.empty)
        result ~= "    imports = %s,".format(imports);
    auto dopts = (target.dflags ~ target.debugVersions.mapPlatformValues(&debugVersionOption))
        .mergePlatformValues;
    auto doptsExpression = dopts.bzlListOrSelectExpression;
    if (!doptsExpression.empty)
        result ~= "    dopts = %s,".format(doptsExpression);
    auto linkopts = (target.lflags ~ target.libs.mapPlatformValues(&libraryOption))
        .mergePlatformValues;
    auto linkoptsExpression = linkopts.bzlListOrSelectExpression;
    if (!linkoptsExpression.empty)
        result ~= "    linkopts = %s,".format(linkoptsExpression);
    auto stringImports = target.stringImportPaths.bzlListOrSelectExpression;
    if (!stringImports.empty)
        result ~= "    string_imports = %s,".format(stringImports);
    auto stringSrcs = target.stringSrcs.bzlListOrSelectExpression;
    if (!stringSrcs.empty)
        result ~= "    string_srcs = %s,".format(stringSrcs);
    auto versions = target.versions.bzlListOrSelectExpression;
    if (!versions.empty)
        result ~= "    versions = %s,".format(versions);
    if ([TargetType.executable, TargetType.test].canFind(target.targetType))
    {
        auto env = target.runEnvironment;
        if (!env.empty)
            result ~= "    env = %s,".format(env.bzlDictExpression);
        auto data = target.copyFiles.bzlListOrSelectExpression;
        if (!data.empty)
            result ~= "    data = %s,".format(data);
    }
    if (target.targetType == TargetType.sourceLibrary)
        result ~= "    source_only = True,";
    result ~= "    visibility = [\"//visibility:public\"],";
    auto depsExpression = target.dependencies.mapPlatformValues(&dependencyLabel)
        .bzlListOrSelectExpression;
    if (!depsExpression.empty)
        result ~= "    deps = %s,".format(depsExpression);
    result ~= ")\n";
    return result.join("\n");
}

string computeBuildFile(Package package_, bool verbose = false)
{
    bool hasBinary = package_.targets.canFind!(t => t.targetType == TargetType.executable);
    bool hasTest = package_.targets.canFind!(t => t.targetType == TargetType.test);
    bool hasLibrary = package_.targets
        .canFind!(t => [
                TargetType.library, TargetType.sourceLibrary,
                TargetType.dynamicLibrary, TargetType.staticLibrary
            ].canFind(t.targetType));

    if (!hasBinary && !hasLibrary && !hasTest)
        return "";

    string[] buildFileSections;
    buildFileSections ~= headerDefinition(hasBinary, hasLibrary, hasTest);
    auto settings = package_.targets.configSettings;
    if (!settings.empty)
        buildFileSections ~= settings.byValue
            .array
            .sort!((a, b) => a.name < b.name)
            .map!(setting => setting.configSettingDefinition)
            .join("\n");
    buildFileSections ~= package_.targets
        .map!(t => targetDefinition(t))
        .join("\n");
    auto buildFileContent = buildFileSections.join("\n\n");
    if (verbose)
    {
        import std.stdio : writeln;

        writeln("Generated BUILD file content for package ", package_.versionedName, ":\n",
            buildFileContent);
    }
    return buildFileContent;
}
