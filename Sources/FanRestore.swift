//
//  FanRestore.swift
//  重启后自动恢复风扇曲线
//
//  为什么需要：
//    曲线写的是 EC 的 AFW1..4 寄存器，掉电即丢，冷启动后 EC 回出厂曲线。
//    AFWBackC/G 只是开机扫描的预设槽位快照，救不回来。
//    要跨重启保活，只能开机时由 root 再写一次。
//
//  做法：
//    登入前由 root 的 LaunchDaemon `dev.dhelper.fanrestore` 执行
//      D-helper fan restore
//    它读 /var/db/dhelper/fan-state.json（上次成功下发的**实际曲线**）重写 EC。
//
//  为什么不存档位名：
//    root 进程读不到用户偏好域，按名字回查预设可能拿不到或拿错；
//    直接存温度/占空数组，恢复过程完全不依赖机型判定和曲线文件。
//
//  命名空间全部用本应用自己的：state 在 /var/db/dhelper，label 是 dev.dhelper.fanrestore。
//

import Foundation

// MARK: - 状态

struct FanApplyState: Codable {
    /// "preset"
    var mode: String
    /// 展示用名称，如「性能」
    var label: String
    var cpu: FanCurve
    var gpu: FanCurve
    var time: Date
}

enum FanStateStore {
    /// root 写、所有人可读：GUI / CLI 要显示，守护进程要读来重放
    static let directory = "/var/db/dhelper"
    static let path = "/var/db/dhelper/fan-state.json"

    static func save(_ state: FanApplyState) -> Bool {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: directory) {
                try fm.createDirectory(atPath: directory,
                                       withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o755])
            }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(state).write(to: URL(fileURLWithPath: path), options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }

    static func load() -> FanApplyState? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let s = try? dec.decode(FanApplyState.self, from: data) else { return nil }
        // 防御：点数不对就别往 EC 里写
        guard s.cpu.temp.count == s.cpu.duty.count, s.cpu.temp.count >= 2,
              s.gpu.temp.count == s.gpu.duty.count, s.gpu.temp.count >= 2 else { return nil }
        return s
    }
}

// MARK: - 守护进程

enum FanAutoRestore {
    static let label = "dev.dhelper.fanrestore"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let logPath = "/var/log/dhelper-fanrestore.log"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// plist 里登记的可执行文件路径
    static var installedExecutable: String? {
        guard let dict = NSDictionary(contentsOfFile: plistPath),
              let args = dict["ProgramArguments"] as? [String],
              let first = args.first else { return nil }
        return first
    }

    /// 装/卸都需要 root
    static func install(executable: String) throws {
        let escaped = executable
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(escaped)</string>
                <string>fan</string>
                <string>restore</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>ThrottleInterval</key>
            <integer>10</integer>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                               ofItemAtPath: plistPath)
        _ = launchctl(["bootout", "system/\(label)"])   // 可能不存在，忽略
        let status = launchctl(["bootstrap", "system", plistPath])
        if status != 0 {
            throw NSError(domain: "DHelperFanRestore", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "launchctl bootstrap 失败（\(status)）"
            ])
        }
    }

    static func uninstall() {
        _ = launchctl(["bootout", "system/\(label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: 重放

    /// kext 加载是异步的：开机时守护进程可能比 SMCAsusFan 先起来，轮询等一会儿
    static func waitForKext(timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let ctrl = FanController()
        while Date() < deadline {
            if ctrl.isKextLoaded { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return ctrl.isKextLoaded
    }

    static func restoreNow() -> (ok: Bool, message: String) {
        guard let state = FanStateStore.load() else {
            return (false, "没有可恢复的曲线记录（先下发一次档位）")
        }
        guard waitForKext() else {
            return (false, "SMCAsusFan.kext 未加载（AFMd 不存在），跳过恢复")
        }
        let ctrl = FanController()
        let before = ctrl.rpms()
        do {
            try ctrl.apply(state.cpu, fan: .cpu)
            // kext 处理 AFWg 是异步的，两只风扇连着写要留间隙
            Thread.sleep(forTimeInterval: 0.25)
            try ctrl.apply(state.gpu, fan: .gpu)
            Thread.sleep(forTimeInterval: 1.0)
            let after = ctrl.rpms()
            return (true, "已恢复「\(state.label)」\nCPU \(before.cpu)→\(after.cpu) RPM / GPU \(before.gpu)→\(after.gpu) RPM")
        } catch {
            return (false, "恢复失败：\(error.localizedDescription)")
        }
    }
}
