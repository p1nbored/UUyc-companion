// 设备类型与配置持久化
import Foundation

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case computer, tablet, phone
    var id: String { rawValue }
    var label: String {
        switch self {
        case .computer: return "电脑"
        case .tablet: return "平板"
        case .phone: return "手机"
        }
    }
}

enum Presets {
    /// 首次配置时的类型预填：UU「电脑」组 → 电脑；名称含 iPad/Pad → 平板；其余 → 手机
    static func guessKind(name: String, isComputerGroup: Bool) -> DeviceKind {
        if isComputerGroup { return .computer }
        return name.lowercased().contains("pad") ? .tablet : .phone
    }
}

struct DeviceConfig: Codable, Identifiable, Hashable {
    var name: String
    var kind: DeviceKind
    /// 横屏原生像素，由用户自己填写；0 表示还没填
    var width: Int
    var height: Int
    var hiDPI: Bool = true
    /// 虚拟屏刷新率；可选类型以兼容旧配置文件（缺这个键时整个配置文件都解码不了），用 hz 取值
    var refreshRate: Int?
    /// 从 UU「全部设备」导入时记下的分组与系统类型（用于按 UU 的样子分组、显示图标）
    var uuComputer: Bool?
    var platform: String?
    var id: String { name }
    var inComputerGroup: Bool { uuComputer ?? (kind == .computer) }

    /// 填了合理的分辨率才建虚拟屏
    var hasSize: Bool { DeviceConfig.validSize.contains(width) && DeviceConfig.validSize.contains(height) }
    static let validSize = 320...16384

    /// 没设置过，或配置文件里的值不在可选档位内时按 60
    var hz: Int { refreshRate.flatMap { DeviceConfig.refreshRates.contains($0) ? $0 : nil } ?? 60 }
    static let refreshRates = [60, 90, 120, 144]

    var sizeLabel: String { "\(width)×\(height)\(hiDPI ? " 高清" : "") \(hz)Hz" }

    static func make(name: String, kind: DeviceKind) -> DeviceConfig {
        DeviceConfig(name: name, kind: kind, width: 0, height: 0)
    }
}

struct AppConfig: Codable {
    var devices: [DeviceConfig] = []
    var paused = false
    /// 远程时关闭物理屏（缺省关闭，在设置里开启；可选类型以兼容旧配置文件）
    var disablePhysical: Bool?
    var shouldDisablePhysical: Bool { disablePhysical ?? false }
    /// 看门狗（兜底恢复物理屏）缺省关闭，只有用户在设置里开启才安装
    var watchdogEnabled: Bool?
    var shouldRunWatchdog: Bool { watchdogEnabled ?? false }
    /// 是否已看过首次启动功能导览
    var tourShown: Bool?
}

final class ConfigStore {
    static let shared = ConfigStore()

    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UUDisplay", isDirectory: true)
    private let url = ConfigStore.dir.appendingPathComponent("config.json")

    var config: AppConfig {
        didSet { save() }
    }

    var isConfigured: Bool { !config.devices.isEmpty }

    private init() {
        try? FileManager.default.createDirectory(at: ConfigStore.dir, withIntermediateDirectories: true)
        config = (try? JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))) ?? AppConfig()
    }

    func device(named name: String?) -> DeviceConfig? {
        guard let name else { return nil }
        return config.devices.first { $0.name == name }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(config).write(to: url, options: .atomic)
    }
}
