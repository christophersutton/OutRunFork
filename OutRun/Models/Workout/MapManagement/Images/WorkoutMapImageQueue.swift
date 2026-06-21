//
//  WorkoutMapImageQueue.swift
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

class WorkoutMapImageQueue {
    
    public var pendingRequests: [WorkoutMapImageRequest] {
        return highPriorityRequests + ordinaryRequests
    }
    
    private var highPriorityRequests = [WorkoutMapImageRequest]()
    private var ordinaryRequests = [WorkoutMapImageRequest]()
    
    func add(_ request: WorkoutMapImageRequest) {
        
        // Identical requests are already pending; keep the original so its completion can still fire.
        if highPriorityRequests.contains(request) {
            return
        }
        
        if request.highPriority {
            if promote(request) {
                return
            }
            highPriorityRequests.append(request)
        } else if !ordinaryRequests.contains(request) {
            ordinaryRequests.append(request)
        }
        
    }
    
    @discardableResult
    func promote(_ request: WorkoutMapImageRequest, excluding excludedRequest: WorkoutMapImageRequest? = nil) -> Bool {
        guard request.highPriority else { return false }
        guard let index = ordinaryRequests.firstIndex(of: request) else { return false }
        let pendingRequest = ordinaryRequests.remove(at: index)
        if pendingRequest === excludedRequest {
            ordinaryRequests.insert(pendingRequest, at: index)
            return false
        }
        highPriorityRequests.append(
            WorkoutMapImageRequest(
                workoutUUID: pendingRequest.workoutUUID,
                size: pendingRequest.size,
                pointSize: pendingRequest.pointSize,
                scale: pendingRequest.scale,
                usesDarkAppearance: pendingRequest.usesDarkAppearance,
                highPriority: true,
                completion: pendingRequest.completion
            )
        )
        return true
    }

    func remove(_ request: WorkoutMapImageRequest) {
        
        switch request.highPriority {
        case true:
            highPriorityRequests.removeAll { (pendingRequest) -> Bool in
                pendingRequest == request
            }
        default:
            ordinaryRequests.removeAll { (pendingRequest) -> Bool in
                pendingRequest == request
            }
        }
        
    }
    
}
