//
//  ApplicationStateObservation.swift
//
//  OutRun
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
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

import Foundation

struct ApplicationStateObservation {
    
    weak var observer: ApplicationStateObserver?

    private static let observationsLock = NSLock()
    private static var _observations: [ObjectIdentifier:ApplicationStateObservation] = [:]

    static var observations: [ObjectIdentifier:ApplicationStateObservation] {
        get {
            observationsLock.lock()
            defer { observationsLock.unlock() }
            return _observations
        }
        set {
            observationsLock.lock()
            defer { observationsLock.unlock() }
            _observations = newValue
        }
    }
    
    static func addObserver(_ observer: ApplicationStateObserver) {
        let identifier = ObjectIdentifier(observer)
        observationsLock.lock()
        defer { observationsLock.unlock() }
        _observations.updateValue(
            ApplicationStateObservation(observer: observer),
            forKey: identifier
        )
    }
    
    static func removeObserver(_ observer: ApplicationStateObserver) {
        let identifier = ObjectIdentifier(observer)
        observationsLock.lock()
        defer { observationsLock.unlock() }
        _observations.removeValue(forKey: identifier)
    }
    
    static func stateChanged(to state: ApplicationState) {
        var activeObservers: [ApplicationStateObserver] = []

        observationsLock.lock()
        for (identifier, observation) in _observations {
            
            guard let observer = observation.observer else {
                _observations.removeValue(forKey: identifier)
                continue
            }

            activeObservers.append(observer)
        }
        observationsLock.unlock()

        for observer in activeObservers {
            observer.didUpdateApplicationState(to: state)
        }
    }
    
}
