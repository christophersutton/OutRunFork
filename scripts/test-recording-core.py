#!/usr/bin/env python3
"""Run dependency-free behavioral XCTest cases against the actual recording core sources.
Uses only synthetic files under a fresh system temporary directory; no app data or sensors.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="feet-recording-tests-") as directory:
    package = Path(directory)
    sources = package / "Sources/RecordingCore"
    tests = package / "Tests/RecordingCoreTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RecordingCore", targets: [
    .target(name: "RecordingCore"),
    .testTarget(name: "RecordingCoreTests", dependencies: ["RecordingCore"])
])
''')
    for name in ["RecordingCheckpointStore.swift", "RecordingLocationGate.swift", "RecordingSaveOperation.swift"]:
        shutil.copy2(root / "MoveFeet/Models/Workout/WorkoutBuilder" / name, sources / name)
    shutil.copy2(root / "UnitTests/RecordingDurabilityTests.swift", tests)
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
