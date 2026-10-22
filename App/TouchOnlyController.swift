import UIKit
import QuartzCore

// A real HID touch must enter UIKit. Network telemetry cannot synthesize a
// touch. The static surface does not draw, animate, or change color per sample.
final class TouchOnlySurface: UIView {
    let session = UUID().uuidString
    private(set) var sequence: UInt64 = 0
    var down: ((String, UInt64, Double) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let handlerTime = CACurrentMediaTime()
        sequence &+= 1
        down?(session, sequence, handlerTime)
    }
}

final class TouchOnlyController: UIViewController {
    private let telemetry = UsbTimingServer()
    private let surface = TouchOnlySurface()

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
        surface.down = { [weak self] session, sequence, time in
            self?.telemetry.touch(session: session, sequence: sequence,
                                  handlerTime: time, white: false, mode: "touch-only")
        }
        telemetry.start(session: surface.session, sequence: 0, white: false, mode: "touch-only")
    }
}
