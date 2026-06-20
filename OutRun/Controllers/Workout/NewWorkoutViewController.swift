//
//  NewWorkoutViewController.swift
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
import SnapKit
import Combine

class NewWorkoutViewController: MapViewControllerWithContainerView, UIGestureRecognizerDelegate {
    
    private let builder: WorkoutBuilder
    private let autoPauseDetection: AutoPauseDetection
    private let locationManagement: LocationManagement
    private let stepCounter: StepCounter
    private let altitudeManagement: AltitudeManagement
    private let liveStats: LiveStats
    
    var initialWorkoutType = Workout.WorkoutType(rawValue: UserPreferences.standardWorkoutType.value)
    
    var userMovedMap: Bool = false {
        didSet {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.25) {
                    self.recenterButton.isHidden = !self.userMovedMap
                }
            }
        }
    }
    
    let readinessIndicatorView = WorkoutBuilderReadinessIndicationView()
    lazy var typeView = FloatingButton(title: workoutTypeSubject.value.description) { [weak self] button in
        guard let self else { return }
        let alert = WorkoutTypeAlert { [weak self, weak button] type in
            self?.workoutTypeSubject.send(type)
            button?.setTitle(type.description.uppercased(), for: .normal)
        }
        alert.present(on: self)
    }
    
    let distanceView = LabelledDataView(title: LS["Workout.Distance"])
    let durationView = LabelledDataView(title: LS["Workout.Duration"])
    let speedView = LabelledDataView(title: UserPreferences.displayRollingSpeed.value ? LS["Workout.AverageSpeed"] : LS["Workout.CurrentSpeed"])
    let paceView = LabelledDataView(title: UserPreferences.displayRollingSpeed.value ? LS["Workout.RollingPace"] : LS["Workout.TotalPace"])
    let caloriesView: LabelledDataView = LabelledDataView(title: LS["Workout.BurnedCalories"])

    /// Either the speed or the pace tile depending on the user's unit preference; this is the
    /// one actually shown on screen, and therefore the one the live speed value is bound to.
    private lazy var speedIndication: LabelledDataView = UserPreferences.speedMeasurementType.safeValue.isPaceUnit ? paceView : speedView

    lazy var actionButton = NewWorkoutControllerActionButton { [weak self] (button, actionType) in
        guard let self else { return }
        switch actionType {
        case .start:
            self.suggestNewStatusSubject.send(.recording)
        case .stop:
            self.suggestNewStatusSubject.send(.ready)
        case .pauseOrContinue:
            self.suggestNewStatusSubject.send(.paused)
        }
    }
    
    var lastLocationWhileNotCentered: CLLocation?
    lazy var recenterButton = FloatingButton(title: LS["NewWorkoutViewController.Recenter"]) { (button) in
        self.userMovedMap = false
        
        guard let location = self.lastLocationWhileNotCentered else { return }
        let camera = MKMapCamera(lookingAtCenter: location.coordinate, fromDistance: 200, pitch: 0, heading: location.course)
        self.mapView?.setCamera(camera, animated: true)
    }
    
    var routeOverlay: MKOverlay?
    
    var blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    
    override func viewDidLoad() {
        
        if !UserPreferences.shouldShowMap.value {
            
            self.mapView = nil
            
        }
        
        self.headline = LS["Workout.NewWorkout"]
        mapView?.delegate = WorkoutMapViewDelegate.standard
        self.readinessIndicatorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(displayIndicationAlert)))
        self.recenterButton.isHidden = true
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(userInteractedWithMap(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(userInteractedWithMap(_:)))
        pan.delegate = self
        pinch.delegate = self
        self.mapView?.addGestureRecognizer(pan)
        self.mapView?.addGestureRecognizer(pinch)
        
        self.view.addSubview(blurView)
        blurView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        
        super.viewDidLoad()

        prepareLayout()
        prepareBindings()
    }
    
    @objc func displayIndicationAlert() {
        if self.readinessIndicatorView.status == .waiting {
            let alert = UIAlertController(
                title: LS["NewWorkoutViewController.WaitingAlert.Title"],
                message: LS["NewWorkoutViewController.WaitingAlert.Message"],
                preferredStyle: .alert,
                options: [
                    (
                        title: LS["Okay"],
                        style: .default,
                        action: nil
                    )
                ]
            )
            self.present(alert, animated: true)
        }
    }
    
    @objc override func close() {
        
        if builder.status.isActiveStatus {
            
            var alert: UIAlertController?
            alert = UIAlertController(
                title: LS["NewWorkoutViewController.Cancel.Error.Recording.Title"],
                message: LS["NewWorkoutViewController.Cancel.Error.Recording.Message"],
                preferredStyle: .alert,
                options: [
                    (
                        title: LS["NewWorkoutViewController.Cancel.Error.Recording.Action.StopRecording"],
                        style: .destructive,
                        action: { [weak self] _ in
                            guard let self else { return }
                            // Ask the builder to stop & persist, then dismiss once it reports `.ready`.
                            self.suggestNewStatusSubject.send(.ready)
                            self.statusSubject
                                .receive(on: DispatchQueue.main)
                                .dropFirst()
                                .filter { $0 == .ready }
                                .first()
                                .sink { [weak self] _ in
                                    alert?.dismiss(animated: true) {
                                        self?.dismiss(animated: true)
                                    }
                                }
                                .store(in: &self.closeCancellables)
                        }
                    ),
                    (
                        title: LS["Continue"],
                        style: .cancel,
                        action: nil
                    )
                ]
            )
            self.present(alert!, animated: true)
            
        } else {
            self.dismiss(animated: true) {
                print("[NewWorkout] dismissed")
            }
        }
    }
    
    override func addMapViewWithConstraints() {
        super.addMapViewWithConstraints()
        self.view.sendSubviewToBack(blurView)
    }
    
    func displayBuilderFailureError() {
        DispatchQueue.main.async {
            self.displayError(withMessage: LS["NewWorkoutViewController.WorkoutBuilder.Error"]
            )
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @objc func userInteractedWithMap(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .ended {
            self.userMovedMap = true
        }
    }
    
    // MARK: - Init
    
    public init() {
        let builder = WorkoutBuilder()
        self.builder = builder
        self.autoPauseDetection = AutoPauseDetection(builder: builder)
        self.locationManagement = LocationManagement(builder: builder)
        self.stepCounter = StepCounter(builder: builder)
        self.altitudeManagement = AltitudeManagement(builder: builder)
        self.liveStats = LiveStats(builder: builder)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        let builder = WorkoutBuilder()
        self.builder = builder
        self.autoPauseDetection = AutoPauseDetection(builder: builder)
        self.locationManagement = LocationManagement(builder: builder)
        self.stepCounter = StepCounter(builder: builder)
        self.altitudeManagement = AltitudeManagement(builder: builder)
        self.liveStats = LiveStats(builder: builder)
        super.init(coder: coder)
    }
    
    // MARK: - Layout
    
    private func prepareLayout() {
        self.view.backgroundColor = .clear
        
        // MARK: adding views to superview
        self.view.addSubview(readinessIndicatorView)
        self.view.addSubview(typeView)
        self.view.addSubview(recenterButton)
        
        // MARK: adding views to statsView
        self.containerView.addSubview(distanceView)
        self.containerView.addSubview(durationView)
        self.containerView.addSubview(speedIndication)
        self.containerView.addSubview(caloriesView)
        self.containerView.addSubview(actionButton)
        
        // MARK: setting constraints
        let safeLayout = self.view.safeAreaLayoutGuide
        readinessIndicatorView.snp.makeConstraints { (make) in
            make.bottom.equalTo(containerView.snp.top).offset(-10)
            make.right.equalTo(safeLayout).offset(-10)
        }
        typeView.snp.makeConstraints { (make) in
            make.bottom.equalTo(containerView.snp.top).offset(-10)
            make.left.equalTo(safeLayout).offset(10)
        }
        recenterButton.snp.makeConstraints { (make) in
            make.bottom.equalTo(readinessIndicatorView.snp.top).offset(-10)
            make.right.equalTo(safeLayout).offset(-10)
        }
        
        let spacing: CGFloat = 20
        
        distanceView.snp.makeConstraints { (make) in
            make.top.equalTo(containerView.snp.top).offset(spacing)
            make.left.equalTo(containerView.snp.left).offset(spacing)
        }
        durationView.snp.makeConstraints { (make) in
            make.top.equalTo(containerView.snp.top).offset(spacing)
            make.left.equalTo(distanceView.snp.right).offset(spacing)
            make.right.equalTo(containerView.snp.right).offset(-spacing)
            make.width.equalTo(distanceView)
        }
        speedIndication.snp.makeConstraints { (make) in
            make.top.equalTo(distanceView.snp.bottom).offset(spacing)
            make.left.equalTo(containerView.snp.left).offset(spacing)
        }
        caloriesView.snp.makeConstraints { (make) in
            make.top.equalTo(durationView.snp.bottom).offset(spacing)
            make.left.equalTo(speedIndication.snp.right).offset(spacing)
            make.right.equalTo(containerView.snp.right).offset(-spacing)
            make.width.equalTo(speedIndication)
        }
        actionButton.snp.makeConstraints { (make) in
            make.top.equalTo(speedIndication.snp.bottom).offset(spacing)
            make.left.equalTo(containerView.snp.left).offset(spacing)
            make.right.equalTo(containerView.snp.right).offset(-spacing)
            make.bottom.equalTo(safeLayout).offset(-spacing)
            make.height.equalTo(50)
        }
    }

    // MARK: - Bindings

    private var cancellables = Set<AnyCancellable>()
    private var closeCancellables = Set<AnyCancellable>()
    private let suggestNewStatusSubject = PassthroughSubject<WorkoutBuilder.Status, Never>()
    private lazy var workoutTypeSubject = CurrentValueSubject<Workout.WorkoutType, Never>(initialWorkoutType)
    private let statusSubject = CurrentValueSubject<WorkoutBuilder.Status, Never>(.waiting)

    private func prepareBindings() {

        // The live stats are emitted on a background queue, so hop to main before touching UIKit.
        liveStats.distance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.distanceView.value = $0 }
            .store(in: &cancellables)
        liveStats.duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.durationView.value = $0 }
            .store(in: &cancellables)
        liveStats.speed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speedIndication.value = $0 }
            .store(in: &cancellables)
        liveStats.burnedEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.caloriesView.value = $0 }
            .store(in: &cancellables)
        liveStats.status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.apply(status: status)
                self?.statusSubject.send(status)
            }
            .store(in: &cancellables)
        liveStats.currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateCamera(with: $0) }
            .store(in: &cancellables)
        liveStats.locations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateRoute(with: $0) }
            .store(in: &cancellables)
        liveStats.insufficientPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleInsufficientPermission($0) }
            .store(in: &cancellables)

        // Feed the user-driven inputs (chosen workout type + status suggestions) into the builder.
        let input = WorkoutBuilder.Input(
            workoutType: workoutTypeSubject.eraseToAnyPublisher(),
            statusSuggestion: suggestNewStatusSubject.eraseToAnyPublisher()
        )
        _ = builder.tranform(input)
    }

    private func apply(status: WorkoutBuilder.Status) {
        readinessIndicatorView.status = status
        actionButton.transition(to: status)
        isModalInPresentation = status.isActiveStatus
    }

    private func updateCamera(with sample: TempWorkoutRouteDataSample?) {
        guard let location = sample?.clLocation else { return }
        if userMovedMap {
            lastLocationWhileNotCentered = location
        } else {
            let camera = MKMapCamera(lookingAtCenter: location.coordinate, fromDistance: 200, pitch: 0, heading: location.course)
            mapView?.setCamera(camera, animated: true)
        }
    }

    private func updateRoute(with routeSamples: [TempWorkoutRouteDataSample]) {
        let coordinates = routeSamples.map { $0.clLocationCoordinate2D }
        let newOverlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView?.addOverlay(newOverlay, level: .aboveRoads)
        if let oldOverlay = routeOverlay {
            mapView?.removeOverlay(oldOverlay)
        }
        routeOverlay = newOverlay
    }

    private func handleInsufficientPermission(_ message: String) {
        displayOpenSettingsAlert(withTitle: LS["Error"], message: message)
    }
}
