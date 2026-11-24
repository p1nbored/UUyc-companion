import Foundation

// 不访问真实 UU 或显示器，只替代 monitor 默认依赖。
enum UUReader {
    static var isTrusted: Bool { false }
    static func readControllers() -> [String]? { nil }
}
enum Log { static func info(_ message: String) {} }

@main struct MonitorTests {
    static func main() {
        let lock = NSLock()
        var reads = 0
        var overlay = true
        var connects = 0
        var disconnects = 0
        var pulses = 0
        let monitor = UUMonitor(trusted: { true }, readControllers: {
            lock.lock(); reads += 1; lock.unlock()
            Thread.sleep(forTimeInterval: 3)
            return ["stale controller"]
        }, hasOverlay: { overlay }, hostSession: { false })
        monitor.onConnect = { connects += 1 }
        monitor.onDisconnect = { disconnects += 1 }
        monitor.start()
        let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in pulses += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        precondition(connects == 1, "覆盖窗口检测不能等待 AX 返回")
        overlay = false
        RunLoop.main.run(until: Date().addingTimeInterval(1.9))
        precondition(disconnects == 1, "AX 阻塞时仍应按覆盖窗口缺席触发断开")
        lock.lock(); let count = reads; lock.unlock()
        precondition(count == 1, "AX 读取不能堆积或并发")
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        precondition(connects == 1, "过期的 AX 结果不能重新触发连接")
        precondition(pulses >= 30, "AX 读取不能阻塞主线程")
        heartbeat.invalidate()

        // 没有覆盖窗口、主窗口关着、也没有辅助功能权限：只凭 UU 会话的电源断言判断连入和断开
        var held = false
        var heldConnects = 0
        var heldDisconnects = 0
        let quiet = UUMonitor(trusted: { false }, readControllers: { nil }, hasOverlay: { false }, hostSession: { held })
        quiet.onConnect = { heldConnects += 1 }
        quiet.onDisconnect = { heldDisconnects += 1 }
        quiet.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        precondition(heldConnects == 0, "没有任何信号时不能算连入")
        held = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        precondition(heldConnects == 1 && quiet.connected, "会话断言应单独确认连入")
        held = false
        // 最后一次看到断言距今不超过 0.5 秒，防抖 1.5 秒：0.9 秒时一定还连着，2.4 秒时一定已断开
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        precondition(heldDisconnects == 0 && quiet.connected, "断言刚消失时仍要防抖")
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        precondition(heldDisconnects == 1 && !quiet.connected, "会话断言释放后应断开")
        precondition(heldConnects == 1, "断开前不能重复连入")
        print("PASS: blocked AX keeps main thread responsive; no overlapping reads; overlay disconnect; stale result rejected; session assertion alone connects and disconnects")
    }
}
