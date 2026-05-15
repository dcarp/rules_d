module dub.selections_lock.selections_lock_generator;

import std.algorithm : canFind, each, filter, map, sort, startsWith;
import std.array : array, assocArray, replace, split;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, getSize, isFile, mkdirRecurse, read, readText, rmdirRecurse;
import std.format : format;
import std.json : parseJSON, JSONOptions, JSONType, JSONValue;
import std.path : baseName, buildNormalizedPath, dirName, relativePath;
import std.range : empty, join;
import std.string : endsWith, indexOf, lastIndexOf, startsWith, stripRight;
import std.stdio : toFile;
import std.typecons : Flag, tuple;

import integrity_hash : computeIntegrityHash;
import build_file_generator : computeBuildFile;
import model;
import mvs : ModuleVersion, minimalVersionSelection;
import semver : SemVer, SemVerRange;

struct Config
{
    string bazelGeneratingTarget;
    string cachePath;
    string dubExecutable;
    enum string dubRegistryUrl = "https://code.dlang.org/packages";
    Flag!"IncludeTests" includeTests;
    Flag!"SkipSSLVerification" skipSSLVerification;
    Flag!"Verbose" verbose;
}

__gshared Config _config;

void setConfig(string bazelGeneratingTarget, string cachePath, string dubExecutable,
    Flag!"IncludeTests" includeTests, Flag!"SkipSSLVerification" skipSSLVerification,
    Flag!"Verbose" verbose)
{
    if (!bazelGeneratingTarget.empty)
        _config.bazelGeneratingTarget = bazelGeneratingTarget;
    if (!cachePath.empty)
        _config.cachePath = cachePath;
    if (!dubExecutable.empty)
        _config.dubExecutable = dubExecutable;
    _config.includeTests = includeTests;
    _config.skipSSLVerification = skipSSLVerification;
    _config.verbose = verbose;
}

auto config()
{
    return _config;
}

string archiveFile(Package package_)
{
    return buildNormalizedPath(config.cachePath, "%s.zip".format(package_.versionedName));
}

string unpackPath(Package package_)
{
    return buildNormalizedPath(config.cachePath, package_.versionedName);
}

string url(Package package_)
{
    return format!"%s/%s/%s.zip"(config.dubRegistryUrl, package_.name, package_.version_);
}

Package[] parseDubSelectionsJson(string content)
{
    auto json = content.parseJSON;
    enforce(json.type == JSONType.object, "Expected JSON object at root.");
    enforce(json["fileVersion"].integer == 1, "Unsupported fileVersion, expected 1.");

    return json["versions"]
        .object
        .byKeyValue
        .filter!(item => item.value.type == JSONType.string)
        .map!(item => Package(item.key, item.value.str))
        .array;
}

string manifestContentForDubUpgrade(string manifestFilePath)
{
    auto content = manifestFilePath.readText;
    if (!manifestFilePath.baseName.endsWith(".json"))
        return content;

    auto json = content.parseJSON;
    if (json.type != JSONType.object || !("dependencies" in json.object) ||
        json["dependencies"].type != JSONType.object)
        return content;

    string[] localDependencies;
    foreach (dependency; json["dependencies"].object.byKeyValue)
    {
        if (dependency.value.type == JSONType.object && "path" in dependency.value.object)
            localDependencies ~= dependency.key;
    }
    if (localDependencies.empty)
        return content;

    foreach (dependencyName; localDependencies)
        json["dependencies"].object.remove(dependencyName);

    return json.toPrettyString(JSONOptions.doNotEscapeSlashes);
}

string generateDubSelectionsJson(string manifestFilePath, string[] manifestFilePaths)
{
    import std.process : execute;
    import std.stdio : writeln;

    auto packageMirrorPath = buildNormalizedPath(config.cachePath, "__dub_manifest_root__");
    if (packageMirrorPath.exists)
        packageMirrorPath.rmdirRecurse;
    packageMirrorPath.mkdirRecurse;
    scope (exit)
    {
        if (packageMirrorPath.exists)
            packageMirrorPath.rmdirRecurse;
    }

    foreach (inputManifestFilePath; manifestFilePaths)
    {
        auto packageManifestFilePath = buildNormalizedPath(packageMirrorPath, inputManifestFilePath);
        packageManifestFilePath.dirName.mkdirRecurse;
        inputManifestFilePath.manifestContentForDubUpgrade.toFile(packageManifestFilePath);
        if (config.verbose)
            writeln("Copied manifest file from ", inputManifestFilePath, " to ", packageManifestFilePath);
    }

    auto packagePath = buildNormalizedPath(packageMirrorPath, manifestFilePath.dirName);

    auto command = [
        config.dubExecutable,
        "upgrade",
        "--missing-only",
        "--root=%s".format(packagePath),
        "--cache=local",
        config.verbose ? "--verbose": "--quiet",
    ];

    if (config.verbose)
        writeln("Running dub command in ", packagePath, ": ", command.join(" "));

    auto result = execute(command);
    enforce(result.status == 0, "Failed to generate dub.selections.json from %s: %s".format(
            manifestFilePath, result.output));

    auto selectionsFilePath = buildNormalizedPath(packagePath, "dub.selections.json");
    enforce(selectionsFilePath.exists && selectionsFilePath.isFile,
        "Failed to generate dub.selections.json from %s.".format(manifestFilePath));
    return selectionsFilePath.readText;
}

