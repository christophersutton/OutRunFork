//
//  BackupManager.swift
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
import UIKit

enum BackupManager {
    
    typealias DataInclusionType = ExportManager.DataInclusionType
    
    /**
     Creates a backup and saves it to a file providing it for export.
     - parameter workouts: the workouts being saved into the backup; if `nil` all workouts inside the database will be used
     - parameter completion: a closure providing the status of success of the operation and an optional url to the created file
     - parameter success: indicates the success of the completion
     - parameter url: points to the saved backup file
     */
    public static func createBackup(for inclusionType: DataInclusionType, completion: @escaping (_ success: Bool, _ url: URL?) -> Void) {
        
        DataManager.queryBackupData(
            for: inclusionType,
            completion: { (error, data) in
                
                guard let data = data else {
                    completion(false, nil)
                    return
                }
                
                let directory = FileManager.default.temporaryDirectory
                let name = "/\(CustomDateFormatting.backupTimeCode(forDate: Date())).orbup"
                let url = directory.appendingPathComponent(name)
                
                do {
                    try TemporaryExportFileProtection.write(data: data, to: url)
                    completion(true, url)
                } catch {
                    completion(false, nil)
                }
                
            }
        )
        
    }
    
    /**
     Inserts the data from the backup file into the database.
     - parameter completion: a closure providing the status of success of the operation and a reference to the saved data
     - parameter success: indicates the success of the completion
     - parameter workouts: the workouts that were saved to the database
     - parameter events: the events that were saved to the database
     */
    static func insertBackup(from url: URL, completion: @escaping (_ success: Bool, _ workouts: [ORWorkoutInterface], _ events: [OREventInterface]) -> Void) {

        insertBackup(from: url) { (result: Result<DataManager.RestoreReport, Error>) in
            switch result {
            case .success(let report): completion(true, report.workouts, report.events)
            case .failure: completion(false, [], [])
            }
        }
    }

    /// Detailed result for callers displaying imported and duplicate counts. Duplicate-only restores
    /// are successful; a genuine failure returns no imported objects because the transaction rolls back.
    static func insertBackup(from url: URL, completion: @escaping (Result<DataManager.RestoreReport, Error>) -> Void) {
        let completion = safeClosure(from: completion)
        do {
            let payload = try decodeBackup(from: Data(contentsOf: url))
            DataManager.restore(workouts: payload.workouts, events: payload.events,
                                in: DataManager.dataStack, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    static func decodeBackup(from data: Data) throws -> (events: [TempEvent], workouts: [TempWorkout]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            throw BackupValidation.InvalidData(field: "backup version")
        }
        switch version {
        case BackupV1.versionCode:
            let backup = try JSONDecoder().decode(BackupV1.self, from: data)
            return ([], backup.workoutData.map { $0.asTemp })
        case BackupV2.versionCode:
            let backup = try JSONDecoder().decode(BackupV2.self, from: data)
            return ([], backup.workoutData.map { $0.asTemp })
        case BackupV3.versionCode:
            let backup = try JSONDecoder().decode(BackupV3.self, from: data)
            return (backup.eventData.map { $0.asTemp }, backup.workoutData.map { $0.asTemp })
        case BackupV4.versionCode:
            let backup = try JSONDecoder().decode(Backup.self, from: data)
            return (backup.eventData, backup.workoutData)
        default:
            throw BackupValidation.InvalidData(field: "unsupported backup version")
        }
    }
}
