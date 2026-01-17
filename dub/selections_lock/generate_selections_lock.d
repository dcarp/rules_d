module dub.selections_lock.generate_selections_lock;

import std.algorithm : canFind, each, filter, map;
import std.array : array, assocArray, replace;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, isFile, mkdirRecurse, read, readText, rmdirRecurse, tempDir;
import std.format : format;
import std.json : parseJSON, JSONOptions, JSONType, JSONValue;
import std.path : baseName, buildNormalizedPath, relativePath;
import std.range : empty, join;
import std.string : assumeUTF, endsWith, startsWith, strip;
import std.stdio : File, toFile;
import std.typecons : tuple;

import tools.integrity_hash : computeIntegrityHash;

struct Config
{
    string bazelGeneratingTarget;
    string cachePath;
    string dubExecutable;
    enum string dubRegistryUrl = "https://code.dlang.org/packages";
}

__gshared Config _config;

void setConfig(string bazelGeneratingTarget, string cachePath, string dubExecutable)
{
    if (!bazelGeneratingTarget.empty)
        _config.bazelGeneratingTarget = bazelGeneratingTarget;
    if (!cachePath.empty)
        _config.cachePath = cachePath;
    if (!dubExecutable.empty)
        _config.dubExecutable = dubExecutable;
}

auto config()
{
    return _config;
}

struct Package
{
    string name;
    string version_;
    string integrity;
    string buildFileContent;
    Target[] targets;

    string archiveFile() const
    {
        return buildNormalizedPath(config.cachePath, "%s.zip".format(versionedName));
    }

    string unpackPath() const
    {
        return buildNormalizedPath(config.cachePath, versionedName);
    }

    string url() const
    {
        return format!"%s/%s/%s.zip"(config.dubRegistryUrl, name, version_);
    }

    string versionedName() const
    {
        return "%s-%s".format(name, version_);
    }
}

Package[] readDubSelectionsJson(string filePath)
{
    auto json = readText(filePath).parseJSON;
    enforce(json.type == JSONType.object, "Expected JSON object at root.");
    enforce(json["fileVersion"].integer == 1, "Unsupported fileVersion, expected 1.");

    return json["versions"]
        .object
        .byKeyValue
        .map!(item => Package(item.key, item.value.str))
        .array;
}

void download(Package package_)
{
    import tools.curl_downloader : CurlDownloader;

    CurlDownloader downloader;
    downloader.downloadToFile(package_.url, package_.archiveFile);
}

string computePackageIntegrity(Package package_)
{
    if (!package_.archiveFile.exists)
        package_.download;
    return computeIntegrityHash!256(package_.archiveFile);
}

void unpack(Package package_)
{
    import std.zip : ZipArchive;

    enforce(package_.archiveFile.exists, "Archive file %s does not exist.".format(
            package_.archiveFile));
    auto zip = new ZipArchive(package_.archiveFile.read);
    scope (failure)
    {
        package_.unpackPath.rmdirRecurse;
    }

    // create directories first
    foreach (name, am; zip.directory)
    {
        enforce(name.startsWith(package_.versionedName ~ "/"),
            "Unexpected entry %s in archive.".format(name));
        if (!name.endsWith("/"))
            continue;
        buildNormalizedPath(package_.unpackPath, "..", name).mkdirRecurse;
    }
    // then expand files
    foreach (name, am; zip.directory)
    {
        if (name.endsWith("/"))
            continue;
        zip.expand(am);
        am.expandedData.toFile(buildNormalizedPath(package_.unpackPath, "..", name));
    }
}

enum TargetType
{
    autodetect,
    none,
    executable,
    library,
    sourceLibrary,
    dynamicLibrary,
    staticLibrary,
    object
}

struct Target
{
    string targetName;
    TargetType targetType;
    string targetPath;
    string mainSourceFile;
    string[] dflags;
    string[] lflags;
    string[] libs;
    string[] sourceFiles;
    string[] injectSourceFiles;
    string[] versions;
    string[] importPaths;
    string[] stringImportPaths;
    string[] stringSrcs;
    string[string] environments;
    string[string] buildEnvironments;
    string[string] runEnvironments;
}

Target parseTarget(JSONValue json)
{
    Target target;
    json = json["buildSettings"].object;
    target.targetName = json["targetName"].str;
    enforce([JSONType.integer, JSONType.string].canFind(json["targetType"].type), "Invalid targetType JSON type.");
    if (json["targetType"].type == JSONType.integer)
        target.targetType = json["targetType"].integer.to!TargetType;
    else if (json["targetType"].type == JSONType.string)
        target.targetType = json["targetType"].str.to!TargetType;
    target.targetPath = json["targetPath"].str;
    target.mainSourceFile = json["mainSourceFile"].str;
    target.dflags = json["dflags"].array.map!(v => v.str).array;
    target.lflags = json["lflags"].array.map!(v => v.str).array;
    target.libs = json["libs"].array.map!(v => v.str).array;
    target.sourceFiles = json["sourceFiles"].array
        .map!(v => v.str.relativePath(target.targetPath)).array;
    target.injectSourceFiles = json["injectSourceFiles"].array
        .map!(v => v.str.relativePath(target.targetPath)).array;
    target.versions = json["versions"].array.map!(v => v.str).array;
    target.importPaths = json["importPaths"].array
        .map!(v => v.str.relativePath(target.targetPath).strip("", "/")).array;
    target.stringImportPaths = json["stringImportPaths"].array
        .map!(v => v.str.relativePath(target.targetPath).strip("", "/")).array;
    target.stringSrcs = json["stringImportFiles"].array
        .map!(v => v.str.relativePath(target.targetPath)).array;
    target.environments = json["environments"].object.byKeyValue
        .map!(env => tuple(env.key, env.value.str)).assocArray;
    target.buildEnvironments = json["buildEnvironments"].object.byKeyValue
        .map!(env => tuple(env.key, env.value.str)).assocArray;
    target.runEnvironments = json["runEnvironments"].object.byKeyValue
        .map!(env => tuple(env.key, env.value.str)).assocArray;
    return target;
}

