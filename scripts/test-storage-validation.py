#!/usr/bin/env python3
"""Run current backup validation, boot routing and reset tests without opening app storage.

CoreStore transaction tests remain in the Xcode UnitTests target for the main agent's native run.
This compiles real TempV4, BackupV4, BackupValidation, RootRouter and SettingsDataReset code;
the support shim supplies platform namespaces and fails on accidental app service access.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="movefeet-storage-tests-", dir=os.environ.get("TMPDIR")) as temporary:
    root = Path(temporary)
    sources = root / "Sources/StorageValidationHarness"
    tests = root / "Tests/StorageValidationHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (root / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "StorageValidationHarness", platforms: [.macOS(.v14)], targets: [
    .target(name: "StorageValidationHarness", swiftSettings: [.define("STORAGE_VALIDATION_PORTABLE")]),
    .testTarget(name: "StorageValidationHarnessTests", dependencies: ["StorageValidationHarness"],
                swiftSettings: [.define("STORAGE_VALIDATION_PORTABLE")])
])
''')
    for relative in [
        "MoveFeet/Models/Data/Temp/Versions/TempV4.swift",
        "MoveFeet/Models/Data/Backup/BackupValidation.swift",
        "MoveFeet/Protocols/TempValueConvertible.swift",
        "UnitTests/StoragePortableSupport.swift",
    ]:
        shutil.copyfile(repo / relative, sources / Path(relative).name)
    backup = (repo / "MoveFeet/Models/Data/Backup/Backup.swift").read_text()
    # Keep the current production declarations; old versions depend on unrelated legacy converters.
    (sources / "Backup.swift").write_text(
        backup[:backup.index("struct BackupV1:")] + backup[backup.index("struct BackupV4:"):]
    )
    router = (repo / "MoveFeet/Views/SwiftUI/Shell/RootView.swift").read_text()
    (sources / "RootRouter.swift").write_text(
        router[:router.index("// MARK: - Root view")]
        .replace("import SwiftUI", "import Foundation\nimport Observation").replace("import UIKit", "")
    )
    settings = (repo / "MoveFeet/Views/SwiftUI/Settings/SettingsView.swift").read_text()
    (sources / "SettingsDataReset.swift").write_text(
        settings[settings.index("enum SettingsDataReset"):settings.index("#Preview")]
    )
    for filename in ["StorageFixtures.swift", "BackupValidationTests.swift", "RootStorageFailureTests.swift", "SettingsDataResetTests.swift"]:
        shutil.copyfile(repo / "UnitTests" / filename, tests / filename)
    subprocess.run(["swift", "test", "--package-path", str(root)], check=True)
