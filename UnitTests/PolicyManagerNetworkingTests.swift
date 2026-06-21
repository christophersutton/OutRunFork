//
//  PolicyManagerNetworkingTests.swift
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

final class PolicyManagerNetworkingTests: XCTestCase {

    func testPolicyFetchUsesHTTPSDefaultCachePolicyAndReusableSession() throws {
        let source = try policyManagerSource()

        XCTAssertTrue(
            source.contains("static let baseURL = \"https://"),
            "PolicyManager must continue fetching policy text over HTTPS."
        )
        XCTAssertFalse(
            source.contains("reloadIgnoringLocalAndRemoteCacheData"),
            "PolicyManager must not bypass local or remote URL loading caches for policy text."
        )
        XCTAssertFalse(
            source.contains("request.cachePolicy"),
            "PolicyManager should leave URLRequest on its default protocol cache policy."
        )
        XCTAssertFalse(
            source.contains("URLSession(configuration:"),
            "PolicyManager must not create a fresh one-off URLSession for each policy query."
        )
        XCTAssertFalse(
            source.contains("finishTasksAndInvalidate"),
            "PolicyManager must not invalidate a reusable/shared policy session after each query."
        )
        XCTAssertTrue(
            source.contains("static let session = URLSession.shared") || source.contains("URLSession.shared.dataTask"),
            "PolicyManager should use URLSession.shared or a static shared session for policy queries."
        )
    }

    private func policyManagerSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("OutRun/Models/Settings/PolicyManager.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
