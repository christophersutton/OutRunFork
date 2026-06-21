//
//  CustomMeasurementFormatting.swift
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

class CustomMeasurementFormatting {

    private static let formatterLock = NSLock()
    private static let wholeNumberFormatter = measurementFormatter(roundingIncrement: 1, unitOptions: .providedUnit)
    private static let oneDigitFormatter = measurementFormatter(roundingIncrement: 0.1, unitOptions: .providedUnit)
    private static let twoDigitFormatter = measurementFormatter(roundingIncrement: 0.01, unitOptions: .providedUnit)
    private static let fourDigitFormatter = measurementFormatter(roundingIncrement: 0.0001, unitOptions: .providedUnit)
    private static let unroundedFormatter = measurementFormatter(roundingIncrement: nil, unitOptions: .providedUnit)
    private static let naturalScaleFormatter = measurementFormatter(roundingIncrement: nil, unitOptions: .naturalScale)
    private static let unitFormatter = MeasurementFormatter()

    private static let clockFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    private static let paceFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    static func string(forMeasurement measurement: NSMeasurement, type: FormattingMeasurementType = .auto, rounding: FormattingRoundingType = .twoDigits) -> String {
        
        let formatter = formatter(for: rounding)
        let type = type == .auto ? FormattingMeasurementType(for: measurement.unit) : type
        
        switch type {
        case .clock, .pace:
            let seconds = measurement.converting(to: UnitDuration.seconds).value
            let formatter = type == .pace ? paceFormatter : clockFormatter
            return formatterLock.withLock { formatter.string(from: seconds) } ?? "Error"
        case .distance:
            return formatterLock.withLock { formatter.string(from: measurement.converting(to: UserPreferences.distanceMeasurementType.safeValue)) }
        case .altitude:
            return formatterLock.withLock { formatter.string(from: measurement.converting(to: UserPreferences.altitudeMeasurementType.safeValue)) }
        case .speed:
            return formatterLock.withLock { formatter.string(from: measurement.converting(to: UserPreferences.speedMeasurementType.safeValue)) }
        case .energy:
            return formatterLock.withLock { formatter.string(from: measurement.converting(to: UserPreferences.energyMeasurementType.safeValue)) }
        case .weight:
            return formatterLock.withLock { formatter.string(from: measurement.converting(to: UserPreferences.weightMeasurementType.safeValue)) }
        default:
            return formatterLock.withLock { naturalScaleFormatter.string(from: measurement as Measurement) }
        }
    }
    
    static func string(forUnit unit: Unit, short: Bool = false) -> String {
        short ? unit.symbol : formatterLock.withLock { unitFormatter.string(from: unit) }
    }

    private static func formatter(for rounding: FormattingRoundingType) -> MeasurementFormatter {
        switch rounding {
        case .wholeNumbers:
            return wholeNumberFormatter
        case .oneDigit:
            return oneDigitFormatter
        case .twoDigits:
            return twoDigitFormatter
        case .fourDigits:
            return fourDigitFormatter
        case .none:
            return unroundedFormatter
        }
    }

    private static func measurementFormatter(roundingIncrement: NSNumber?, unitOptions: MeasurementFormatter.UnitOptions) -> MeasurementFormatter {
        let measurementFormatter = MeasurementFormatter()
        measurementFormatter.unitOptions = unitOptions
        if let roundingIncrement {
            measurementFormatter.numberFormatter.roundingIncrement = roundingIncrement
        }
        return measurementFormatter
    }
    
    enum FormattingMeasurementType {
        case clock, time, pace
        case distance, altitude
        case speed
        case energy
        case weight
        case count
        case auto
        
        init(for unit: Unit, asClock: Bool = false, asAltitude: Bool = false) {
            switch unit {
            case is UnitDuration:
                self = asClock ? .clock : .time
            case is UnitLength:
                self = asAltitude ? .altitude : .distance
            case is UnitSpeed:
                let isPace = [UnitSpeed.minutesPerLengthUnit(from: .kilometers) as Unit, UnitSpeed.minutesPerLengthUnit(from: .miles) as Unit].contains(unit)
                self = isPace ? .pace : .speed
            case is UnitEnergy:
                self = .energy
            case is UnitMass:
                self = .weight
            case is UnitCount:
                self = .count
            default:
                self = .auto
            }
        }
    }
    
    enum FormattingRoundingType {
        case wholeNumbers, oneDigit, twoDigits, fourDigits, none
    }
    
}
