import AppKit
import Foundation

@main
struct HardwareTests {
    @MainActor static func main() async {
        func decode(_ type: String, _ bytes: [UInt8]) -> Double? {
            var value = 0.0
            let valid = type.withCString { typePointer in bytes.withUnsafeBufferPointer { buffer in
                smc_decode_value(typePointer, buffer.baseAddress, buffer.count, &value)
            } }
            return valid != 0 ? value : nil
        }
        precondition(decode("sp78", [0x32, 0x80]) == 50.5)
        precondition(decode("sp78", [0xff, 0x00]) == -1)
        precondition(decode("fpe2", [0x1f, 0x40]) == 2000)
        precondition(decode("ui16", [0x01, 0x00]) == 256)
        precondition(decode("ui32", [0x00, 0x01, 0x00, 0x00]) == 65536)
        precondition(decode("flt ", [0x00, 0x00, 0x80, 0x3f]) == 1)
        precondition(decode("flt ", [0x00, 0x00, 0xc0, 0x7f]) == nil)
        precondition(decode("flt ", [0x00]) == nil)
        precondition(decode("bad!", [0, 0, 0, 0]) == nil)
        precondition(HardwareValidation.power(0) && HardwareValidation.fan(0))
        precondition(!HardwareValidation.power(-1) && !HardwareValidation.power(.nan))
        precondition(!HardwareValidation.temperature(0) && !HardwareValidation.temperature(130))
        precondition(HardwareValidation.fanCount(2) == 2 && HardwareValidation.fanCount(2.5) == nil)
        precondition(HardwareValidation.battery([:]).isEmpty)
        let battery = HardwareValidation.battery(["Voltage": NSNumber(value: 12000), "Amperage": NSNumber(value: -1000), "CurrentCapacity": NSNumber(value: 50), "MaxCapacity": NSNumber(value: 100)])
        precondition(battery.count == 4 && battery.first(where: { $0.id == "batteryPower" })?.value == 12)
        precondition(battery.first(where: { $0.id == "batteryPower" })?.name == "电池放电")
        precondition(HardwareValidation.battery(["CurrentCapacity": NSNumber(value: 101), "MaxCapacity": NSNumber(value: 100)]).isEmpty)
        precondition(!HardwareSnapshot().isFresh)
        let reading = HardwareReading(id: "PSTR", name: "系统总功率", value: 0, unit: "W", source: "test")
        precondition(HardwareSnapshot(powers: [reading], sampledAt: Date()).isFresh)
        precondition(!HardwareSnapshot(powers: [reading], sampledAt: Date(timeIntervalSinceNow: -15)).isFresh)
        print("PASS: SMC numeric formats, malformed lengths, invalid values, valid zero power, battery units, staleness")
        if CommandLine.arguments.contains("--hardware-test") {
            let monitor = HardwareMonitor()
            monitor.start()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let first = monitor.snapshot
            for reading in first.temperatures + first.powers + first.fans + first.battery {
                print("\(reading.name): \(reading.formatted) [\(reading.source)]")
            }
            print("LIVE: temperatures=\(first.temperatures.count), powers=\(first.powers.count), fans=\(first.fans.count), battery=\(first.battery.count), fresh=\(first.isFresh)")
            monitor.stop()
            precondition(monitor.snapshot.sampledAt == nil)
            // Simulate the NSWorkspace notifications; this does not put the actual Mac to sleep.
            monitor.start()
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            try? await Task.sleep(nanoseconds: 200_000_000)
            precondition(!monitor.snapshot.isFresh)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let resumed = monitor.snapshot
            monitor.stop()
            print("LIFECYCLE: stop/restart, synthetic sleep invalidation, synthetic wake resampling; resumed fresh=\(resumed.isFresh)")
            precondition(first.isFresh, "No live readable hardware metrics: cannot report real-device test passed.")
            precondition(resumed.isFresh)
            if CommandLine.arguments.contains("--require-smc") {
                precondition(!first.temperatures.isEmpty && !first.powers.isEmpty, "SMC telemetry not readable in this execution context.")
                precondition(!resumed.temperatures.isEmpty && !resumed.powers.isEmpty)
            }
            // An old queued sample must not repopulate state after stop().
            for _ in 0..<20 {
                monitor.start()
                monitor.refresh()
                monitor.stop()
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            precondition(monitor.snapshot.sampledAt == nil)
            print("PASS: 20 rapid start/refresh/stop cycles leave no stale snapshot")
        }
    }
}
