import UIKit
import QuartzCore

// Opt-in experiment only. No drawing or synthetic touch callbacks. The static
// control never creates a display link, so its event loop stays unchanged.
private final class FrameCallbackTarget: NSObject {
    weak var probe: FrameCadenceProbe?
    @objc func tick(_ link: CADisplayLink) { probe?.tick(link) }
}

private final class FrameCadenceProbe {
    private var link: CADisplayLink?
    private let target = FrameCallbackTarget()
    private(set) var callbacks = 0
    private var callbackTime: Double?
    private var frameTimestamp: Double?
    private var targetTimestamp: Double?
    var ready: (([String: Any]) -> Void)?

    func start(maximumFPS: Int) {
        guard link == nil else { return }
        target.probe = self
        let displayLink = CADisplayLink(target: target, selector: #selector(FrameCallbackTarget.tick(_:)))
        let fps = Float(max(1, maximumFPS))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        link = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func stop() { link?.invalidate(); link = nil }
    deinit { stop() }

    fileprivate func tick(_ link: CADisplayLink) {
        callbackTime = CACurrentMediaTime()
        frameTimestamp = link.timestamp
        targetTimestamp = link.targetTimestamp
        callbacks += 1
        // Publish startup evidence once, without per-frame telemetry traffic.
        if callbacks == 8 { ready?(details()) }
    }

    func details() -> [String: Any] {
        var values: [String: Any] = ["displayLinkActive": link != nil, "displayLinkCallbackCount": callbacks]
        if let time = callbackTime { values["lastDisplayLinkCallbackTime"] = time }
        if let time = frameTimestamp { values["lastDisplayLinkFrameTimestamp"] = time }
        if let time = targetTimestamp { values["lastDisplayLinkTargetTimestamp"] = time }
        if let start = frameTimestamp, let end = targetTimestamp, end > start {
            values["displayLinkFrameIntervalMs"] = (end - start) * 1000
        }
        return values
    }
}

// Observe the existing event path without changing event dispatch or drawing.
final class TouchTimingWindow: UIWindow {
    private(set) var dispatchTime: Double?
    override func sendEvent(_ event: UIEvent) {
        dispatchTime = CACurrentMediaTime()
        defer { dispatchTime = nil }
        super.sendEvent(event)
    }
}

// A real HID touch must enter UIKit. Network telemetry cannot synthesize a
// touch. The static surface does not draw, animate, or change color per sample.
final class TouchOnlySurface: UIView {
    let session = UUID().uuidString
    private(set) var sequence: UInt64 = 0
    var down: ((String, UInt64, Double, [String: Any]) -> Void)?
    var experimentDetails: (() -> [String: Any])?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let handlerTime = CACurrentMediaTime()
        sequence &+= 1
        var details: [String: Any] = ["touchCount": touches.count, "appVersion": "1.4.0"]
        if let touch = touches.first {
            let point = touch.location(in: self)
            details["touchTimestamp"] = touch.timestamp
            details["touchType"] = touch.type.rawValue
            details["normalizedX"] = Double(point.x / max(1, bounds.width))
            details["normalizedY"] = Double(point.y / max(1, bounds.height))
        }
        if let event = event { details["eventTimestamp"] = event.timestamp }
        if let time = (window as? TouchTimingWindow)?.dispatchTime { details["windowDispatchTime"] = time }
        for (key, value) in experimentDetails?() ?? [:] where details[key] == nil { details[key] = value }
        down?(session, sequence, handlerTime, details)
    }
}

final class TouchOnlyController: UIViewController {
    private let telemetry = UsbTimingServer()
    private let surface = TouchOnlySurface()
    private let frames = FrameCadenceProbe()
    private let activeLoop = ProcessInfo.processInfo.arguments.contains("--touch-display-link")

    private func experimentDetails() -> [String: Any] {
        var values: [String: Any] = ["eventLoopMode": activeLoop ? "display-link" : "static",
            "screenMaximumFPS": (surface.window?.screen ?? UIScreen.main).maximumFramesPerSecond,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
        for (key, value) in frames.details() { values[key] = value }
        return values
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func loadView() { view = surface }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        UIApplication.shared.isIdleTimerDisabled = true
        surface.backgroundColor = UIColor(white: 0.08, alpha: 1)
        surface.isMultipleTouchEnabled = true
        let label = UILabel()
        label.text = "纯触摸延迟测试\n\n由电脑自动发送真实 USB 触摸\n终点：iPad 开始处理 touchesBegan\n\n无需按 F8，无需点击\n测量不包含画面回传、解码或显示\n\n保持本 App 在前台，等待电脑采样"
        label.textColor = .white
        label.font = .systemFont(ofSize: 22)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: surface.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: surface.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
        surface.down = { [weak self] session, sequence, time, details in
            self?.telemetry.touch(session: session, sequence: sequence,
                                  handlerTime: time, white: false, mode: "touch-only", details: details)
        }
        surface.experimentDetails = { [weak self] in self?.experimentDetails() ?? [:] }
        frames.ready = { [weak self] details in self?.telemetry.updateDetails(details) }
        telemetry.start(session: surface.session, sequence: 0, white: false, mode: "touch-only",
                        details: experimentDetails().merging(["appVersion": "1.4.0"]) { first, _ in first })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if activeLoop { frames.start(maximumFPS: (surface.window?.screen ?? UIScreen.main).maximumFramesPerSecond) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        frames.stop()
        super.viewDidDisappear(animated)
    }
}