Package[] readDubDependencies(string filePath, string[] manifestFilePaths)
{
    auto fileName = filePath.baseName;
    if (fileName == "dub.selections.json")
        return filePath.readText.parseDubSelectionsJson;
    if (fileName.endsWith(".json"))
    {
        auto content = filePath.readText;
        auto json = content.parseJSON;
        if (json.type == JSONType.object &&
            "fileVersion" in json.object &&
            "versions" in json.object)
            return content.parseDubSelectionsJson;
        return filePath.generateDubSelectionsJson(manifestFilePaths).parseDubSelectionsJson;
    }
    if (fileName == "dub.sdl")
        return filePath.generateDubSelectionsJson(manifestFilePaths).parseDubSelectionsJson;

    enforce(false, "Unsupported input file %s. Expected JSON selections, dub.json, or dub.sdl.".format(
            filePath));
    return [];
}

Package[] resolveDubDependencies(Package[] packages)
{
    enum rootVersion = "0.0.0";
    enum rootPrefix = "__rules_d_dub_lock_root_";
    SemVerRange[string] rootConstraints;
    SemVer[][string] availableVersions;
    SemVerRange[string][ModuleVersion] dependencies;
    Package[ModuleVersion] packageByVersion;

    foreach (i, package_; packages)
    {
        auto semVer = SemVer(package_.version_);
        enforce(semVer.isValid, "Invalid semantic version '%s' for package %s.".format(
                package_.version_, package_.name));
        auto rootName = rootPrefix ~ i.to!string;
        rootConstraints[rootName] = SemVerRange(">=" ~ rootVersion);
        availableVersions[rootName] = [SemVer(rootVersion)];
        dependencies[ModuleVersion(rootName, SemVer(rootVersion))] = [
            package_.name: SemVerRange(">=" ~ package_.version_),
        ];
        availableVersions[package_.name] ~= semVer;
        packageByVersion[ModuleVersion(package_.name, semVer)] = package_;
    }

    auto selectedVersions = minimalVersionSelection(rootConstraints, availableVersions, dependencies);
    return selectedVersions.byKeyValue
        .filter!(item => !item.key.startsWith(rootPrefix))
        .array
        .sort!((a, b) => a.key < b.key)
        .map!(item => packageByVersion[ModuleVersion(item.key, item.value)])
        .array;
}

void download(Package package_)
{
    import curl_downloader : CurlDownloader;

    auto downloader = CurlDownloader(config.skipSSLVerification);
    downloader.downloadToFile(package_.url, package_.archiveFile);
}

string computePackageIntegrity(Package package_)
{
    if (!package_.archiveFile.exists || package_.archiveFile.getSize == 0)
        package_.download;
    return computeIntegrityHash!256(package_.archiveFile);
}

string computePackageStripPrefix(Package package_)
{
    import std.zip : ZipArchive;

    enforce(package_.archiveFile.exists, "Archive file %s does not exist.".format(
            package_.archiveFile));
    auto zip = new ZipArchive(package_.archiveFile.read);

    string archiveRoot;
    foreach (name, am; zip.directory)
    {
        auto segments = name.split("/");
        enforce(!segments.empty && !segments[0].empty,
            "Unexpected entry %s in archive.".format(name));
        foreach (segment; segments)
            enforce(segment != "..", "Unexpected entry %s in archive.".format(name));

        if (segments.length < 2)
        {
            return "";
        }
        if (archiveRoot.empty)
            archiveRoot = segments[0];
        else if (archiveRoot != segments[0])
        {
            return "";
        }
    }
    return archiveRoot;
}

void unpack(Package package_)
{
    import std.zip : ZipArchive;

    enforce(package_.archiveFile.exists, "Archive file %s does not exist.".format(
            package_.archiveFile));
    auto zip = new ZipArchive(package_.archiveFile.read);
    scope (failure)
    {
        if (package_.unpackPath.exists)
            package_.unpackPath.rmdirRecurse;
    }

    foreach (name, am; zip.directory)
    {
        auto relativeName = package_.stripPrefix.empty ? name
            : name[package_.stripPrefix.length + 1 .. $];
        if (relativeName.empty)
            continue;
        if (!name.endsWith("/"))
            continue;
        buildNormalizedPath(package_.unpackPath, relativeName).mkdirRecurse;
    }
    foreach (name, am; zip.directory)
    {
        auto relativeName = package_.stripPrefix.empty ? name
            : name[package_.stripPrefix.length + 1 .. $];
        if (relativeName.empty)
            continue;
        if (name.endsWith("/"))
            continue;
        zip.expand(am);
        auto destination = buildNormalizedPath(package_.unpackPath, relativeName);
        destination.dirName.mkdirRecurse;
        am.expandedData.toFile(destination);
    }
}

