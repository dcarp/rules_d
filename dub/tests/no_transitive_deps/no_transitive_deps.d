import semver;

unittest
{
    assert(SemVer("1.2.3").queryAsString(VersionPart.MAJOR) == "1");
    assert(SemVer("1.2.3").queryAsString(VersionPart.MINOR) == "2");
    assert(SemVer("1.2.3").queryAsString(VersionPart.PATCH) == "3");
}
