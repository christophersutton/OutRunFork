//
//  WorkoutMapImageManager.swift
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

import MapKit
import UIKit

/// An enum containing static functions and properties, dedicated to rendering workout map images.
enum WorkoutMapImageManager {
    
    private static var internalStatus = Status.idle {
        didSet {
            if oldValue == .suspended {
                executeNextInQueue()
            }
        }
    }
    private static var requestQueue = WorkoutMapImageQueue()
    private static var requestCompletions = [String: [(Bool, UIImage?) -> Void]]()
    private static var runningRequest: WorkoutMapImageRequest?
    private static let processQueue = DispatchQueue(label: "processQueue", qos: .userInitiated)
    private static let snapshotQueue = DispatchQueue(label: "snapshotQueue")
    
    /// A funtion for the execution of a WorkoutMapImageRequest, adding it to the running WorkoutMapImageQueue. If cached this method directly executes the closure, not rendering the image again.
    ///
    /// - Parameter request: An instance of WorkoutMapImageRequest indicating the type of image being requested
    public static func execute(_ request: WorkoutMapImageRequest) {

        guard let id = request.cacheIdentifier() else {
            DispatchQueue.main.async {
                request.completion(false, nil)
            }
            return
        }

        processQueue.async {
            if let image = CustomImageCache.mapImageCache.getMapImage(for: id) {
                DispatchQueue.main.async {
                    request.completion(true, image)
                }
                return
            }

            DispatchQueue.main.async {
                enqueueUncached(request, cacheIdentifier: id)
            }
        }
    }

    private static func enqueueUncached(_ request: WorkoutMapImageRequest, cacheIdentifier: String) {

        if requestCompletions[cacheIdentifier] != nil {
            requestCompletions[cacheIdentifier]?.append(request.completion)
            if request.highPriority {
                requestQueue.promote(request, excluding: runningRequest)
            }
            return
        }

        requestCompletions[cacheIdentifier] = [request.completion]
        let queuedRequest = WorkoutMapImageRequest(
            workoutUUID: request.workoutUUID,
            size: request.size,
            pointSize: request.pointSize,
            scale: request.scale,
            usesDarkAppearance: request.usesDarkAppearance,
            highPriority: request.highPriority,
            completion: { success, image in
                let completions = requestCompletions.removeValue(forKey: cacheIdentifier) ?? []
                completions.forEach { $0(success, image) }
            }
        )

        requestQueue.add(queuedRequest)
        if internalStatus == .idle {
            executeNextInQueue()
        }
    }
    
    /// A function suspending the rendering process of new map images to limit cpu cost. This function should only be used when the app enters the background, to ensure that it does not get terminated by the system.
    public static func suspendRenderProcess() {
        guard internalStatus != .suspended else {
            return
        }

        internalStatus = .suspended
    }
    
    /// A Funtion resuming the rendering process of new map images after it was suspended by `suspendRenderProcess()`.
    public static func resumeRenderProcess() {
        guard internalStatus == .suspended else {
            return
        }

        internalStatus = .idle
    }
    
