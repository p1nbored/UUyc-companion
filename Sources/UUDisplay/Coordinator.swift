// 连入/断开 → 选设备配置 → 建屏/还原
// 控制端上报了尺寸就按它的，它是否还连着也看上报（见 ControllerReports）；否则只处理 UU 设备列表里、且填了分辨率的设备，
// 读不到名字或认不出就不调整，交给 UU远程 自己处理
import AppKit

final class Coordinator {
    let monitor = UUMonitor()
    let display = DisplayManager()
    private let store = ConfigStore.shared

    /// 状态变化时通知菜单栏刷新
    var onChange: (() -> Void)?

    private(set) var controllerName: String?
    private var namePoll: Timer?
    private var connectedAt = Date.distantPast
    private var openedUUWindow = false
    private var reportTimer: Timer?
    /// 控制端还在上报：这期间都听它的，读 UU 界面得到的连接状态不算数
    private var lease = ReportLease()

    /// 调试：模拟连入的控制端名称（不读 UU）
    var simulatedName: String?
    /// 连入后等这么久还没有上报，才打开 UU 主窗口读控制端名称
    private static let windowPatience: TimeInterval = 3

    var connected: Bool { monitor.connected || simulatedName != nil || lease.live() }

    func start() {
        display.shouldDisablePhysical = { [weak self] in self?.physicalDisableAllowed ?? false }
        display.recoverIfNeeded()
        monitor.onConnect = { [weak self] in self?.handleConnect() }
        monitor.onDisconnect = { [weak self] in self?.handleDisconnect() }
        monitor.start()
        startReports()
    }

