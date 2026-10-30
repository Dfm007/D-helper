//
//  AMDProcessor.swift
//  AMDRyzenCPUPowerManagement 用户客户端读取（selector 4，免 root）
//
//  返回数组布局：
//    scalarOutput[0] = 物理核心数
//    float[0] = 封装功耗 W
//    float[1] = 封装温度 °C
//    float[2] = 当前 P-State
//    float[3...] = 各物理核心的有效频率 MHz
//
//  注意：这段布局属于第三方 kext 的私有接口，换 kext 版本后要重新核对。
//

import Foundation
import IOKit

struct AMDProcessorMetrics {
    let powerWatts: Double?
    let packageTemperatureC: Double?
    let pstate: Int
    let coreFrequenciesMHz: [Double]

    /// 有效核心频率（过滤掉 0 和异常值，避免低频核把均值拉塌）
    private var validFrequencies: [Double] {
        coreFrequenciesMHz.filter { $0.isFinite && $0 >= 100 && $0 <= 10_000 }
    }

    var averageFrequencyMHz: Double? {
        let valid = validFrequencies
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    var maxFrequencyMHz: Double? { validFrequencies.max() }
    var minFrequencyMHz: Double? { validFrequencies.min() }
    var coreCount: Int { validFrequencies.count }
}

/// 连接会复用；驱动重载或读取失败时自动重连一次。
final class AMDProcessorClient {
    static let shared = AMDProcessorClient()

    private let lock = NSLock()
    private var connection: io_connect_t = 0

    private init() {}

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func sample() -> AMDProcessorMetrics? {
        lock.lock()
        defer { lock.unlock() }

        if connection == 0, !openConnection() { return nil }
        if let metrics = readMetrics() { return metrics }

        // kext 重载后旧连接会失效；关掉重连一次
        closeConnection()
        guard openConnection() else { return nil }
        return readMetrics()
    }

    private func openConnection() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AMDRyzenCPUPowerManagement")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var newConnection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &newConnection) == KERN_SUCCESS else {
            return false
        }
        connection = newConnection
        return true
    }

    private func closeConnection() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    private func readMetrics() -> AMDProcessorMetrics? {
        var coreCount: UInt64 = 0
        var scalarCount: UInt32 = 1
        var values = [Float](repeating: 0, count: 67)
        var valueBytes = values.count * MemoryLayout<Float>.size

        let result = IOConnectCallMethod(
            connection, 4,
            nil, 0, nil, 0,
            &coreCount, &scalarCount,
            &values, &valueBytes
        )
        guard result == KERN_SUCCESS, scalarCount == 1,
              coreCount >= 1, coreCount <= 64,
              valueBytes >= Int(coreCount + 3) * MemoryLayout<Float>.size else {
            return nil
        }

        let count = Int(coreCount)
        let frequencies = values[3..<(3 + count)].map(Double.init)
        let power = Double(values[0])
        let temperature = Double(values[1])
        let pstate = Int(values[2])

        return AMDProcessorMetrics(
            powerWatts: power.isFinite && power >= 0 && power < 1_000 ? power : nil,
            packageTemperatureC: temperature.isFinite && temperature > 0 && temperature < 150
                ? temperature : nil,
            pstate: pstate,
            coreFrequenciesMHz: frequencies
        )
    }
}
