module dub.selections_lock.generate_selections_lock;

import std.algorithm : each, filter, map;
import std.array : array, assocArray, replace;
import std.exception : enforce;
import std.file : exists, isFile, mkdirRecurse, read, readText, rmdirRecurse, tempDir;
import std.format : format;
import std.json : parseJSON, JSONOptions, JSONType, JSONValue;
import std.path : buildNormalizedPath;
import std.range : empty, join;
import std.string : assumeUTF, endsWith, startsWith;
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

string binary_definition(JSONValue target)
{
    return "binary_def";
}

string library_definition(JSONValue target, bool isSourceOnly = false)
{
    enum string[] attributesOrder = [
            "name", "srcs", "imports", "source_only", "visibility", "deps"
        ];

    string[string] attributes;
    attributes["name"] = `"%s"`.format(target["name"].str);
    attributes["srcs"] = `[%s]`.format(
        target["files"].array
            .filter!(f => f["role"].str == "source")
            .map!(f => `"%s"`.format(f["path"].str))
            .join(", "));
    if (!target["importPaths"].array.empty)
        attributes["imports"] = `[%s]`.format(
            target["importPaths"].array
                .map!(p => `"%s"`.format(p.str))
                .join(", "));
    if (isSourceOnly)
        attributes["source_only"] = "True";
    attributes["visibility"] = `["//visibility:public"]`;

    return "\nd_library(\n%s\n)\n".format(
        attributesOrder
            .filter!(key => key in attributes)
            .map!(key => "    %s=%s,".format(key, attributes[key]))
            .join("\n"));
}

string computeBuildFile(Package package_)
{
    import std.file : getcwd;
    import std.process : Config, execute;

    if (!package_.archiveFile.exists)
        package_.download;

    if (!package_.unpackPath.exists)
        package_.unpack;

    auto result = execute([
        config.dubExecutable,
        "describe",
        "--root=%s".format(package_.unpackPath),
    ]);
    enforce(result.status == 0, "Failed to describe package %s: %s".format(
            package_.versionedName, result.output));

    string[] targetDefinitions;
    bool hasBinary, hasLibrary;
    auto dub_description = result.output.parseJSON;
    foreach (target; dub_description["packages"].array)
    {
        switch (target["targetType"].str)
        {
        case "executable":
            targetDefinitions ~= binary_definition(target);
            hasBinary = true;
            break;
        case "library":
            targetDefinitions ~= library_definition(target);
            hasLibrary = true;
            break;
        default:
            enforce(false, "Unsupported target type %s in package %s.".format(
                    target["targetType"], package_.versionedName));
        }
    }
    return header_definition(hasBinary, hasLibrary) ~ "\n" ~ targetDefinitions.join("\n");
}

void writeDubSelectionsLockJson(Package[] packages, string filePath)
{
    JSONValue outputJson;
    outputJson["_comment"] =
        format!"This file is auto-generated with `bazel run %s`. Do not edit."(
            config.bazelGeneratingTarget);
    outputJson["fileVersion"] = 1;
    outputJson["packages"] = JSONValue(
        packages
            .map!(p => tuple(p.name, JSONValue([
                    "buildFileContent": p.buildFileContent,
                    "integrity": p.integrity,
                    "url": p.url,
                    "version": p.version_,
                ])))
        .assocArray);
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
    if (bazelGeneratingTarget.empty)
    {
        writeln("The --bazel_generating_target option must be specified.");
        return 1;
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
    packages.each!((ref p) => p.buildFileContent = computeBuildFile(p));

    writeDubSelectionsLockJson(packages, outputFilePath);
    return 0;
}
