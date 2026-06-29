//
//  MainActorIsolationTests.swift
//
//  OutRun
//  Copyright (C) 2026 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import XCTest

final class MainActorIsolationTests: XCTestCase {

    func testUIKitClassesDeclareMainActorIsolation() throws {
        let targets = [
            UIKitType(path: "MoveFeet/Views/Data/LoadingView.swift", declaration: "class LoadingView: UIView"),
            UIKitType(path: "MoveFeet/Views/Data/LabelledDataView.swift", declaration: "class LabelledDataView: UIView"),
            UIKitType(path: "MoveFeet/Views/Workout/WorkoutActionView.swift", declaration: "class WorkoutActionView: UIView"),
            UIKitType(path: "MoveFeet/Views/Workout/WorkoutBuilderTypeView.swift", declaration: "class WorkoutBuilderTypeView: UIView"),
            UIKitType(path: "MoveFeet/Views/Workout/WorkoutBuilderReadinessIndicationView.swift", declaration: "class WorkoutBuilderReadinessIndicationView: UIView"),
            UIKitType(path: "MoveFeet/Views/Workout/NewWorkoutControllerActionButton.swift", declaration: "class NewWorkoutControllerActionButton: UIView"),
            UIKitType(path: "MoveFeet/Views/ORBanner/ORBaseBanner.swift", declaration: "public class ORBaseBanner: UIView"),
            UIKitType(path: "MoveFeet/Controllers/General/DetailViewController.swift", declaration: "class DetailViewController: UIViewController")
        ]

        for target in targets {
            let source = try String(contentsOf: repositoryRoot.appendingPathComponent(target.path), encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            let declarationIndex = try XCTUnwrap(
                lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(target.declaration) },
                "\(target.path) should contain \(target.declaration)"
            )
            let previousNonEmptyLine = lines[..<declarationIndex]
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                .trimmingCharacters(in: .whitespaces)

            XCTAssertEqual(
                previousNonEmptyLine,
                "@MainActor",
                "\(target.path) should explicitly isolate \(target.declaration) to the main actor."
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

}

private struct UIKitType {

    let path: String
    let declaration: String

}