bool hasField(JSONValue json, string name)
{
    return json.type == JSONType.object && (name in json.object) !is null;
}

JSONValue field(JSONValue json, string name)
{
    enforce(json.hasField(name), "Expected JSON field '%s'.".format(name));
    return json.object[name];
}

string optionalString(JSONValue json, string name, string defaultValue = "")
{
    if (!json.hasField(name))
        return defaultValue;
    enforce(json.field(name).type == JSONType.string, "Expected '%s' to be a string.".format(name));
    return json.field(name).str;
}

string[] optionalStringArray(JSONValue json, string name)
{
    if (!json.hasField(name))
        return [];
    enforce(json.field(name).type == JSONType.array, "Expected '%s' to be an array.".format(name));
    return json.field(name).array
        .map!(v => v.str)
        .array;
}

string platformTokenName(string label)
{
    return label
        .replace("@platforms//os:", "")
        .replace("@platforms//cpu:", "");
}

PlatformCondition parsePlatformCondition(string suffix)
{
    PlatformCondition condition;
    string osConstraint;
    string cpuConstraint;
    bool hasInvalidToken;
    foreach (token; suffix.split("-"))
    {
        switch (token)
        {
        case "windows":
            osConstraint = "@platforms//os:windows";
            break;
        case "linux":
            osConstraint = "@platforms//os:linux";
            break;
        case "osx":
        case "darwin":
            osConstraint = "@platforms//os:osx";
            break;
        case "posix":
            condition.posix = true;
            break;
        case "x86_64":
        case "aarch64":
            cpuConstraint = "@platforms//cpu:" ~ token;
            break;
        case "dmd":
        case "ldc":
        case "gdc":
            break;
        default:
            hasInvalidToken = true;
            break;
        }
    }

    if (hasInvalidToken)
        return condition;
    if (!osConstraint.empty)
        condition.constraintValues ~= osConstraint;
    if (!cpuConstraint.empty)
        condition.constraintValues ~= cpuConstraint;
    if (!condition.posix && condition.constraintValues.empty)
        return condition;

    string[] names;
    if (condition.posix)
        names ~= "posix";
    foreach (constraintValue; condition.constraintValues)
        names ~= constraintValue.platformTokenName;
    condition.name = "_dub_platform_" ~ names.join("_").replace("-", "_");
    return condition;
}

bool isValid(PlatformCondition condition)
{
    return !condition.name.empty;
}

PlatformValues[] platformStringArrays(JSONValue json, string name)
{
    PlatformValues[] result;
    if (json.type != JSONType.object)
        return result;
    foreach (field; json.object.byKeyValue)
    {
        auto prefix = name ~ "-";
        if (!field.key.startsWith(prefix))
            continue;
        enforce(field.value.type == JSONType.array,
            "Expected '%s' to be an array.".format(field.key));
        auto condition = field.key[prefix.length .. $].parsePlatformCondition;
        if (!condition.isValid)
            continue;
        result ~= PlatformValues(condition, field.value.array.map!(v => v.str).array);
    }
    return result;
}

PlatformValues[] stringArrays(JSONValue json, string name)
{
    PlatformValues[] values;
    auto genericValues = json.optionalStringArray(name);
    if (!genericValues.empty)
        values ~= PlatformValues(genericPlatformCondition, genericValues);
    return (values ~ json.platformStringArrays(name)).mergePlatformValues;
}

PlatformValues[] dependencies(JSONValue json, bool pathDependencies)
{
    PlatformValues[] result;
    if (!json.hasField("dependencies"))
        return result;
    enforce(json.field("dependencies").type == JSONType.object,
        "Expected 'dependencies' to be an object.");
    string[] genericValues;
    foreach (dependency; json.field("dependencies").object.byKeyValue)
    {
        auto hasPath = dependency.value.type == JSONType.object &&
            dependency.value.hasField("path");
        if (hasPath == pathDependencies)
            genericValues ~= dependency.key;
    }
    if (!genericValues.empty)
        result ~= PlatformValues(genericPlatformCondition, genericValues);
    return (result ~ json.platformDependencies(pathDependencies)).mergePlatformValues;
}

