// UU 会话的电源断言：UURemoteServer 每次远控会话开始时创建「UURemote Disable Display Sleep」（PreventUserIdleDisplaySleep），
// 整个会话都持有，会话结束才释放。控制端走后 UU 还会把会话保留约 30 秒，断言也跟着多留这么久。
// 读它不需要任何权限，也不看 UU 的窗口。UU 4.48.1 被控时不再铺覆盖窗口，主窗口平时又关着，
// 只靠这两样，官方客户端（例如 Windows 版 UU远程）的会话根本发现不了。
import Foundation
import IOKit.pwr_mgt

enum UUHostSession {
    static let processName = "UURemoteServer"

    /// UURemoteServer 现在是否持有会话断言
    static func active() -> Bool {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let byProcess = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        return holds(byProcess)
    }

    /// 按进程分组的断言表（IOPMCopyAssertionsByProcess 的结果）里有没有会话断言
    static func holds(_ byProcess: [NSNumber: [[String: Any]]]) -> Bool {
        byProcess.values.contains { $0.contains(where: isSessionAssertion) }
    }

    /// 只认 UURemoteServer 的「不让显示器休眠」。它每次会话还会建一个「Wake Up Display」（UserIsActive），从不释放，不能当信号
    static func isSessionAssertion(_ assertion: [String: Any]) -> Bool {
        (assertion["Process Name"] as? String) == processName
            && (assertion[kIOPMAssertionTypeKey as String] as? String) == (kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
            && ((assertion[kIOPMAssertionLevelKey as String] as? Int).map { $0 != 0 } ?? true)
    }
}
