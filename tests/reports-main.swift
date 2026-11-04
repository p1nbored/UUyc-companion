import Foundation
@main struct ReportTests {
 static func folder(_ root: URL) -> URL { ControllerReports.folder(in: root) }
 static func report(_ root: URL, _ name: String, age: TimeInterval = 0) {
  let url = folder(root).appendingPathComponent(name, isDirectory: true)
  try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  try! FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
 }
 static func left(_ root: URL) -> [String] {
  (try? FileManager.default.contentsOfDirectory(atPath: folder(root).path).sorted()) ?? []
 }
 static func main() {
  // 控制端的写法
  precondition(ControllerReport.parse("3296x2472@120s175.1730000000") == .show(width: 3296, height: 2472, hz: 120, scale: 175))
  precondition(ControllerReport.parse("2472x3296@60.1") == .show(width: 2472, height: 3296, hz: 60, scale: 200))
  precondition(ControllerReport.parse("off.7") == .hide)
  // HiDPI 模式要除以 2，奇数取偶
  precondition(ControllerReport.parse("2473x1609@60.1") == .show(width: 2472, height: 1608, hz: 60, scale: 200))
  // 不是报告的都不算：UU 建文件夹时的临时名字、超范围的尺寸、缺项
  for bad in ["未命名文件夹", "New Folder", "3296x2472@120", "3296x2472.1", "x@.1", "0x0@60.1", "100x2472@60.1",
              "16385x2472@60.1", "3296x2472@0.1", "3296x2472@-1.1", "off", "off.x", "..", "",
              "3296x2472@120s.1", "3296x2472@120s99.1", "3296x2472@120s401.1", "3296x2472@120sx.1", "3296x2472@s175.1", "3296x2472@120s175s2.1"] {
   precondition(ControllerReport.parse(bad) == nil, bad)
  }

  // 上报的配置只用得上可选的刷新率，其余按 60；总是高清
  let cfg = ControllerReports.config(width: 3296, height: 2472, hz: 120)
  precondition(cfg.hasSize && cfg.hiDPI && cfg.hz == 120 && cfg.kind == .tablet)
  precondition(ControllerReports.config(width: 3296, height: 2472, hz: 75).hz == 60)

  // 点数跟着缩放走：2 倍时正好一半，175% 时界面小一些，手工配置的设备仍然是一半
  precondition(ControllerReports.config(width: 3296, height: 2472, hz: 120).points == (1648, 1236))
  precondition(ControllerReports.config(width: 2472, height: 1608, hz: 120, scale: 175).points == (1413, 919))
  precondition(ControllerReports.config(width: 3296, height: 2472, hz: 120, scale: 175).points == (1883, 1413))
  precondition(DeviceConfig(name: "x", kind: .tablet, width: 2360, height: 1640).points == (1180, 820))
  precondition(DeviceConfig(name: "x", kind: .tablet, width: 2360, height: 1640, hiDPI: false).points == (2360, 1640))
  // 配置文件里写坏的缩放不算数
  precondition(DeviceConfig(name: "x", kind: .tablet, width: 2360, height: 1640, scalePercent: 7).points == (1180, 820))
  // 旧配置文件没有这个键也能读
  let old = #"{"name":"x","kind":"tablet","width":2360,"height":1640,"hiDPI":true}"#
  precondition(try! JSONDecoder().decode(DeviceConfig.self, from: Data(old.utf8)).scalePercent == nil)

  // 控制端最近上报过就算还连着；到期只提醒一次；中途续上就不到期
  var lease = ReportLease()
  let t = Date(timeIntervalSince1970: 1000)
  precondition(!lease.live(at: t) && !lease.expired(at: t))
  lease.renew(at: t)
  precondition(lease.live(at: t.addingTimeInterval(ControllerReports.leaseTime - 1)))
  precondition(!lease.expired(at: t.addingTimeInterval(ControllerReports.leaseTime - 1)))
  lease.renew(at: t.addingTimeInterval(4))
  precondition(!lease.expired(at: t.addingTimeInterval(ControllerReports.leaseTime + 1)))
  precondition(lease.expired(at: t.addingTimeInterval(ControllerReports.leaseTime + 5)))
  precondition(!lease.expired(at: t.addingTimeInterval(ControllerReports.leaseTime + 6)))
  precondition(!lease.live(at: t.addingTimeInterval(ControllerReports.leaseTime + 6)))
  lease.renew(at: t)
  lease.end()
  precondition(!lease.live(at: t) && !lease.expired(at: t.addingTimeInterval(100)))

  let root = FileManager.default.temporaryDirectory.appendingPathComponent("uureports-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  // 没开始接收时什么也读不到
  precondition(ControllerReports.take(root: root) == nil)

  // 开始接收：文件夹在，不在运行期间留下的被清掉
  ControllerReports.open(root: root)
  report(root, "1000x1000@60.1")
  ControllerReports.open(root: root)
  precondition(left(root).isEmpty)

  // 读走后删除，下次读不到
  report(root, "3296x2472@120.2")
  precondition(ControllerReports.take(root: root) == .show(width: 3296, height: 2472, hz: 120, scale: 200))
  precondition(left(root).isEmpty)
  precondition(ControllerReports.take(root: root) == nil)

  // 一次来了几条，最新的说了算，其余一并删除
  report(root, "2472x1648@120.3", age: 3)
  report(root, "3296x2472@120.4", age: 2)
  report(root, "off.5", age: 1)
  precondition(ControllerReports.take(root: root) == .hide)
  precondition(left(root).isEmpty)

  // 上次连接留下的不算，也不留着
  report(root, "3296x2472@120.6", age: ControllerReports.maxAge + 5)
  precondition(ControllerReports.take(root: root) == nil)
  precondition(left(root).isEmpty)

  // UU 还没改名的文件夹留给它改名；搁久了的才清
  report(root, "未命名文件夹")
  precondition(ControllerReports.take(root: root) == nil)
  precondition(left(root) == ["未命名文件夹"])
  try! FileManager.default.removeItem(at: folder(root).appendingPathComponent("未命名文件夹"))
  report(root, "untitled", age: ControllerReports.maxAge + 5)
  precondition(ControllerReports.take(root: root) == nil)
  precondition(left(root).isEmpty)

  // 停止接收：整个文件夹没了，控制端就知道这边不接收
  ControllerReports.close(root: root)
  precondition(!FileManager.default.fileExists(atPath: root.path))

  // 同一块虚拟屏的序列号每次都一样，换名字才换；两个候选用来在换分辨率时短暂并存
  let a = DisplayIdentity.serials(for: "UUyc companion · OpenUU")
  precondition(a == DisplayIdentity.serials(for: "UUyc companion · OpenUU"))
  precondition(a.count == 2 && a[0] != a[1] && a.allSatisfy { $0 >= 1 && $0 <= 0xFFFF_FFF0 })
  precondition(a != DisplayIdentity.serials(for: "UUyc companion · iPad Air"))
  // 正在用的序列号不再挑
  precondition(DisplayIdentity.candidates(for: "x", inUse: []) == DisplayIdentity.serials(for: "x"))
  let both = DisplayIdentity.serials(for: "x")
  precondition(DisplayIdentity.candidates(for: "x", inUse: [both[0]]) == [both[1]])
  precondition(DisplayIdentity.candidates(for: "x", inUse: [both[1]]) == [both[0]])
  precondition(DisplayIdentity.candidates(for: "x", inUse: both).isEmpty)

  print("PASS: report names and scale, points, lease, take/open/close, stale reports, stable display serials")
 }
}