PlatformValues[] platformDependencies(JSONValue json, bool pathDependencies)
{
    PlatformValues[] result;
    if (json.type != JSONType.object)
        return result;
    foreach (field; json.object.byKeyValue)
    {
        enum prefix = "dependencies-";
        if (!field.key.startsWith(prefix))
            continue;
        enforce(field.value.type == JSONType.object,
            "Expected '%s' to be an object.".format(field.key));
        auto condition = field.key[prefix.length .. $].parsePlatformCondition;
        if (!condition.isValid)
            continue;
        string[] values;
        foreach (dependency; field.value.object.byKeyValue)
        {
            auto hasPath = dependency.value.type == JSONType.object &&
                dependency.value.hasField("path");
            if (hasPath == pathDependencies)
                values ~= dependency.key;
        }
        if (!values.empty)
            result ~= PlatformValues(condition, values);
    }
    return result;
}

string[string] optionalStringMap(JSONValue json, string name)
{
    string[string] result;
    if (!json.hasField(name))
        return result;
    enforce(json.field(name).type == JSONType.object, "Expected '%s' to be an object.".format(name));
    foreach (item; json.field(name).object.byKeyValue)
        result[item.key] = item.value.str;
    return result;
}

TargetType parseTargetType(JSONValue json, string defaultValue = "library")
{
    auto targetType = json.hasField("targetType") ? json.field(
        "targetType") : JSONValue(defaultValue);
    enforce([JSONType.integer, JSONType.string].canFind(targetType.type), "Invalid targetType JSON type.");
    if (targetType.type == JSONType.integer)
        return targetType.integer.to!TargetType;
    return targetType.str.to!TargetType;
}

bool isLibraryTargetType(JSONValue json)
{
    if (!json.hasField("targetType"))
        return true;
    auto targetType = json.parseTargetType;
    return [
        TargetType.library, TargetType.sourceLibrary,
        TargetType.dynamicLibrary, TargetType.staticLibrary
    ].canFind(targetType);
}

bool isTestConfiguration(JSONValue json)
{
    auto configurationName = json.optionalString("name");
    if (configurationName == "test" || configurationName == "unittest")
        return true;
    if (!json.hasField("targetType"))
        return false;
    auto targetType = json.parseTargetType;
    return targetType == TargetType.executable || targetType == TargetType.test;
}

JSONValue cloneJson(JSONValue json)
{
    return json.toString.parseJSON;
}

JSONValue recipeWithSelectedConfiguration(JSONValue json, string packageName)
{
    if (!json.hasField("configurations"))
        return json;

    auto configurations = json.field("configurations").array;
    enforce(!configurations.empty,
        "Package %s has an empty configurations array.".format(packageName));

    JSONValue* selectedConfiguration;
    foreach (ref configuration; configurations)
    {
        if (configuration.optionalString("name") == "library")
        {
            selectedConfiguration = &configuration;
            break;
        }
    }
    if (selectedConfiguration is null)
    {
        foreach (ref configuration; configurations)
        {
            if (configuration.isLibraryTargetType)
            {
                selectedConfiguration = &configuration;
                break;
            }
        }
    }
    if (selectedConfiguration is null)
        selectedConfiguration = &configurations[0];

    auto result = json.cloneJson;
    result.object.remove("configurations");
    foreach (configurationField; selectedConfiguration.object.byKeyValue)
    {
        if (configurationField.key == "name")
            continue;
        result.object[configurationField.key] = configurationField.value;
    }
    return result;
}

JSONValue recipeWithConfiguration(JSONValue json, JSONValue configuration)
{
    auto result = json.cloneJson;
    result.object.remove("configurations");
    foreach (configurationField; configuration.object.byKeyValue)
        result.object[configurationField.key] = configurationField.value;
    return result;
}

string stripCurrentDirectory(string path)
{
    path = path.stripRight("/");
    return path == "." ? "" : path;
}

string prefixedPath(string prefix, string path)
{
    prefix = prefix.stripCurrentDirectory;
    path = path.stripCurrentDirectory;
    if (path.empty)
        return prefix;
    if (prefix.empty)
        return path;
    return buildNormalizedPath(prefix, path).stripCurrentDirectory;
}

string[] prefixedPaths(string prefix, string[] paths)
{
    return paths
        .map!(path => prefix.prefixedPath(path))
        .array;
}

PlatformValues[] prefixedPlatformPaths(string prefix, PlatformValues[] values)
{
    return values
        .map!(value => PlatformValues(value.condition, prefix.prefixedPaths(value.values)))
        .array;
}

bool shouldOmitImportPath(string path)
{
    path = path.stripRight("/");
    return path.empty || path == "." || path == "..";
}

string[] filteredImportPaths(string[] paths)
{
    return paths
        .filter!(path => !path.shouldOmitImportPath)
        .array;
}

