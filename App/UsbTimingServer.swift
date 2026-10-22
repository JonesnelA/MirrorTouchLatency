import Foundation
import Network
import QuartzCore

// Read-only test telemetry. Bound to loopback, reached through usbmux; no
// Bonjour, LAN listener, input injection, or control commands.
final class UsbTimingServer {
    private let queue = DispatchQueue(label: "MirrorLatency.USBTiming")
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var queued: [UUID: Int] = [:]
    private var state: [String: Any] = [:]
    var statusChanged: ((String) -> Void)?

    func start(session: String, sequence: UInt64, white: Bool, mode: String = "tap") {
        queue.async {
            self.state = ["type": "hello", "version": 2, "session": session,
                          "sequence": sequence, "white": white, "mode": mode]
            do {
                let tcp = NWProtocolTCP.Options()
                tcp.noDelay = true
                let parameters = NWParameters(tls: nil, tcp: tcp)
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 47091)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] status in
                    if case .ready = status { self?.notify("USB 计时待连接") }
                    if case .failed = status { self?.notify("USB 计时不可用") }
                }
                listener.newConnectionHandler = { [weak self] in self?.accept($0) }
                listener.start(queue: self.queue)
            } catch { self.notify("USB 计时不可用") }
        }
    }

    // Caller captured handler time on the main thread before drawing. Enqueue
    // AFTER changing the visual; transport never blocks the touch handler.
    func touch(session: String, sequence: UInt64, handlerTime: Double, white: Bool, mode: String) {
        queue.async {
            self.state = ["type": "hello", "version": 2, "session": session,
                          "sequence": sequence, "white": white, "mode": mode]
            let event: [String: Any] = ["type": "touch", "session": session,
                "sequence": sequence, "handlerTime": handlerTime, "white": white, "mode": mode]
            for id in Array(self.clients.keys) { self.send(event, to: id) }
        }
    }
    func reset(session: String, mode: String) {
        queue.async {
            self.state = ["type": "hello", "version": 2, "session": session,
                          "sequence": UInt64(0), "white": false, "mode": mode]
            for id in Array(self.clients.keys) { self.send(self.state, to: id) }
        }
    }
    private func notify(_ status: String) {
        DispatchQueue.main.async { [weak self] in self?.statusChanged?(status) }
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 2 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection; queued[id] = 0
        connection.stateUpdateHandler = { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .ready:
                self.send(self.state, to: id); self.receive(id, buffer: Data())
                self.notify("USB 计时已连接")
            case .failed, .cancelled: self.remove(id)
            default: break
            }
        }
        connection.start(queue: queue)
    }
    private func remove(_ id: UUID) {
        let connection = clients.removeValue(forKey: id)
        queued.removeValue(forKey: id); connection?.cancel()
        if clients.isEmpty { notify("USB 计时待连接") }
    }
    private func send(_ object: [String: Any], to id: UUID) {
        guard let connection = clients[id], let count = queued[id], count < 32,
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            remove(id); return
        }
        data.append(10); queued[id] = count + 1
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self, let count = self.queued[id] else { return }
            self.queued[id] = count - 1
            if error != nil { self.remove(id) }
        })
    }
    private func receive(_ id: UUID, buffer: Data) {
        guard let connection = clients[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            guard let self = self else { return }
            var pending = buffer
            if let data = data { pending.append(data) }
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                guard line.count <= 4096 else { self.remove(id); return }
                pending.removeSubrange(...newline)
                let received = CACurrentMediaTime()
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   object["type"] as? String == "ping", let number = object["id"] as? Int {
                    self.send(["type": "pong", "id": number,
                        "receivedTime": received, "sendTime": CACurrentMediaTime()], to: id)
                }
            }
            guard pending.count <= 4096, !done, error == nil else { self.remove(id); return }
            self.receive(id, buffer: pending)
        }
    }
}