Target[] describePackage(Package package_)
{
    import std.file : getcwd;
    import std.process : Config, execute;

    if (!package_.archiveFile.exists)
        package_.download;

    if (!package_.unpackPath.exists)
        package_.unpack;

    // return no targets if this is a Bazel package already
    if (package_.unpackPath.buildNormalizedPath("WORKSPACE").exists ||
        package_.unpackPath.buildNormalizedPath("MODULE.bazel").exists)
        return [];

    auto result = execute([
        config.dubExecutable,
        "describe",
        "--root=%s".format(package_.unpackPath),
    ]);
    enforce(result.status == 0, "Failed to describe package %s: %s".format(
            package_.versionedName, result.output));

    auto dub_description = result.output.parseJSON;
    return dub_description["targets"].array.map!(t => parseTarget(t)).array;
}

string header_definition(bool hasBinary, bool hasLibrary)
{
    if (hasBinary && hasLibrary)
        return `load("@rules_d//d:defs.bzl", "d_binary", "d_library")`;
    else if (hasBinary)
        return `load("@rules_d//d:defs.bzl", "d_binary")`;
    else if (hasLibrary)
        return `load("@rules_d//d:defs.bzl", "d_library")`;
    return "";
}

string target_definition(Target target)
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
    default:
        enforce(false, "Unsupported target type %s.".format(target.targetType));
        return "";
    }
    result ~= "    name = \"%s\",".format(target.targetName);
    if (!target.sourceFiles.empty)
        result ~= "    srcs = [%s],".format(target.sourceFiles
                .map!(s => "\"" ~ s ~ "\"").join(", "));
    if (!target.importPaths.empty)
        result ~= "    imports = [%s],".format(
            target.importPaths
                .map!(s => "\"" ~ s ~ "\"").join(", "));
    if (target.targetType == TargetType.sourceLibrary)
        result ~= "    source_only = True,";
    result ~= "    visibility = [\"//visibility:public\"],";
    result ~= ")\n";
    return result.join("\n");
}

string computeBuildFile(Package package_)
{
    bool hasBinary = package_.targets.canFind!(t => t.targetType == TargetType.executable);
    bool hasLibrary = package_.targets
        .canFind!(t => [
                TargetType.library, TargetType.sourceLibrary,
                TargetType.dynamicLibrary, TargetType.staticLibrary
            ].canFind(t.targetType));

    if (!hasBinary && !hasLibrary)
        return "";

    return header_definition(hasBinary, hasLibrary) ~ "\n\n" ~
        package_.targets
        .map!(t => target_definition(t))
        .join("\n");
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
            p.buildFileContent.empty ? [] : [
                tuple("buildFileContent", p.buildFileContent)
            ] ~ [
                tuple("integrity", p.integrity),
                tuple("url", p.url),
                tuple("version", p.version_),
            ]).assocArray)).assocArray;
    (outputJson
            .toPrettyString(JSONOptions.doNotEscapeSlashes)
            .replace("    ", "  ") ~ "\n")
        .toFile(filePath);
}

int main(string[] args)
{
    import std.getopt : defaultGetoptPrinter, getopt;
    import std.stdio : writefln, writeln;
    import std.process : environment;

    string bazelGeneratingTarget;
    string cachePath;
    string dub;
    string inputFilePath;
    string outputFilePath;

    auto parseArgs = args.getopt(
        "bazel_generating_target|b", "Document the bazel generating target.", &bazelGeneratingTarget,
        "cache_path|c", "Path to dub cache.", &cachePath,
        "dub|d", "Path to dub executable.", &dub,
        "input|i", "Input file path. One of dub.json, dub.sdl or, dub.selections.json.", &inputFilePath,
        "output|o", "Output dub.selections.lock.json file path.", &outputFilePath,
    );

    if (parseArgs.helpWanted)
    {
        defaultGetoptPrinter(
            "Generates a dub.selections.lock.json file from a dub.json, dub.sdl or, dub.selections.json.",
            parseArgs.options);
        return 0;
    }
    if (!inputFilePath.exists || !inputFilePath.isFile)
    {
        writefln("Input file path %s does not exist or is not a file.", inputFilePath);
        return 1;
    }
    if (outputFilePath.exists && !outputFilePath.isFile)
    {
        writefln("Output file %s is not a file.", outputFilePath);
        return 1;
    }
    if (cachePath.empty)
    {
        cachePath = buildNormalizedPath(tempDir, "__dub_selection_cache__");
        cachePath.mkdirRecurse;
    }
    if (dub.empty)
        dub = environment.get("DUB");
    enforce(!dub.empty, "DUB executable path must be specified via --dub option or DUB environment variable.");

    setConfig(bazelGeneratingTarget, cachePath, dub);

    auto packages = readDubSelectionsJson(inputFilePath);
    packages.each!((ref p) => p.integrity = computePackageIntegrity(p));
    packages.each!((ref p) => p.targets = describePackage(p));
    packages.each!((ref p) => p.buildFileContent = computeBuildFile(p));

    writeDubSelectionsLockJson(packages, outputFilePath);
    return 0;
}