PlatformValues[] filteredPlatformImportPaths(PlatformValues[] values)
{
    return values
        .map!(value => PlatformValues(value.condition, value.values.filteredImportPaths))
        .filter!(value => !value.values.empty)
        .array;
}

string[] defaultSourcePaths(string packagePath, string prefix)
{
    auto sourcePath = buildNormalizedPath(packagePath, prefix, "source");
    if (sourcePath.exists)
        return [prefix.prefixedPath("source")];
    auto srcPath = buildNormalizedPath(packagePath, prefix, "src");
    if (srcPath.exists)
        return [prefix.prefixedPath("src")];
    return [prefix.stripCurrentDirectory];
}

bool hasSourceFileWithExtension(string packagePath, string sourcePath, string extension,
    string[] excludedSourceFiles)
{
    import std.file : SpanMode, dirEntries;

    auto searchPath = sourcePath.empty ? packagePath : buildNormalizedPath(packagePath, sourcePath);
    if (!searchPath.exists)
        return false;

    bool[string] excluded;
    foreach (excludedSourceFile; excludedSourceFiles)
        excluded[excludedSourceFile.stripCurrentDirectory] = true;

    foreach (entry; dirEntries(searchPath, SpanMode.depth))
    {
        if (!entry.isFile || !entry.name.endsWith(extension))
            continue;
        auto relativeName = entry.name.relativePath(packagePath).stripCurrentDirectory;
        if ((relativeName in excluded) !is null)
            continue;
        return true;
    }
    return false;
}

string sourceGlobPattern(string sourcePath, string extension)
{
    sourcePath = sourcePath.stripCurrentDirectory;
    if (sourcePath.empty)
        return "**/*" ~ extension;
    return sourcePath ~ "/**/*" ~ extension;
}

bool isUnderSourcePath(string path, string sourcePath)
{
    path = path.stripCurrentDirectory;
    sourcePath = sourcePath.stripCurrentDirectory;
    return sourcePath.empty || path == sourcePath || path.startsWith(sourcePath ~ "/");
}

string[] excludedSourceFilesForSourcePath(string sourcePath, string[] excludedSourceFiles)
{
    return excludedSourceFiles
        .filter!(path => path.isUnderSourcePath(sourcePath))
        .array;
}

SourceGlobGroup[] sourceGlobGroups(string packagePath, string[] sourcePaths,
    string[] excludedSourceFiles)
{
    SourceGlobGroup[] groups;
    foreach (sourcePath; sourcePaths)
    {
        string[] patterns;
        foreach (extension; [".d", ".di"])
        {
            if (packagePath.hasSourceFileWithExtension(sourcePath, extension, excludedSourceFiles))
                patterns ~= sourcePath.sourceGlobPattern(extension);
        }
        if (!patterns.empty)
        {
            SourceGlobGroup group;
            group.patterns = patterns;
            group.excludes = sourcePath.excludedSourceFilesForSourcePath(excludedSourceFiles);
            groups ~= group;
        }
    }
    return groups;
}

void addGenericSourcePaths(ref Target target, string packagePath, string[] sourcePaths)
{
    if (sourcePaths.empty)
        return;
    target.sourcePaths ~= PlatformValues(genericPlatformCondition, sourcePaths);
    auto genericExcludes = target.excludedSourceFiles.valuesForCondition(genericPlatformCondition);
    target.sourceGlobGroups ~= PlatformSourceGlobGroups(
        genericPlatformCondition,
        packagePath.sourceGlobGroups(sourcePaths, genericExcludes));
    if (target.importPaths.empty)
        target.importPaths = target.sourcePaths.filteredPlatformImportPaths;
}

bool hasExplicitSourceInputs(Target target)
{
    return !target.sourceFiles.empty || !target.sourcePaths.empty;
}

