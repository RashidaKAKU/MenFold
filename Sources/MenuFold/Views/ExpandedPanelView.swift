import SwiftUI

struct ExpandedPanelView: View {
    @ObservedObject var model: AppModel
    let onActivate: (MenuBarItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 112), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("MenuFold", systemImage: "rectangle.3.group")
                    .font(.headline)
                Spacer()
                Text(Date(), style: .time)
                    .foregroundStyle(.secondary)
                Button {
                    model.onSettingsRequested?()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("打开设置")
            }

            if model.preferences.showDashboard {
                DashboardView(metrics: model.metrics)
            }

            Label(
                "最左侧折叠标记是遮罩；请点击 MenuFold 软件图标打开本抽屉。",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            if model.collapsedItems.isEmpty {
                ContentUnavailableView(
                    "折叠栏是空的",
                    systemImage: "menubar.rectangle",
                    description: Text("在设置中把项目改为“折叠”，它就会出现在这里。")
                )
                .frame(maxWidth: .infinity, minHeight: 86)
            } else {
                Divider()
                ForEach(model.collapsedItemGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(group.name)
                            Text("\(group.items.count)")
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(group.items) { item in
                                FoldedItemButton(
                                    item: item,
                                    action: { onActivate(item) }
                                )
                            }
                        }
                    }
                }
            }

            if !model.hasAccessibilityAccess && !model.collapsedItems.isEmpty {
                Button("允许辅助功能权限以点击折叠项目") {
                    model.requestAccessibility()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct DashboardView: View {
    let metrics: SystemMetrics

    var body: some View {
        HStack(spacing: 10) {
            MetricChip(symbol: "calendar", text: Date().formatted(.dateTime.month().day().weekday()))
            if let battery = metrics.batteryPercent {
                MetricChip(symbol: "battery.75percent", text: "\(battery)%")
            }
            MetricChip(symbol: "memorychip", text: "内存 \(metrics.memoryPressure)%")
        }
    }
}

private struct MetricChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}

private struct FoldedItemButton: View {
    let item: MenuBarItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let symbol = item.systemSymbolName {
                        Image(systemName: symbol)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    } else if let appIcon = item.appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    }
                }
                .frame(width: 28, height: 24)

                Text(item.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(FoldedButtonStyle())
        .help("点击打开 \(item.displayName)")
    }
}

private struct FoldedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}
