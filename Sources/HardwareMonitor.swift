import AppKit
import Combine
import Foundation
import IOKit

struct HardwareReading: Identifiable, Sendable {
    let id: String
    let name: String
    let value: Double
    let unit: String
    let source: String
    var formatted: String {
        String(format: unit == "RPM" || unit == "%" ? "%.0f" : "%.1f", value) + " " + unit
    }
}

struct HardwareSnapshot: Sendable {
    var temperatures: [HardwareReading] = []
    var powers: [HardwareReading] = []
    var fans: [HardwareReading] = []
    var battery: [HardwareReading] = []
    var sampledAt: Date?
    var isFresh: Bool {
        guard let sampledAt else { return false }
        let age = Date().timeIntervalSince(sampledAt)
        return age >= -1 && age <= 10 && !(temperatures + powers + fans + battery).isEmpty
    }
}

// Validation is shared by production sampling and tests. Zero power / stopped fans are valid.
enum HardwareValidation {
    static func temperature(_ value: Double) -> Bool { value.isFinite && value > 0 && value < 130 }
    static func power(_ value: Double) -> Bool { value.isFinite && value >= 0 && value < 1000 }
    static func fan(_ value: Double) -> Bool { value.isFinite && value >= 0 && value < 20000 }
    static func fanCount(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value <= 8, value.rounded() == value else { return nil }
        return Int(value)
    }
    static func battery(_ properties: [String: Any]) -> [HardwareReading] {
        var readings: [HardwareReading] = []
        func add(_ id: String, _ name: String, _ value: Double, _ unit: String) {
            guard value.isFinite else { return }
            readings.append(HardwareReading(id: id, name: name, value: value, unit: unit, source: "系统电池接口"))
        }
        let voltage = (properties["Voltage"] as? NSNumber)?.doubleValue
        let current = (properties["Amperage"] as? NSNumber)?.int64Value
        if let voltage, voltage.isFinite, voltage > 0, voltage < 100000 {
            add("voltage", "电池电压", voltage / 1000, "V")
        }
        // int64Value also preserves the signed interpretation of the macOS registry value.
        if let current, current > -100000, current < 100000 {
            add("current", "电池电流", Double(current) / 1000, "A")
            if let voltage, voltage.isFinite, voltage > 0, voltage < 100000 {
                add("batteryPower", current < 0 ? "电池放电" : "电池充电", abs(Double(current)) * voltage / 1_000_000, "W")
            }
        }
        if let capacity = properties["CurrentCapacity"] as? NSNumber,
           let maximum = properties["MaxCapacity"] as? NSNumber,
           capacity.doubleValue.isFinite, maximum.doubleValue.isFinite,
           maximum.doubleValue > 0, capacity.doubleValue >= 0,
           capacity.doubleValue <= maximum.doubleValue {
            add("charge", "电池电量", capacity.doubleValue / maximum.doubleValue * 100, "%")
        }
        return readings
    }
}