Target parseRecipeTarget(JSONValue json, string packagePath, string packageName, string pathPrefix = "")
{
    json = json.recipeWithSelectedConfiguration(packageName);
    Target target;
    target.targetName = json.optionalString("targetName", json.optionalString("name", packageName));
    target.targetType = json.parseTargetType;
    target.targetPath = pathPrefix.prefixedPath(json.optionalString("targetPath"));
    auto mainSourceFile = json.optionalString("mainSourceFile");
    target.mainSourceFile = pathPrefix.prefixedPath(mainSourceFile);
    target.dflags = json.stringArrays("dflags");
    target.debugVersions = json.stringArrays("debugVersions");
    target.lflags = json.stringArrays("lflags");
    target.libs = json.stringArrays("libs");
    target.copyFiles = pathPrefix.prefixedPlatformPaths(json.stringArrays("copyFiles"));
    auto sourceFiles = json.stringArrays("sourceFiles") ~ json.stringArrays("importFiles");
    if (!mainSourceFile.empty)
        sourceFiles ~= PlatformValues(genericPlatformCondition, [mainSourceFile]);
    target.sourceFiles = pathPrefix.prefixedPlatformPaths(sourceFiles.mergePlatformValues);
    auto sourcePaths = json.optionalStringArray("sourcePaths");
    if (!sourcePaths.empty)
        target.sourcePaths ~= PlatformValues(genericPlatformCondition, pathPrefix.prefixedPaths(
                sourcePaths));
    target.sourcePaths = (target.sourcePaths ~ pathPrefix.prefixedPlatformPaths(
            json.platformStringArrays("sourcePaths"))).mergePlatformValues;
    target.excludedSourceFiles = pathPrefix.prefixedPlatformPaths(
        json.stringArrays("excludedSourceFiles"));
    auto genericExcludes = target.excludedSourceFiles.valuesForCondition(genericPlatformCondition);
    foreach (sourcePathsByPlatform; target.sourcePaths)
    {
        auto excludes = genericExcludes;
        if (!sourcePathsByPlatform.condition.isGeneric)
            excludes ~= target.excludedSourceFiles.valuesForCondition(
                sourcePathsByPlatform.condition);
        target.sourceGlobGroups ~= PlatformSourceGlobGroups(
            sourcePathsByPlatform.condition,
            packagePath.sourceGlobGroups(sourcePathsByPlatform.values, excludes));
    }
    target.injectSourceFiles = pathPrefix.prefixedPlatformPaths(
        json.stringArrays("injectSourceFiles"));
    target.versions = json.stringArrays("versions");
    auto importPaths = json.optionalStringArray("importPaths");
    if (importPaths.empty)
        target.importPaths = target.sourcePaths.filteredPlatformImportPaths;
    else
        target.importPaths = pathPrefix.prefixedPlatformPaths(json.stringArrays("importPaths")
                .filteredPlatformImportPaths).filteredPlatformImportPaths;
    target.stringImportPaths = pathPrefix.prefixedPlatformPaths(
        json.stringArrays("stringImportPaths"));
    target.stringSrcs = pathPrefix.prefixedPlatformPaths(json.stringArrays("stringImportFiles"));
    target.environments = json.optionalStringMap("environments");
    target.buildEnvironments = json.optionalStringMap("buildEnvironments");
    target.runEnvironments = json.optionalStringMap("runEnvironments");
    target.dependencies = json.dependencies(false);
    target.pathDependencies = json.dependencies(true);
    return target;
}

Target parseTestConfigurationTarget(JSONValue recipe, JSONValue configuration, string packagePath,
    string packageName, string pathPrefix = "")
{
    auto baseTargetName = recipe.optionalString("targetName", recipe.optionalString("name", packageName));
    auto target = recipe.recipeWithConfiguration(configuration)
        .parseRecipeTarget(packagePath, packageName, pathPrefix);
    target.targetType = TargetType.test;
    target.targetName = "%s_test".format(baseTargetName);
    return target;
}

Target[] testConfigurationTargets(JSONValue recipe, string packagePath, string packageName,
    string pathPrefix = "")
{
    if (!config.includeTests || !recipe.hasField("configurations"))
        return [];
    Target[] targets;
    foreach (configuration; recipe.field("configurations").array)
    {
        if (configuration.isTestConfiguration)
            targets ~= recipe.parseTestConfigurationTarget(configuration, packagePath, packageName, pathPrefix);
    }
    return targets;
}

JSONValue parseJsonObjectFromOutput(string output, string commandDescription)
{
    auto jsonStart = output.indexOf("{");
    auto jsonEnd = output.lastIndexOf("}");
    enforce(jsonStart >= 0 && jsonEnd >= jsonStart,
        "Failed to find JSON object in %s output: %s".format(commandDescription, output));
    auto json = output[jsonStart .. jsonEnd + 1].parseJSON;
    enforce(json.type == JSONType.object, "Expected JSON object from %s.".format(
            commandDescription));
    return json;
}

JSONValue convertPackageRecipe(string packagePath)
{
    import std.process : execute;

    auto result = execute([
        config.dubExecutable,
        "convert",
        "--format=json",
        "--stdout",
        "--root=%s".format(packagePath),
    ]);
    enforce(result.status == 0, "Failed to convert package recipe at %s: %s".format(
            packagePath, result.output));
    auto convertedRecipe = result.output.parseJsonObjectFromOutput("dub convert");
    if (config.verbose)
    {
        import std.stdio : writeln;

        writeln("Converted dub recipe for package at ", packagePath, ":\n",
            convertedRecipe.toPrettyString(JSONOptions.doNotEscapeSlashes));
    }
    return convertedRecipe;
}

