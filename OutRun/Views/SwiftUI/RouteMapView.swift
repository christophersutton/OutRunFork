//
//  RouteMapView.swift
//
//  OutRun
//
//  Reusable SwiftUI wrapper around MKMapView for rendering a workout route polyline. MapKit stays in UIKit
//  here deliberately: the route uses a custom MKPolylineRenderer (and fine-grained delegate control) that
//  SwiftUI's Map cannot express. The Coordinator owns the renderer; updateUIView diffs the route to avoid
//  redundant work.
//

import SwiftUI
import MapKit

struct RouteMapView: UIViewRepresentable {

    let coordinates: [CLLocationCoordinate2D]
    var isInteractive: Bool = true
    var insets: UIEdgeInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = isInteractive
        map.showsUserLocation = false
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Guard: only rebuild the overlay when the route actually changes.
        guard context.coordinator.appliedCount != coordinates.count else { return }
        context.coordinator.appliedCount = coordinates.count

        map.removeOverlays(map.overlays)
        guard coordinates.count > 1 else { return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline, level: .aboveRoads)
        map.setVisibleMapRect(polyline.boundingMapRect, edgePadding: insets, animated: false)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.removeOverlays(map.overlays)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var appliedCount = -1

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .accentColor
            renderer.lineWidth = 8.0
            renderer.lineCap = .round
            return renderer
        }
    }
}
