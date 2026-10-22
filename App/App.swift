import UIKit
import QuartzCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = TouchTimingWindow(windowScene: scene)
        window.rootViewController = ProcessInfo.processInfo.arguments.contains("--visual-test")
            ? TestController() : TouchOnlyController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

struct TouchSample: Codable {
    let sequence: UInt64
    let phase: String
    let touchUptimeSeconds: Double
    let handlerUptimeSeconds: Double
    let x: Double
    let y: Double
    let white: Bool
}

struct SessionExport: Codable {
    let version: Int
    let session: String
    let mode: String
    let createdAt: String
    let device: String
    let systemVersion: String
    let screenMaximumFPS: Int
    let clockNote: String
    let droppedSamples: Int
    let samples: [TouchSample]
}

// The response is driven by touch DOWN, without waiting for a tap recognizer,
// release, timer, network round-trip, or display-link callback.
final class ResponseView: UIView {
    enum Mode: Int { case tap, hold, move }
    var mode: Mode = .tap
    var changed: (() -> Void)?
    var touchReceived: ((String, UInt64, Double, Bool, String) -> Void)?
    var sessionReset: ((String, String) -> Void)?
    private(set) var sequence: UInt64 = 0
    private(set) var white = false
    private(set) var samples: [TouchSample] = []
    private(set) var droppedSamples = 0
    private(set) var session = UUID().uuidString
    private(set) var createdAt = ISO8601DateFormatter().string(from: Date())
    private var activeTouches = Set<UITouch>()
    private let marker = CALayer()
    private let bits = (0..<16).map { _ in CALayer() }
    private let start = CALayer()
    private let end = CALayer()
    private let position = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        layer.borderColor = UIColor.systemTeal.cgColor
        layer.borderWidth = 2
        layer.addSublayer(marker)
        marker.addSublayer(start)
        bits.forEach { marker.addSublayer($0) }
        marker.addSublayer(end)
        start.backgroundColor = UIColor.white.cgColor
        end.backgroundColor = UIColor.black.cgColor
        position.backgroundColor = UIColor.systemRed.cgColor
        position.cornerRadius = 12
        position.isHidden = true
        layer.addSublayer(position)
        updateVisual()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = max(1, bounds.width / 20)
        marker.frame = CGRect(x: width, y: 12, width: width * 18, height: 32)
        start.frame = CGRect(x: 0, y: 0, width: width, height: 32)
        for (i, bit) in bits.enumerated() {
            bit.frame = CGRect(x: CGFloat(i + 1) * width, y: 0, width: width, height: 32)
        }
        end.frame = CGRect(x: 17 * width, y: 0, width: width, height: 32)
        CATransaction.commit()
    }

    private func updateVisual() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = (white ? UIColor.white : UIColor.black).cgColor
        let gray = sequence ^ (sequence >> 1)
        for (i, bit) in bits.enumerated() {
            bit.backgroundColor = ((gray >> i) & 1 == 1 ? UIColor.white : UIColor.black).cgColor
        }
        CATransaction.commit()
    }

    private func record(_ touch: UITouch, phase: String, handlerTime: Double) {
        guard samples.count < 20_000 else { droppedSamples += 1; return }
        let point = touch.location(in: self)
        samples.append(TouchSample(sequence: sequence, phase: phase,
            touchUptimeSeconds: touch.timestamp, handlerUptimeSeconds: handlerTime,
            x: Double(point.x / max(1, bounds.width)),
            y: Double(point.y / max(1, bounds.height)), white: white))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        activeTouches.formUnion(touches)
        sequence &+= 1
        white = mode == .tap ? !white : true
        updateVisual()
        touchReceived?(session, sequence, now, white, ["tap", "hold", "move"][mode.rawValue])
        for touch in touches { record(touch, phase: "down", handlerTime: now) }
        if mode == .move, let touch = touches.first { moveMarker(touch) }
        changed?()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        for touch in touches { record(touch, phase: "move", handlerTime: now) }
        if mode == .move, let touch = touches.first { moveMarker(touch) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, phase: "up")
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, phase: "cancel")
    }
    private func finish(_ touches: Set<UITouch>, phase: String) {
        let now = CACurrentMediaTime()
        activeTouches.subtract(touches)
        if mode != .tap && activeTouches.isEmpty { white = false; updateVisual() }
        for touch in touches { record(touch, phase: phase, handlerTime: now) }
        changed?()
    }
    private func moveMarker(_ touch: UITouch) {
        let point = touch.location(in: self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        position.isHidden = false
        position.frame = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        CATransaction.commit()
    }

    @discardableResult
    func reset() -> Bool {
        guard activeTouches.isEmpty else { return false }
        sequence = 0; white = false; samples.removeAll(keepingCapacity: true)
        droppedSamples = 0; session = UUID().uuidString
        createdAt = ISO8601DateFormatter().string(from: Date())
        position.isHidden = true
        updateVisual(); changed?()
        sessionReset?(session, ["tap", "hold", "move"][mode.rawValue])
        return true
    }
    var isHolding: Bool { !activeTouches.isEmpty }
    func exportData() throws -> Data {
        let result = SessionExport(version: 1, session: session,
            mode: ["tap", "hold", "move"][mode.rawValue], createdAt: createdAt,
            device: UIDevice.current.model, systemVersion: UIDevice.current.systemVersion,
            screenMaximumFPS: window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond,
            clockNote: "iPad monotonic uptime only. Cannot subtract a PC timestamp; no physical display latency is measured here.",
            droppedSamples: droppedSamples, samples: samples)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }
}

