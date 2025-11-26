"""Known DUB versions and their download URLs and integrity hashes."""

DUB_VERSIONS = {
    "dub-1.40.0": {
        "x86_64-unknown-linux-gnu": {
            "url": "https://github.com/dlang/dub/releases/download/v1.40.0/dub-v1.40.0-linux-x86_64.tar.gz",
            "integrity": "sha256-77mJHmjU05ricPm9GuBbiII03gDB5JCyUjrXLfv+WZE=",
        },
        "x86_64-apple-darwin": {
            "url": "https://github.com/dlang/dub/releases/download/v1.40.0/dub-v1.40.0-osx-x86_64.tar.gz",
            "integrity": "sha256-BSWtvlSkTISpMgPbQgVk4Bv3l1d9c36NPoxDGSNRp98=",
        },
        "aarch64-apple-darwin": {
            "url": "https://github.com/dlang/dub/releases/download/v1.40.0/dub-v1.40.0-osx-arm64.tar.gz",
            "integrity": "sha256-bjMjfFsWq8Ov0xbKSM7ptlf7w1ZdtmSiYrkajZXgWaw=",
        },
        "x86_64-pc-windows-msvc": {
            "url": "https://github.com/dlang/dub/releases/download/v1.40.0/dub-v1.40.0-windows-x86_64.zip",
            "integrity": "sha256-MaammCZTsnn+CEnB2VtlcvJ2KkUWfFdxsE9mUc9SfDk=",
        },
    },
}