string[] candidateRecipePaths(string packagePath)
{
    import std.file : SpanMode, dirEntries;

    string[] result;
    foreach (entry; dirEntries(packagePath, SpanMode.depth))
    {
        if (!entry.isFile)
            continue;
        auto fileName = entry.name.baseName;
        if (fileName == "dub.json" || fileName == "dub.sdl")
        {
            if (entry.name.dirName == packagePath)
                continue;
            result ~= entry.name;
        }
    }
    return result;
}

Target[] pathSubPackageMatches(JSONValue subPackage, string packagePath, string packageName)
{
    auto subPackageName = subPackage.optionalString("name");
    enforce(!subPackageName.empty, "Subpackage in %s must have a name.".format(packageName));
    Target[] matches;
    foreach (recipePath; packagePath.candidateRecipePaths)
    {
        auto subPackagePath = recipePath.dirName;
        auto convertedRecipe = subPackagePath.convertPackageRecipe;
        if (convertedRecipe.optionalString("name") != subPackageName)
            continue;
        auto pathPrefix = subPackagePath.relativePath(packagePath).stripCurrentDirectory;
        auto target = convertedRecipe.parseRecipeTarget(packagePath, packageName, pathPrefix);
        if (!target.hasExplicitSourceInputs)
            target.addGenericSourcePaths(packagePath, defaultSourcePaths(packagePath, pathPrefix));
        target.targetName = subPackageName;
        auto childTargets = [target] ~ convertedRecipe.testConfigurationTargets(
            packagePath, packageName, pathPrefix);
        enforce(matches.empty, "Found multiple recipes for subpackage %s in package %s.".format(
                subPackageName, packageName));
        matches ~= childTargets;
    }
    return matches;
}

Target[] stringPathSubPackageTargets(JSONValue subPackage, string packagePath, string packageName)
{
    enforce(subPackage.type == JSONType.string, "Expected path subpackage to be a string.");
    auto pathPrefix = subPackage.str.stripCurrentDirectory;
    auto subPackagePath = buildNormalizedPath(packagePath, pathPrefix);
    if (!buildNormalizedPath(subPackagePath, "dub.json").exists &&
        !buildNormalizedPath(subPackagePath, "dub.sdl").exists)
        return [];

    Target target;
    target.targetName = pathPrefix.baseName;
    target.targetType = TargetType.library;
    target.addGenericSourcePaths(packagePath, defaultSourcePaths(packagePath, pathPrefix));
    return [target];
}

bool isPathSubPackage(JSONValue subPackage)
{
    return subPackage.type == JSONType.string ||
        (subPackage.type == JSONType.object && subPackage.object.length == 1 &&
            subPackage.hasField("name"));
}

Target[] packageTargetsFromRecipe(JSONValue recipe, string packagePath, string packageName,
    out string mainTargetName)
{
    Target[] targets;
    auto rootTarget = recipe.parseRecipeTarget(packagePath, packageName);
    if (!rootTarget.hasExplicitSourceInputs)
        rootTarget.addGenericSourcePaths(packagePath, defaultSourcePaths(packagePath, ""));
    mainTargetName = rootTarget.targetName;
    targets ~= rootTarget;
    targets ~= recipe.testConfigurationTargets(packagePath, packageName);

    if (!recipe.hasField("subPackages"))
        return targets;
    enforce(recipe.field("subPackages").type == JSONType.array,
        "Expected 'subPackages' to be an array.");
    foreach (subPackage; recipe.field("subPackages").array)
    {
        if (subPackage.type == JSONType.string)
        {
            targets ~= subPackage.stringPathSubPackageTargets(packagePath, packageName);
            continue;
        }
        if (subPackage.isPathSubPackage)
        {
            auto matches = subPackage.pathSubPackageMatches(packagePath, packageName);
            if (!matches.empty)
            {
                targets ~= matches;
                continue;
            }
            auto target = subPackage.parseRecipeTarget(packagePath, packageName);
            target.targetName = subPackage.optionalString("name");
            targets ~= target;
            targets ~= subPackage.testConfigurationTargets(packagePath, packageName);
            continue;
        }
        auto subPackageName = subPackage.optionalString("name");
        enforce(!subPackageName.empty, "Subpackage in %s must have a name.".format(packageName));
        auto target = subPackage.parseRecipeTarget(packagePath, packageName);
        target.targetName = subPackageName;
        targets ~= target;
        targets ~= subPackage.testConfigurationTargets(packagePath, packageName);
    }
    return targets;
}

Target[] convertPackage(Package package_, out string mainTargetName)
{
    if (!package_.archiveFile.exists)
        package_.download;

    if (!package_.unpackPath.exists)
        package_.unpack;

    // return no targets if this is a Bazel package already
    if (package_.unpackPath.buildNormalizedPath("WORKSPACE").exists ||
        package_.unpackPath.buildNormalizedPath("MODULE.bazel").exists)
        return [];

    auto recipe = package_.unpackPath.convertPackageRecipe;
    return recipe.packageTargetsFromRecipe(package_.unpackPath, package_.name, mainTargetName);
}

