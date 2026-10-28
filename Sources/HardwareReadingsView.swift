import SwiftUI

struct HardwareReadingsView: View {
    @ObservedObject var monitor: HardwareMonitor
    var compact = false
    private var snapshot: HardwareSnapshot { monitor.snapshot }
    private var hasReadings: Bool {
        !snapshot.temperatures.isEmpty || !snapshot.powers.isEmpty || !snapshot.fans.isEmpty || !snapshot.battery.isEmpty
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 18) {
            HStack(alignment: .firstTextBaseline) {
                Label("当前电脑", systemImage: "desktopcomputer").font(compact ? .headline : .title3)
                Spacer()
                if let date = snapshot.sampledAt {
                    Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
            if snapshot.isFresh && hasReadings {
                readings("温度", snapshot.temperatures)
                readings("功率", snapshot.powers)
                readings("风扇", snapshot.fans)
                readings("电池", snapshot.battery)
            } else {
                Text(hasReadings ? "正在重新读取实时数据…" : "正在读取可用的硬件传感器…")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !compact {
                Text("仅显示成功读取的项目。功率为设备侧遥测；不同部件可能存在包含关系，不能直接相加。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("刷新读数") { monitor.refresh() }.buttonStyle(HUDButtonStyle())
            }
        }
        .padding(compact ? 14 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanionTheme.surface)
        .foregroundStyle(CompanionTheme.text)
        .preferredColorScheme(.light)
    }
    @ViewBuilder private func readings(_ title: String, _ items: [HardwareReading]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(CompanionTheme.accent)
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Text(item.name).font(compact ? .system(size: 11) : .callout)
                        Spacer(minLength: 8)
                        Text(item.formatted).font(compact ? .system(size: 11, weight: .medium, design: .monospaced) : .system(.callout, design: .monospaced))
                    }.help(item.source)
                }
            }
        }
    }
}
