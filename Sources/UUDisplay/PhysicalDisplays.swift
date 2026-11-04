// 远程期间禁用物理屏（CGSConfigureDisplayEnabled 私有 API）及其兜底恢复
// 实测（macOS 27）：
//   - 禁用不受 .forAppOnly 约束，进程退出后不会自动恢复，必须由别的进程重新启用
//   - 被禁用的屏会从 CGGetOnlineDisplayList 中消失，所以禁用前必须先把 ID 写盘
//   - 物理屏全禁用且虚拟屏也移除时，系统会生成一块 1920×1080 占位屏；按 ID 重新启用即可恢复
import CoreGraphics
import Foundation

/// 同步执行一次显示器配置事务。GUI 进程中不可在主线程调用（会与自身重配置通知死锁）
@discardableResult
func applyDisplayConfig(_ body: (CGDisplayConfigRef?) -> Void) -> CGError {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return .failure }
    body(cfg)
    let err = CGCompleteDisplayConfiguration(cfg, .forSession)
    if err != .success { CGCancelDisplayConfiguration(cfg) }
    return err
}

enum PhysicalDisplays {
    private typealias EnableFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private static let setEnabled: EnableFn? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled")
        .map { unsafeBitCast($0, to: EnableFn.self) }

    static var available: Bool { setEnabled != nil }

    /// 已被禁用、待恢复的物理屏记录
    static let markerURL = ConfigStore.dir.appendingPathComponent("disabled-displays.json")

    static var pending: [CGDirectDisplayID]? {
        guard let data = try? Data(contentsOf: markerURL),
              let ids = try? JSONDecoder().decode([CGDirectDisplayID].self, from: data), !ids.isEmpty else { return nil }
        return ids
    }

    /// 先记账再禁用。须在后台队列调用
    static func disable(_ ids: [CGDirectDisplayID]) -> CGError {
        guard let setEnabled, !ids.isEmpty else { return .failure }
        let merged = Array(Set((pending ?? []) + ids))
        guard (try? JSONEncoder().encode(merged).write(to: markerURL, options: .atomic)) != nil else {
            Log.info("❌ 无法写入物理屏记录，放弃禁用")
            return .failure
        }
        return applyDisplayConfig { cfg in ids.forEach { _ = setEnabled(cfg, $0, false) } }
    }

    /// 记录里的屏都已经开着：显示器自己或别的程序把它开回来了
    static var pendingAreOnline: Bool {
        guard let ids = pending else { return false }
        let online = Set(DisplayManager.onlineDisplays())
        return ids.allSatisfy(online.contains)
    }

    static func forget() { try? FileManager.default.removeItem(at: markerURL) }

    /// 按记录重新启用物理屏；成功后删除记录。可在任意进程调用，重复调用无害
    @discardableResult
    static func restore(reason: String) -> Bool {
        guard let ids = pending else { return true }
        // 已经开着的屏再启用会报 1001，只启用真正关着的，否则这条记录永远清不掉
        let online = Set(DisplayManager.onlineDisplays())
        let off = ids.filter { !online.contains($0) }
        guard !off.isEmpty else {
            forget()
            Log.info("物理屏 \(ids) 已经开着（\(reason)）")
            return true
        }
        guard let setEnabled else { return false }
        let err = applyDisplayConfig { cfg in off.forEach { _ = setEnabled(cfg, $0, true) } }
        if err == .success {
            forget()
            Log.info("✅ 已恢复物理屏 \(off)（\(reason)）")
            return true
        }
        Log.info("⚠️ 恢复物理屏失败 CGError=\(err.rawValue)（\(reason)），稍后重试")
        return false
    }
}