// All SMC lifecycle and IOKit sampling run on this serial queue. Main-thread state stays in HardwareMonitor.
private final class HardwareSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "XiaoKe.hardware.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var callback: (@Sendable (HardwareSnapshot) -> Void)?
    private var started = false
    private var consecutiveSMCFailures = 0
    private let temperatureKeys: [(String, String)] = [
        ("Tp09", "CPU 传感器 1"), ("Tp0T", "CPU 传感器 2"),
        ("Tp01", "CPU 传感器 3"), ("Tp05", "CPU 传感器 4"),
        ("Tp0D", "CPU 传感器 5"), ("Tp0H", "CPU 传感器 6"),
        ("Tp0L", "CPU 传感器 7"), ("Tp0P", "CPU 传感器 8"),
        ("Tp0X", "CPU 传感器 9"), ("Tp0b", "CPU 传感器 10"),
        ("Tg05", "GPU 传感器 1"), ("Tg0D", "GPU 传感器 2"),
        ("Tg0L", "GPU 传感器 3"), ("Tg0T", "GPU 传感器 4"),
        ("TH0x", "SSD / NAND"), ("TB1T", "电池传感器 1"), ("TB2T", "电池传感器 2"),
        ("TW0P", "无线模块"), ("TaLP", "左侧风道"), ("TaRF", "右侧风道")
    ]
    private let powerKeys: [(String, String)] = [
        ("PSTR", "系统总功率"), ("PDTR", "直流输入"), ("PDBR", "显示背光供电"),
        ("PU1R", "左侧雷雳供电"), ("PU2R", "右侧雷雳供电")
    ]

    func start(_ callback: @escaping @Sendable (HardwareSnapshot) -> Void) {
        queue.async { [self] in
            self.callback = callback
            guard !started else { sample(); return }
            started = true
            _ = smc_open()
            let newTimer = DispatchSource.makeTimerSource(queue: queue)
            newTimer.schedule(deadline: .now(), repeating: .seconds(3), leeway: .milliseconds(250))
            newTimer.setEventHandler { [weak self] in self?.sample() }
            timer = newTimer
            newTimer.resume()
        }
    }
    func refresh() { queue.async { [weak self] in guard let self, self.started else { return }; self.sample() } }
    func stop() {
        queue.sync {
            started = false
            callback = nil
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            consecutiveSMCFailures = 0
            smc_close()
        }
    }
    private func read(_ key: String) -> Double? {
        var value = 0.0
        guard key.withCString({ smc_value($0, &value) }) != 0, value.isFinite else { return nil }
        return value
    }
    private func sample() {
        guard started else { return }
        _ = smc_open()
        let temperatures = temperatureKeys.compactMap { key, name -> HardwareReading? in
            guard let value = read(key), HardwareValidation.temperature(value) else { return nil }
            return HardwareReading(id: key, name: name, value: value, unit: "°C", source: "SMC · \(key)")
        }
        let powers = powerKeys.compactMap { key, name -> HardwareReading? in
            guard let value = read(key), HardwareValidation.power(value) else { return nil }
            return HardwareReading(id: key, name: name, value: value, unit: "W", source: "SMC · \(key) · 设备侧遥测")
        }
        var fans: [HardwareReading] = []
        if let rawCount = read("FNum"), let count = HardwareValidation.fanCount(rawCount), count > 0 {
            for index in 0..<count {
                if let value = read("F\(index)Ac"), HardwareValidation.fan(value) {
                    fans.append(HardwareReading(id: "fan\(index)", name: "风扇 \(index + 1)", value: value, unit: "RPM", source: "SMC · 实际转速"))
                }
            }
        }
        let battery = readBattery()
        // A stale connection is closed and reopened on the next pass, without fabricating values.
        if temperatures.isEmpty && powers.isEmpty && fans.isEmpty {
            consecutiveSMCFailures += 1
            if consecutiveSMCFailures >= 2 { smc_close(); consecutiveSMCFailures = 0 }
        } else { consecutiveSMCFailures = 0 }
        let any = !(temperatures + powers + fans + battery).isEmpty
        callback?(HardwareSnapshot(temperatures: temperatures, powers: powers, fans: fans, battery: battery, sampledAt: any ? Date() : nil))
    }
    private func readBattery() -> [HardwareReading] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return [] }
        return HardwareValidation.battery(dictionary)
    }
}

@MainActor
final class HardwareMonitor: ObservableObject {
    @Published private(set) var snapshot = HardwareSnapshot()
    private let sampler = HardwareSampler()
    private var running = false
    private var sleeping = false
    private var generation = 0
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        guard !running else { return }
        running = true
        sleeping = false
        installSleepObservers()
        resumeSampling()
    }
    func stop() {
        guard running else { return }
        running = false
        generation += 1
        sampler.stop()
        snapshot = HardwareSnapshot()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }
    func refresh() { guard running, !sleeping else { return }; sampler.refresh() }

    private func resumeSampling() {
        generation += 1
        let expected = generation
        sampler.start { [weak self] newSnapshot in
            Task { @MainActor [weak self] in
                guard let self, self.running, !self.sleeping, self.generation == expected else { return }
                self.snapshot = newSnapshot
            }
        }
    }
    private func installSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.sleeping = true
                self.generation += 1
                self.sampler.stop()
                self.snapshot = HardwareSnapshot()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.sleeping = false
                self.resumeSampling()
            }
        })
    }
}
