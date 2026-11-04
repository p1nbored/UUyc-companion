// 虚拟屏在系统眼里是谁：系统按厂商号、产品号、序列号认屏，同一身份只留一份 ICC 和显示器布局记录。
import Foundation

enum DisplayIdentity {
    /// 这个名字的虚拟屏固定用这两个序列号。两个是因为换分辨率时新屏先上线、旧屏后释放，要短暂并存
    static func serials(for name: String) -> [UInt32] {
        var hash: UInt32 = 2_166_136_261  // FNV-1a：跨进程、跨重启不变（Swift 的 hashValue 每次启动都变）
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let base = hash % 0xFFFF_FFEF + 1
        return [base, base + 1]
    }

    static func candidates(for name: String, inUse: [UInt32]) -> [UInt32] {
        serials(for: name).filter { !inUse.contains($0) }
    }
}