    /// 开始接收控制端的上报（暂停时不接收，控制端看不到文件夹就不会报）
    func startReports() {
        if store.config.paused { ControllerReports.close() } else { ControllerReports.open() }
        reportTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.readReports() }
    }

    private func readReports() {
        guard !store.config.paused else { return }
        if connected { Heartbeat.beat(Heartbeat.sessionURL) }
        if lease.expired() { reportsEnded() }
        // 物理屏可能被别的程序或显示器自己开回来，定期看一眼
        display.kick()
        guard let report = ControllerReports.take() else { return }
        let first = !lease.live()
        lease.renew()
        if first {
            Log.info("控制端开始上报")
            namePoll?.invalidate()
            namePoll = nil
        }
        switch report {
        case let .show(width, height, hz, scale):
            let cfg = ControllerReports.config(width: width, height: height, hz: hz, scale: scale)
            guard !display.matches(cfg) else { return }
            Log.info("控制端上报：\(cfg.sizeLabel)")
            display.create(cfg)
        case .hide:
            guard display.isActive else { return }
            Log.info("控制端上报：不要虚拟屏")
            display.remove()
        }
        onChange?()
    }

    /// 控制端不再上报：它已经走了。如果 UU 表格里还有别的控制端，按它的设置重新来
    private func reportsEnded() {
        Log.info("控制端已不再上报，视为断开")
        display.remove()
        try? FileManager.default.removeItem(at: Heartbeat.sessionURL)
        if monitor.connected, let name = controllerName { resolve(name) }
        onChange?()
    }

    /// 开关打开且私有 API 可用时关闭物理屏；看门狗是可选兜底（快捷键 ⌃⌥⌘9 始终可用）
    var physicalDisableAllowed: Bool {
        store.config.shouldDisablePhysical && PhysicalDisplays.available
    }

    var statusText: String {
        if display.wedged { return "⛔️ 屏幕设置无响应，请重启 Mac" }
        if store.config.paused { return "虚拟屏已暂停：连接时不做调整" }
        guard connected else { return "等待其它设备连接中" }
        let who = controllerName ?? (lease.live() ? ControllerReports.deviceName : "未知设备")
        if let c = display.current, display.isActive {
            let physical = display.physicalOff ? " · 物理屏幕已软关闭" : display.physicalKeptOn ? " · 物理屏被其他程序打开" : ""
            return "\(who) 已连接 · 虚拟屏已匹配 \(c.sizeLabel)\(physical)"
        }
        return "\(who) 已连接 · 虚拟屏没有调整"
    }

    // MARK: - 事件

    func handleConnect() {
        connectedAt = Date()
        controllerName = nil
        openedUUWindow = false
        onChange?()
        guard !store.config.paused, !lease.live() else { return }
        if pollName() { return }
        namePoll?.invalidate()
        namePoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            if self.pollName() { t.invalidate() }
        }
    }

    func handleDisconnect() {
        namePoll?.invalidate()
        namePoll = nil
        controllerName = nil
        defer { onChange?() }
        guard !lease.live() else { return }
        display.remove()
        try? FileManager.default.removeItem(at: Heartbeat.sessionURL)
    }

    /// 返回 true 表示已拿到名称、无需继续轮询
    private func pollName() -> Bool {
        guard connected, !store.config.paused else { return true }
        let elapsed = Date().timeIntervalSince(connectedAt)

        if let name = simulatedName ?? readControllerName() {
            resolve(name)
            return true
        }
        if elapsed >= 30 {
            Log.info("30 秒内未读到控制端名称，停止等待")
            return true
        }
        return false
    }

    private func readControllerName() -> String? {
        guard UUReader.isTrusted else { return nil }
        switch UUReader.readControllers() {
        case .none:
            // 主窗口没开：打开一次 UU 主界面再读。先等一会儿，会上报的控制端不需要它
            if !openedUUWindow, Date().timeIntervalSince(connectedAt) >= Coordinator.windowPatience {
                openedUUWindow = true
                Log.info("UU 主窗口未打开，尝试打开以读取控制端名称")
                UUReader.showMainWindow()
            }
            return nil
        case .some(let names):
            return names.first
        }
    }

    private func resolve(_ name: String) {
        controllerName = name
        Log.info("控制端：\(name)")
        if lease.live() { return }
        let cfg: DeviceConfig?
        if let known = store.device(named: name) {
            cfg = known
        } else if simulatedName != nil {
            // 调试模拟：未配置的名称用固定测试尺寸
            cfg = DeviceConfig(name: name, kind: .tablet, width: 2360, height: 1640)
        } else {
            cfg = nil
            Log.info("「\(name)」不在设备列表里，不调整")
        }
        apply(cfg)
    }

    private func apply(_ cfg: DeviceConfig?) {
        defer { onChange?() }
        guard let cfg, cfg.kind != .computer, cfg.hasSize else {
            if display.isActive { display.remove() }
            Log.info(cfg == nil ? "无可用配置，不切换" : "「\(cfg!.name)」不指定分辨率或还没填写，不切换")
            return
        }
        if display.matches(cfg) { return }
        display.create(cfg)
    }

    // MARK: - 菜单操作

    func setPaused(_ paused: Bool) {
        store.config.paused = paused
        if paused {
            ControllerReports.close()
            namePoll?.invalidate()
            lease.end()
            display.remove()
        } else {
            ControllerReports.open()
            if connected { handleConnect() }
        }
        onChange?()
    }

    /// 配置变更后，若正在被控则按新配置重新应用
    func configChanged() {
        if connected, !store.config.paused {
            if let name = controllerName { resolve(name) } else { handleConnect() }
        }
        onChange?()
    }

    /// 快捷键 ⌃⌥⌘9 / 菜单：立即恢复物理屏
    func restorePhysical() {
        Log.info("手动恢复物理屏")
        display.restorePhysicalNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.onChange?() }
    }

    func setDisablePhysical(_ on: Bool) {
        store.config.disablePhysical = on
        if on { display.disablePhysicalIfNeeded() } else { display.restorePhysicalNow(override: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.onChange?() }
    }

    func shutdown(completion: @escaping () -> Void) {
        ControllerReports.close()
        display.remove(completion: completion)
    }
}
