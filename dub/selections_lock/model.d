module model;

import std.range : empty;

enum TargetType
{
    autodetect,
    none,
    executable,
    library,
    sourceLibrary,
    dynamicLibrary,
    staticLibrary,
    object,
    test
}

struct Package
{
    string name;
    string version_;
    string integrity;
    string stripPrefix;
    string buildFileContent;
    string mainTargetName;
    Target[] targets;

    string versionedName() const
    {
        import std.format : format;

        return "%s-%s".format(name, version_);
    }
}

struct SourceGlobGroup
{
    string[] patterns;
    string[] excludes;
}

struct PlatformCondition
{
    string name;
    string[] constraintValues;
    bool posix;
}

PlatformCondition genericPlatformCondition()
{
    return PlatformCondition();
}

bool isGeneric(PlatformCondition condition)
{
    return condition.name.empty && condition.constraintValues.empty && !condition.posix;
}

string key(PlatformCondition condition)
{
    return condition.isGeneric ? "" : condition.name;
}

struct PlatformValues
{
    PlatformCondition condition;
    string[] values;
}

struct PlatformSourceGlobGroups
{
    PlatformCondition condition;
    SourceGlobGroup[] groups;
}

struct Target
{
    string targetName;
    TargetType targetType;
    string targetPath;
    string mainSourceFile;
    PlatformValues[] dflags;
    PlatformValues[] debugVersions;
    PlatformValues[] lflags;
    PlatformValues[] libs;
    PlatformValues[] copyFiles;
    PlatformValues[] sourceFiles;
    PlatformValues[] sourcePaths;
    PlatformValues[] excludedSourceFiles;
    PlatformSourceGlobGroups[] sourceGlobGroups;
    PlatformValues[] injectSourceFiles;
    PlatformValues[] versions;
    PlatformValues[] importPaths;
    PlatformValues[] stringImportPaths;
    PlatformValues[] stringSrcs;
    string[string] environments;
    string[string] buildEnvironments;
    string[string] runEnvironments;
    PlatformValues[] dependencies;
    PlatformValues[] pathDependencies;
}

string[] valuesForCondition(PlatformValues[] values, PlatformCondition condition)
{
    foreach (value; values)
    {
        if (value.condition.key == condition.key)
            return value.values;
    }
    return [];
}

PlatformValues[] mergePlatformValues(PlatformValues[] values)
{
    PlatformValues[] result;
    size_t[string] indexByCondition;
    foreach (value; values)
    {
        if (value.values.empty)
            continue;
        auto conditionKey = value.condition.key;
        auto index = conditionKey in indexByCondition;
        if (index is null)
        {
            indexByCondition[conditionKey] = result.length;
            result ~= value;
        }
        else
            result[*index].values ~= value.values;
    }
    return result;
}
