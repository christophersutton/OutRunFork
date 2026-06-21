//
//  LocationAccuracyPreferenceTests.swift
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

import CoreLocation
import XCTest
@testable import OutRun

final class LocationAccuracyPreferenceTests: XCTestCase {

    func testLocationManagerDesiredAccuracyFollowsGPSAccuracyPreference() {
        XCTAssertEqual(LocationManagement.locationManagerDesiredAccuracy(forGPSAccuracyPreference: 20), 20)
        XCTAssertEqual(LocationManagement.locationManagerDesiredAccuracy(forGPSAccuracyPreference: 30), 30)
        XCTAssertEqual(LocationManagement.locationManagerDesiredAccuracy(forGPSAccuracyPreference: 50), 50)
    }

    func testLocationManagerDesiredAccuracyPreservesStandardAdaptiveMode() {
        XCTAssertEqual(LocationManagement.locationManagerDesiredAccuracy(forGPSAccuracyPreference: nil), kCLLocationAccuracyBest)
    }

    func testLocationTrackingIsEnabledForStandardAndMeterPreferences() {
        XCTAssertTrue(LocationManagement.locationUpdatesEnabled(forGPSAccuracyPreference: nil))
        XCTAssertTrue(LocationManagement.locationUpdatesEnabled(forGPSAccuracyPreference: 20))
        XCTAssertTrue(LocationManagement.locationUpdatesEnabled(forGPSAccuracyPreference: 30))
        XCTAssertTrue(LocationManagement.locationUpdatesEnabled(forGPSAccuracyPreference: 50))
    }

    func testRouteFilteringAccuracyKeepsExistingPreferenceSemantics() {
        XCTAssertEqual(LocationManagement.routeFilteringAccuracy(forGPSAccuracyPreference: nil), 20)
        XCTAssertEqual(LocationManagement.routeFilteringAccuracy(forGPSAccuracyPreference: 20), 20)
        XCTAssertEqual(LocationManagement.routeFilteringAccuracy(forGPSAccuracyPreference: 30), 30)
        XCTAssertEqual(LocationManagement.routeFilteringAccuracy(forGPSAccuracyPreference: 50), 50)
    }

    func testLocationTrackingAndRouteFilteringAreDisabledWhenPreferenceIsOff() {
        XCTAssertFalse(LocationManagement.locationUpdatesEnabled(forGPSAccuracyPreference: -1))
        XCTAssertNil(LocationManagement.locationManagerDesiredAccuracy(forGPSAccuracyPreference: -1))
        XCTAssertNil(LocationManagement.routeFilteringAccuracy(forGPSAccuracyPreference: -1))
    }

}
