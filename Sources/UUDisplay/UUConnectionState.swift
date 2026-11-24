import Foundation

/// 合并 UU 自己给出的会话信号与 UU 被控设备表格，保留切屏期间的断开防抖。
struct UUConnectionState {
    enum Event: Equatable { case connected, controllerChanged, disconnected }
    private(set) var connected = false
    private var lastSeen = Date.distantPast
    private var controller: String?
    private let debounce: TimeInterval = 1.5

    /// host：不需要权限的会话信号（UU 会话的电源断言或覆盖窗口）；controllers：表格里的控制端，主窗口没开时为 nil
    mutating func update(host: Bool, controllers: [String]?, now: Date) -> Event? {
        let name = controllers?.first
        if host || name != nil {
            lastSeen = now
            if !connected {
                connected = true
                controller = name
                return .connected
            }
            if let name, name != controller {
                controller = name
                return .controllerChanged
            }
        } else if connected, now.timeIntervalSince(lastSeen) > debounce {
            connected = false
            controller = nil
            return .disconnected
        }
        return nil
    }
}
