module dub.selections_lock.generate_selections_lock;

import std.conv : to;
import std.exception : enforce;
import std.file : exists, isFile, mkdirRecurse, tempDir;
import std.getopt : defaultGetoptPrinter, getopt;
import std.path : buildNormalizedPath;
import std.process : environment;
import std.range : empty;
import std.stdio : writefln, writeln;
import std.typecons : Flag;

import selections_lock_generator : generateSelectionsLock, setConfig;

int main(string[] args)
{
    string bazelGeneratingTarget;
    string cachePath;
    string dub;
    bool includeTests;
    string[] inputFilePaths;
    string outputFilePath;
    bool skipSSLVerification;
    bool verbose;

    auto parseArgs = args.getopt(
        "bazel_generating_target|b", "Document the bazel generating target.", &bazelGeneratingTarget,
        "cache_path|c", "Path to dub cache.", &cachePath,
        "dub|d", "Path to dub executable.", &dub,
        "include_tests", "Generate d_test targets from DUB test configurations.", &includeTests,
        "input|i", "Input file path. May be repeated. One of dub.json, dub.sdl or, dub.selections.json.", &inputFilePaths,
        "output|o", "Output dub.selections.lock.json file path.", &outputFilePath,
        "skip_ssl_verification|s", "Skip SSL verification when downloading packages.", &skipSSLVerification,
        "verbose|v", "Enable verbose output.", &verbose,
    );

    if (parseArgs.helpWanted)
    {
        defaultGetoptPrinter(
            "Generates a dub.selections.lock.json file from one or more dub.json, dub.sdl or, dub.selections.json inputs.",
            parseArgs.options);
        return 0;
    }
    if (inputFilePaths.empty)
    {
        writeln("At least one input file path must be specified.");
        return 1;
    }
    if (outputFilePath.empty)
    {
        writeln("Output file path must be specified.");
        return 1;
    }
    foreach (inputFilePath; inputFilePaths)
    {
        if (!inputFilePath.exists || !inputFilePath.isFile)
        {
            writefln("Input file path %s does not exist or is not a file.", inputFilePath);
            return 1;
        }
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

    setConfig(bazelGeneratingTarget, cachePath, dub, includeTests.to!(
            Flag!"IncludeTests"), skipSSLVerification.to!(
            Flag!"SkipSSLVerification"),
        verbose.to!(Flag!"Verbose"));
    generateSelectionsLock(inputFilePaths, outputFilePath);
    return 0;
}
