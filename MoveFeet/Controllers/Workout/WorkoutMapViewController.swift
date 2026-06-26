//
//  WorkoutMapViewController.swift
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

import UIKit
import MapKit

class WorkoutMapViewController: MapViewControllerWithContainerView {

    var workout: Workout?

    var annotation: MKPointAnnotation?
    lazy var marker = MKMarkerAnnotationView(annotation: self.annotation, reuseIdentifier: nil)

    lazy var compass: MKCompassButton = {
        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .adaptive
        return compass
    }()
    
    lazy var mapTypeButton = FloatingButton(
        title: LS["Standard"].uppercased(),
        action: { button in
            
            func option(for type: MKMapType) -> (title: String, style: UIAlertAction.Style, action: (UIAlertAction) -> Void) {
                let title: String = {
                    switch type {
                    case .standard:
                        return LS["Standard"]
                    case .hybrid:
                        return LS["MapView.MapType.Hybrid"]
                    case .satellite:
                        return LS["MapView.MapType.Satellite"]
                    default:
                        return LS["Error"]
                    }
                }()
                
                return (
                    title: title,
                    style: .default,
                    action: { action in
                        Task { @MainActor in
                            self.mapView?.mapType = type
                            button.setTitle(title.uppercased(), for: .normal)
                        }
                    }
                )
            }
            
            let alert = UIAlertController(
                title: LS["MapView.MapTypeAlert.Title"],
                message: LS["MapView.MapTypeAlert.Message"],
                preferredStyle: .alert,
                options: [
                    option(for: .standard),
                    option(for: .hybrid),
                    option(for: .satellite),
                    (
                        title: LS["Cancel"],
                        style: .cancel,
                        action: nil
                    )
                ]
            )
            
            self.present(alert, animated: true)
        }
    )
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .backgroundColor

        // The old bottom panel hosted an (always-empty) DGCharts diagram; it has been removed, so the map
        // is now full-bleed. Collapse the inherited containerView and anchor the controls to the safe area.
        containerView.isHidden = true
        containerView.snp.makeConstraints { (make) in
            make.height.equalTo(0)
        }

        self.view.addSubview(compass)
        self.view.addSubview(mapTypeButton)

        compass.snp.makeConstraints { (make) in
            make.right.equalTo(view.safeAreaLayoutGuide).offset(-20)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-20)
        }
        mapTypeButton.snp.makeConstraints { (make) in
            make.left.equalTo(view.safeAreaLayoutGuide).offset(10)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-10)
        }

        guard let workout = workout else {
            print("Workout map controller dismissed, because workout == nil")
            self.dismiss(animated: true)
            return
        }

        self.headline = LS["WorkoutMapController.Headline"]

        if let mapView = self.mapView {
            WorkoutMapViewManager.setupRoute(
                forWorkout: workout,
                mapView: mapView,
                customEdgePadding: UIEdgeInsets(top: 100, left: 20, bottom: 50, right: 20)
            ) {
                print("Map set up")
            }
        }
    }

    override func close() {
        self.dismiss(animated: true)
    }

}