void expandDependencyTargetNames(ref Package package_, string[string] targetNameByPackage)
{
    string[string] localTargetNameByDependency;
    localTargetNameByDependency[package_.name] = package_.mainTargetName;
    foreach (target; package_.targets)
        localTargetNameByDependency[package_.name ~ ":" ~ target.targetName] = target.targetName;

    foreach (ref target; package_.targets)
    {
        PlatformValues[] dependencies;
        foreach (pathDeps; target.pathDependencies)
            dependencies ~= PlatformValues(
                pathDeps.condition,
                pathDeps.values.expandPathDependencies(localTargetNameByDependency));

        foreach (externalDeps; target.dependencies)
        {
            dependencies ~= PlatformValues(
                externalDeps.condition,
                externalDeps.values
                    .map!(dep => dep.expandExternalDependency(targetNameByPackage))
                    .array);
        }
        target.dependencies = dependencies.mergePlatformValues;
        target.pathDependencies = [];
    }
}

string[] expandPathDependencies(string[] deps, string[string] localTargetNameByDependency)
{
    string[] dependencies;
    foreach (dep; deps)
    {
        auto localTargetName = dep in localTargetNameByDependency;
        if (localTargetName !is null)
        {
            dependencies ~= ":" ~ *localTargetName;
            continue;
        }

        auto separatorIndex = dep.indexOf(":");
        dependencies ~= ":" ~ (separatorIndex >= 0 ? dep[separatorIndex + 1 .. $] : dep);
    }
    return dependencies;
}

string expandExternalDependency(string dep, string[string] targetNameByPackage)
{
    auto targetName = dep in targetNameByPackage;
    if (targetName is null)
        return dep;
    if ((*targetName).empty || *targetName == dep)
        return dep;
    return dep ~ ":" ~ *targetName;
}

void writeDubSelectionsLockJson(Package[] packages, string filePath)
{
    JSONValue outputJson;
    if (!config.bazelGeneratingTarget.empty)
        outputJson["_comment"] =
            format!"This file is auto-generated with `bazel run %s`. Do not edit."(
                config.bazelGeneratingTarget);
    outputJson["fileVersion"] = 1;
    outputJson["packages"] = packages.map!(p => tuple(p.name, (
            (p.buildFileContent.empty ?
            [] : [tuple("buildFileContent", p.buildFileContent)]) ~
            (p.stripPrefix.empty || p.stripPrefix == p.versionedName ?
            [] : [tuple("strip_prefix", p.stripPrefix)]) ~
            [
                tuple("integrity", p.integrity),
                tuple("url", p.url),
                tuple("version", p.version_),
            ]).assocArray)).assocArray;
    (outputJson
            .toPrettyString(JSONOptions.doNotEscapeSlashes)
            .replace("    ", "  ") ~ "\n")
        .toFile(filePath);
}

void generateSelectionsLock(string[] inputFilePaths, string outputFilePath)
{
    auto packages = inputFilePaths
        .map!(inputFilePath => readDubDependencies(inputFilePath, inputFilePaths))
        .join
        .array
        .resolveDubDependencies;
    packages.each!((ref p) => p.integrity = computePackageIntegrity(p));
    packages.each!((ref p) => p.stripPrefix = computePackageStripPrefix(p));
    packages.each!((ref p) => p.targets = convertPackage(p, p.mainTargetName));
    auto targetNameByPackage = packages.map!(p => tuple(p.name, p.mainTargetName)).assocArray;
    packages.each!((ref p) => p.expandDependencyTargetNames(targetNameByPackage));
    packages.each!((ref p) => p.buildFileContent = computeBuildFile(p, config.verbose));

    writeDubSelectionsLockJson(packages, outputFilePath);
}

string generateBuildFile(string inputFilePath)
{
    enforce(inputFilePath.baseName == "dub.json" || inputFilePath.baseName == "dub.sdl",
        "BUILD file generation input must be dub.json or dub.sdl, got %s.".format(
            inputFilePath));
    auto packagePath = inputFilePath.dirName;
    auto recipe = packagePath.convertPackageRecipe;
    auto packageName = recipe.optionalString("name", packagePath.baseName);
    string mainTargetName;
    Package package_;
    package_.name = packageName;
    package_.targets = recipe.packageTargetsFromRecipe(packagePath, packageName, mainTargetName);
    package_.mainTargetName = mainTargetName;
    return package_.computeBuildFile(config.verbose);
}

void generateBuildFile(string inputFilePath, string outputFilePath)
{
    auto content = inputFilePath.generateBuildFile;
    if (outputFilePath.empty)
    {
        import std.stdio : write;

        write(content);
        return;
    }
    content.toFile(outputFilePath);
}
