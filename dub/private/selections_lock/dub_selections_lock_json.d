import std.algorithm : each, map;
import std.array : array, assocArray, replace;
import std.exception : enforce;
import std.file : exists, isFile, readText;
import std.format : format;
import std.json : parseJSON, JSONOptions, JSONType, JSONValue;
import std.range : empty;
import std.string : assumeUTF;
import std.stdio : File, toFile;
import std.typecons : tuple;

import tools.integrity_hash : computeIntegrityHash;

string DUB_REGISTRY_URL = "https://code.dlang.org/packages";

struct Package
{
    string name;
    string version_;
    string url;
    string integrity;
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

string computeIntegrityByUrl(string url)
{
    import tools.curl_downloader : CurlDownloader;

    auto tmpFile = File.tmpfile;
    CurlDownloader downloader;
    downloader.downloadToFile(url, tmpFile);
    return computeIntegrityHash!256(tmpFile);
}

void writeDubSelectionsLockJson(string filePath, Package[] packages, string bazelGeneratingTarget, string inputIntegrity)
{
    JSONValue outputJson;
    outputJson["_comment"] =
        format!"This file is auto-generated with `bazel run %s`. Do not edit."(
            bazelGeneratingTarget);
    outputJson["fileVersion"] = 1;
    outputJson["inputIntegrity"] = inputIntegrity;
    outputJson["packages"] = JSONValue(
        packages
            .map!(p => tuple(p.name, JSONValue([
                    "version": p.version_,
                    "url": p.url,
                    "integrity": p.integrity
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

    string bazelGeneratingTarget;
    bool check = false;
    string inputFilePath;
    bool generate = false;
    string outputFilePath;

    auto parseArgs = args.getopt(
        "bazel_generating_target|b", "Document the bazel generating target.", &bazelGeneratingTarget,
        "check|c", "Check that the existing dub.selections.lock.json file is up to date", &check,
        "input|i", "Input file path. One of dub.json, dub.sdl or, dub.selections.json.", &inputFilePath,
        "generate|g", "Generate a dub.selections.lock.json file.", &generate,
        "output|o", "Output dub.selections.lock.json file path.", &outputFilePath,
    );

    if (parseArgs.helpWanted)
    {
        defaultGetoptPrinter(
            "Generates a dub.selections.lock.json file from a dub.json, dub.sdl or, dub.selections.json.",
            parseArgs.options);
        return 0;
    }
    if (!(check || generate))
    {
        writeln("Either --check or --generate must be specified.");
        return 1;
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
    if (!outputFilePath.exists || !outputFilePath.isFile)
    {
        writefln("Output file path %s does not exist or is not a file.", outputFilePath);
        return 1;
    }

    if (generate)
    {
        auto packages = readDubSelectionsJson(inputFilePath);
        packages.each!((ref p) => p.url = format!"%s/%s/%s.zip"(DUB_REGISTRY_URL, p.name, p
                .version_));
        packages.each!((ref p) => p.integrity = computeIntegrityByUrl(p.url));

        writeDubSelectionsLockJson(outputFilePath, packages, bazelGeneratingTarget,
            computeIntegrityHash!256(inputFilePath));
    }
    else if (check)
    {
        auto rootObject = readText(outputFilePath).parseJSON;
        string expectedInputIntegrity;
        if (rootObject.type == JSONType.object &&
            rootObject.object.get("inputIntegrity", JSONValue.init).type == JSONType.string)
        {
            expectedInputIntegrity = rootObject["inputIntegrity"].str;
        }
        string actualInputIntegrity = computeIntegrityHash!256(inputFilePath);

        if (expectedInputIntegrity != actualInputIntegrity)
        {
            writefln("Input and output integrity hashes do not match. Run `bazel run %s` to update.",
                bazelGeneratingTarget);
            return 1;
        }
    }
    return 0;
}
