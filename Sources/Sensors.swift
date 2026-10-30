//
//  Sensors.swift
//  只读采样：CPU 温度、GPU 温度、双风扇转速、kext 是否就绪
//
//  数据来源：
//    CPU 温度  AppleSMC · TC0P（sp78，大端 16 位 / 256）
//    GPU 温度  IOAccelerator → PerformanceStatistics → Temperature(C)
//    风扇转速  AppleSMC · F0Ac / F1Ac（fpe2 → RPM）
//    kext 就绪 AppleSMC · AFMd 是否存在
//

import Foundation
import IOKit

enum Sensors {

    // MARK: CPU

    /// TC0P 是 sp78：有符号 16 位大端定点数，小数 8 位
    static func cpuTemp() -> Double? {
        guard let bytes = try? SMCClient.shared.read("TC0P"), bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        let value = Double(raw) / 256.0
        // 明显不合理就丢掉，别让界面上出现 -1°C 这种东西
        return value > 0 && value < 130 ? value : nil
    }

    // MARK: GPU

    /// NVIDIA NullMoth 实测在 PerformanceStatistics 里提供 `Temperature(C)`
    static func gpuTemp() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let raw = props?.takeRetainedValue(),
               let dict = raw as? [String: Any] {
                let stats = dict["PerformanceStatistics"] as? [String: Any]
                if let t = stats.flatMap(temperature(in:)) ?? temperature(in: dict) {
                    IOObjectRelease(entry)
                    return t
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return nil
    }

    private static func temperature(in dict: [String: Any]) -> Double? {
        for (key, value) in dict {
            let lk = key.lowercased()
            guard lk.contains("temperature") || lk == "temp" else { continue }
            guard !lk.contains("fahrenheit") && !lk.contains("(f)") else { continue }
            let v: Double?
            if let d = value as? Double { v = d }
            else if let i = value as? Int { v = Double(i) }
            else if let n = value as? NSNumber { v = n.doubleValue }
            else { continue }
            guard let v, v.isFinite, v > 0, v < 150 else { continue }
            return v
        }
        return nil
    }

    // MARK: 风扇

    static func rpms() -> (cpu: Int, gpu: Int) {
        let c = (try? SMCClient.shared.readRPM("F0Ac")) ?? 0
        let g = (try? SMCClient.shared.readRPM("F1Ac")) ?? 0
        return (c, g)
    }

    /// 用 AFMd 是否存在判断 SMCAsusFan 是否加载（比匹配类名可靠）
    static var kextLoaded: Bool {
        (try? SMCClient.shared.keyInfo("AFMd")) != nil
    }
}
