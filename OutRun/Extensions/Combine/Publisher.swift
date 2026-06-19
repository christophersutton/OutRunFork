//
//  Publisher.swift
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
import Combine

/// A single, responsive serial queue used to deliver WorkoutBuilder output off the relay-mutation thread.
///
/// This replaces the previous implementation, which created a fresh `qos: .background` queue per call and
/// added `.subscribe(on:)`. That had two problems: `.background` QoS starved real-time GPS/timer updates, and
/// — critically — combining several of these publishers with `combineLatest` never emitted, because each had
/// its own async `.subscribe(on:)` queue, which broke combineLatest's subscription/demand coordination. That
/// silently froze the live duration, speed and burned-energy readouts. Delivering on one shared queue (and
/// dropping `.subscribe(on:)`) restores combineLatest while keeping work off the mutation thread.
private let outRunBackgroundDeliveryQueue = DispatchQueue(label: "outrun.background.delivery", qos: .userInitiated)

public extension Publisher {

    /// Creates a `Publisher` whose values are delivered on a shared, responsive background queue.
    func asBackgroundPublisher() -> AnyPublisher<Output, Failure> {
        return self.receive(on: outRunBackgroundDeliveryQueue).eraseToAnyPublisher()
    }
    
    /**
     Publishes the current element together with its predecessor.
     
         let range = (1...3)
         cancellable = range.publisher
            .withPrevious()
            .sink {
                print ("(\($0.previous), \($0.current))", terminator: " ")
            }
         // Prints: "(nil, 1) (Optional(1), 2) (Optional(2), 3) ".
     
     - note: The first element will be accompanied by `nil` as the previous value.
     - returns: A publisher of a touple of the optional previous and the current element from the upstream publisher.
     */
    func withPrevious() -> AnyPublisher<(previous: Output?, current: Output), Failure> {
        scan(Optional<(Output?, Output)>.none) { ($0?.1, $1) }
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}
