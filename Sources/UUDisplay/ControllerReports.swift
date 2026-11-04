// 控制端自己上报要多大的虚拟屏，省去手工填分辨率，折叠屏展开、转屏后也能跟着变。
// 控制端（目前是 OpenUU）和本软件之间没有网络通道，只有 UU 会话本身，而 UU 的文件管理能在这台 Mac 上建文件夹：
// 本软件运行时建好 reports 文件夹，表示「可以上报」；控制端每次上报就在里面建一个文件夹，名字就是内容：
//   <宽>x<高>@<刷新率>s<缩放>.<序号>   例如 3296x2472@120s175.1730000000，缩放是每点多少像素的百分比，可省略
//   off.<序号>                         不要虚拟屏了
// 序号只为让名字不重复。读到后删除；没有这个文件夹的 Mac 上，控制端什么也不做。
// 要虚拟屏期间控制端每隔几秒重复上报一次：最近上报过就算它还连着（见 ReportLease），读 UU 界面判断连接不可靠。
import Foundation

enum ControllerReport: Equatable {
    case show(width: Int, height: Int, hz: Int, scale: Int)
    case hide

    static func parse(_ name: String) -> ControllerReport? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, Int64(parts[1]) != nil else { return nil }
        if parts[0] == "off" { return .hide }
        let sizeAndRate = parts[0].split(separator: "@", omittingEmptySubsequences: false)
        guard sizeAndRate.count == 2 else { return nil }
        let rateAndScale = sizeAndRate[1].split(separator: "s", omittingEmptySubsequences: false)
        guard (1...2).contains(rateAndScale.count), let hz = Int(rateAndScale[0]), hz > 0 else { return nil }
        var scale = DeviceConfig.nativeScale
        if rateAndScale.count == 2 {
            guard let given = Int(rateAndScale[1]), DeviceConfig.validScale.contains(given) else { return nil }
            scale = given
        }
        let size = sizeAndRate[0].split(separator: "x", omittingEmptySubsequences: false)
        guard size.count == 2, let w = Int(size[0]), let h = Int(size[1]),
              DeviceConfig.validSize.contains(w), DeviceConfig.validSize.contains(h) else { return nil }
        return .show(width: w & ~1, height: h & ~1, hz: hz, scale: scale)
    }
}

enum ControllerReports {
    /// 上报来的虚拟屏都叫这个名字：系统按名字生成 ICC 文件名，不把设备名写进系统目录
    static let deviceName = "OpenUU"
    static let root = URL(fileURLWithPath: "/Users/Shared/UUyc companion", isDirectory: true)
    /// 比这更早的报告算上次连接留下的，不再理会
    static let maxAge: TimeInterval = 15
    /// 这么久没收到上报就算控制端走了。控制端每 4 秒报一次，能容忍丢两次
    static let leaseTime: TimeInterval = 12

    static func folder(in root: URL) -> URL { root.appendingPathComponent("reports", isDirectory: true) }

    /// 开始接收：顺手清掉不在运行期间留下的报告
    static func open(root: URL = root) {
        let fm = FileManager.default
        let folder = folder(in: root)
        try? fm.removeItem(at: folder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// 停止接收：控制端看不到文件夹，就知道这边不接收了
    static func close(root: URL = root) {
        try? FileManager.default.removeItem(at: root)
    }

    /// 取走所有报告，返回最新的一条
    static func take(root: URL = root, now: Date = Date()) -> ControllerReport? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.creationDateKey]
        let entries = (try? fm.contentsOfDirectory(at: folder(in: root), includingPropertiesForKeys: keys)) ?? []
        var newest: (created: Date, name: String, report: ControllerReport)?
        for url in entries {
            let name = url.lastPathComponent
            let created = (try? url.resourceValues(forKeys: Set(keys)))?.creationDate ?? .distantPast
            let fresh = now.timeIntervalSince(created) <= maxAge
            guard let report = ControllerReport.parse(name) else {
                // UU 建文件夹分两步：先建「未命名文件夹」再改名，刚建的要等它改名
                if !fresh { try? fm.removeItem(at: url) }
                continue
            }
            try? fm.removeItem(at: url)
            guard fresh else { continue }
            if let n = newest, (n.created, n.name) >= (created, name) { continue }
            newest = (created, name, report)
        }
        return newest?.report
    }

    /// 上报的尺寸对应的设备配置
    static func config(width: Int, height: Int, hz: Int, scale: Int = DeviceConfig.nativeScale) -> DeviceConfig {
        DeviceConfig(name: deviceName, kind: .tablet, width: width, height: height, refreshRate: hz, scalePercent: scale)
    }
}

/// 控制端最近上报过，就算它还连着
struct ReportLease {
    private var until: Date?

    func live(at now: Date = Date()) -> Bool { until.map { $0 > now } ?? false }

    mutating func renew(at now: Date = Date()) { until = now.addingTimeInterval(ControllerReports.leaseTime) }

    mutating func end() { until = nil }

    /// 刚刚到期时返回 true，只一次
    mutating func expired(at now: Date = Date()) -> Bool {
        guard let until, until <= now else { return false }
        self.until = nil
        return true
    }
}
