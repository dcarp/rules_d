module dub.selections_lock.generate_build_file;

import std.exception : enforce;
import std.conv : to;
import std.file : exists, isFile;
import std.getopt : defaultGetoptPrinter, getopt;
import std.process : environment;
import std.range : empty;
import std.stdio : writefln, writeln;
import std.typecons : Flag;

import selections_lock_generator : generateBuildFile, setConfig;

int main(string[] args)
{
    string dub;
    bool includeTests;
    string inputFilePath;
    string outputFilePath;
    bool verbose;

    auto parseArgs = args.getopt(
        "dub|d", "Path to dub executable.", &dub,
        "include_tests", "Generate d_test targets from DUB test configurations.", &includeTests,
        "input|i", "Input dub.json or dub.sdl file path.", &inputFilePath,
        "output|o", "Output BUILD.bazel file path. Defaults to stdout.", &outputFilePath,
        "verbose|v", "Enable verbose output.", &verbose,
    );

    if (parseArgs.helpWanted)
    {
        defaultGetoptPrinter(
            "Generates BUILD.bazel content from one dub.json or dub.sdl input.",
            parseArgs.options);
        return 0;
    }
    if (inputFilePath.empty)
    {
        writeln("Input file path must be specified.");
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
    if (dub.empty)
        dub = environment.get("DUB");
    enforce(!dub.empty, "DUB executable path must be specified via --dub option or DUB environment variable.");

    setConfig("", "", dub, includeTests.to!(Flag!"IncludeTests"),
        false.to!(Flag!"SkipSSLVerification"),
        verbose.to!(Flag!"Verbose"));
    inputFilePath.generateBuildFile(outputFilePath);
    return 0;
}
