//
//  CustomDateFormatting.swift
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

class CustomDateFormatting {
    
    static let dayIDFormat = "yyyyMMdd"

    private static let formatterLock = NSLock()
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayIdentifierFormatter = fixedDateFormatter(for: dayIDFormat)
    private static let backupTimeCodeFormatter = fixedDateFormatter(for: "yyyyMMdd-HHmmss")
    
    static func dayString(forDate date: Date) -> String {
        if date.isSameDay() {
            return LS["Today"]
        } else if date.isYesterday() {
            return LS["Yesterday"]
        }
        
        if date.isLessThanAWeekAway() {
            return formatterLock.withLock { weekdayFormatter.string(from: date) }
        }
        
        return formatterLock.withLock { mediumDateFormatter.string(from: date) }
    }
    
    static func dayString(forIdentifier dayIdentifier: String) -> String? {
        guard let date = formatterLock.withLock({ dayIdentifierFormatter.date(from: dayIdentifier) }) else {
            return nil
        }
        return dayString(forDate: date)
    }
    
    static func dayIdentifier(forDate date: Date) -> String {
        formatterLock.withLock { dayIdentifierFormatter.string(from: date) }
    }
    
    static func timeString(forDate date: Date) -> String {
        formatterLock.withLock { timeFormatter.string(from: date) }
    }
    
    static func backupTimeCode(forDate date: Date) -> String {
        formatterLock.withLock { backupTimeCodeFormatter.string(from: date) }
    }
    
    static func fullDateString(forDate date: Date) -> String {
        formatterLock.withLock { fullDateFormatter.string(from: date) }
    }

    private static func fixedDateFormatter(for dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.calendar = gregorianCalendar
        formatter.dateFormat = dateFormat
        return formatter
    }
    
}
