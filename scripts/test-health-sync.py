#!/usr/bin/env python3
"""Run the production Foundation synchronization seams without an app/device/store.
Native app builds and HealthKit integration tests remain the main agent's job.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
package = Path(tempfile.mkdtemp(prefix="movefeet-health-tests-", dir=os.environ.get("TMPDIR")))
(package / "Sources/HealthSyncCore").mkdir(parents=True)
(package / "Tests/HealthSyncCoreTests").mkdir(parents=True)
(package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HealthSyncCore", products: [], targets: [
    .target(name: "HealthSyncCore"),
    .testTarget(name: "HealthSyncCoreTests", dependencies: ["HealthSyncCore"])
])
''')
shutil.copy2(root / "MoveFeet/Models/HealthKit/HealthStoreManager+SyncState.swift", package / "Sources/HealthSyncCore/HealthSyncState.swift")
shutil.copy2(root / "UnitTests/HealthSyncBehaviorTests.swift", package / "Tests/HealthSyncCoreTests/HealthSyncBehaviorTests.swift")
# Run the existing HealthKit blocking-query regressions unchanged. Their source
# location is retained so their repository inspections still point to this worktree.
blocking = root / "UnitTests/HealthKitBlockingQueryTests.swift"
(package / "Tests/HealthSyncCoreTests/HealthKitBlockingQueryTests.swift").write_text(
    blocking.read_text().replace("#filePath", '"' + str(blocking) + '"'))
print(f"Temporary test package: {package}", flush=True)
raise SystemExit(subprocess.call(["swift", "test", "--package-path", str(package)]))
