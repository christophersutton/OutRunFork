//
//  PrivacyManifestTests.swift
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

final class PrivacyManifestTests: XCTestCase {

    func testAppPrivacyManifestDeclaresRequiredReasonAPIs() throws {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "OutRun.app must include PrivacyInfo.xcprivacy in its bundle resources."
        )

        let data = try Data(contentsOf: manifestURL)
        let manifest = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dictionary = try XCTUnwrap(
            manifest as? [String: Any],
            "PrivacyInfo.xcprivacy must be a plist dictionary."
        )
        let accessedAPITypes = try XCTUnwrap(
            dictionary["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "PrivacyInfo.xcprivacy must declare NSPrivacyAccessedAPITypes."
        )

        let declaredReasonsByCategory = accessedAPITypes.reduce(into: [String: Set<String>]()) { result, entry in
            guard let category = entry["NSPrivacyAccessedAPIType"] as? String else { return }
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            result[category, default: []].formUnion(reasons)
        }

        let requiredReasonsByCategory: [String: Set<String>] = [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]
        ]

        for (category, requiredReasons) in requiredReasonsByCategory {
            let declaredReasons = declaredReasonsByCategory[category] ?? []
            XCTAssertTrue(
                declaredReasons.isSuperset(of: requiredReasons),
                "PrivacyInfo.xcprivacy must declare \(category) with reasons \(requiredReasons.sorted())."
            )
        }
    }

}
