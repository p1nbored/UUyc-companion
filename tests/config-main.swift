import Foundation
@main struct ConfigTests {
 static func decode(_ json: String) -> AppConfig { try! JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)) }
 static func main() {
  // 旧配置文件没有 refreshRate：必须能解码（解码失败 ConfigStore 会退回空配置并在下次保存时覆盖文件）
  let old = decode(#"{"devices":[{"name":"iPad","kind":"tablet","width":2360,"height":1640,"hiDPI":true}],"paused":false}"#)
  precondition(old.devices[0].refreshRate == nil)
  precondition(old.devices[0].hz == 60)
  // 没设置过就不写这个键，保存后的文件和旧版一样
  let saved = String(decoding: try! JSONEncoder().encode(old), as: UTF8.self)
  precondition(!saved.contains("refreshRate"))
  // 能原样读回
  var cfg = old.devices[0]
  cfg.refreshRate = 120
  let again = try! JSONDecoder().decode(DeviceConfig.self, from: JSONEncoder().encode(cfg))
  precondition(again.refreshRate == 120 && again.hz == 120)
  // 手改过的值不进 CGVirtualDisplay
  for bad in [0, -1, 75, 1000] {
   cfg.refreshRate = bad
   precondition(cfg.hz == 60)
  }
  print("PASS: old config loads, unset key not written, round trip, invalid value falls back to 60")
 }
}