    private static func executeNextInQueue() {
        
        if internalStatus == .suspended {
            return
        }
        
        guard let request = requestQueue.pendingRequests.first else {
            internalStatus = .idle
            return
        }
        
        internalStatus = .running
        runningRequest = request
        
        let imageUsesDarkMode = request.usesDarkAppearance
        let completion: (Bool, UIImage?) -> Void = { (success, image) in
            finish(request, success: success, image: image)
        }
        
        guard let uuid = request.workoutUUID else {
            completion(false, nil)
            return
        }
        
        DataManager.asyncLocationCoordinatesQuery(
            for: ORPrimitive<Workout>(uuid: uuid),
            completion: { error, coordinates in
                if error == nil {
                    
                    processQueue.async {
                        
                        guard coordinates.count > 1 else {
                            completion(false, nil)
                            return
                        }
                        
                        let route = MKPolyline(coordinates: coordinates, count: coordinates.count)
                        let renderCoordinates = simplifiedCoordinates(coordinates, for: request.size)
                        
                        let mapSnapshotOptions = MKMapSnapshotter.Options()
                        mapSnapshotOptions.region = MKCoordinateRegion(route.boundingMapRect.insetBy(dx: route.boundingMapRect.width * -0.1, dy: route.boundingMapRect.height * -0.1))
                        mapSnapshotOptions.scale = request.scale
                        mapSnapshotOptions.size = request.pointSize
                        mapSnapshotOptions.showsBuildings = true
                        mapSnapshotOptions.showsPointsOfInterest = false
                        mapSnapshotOptions.mapType = .standard
                        mapSnapshotOptions.traitCollection = UITraitCollection(userInterfaceStyle: imageUsesDarkMode ? .dark : .light)
                        
                        let snapshotter = MKMapSnapshotter(options: mapSnapshotOptions)
                        
                        snapshotter.start(with: snapshotQueue, completionHandler: { snapshot, error in
                            if error == nil, let snapshot = snapshot {
                                let image = snapshot.image
                                let format = UIGraphicsImageRendererFormat()
                                format.scale = image.scale
                                format.opaque = true

                                let renderer = UIGraphicsImageRenderer(size: request.pointSize, format: format)
                                let resultImage = renderer.image { rendererContext in
                                    image.draw(at: CGPoint.zero)

                                    let context = rendererContext.cgContext
                                    context.setLineWidth(3.0)
                                    context.setLineCap(.round)
                                    context.setStrokeColor(UIColor.accentColor.cgColor)
                                    context.move(to: snapshot.point(for: renderCoordinates[0]))
                                    for coordinate in renderCoordinates.dropFirst() {
                                        context.addLine(to: snapshot.point(for: coordinate))
                                    }
                                    context.strokePath()
                                }
                                
                                if let id = request.cacheIdentifier(forDarkAppearance: imageUsesDarkMode) {
                                    CustomImageCache.mapImageCache.set(mapImage: resultImage, for: id)
                                }
                                
                                finish(request, success: true, image: resultImage) {
                                    if Config.isDarkModeEnabled != imageUsesDarkMode {
                                        let updatedAppearanceRequest = WorkoutMapImageRequest(
                                            workoutUUID: request.workoutUUID,
                                            size: request.size,
                                            pointSize: request.pointSize,
                                            scale: request.scale,
                                            usesDarkAppearance: Config.isDarkModeEnabled,
                                            highPriority: request.highPriority,
                                            completion: request.completion
                                        )
                                        if let updatedCacheIdentifier = updatedAppearanceRequest.cacheIdentifier() {
                                            enqueueUncached(updatedAppearanceRequest, cacheIdentifier: updatedCacheIdentifier)
                                        } else {
                                            updatedAppearanceRequest.completion(false, nil)
                                        }
                                    }
                                }
                                
                            } else {
                                completion(false, nil)
                            }
                        })
                    }
                } else {
                    completion(false, nil)
                }
            }
        )
        
    }

    private static func finish(_ request: WorkoutMapImageRequest, success: Bool, image: UIImage?, followedBy followUp: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            requestQueue.remove(request)
            if runningRequest === request {
                runningRequest = nil
            }
            request.completion(success, image)
            followUp?()
            executeNextInQueue()
        }
    }

    private static func simplifiedCoordinates(_ coordinates: [CLLocationCoordinate2D], for size: WorkoutMapImageSize) -> [CLLocationCoordinate2D] {
        let maximumCount: Int
        switch size {
        case .list:
            maximumCount = 700
        case .stats:
            maximumCount = 1_500
        }

        guard coordinates.count > maximumCount, maximumCount > 2 else {
            return coordinates
        }

        let stride = Double(coordinates.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            coordinates[Int((Double(index) * stride).rounded())]
        }
    }
    
    private enum Status {
        case idle, running, suspended
    }
    
}
