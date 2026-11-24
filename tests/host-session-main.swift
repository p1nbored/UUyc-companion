import Foundation

// 用 IOPMCopyAssertionsByProcess 实际返回的键名造数据，不依赖本机此刻有没有会话
@main struct HostSessionTests {
    static func main() {
        func assertion(_ process: String, _ type: String, _ name: String, level: Int? = 255) -> [String: Any] {
            var a: [String: Any] = ["Process Name": process, "AssertType": type, "AssertName": name]
            if let level { a["AssertLevel"] = level }
            return a
        }
        let session = assertion("UURemoteServer", "PreventUserIdleDisplaySleep", "UURemote Disable Display Sleep")
        // 没有会话时 UU 也留着的：主程序的「不让系统休眠」，和每次会话建了从不释放的「Wake Up Display」
        let idle: [NSNumber: [[String: Any]]] = [
            1280: [assertion("UURemote", "PreventUserIdleSystemSleep", "UURemote Disable Idle System Sleep")],
            1285: Array(repeating: assertion("UURemoteServer", "UserIsActive", "Wake Up Display"), count: 3),
        ]
        precondition(!UUHostSession.holds(idle), "没有会话时 UU 常驻的断言不能算会话")
        var live = idle
        live[1285, default: []].append(session)
        precondition(UUHostSession.holds(live), "UURemoteServer 的「不让显示器休眠」就是会话")
        precondition(!UUHostSession.holds([:]), "空表不算会话")
        precondition(!UUHostSession.holds([77: [assertion("Safari", "PreventUserIdleDisplaySleep", "Playing video")]]),
                     "别的程序不让显示器休眠，不算 UU 会话")
        precondition(!UUHostSession.holds([1285: [assertion("UURemoteServer", "PreventUserIdleDisplaySleep", "UURemote Disable Display Sleep", level: 0)]]),
                     "已关掉的断言不算")
        precondition(UUHostSession.holds([1285: [assertion("UURemoteServer", "PreventUserIdleDisplaySleep", "UURemote Disable Display Sleep", level: nil)]]),
                     "没有级别字段时按开着算")
        // 真接口能调通即可；结果取决于此刻有没有会话，只打印
        print("PASS: session assertion matched; UU's idle assertions, other apps and released assertions ignored (now: \(UUHostSession.active() ? "in a session" : "no session"))")
    }
}
