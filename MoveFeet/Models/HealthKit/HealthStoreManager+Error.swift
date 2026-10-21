//
//  HealthStoreManager+Error.swift
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
import HealthKit

extension HealthStoreManager {
    
    enum HealthError: Error, LocalizedError, CustomDebugStringConvertible {
        
        /// The intended action could not be performed due to lack of proper authorisation.
        case insufficientAuthorisation
        /// While carrying out the intended action an error occured in the health store.
        case healthKitError(error: Error?)
        /// The intended action could be performed, but not carried out in it's full extend due to lack of optional authorisation
        case optionalAuthorisationMissing
        /// The input provided to perform the intended action was invalid
        case invalidInput
        
        case importConversionFailed
        case exportIncomplete
        case exportOptionalDataDenied
        case exportRecoveryRequired
        case existingHealthHistoryPreserved

        var errorDescription: String? { debugDescription }

        var debugDescription: String {
            switch self {
            case .importConversionFailed:
                return "Health import could not be fully converted. The import checkpoint was retained for retry."
            case .exportOptionalDataDenied:
                return "The Health workout was saved with incomplete optional data. Your local workout is safe. Allow the desired types in Health, then use Sync All to retry."
            case .exportIncomplete:
                return "The Health workout was saved, but some attachments failed. Your local workout is safe. Use Sync All to retry."
            case .exportRecoveryRequired:
                return "The existing Health export could not be safely identified. No duplicate was created. Your local workout is safe."
            case .existingHealthHistoryPreserved:
                return "Your local edits were saved. The existing Health workout was preserved; Health history is not automatically replaced."
            case .insufficientAuthorisation:
                return "The intended action could not be performed due to lack of proper authorisation."
            case .healthKitError(let error):
                return "While carrying out the intended action an error occured in the health store." + (error != nil ? " Health Error: \(error!.localizedDescription)" : "")
            case .optionalAuthorisationMissing:
                return "The intended action could be performed, but not carried out to it's full extend due to lack of optional authorisation. Please check whether you have granted all the required permissions in Health."
            case .invalidInput:
                return "The input provided to perform the intended action was invalid"
            }
        }
        
    }
    
}