final class TestController: UIViewController {
    private let usbTiming = UsbTimingServer()
    private var usbStatus = "USB 计时准备中"
    private let response = ResponseView()
    private let mode = UISegmentedControl(items: ["单次延迟", "按住检测", "移动检测"])
    private let countLabel = UILabel()
    private let hint = UILabel()
    private let exportButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        UIApplication.shared.isIdleTimerDisabled = true
        let title = UILabel()
        title.text = "同屏延迟测试"
        title.font = .boldSystemFont(ofSize: 26)
        title.textColor = .white
        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action: #selector(changeMode), for: .valueChanged)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        countLabel.textColor = .systemTeal
        hint.font = .systemFont(ofSize: 15)
        hint.textColor = .lightGray; hint.numberOfLines = 0
        resetButton.setTitle("重置编号", for: .normal)
        resetButton.addTarget(self, action: #selector(reset), for: .touchUpInside)
        exportButton.setTitle("导出触摸记录", for: .normal)
        exportButton.addTarget(self, action: #selector(export), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [resetButton, exportButton])
        buttons.axis = .horizontal; buttons.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [title, mode, countLabel, response, hint, buttons])
        stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            title.heightAnchor.constraint(equalToConstant: 34),
            mode.heightAnchor.constraint(equalToConstant: 36),
            countLabel.heightAnchor.constraint(equalToConstant: 28),
            buttons.heightAnchor.constraint(equalToConstant: 36)
        ])
        response.changed = { [weak self] in self?.updateStatus() }
        response.touchReceived = { [weak self] session, sequence, time, white, mode in
            self?.usbTiming.touch(session: session, sequence: sequence, handlerTime: time, white: white, mode: mode)
        }
        response.sessionReset = { [weak self] session, mode in self?.usbTiming.reset(session: session, mode: mode) }
        usbTiming.statusChanged = { [weak self] status in self?.usbStatus = status; self?.updateStatus() }
        usbTiming.start(session: response.session, sequence: response.sequence, white: response.white)
        updateStatus()
    }
    private func updateStatus() {
        countLabel.text = "#\(response.sequence) · \(response.isHolding ? "按住中" : "等待按键") · \(usbStatus)"
        countLabel.adjustsFontSizeToFitWidth = true
        resetButton.isEnabled = !response.isHolding
        exportButton.isEnabled = !response.isHolding
        mode.isEnabled = !response.isHolding
        switch response.mode {
        case .tap:
            hint.text = "将一个普通单击映射到大方框中央。每按一次立即切换黑白；松开后保持颜色。间隔约 1 秒，测试 30 次。这里不显示电脑端总延迟。"
        case .hold:
            hint.text = "将按住映射到大方框中央。触摸按下变白，松开变黑；用于核对断触。外部录制或电脑端计时才能测量总延迟。"
        case .move:
            hint.text = "在大方框内拖动：红点跟随触摸位置。用于测试移动及滑动映射；记录只包含平板自身的时间。"
        }
    }
    @objc private func changeMode() {
        guard !response.isHolding else { mode.selectedSegmentIndex = response.mode.rawValue; return }
        response.mode = ResponseView.Mode(rawValue: mode.selectedSegmentIndex) ?? .tap
        response.reset()
    }
    @objc private func reset() { response.reset() }
    @objc private func export() {
        do {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("MirrorLatency-\(response.session).json")
            try response.exportData().write(to: file, options: .atomic)
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = exportButton
            share.popoverPresentationController?.sourceRect = exportButton.bounds
            present(share, animated: true)
        } catch {
            let alert = UIAlertController(title: "导出失败", message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }
}
