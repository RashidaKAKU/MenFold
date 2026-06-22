import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Picker("设置页面", selection: $model.settingsPage) {
                ForEach(SettingsPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.settingsPage {
                    case .general:
                        permissions
                        behavior
                    case .groups:
                        groupSettings
                    case .items:
                        itemList
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "MenuFold",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var groupSettings: some View {
        SettingsSection(
            title: "折叠分组",
            subtitle: "使用上下箭头调整抽屉中的分组顺序；删除分组后，其中的项目会回到“未分组”。"
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                    TextField("新分组名称", text: $model.newGroupName)
                        .textFieldStyle(.plain)
                        .onSubmit(addGroup)
                    Button("新建", action: addGroup)
                        .disabled(model.newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))

                if model.preferences.foldGroups.isEmpty {
                    Text("还没有分组。新建后，可在下方为折叠项目选择分组。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.preferences.foldGroups.enumerated()), id: \.element.id) { index, group in
                            FoldGroupRow(
                                group: group,
                                index: index,
                                groupCount: model.preferences.foldGroups.count,
                                model: model
                            )
                            if index < model.preferences.foldGroups.count - 1 { Divider() }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(.separator.opacity(0.5), lineWidth: 1)
                    }
                }
            }
        }
    }

    private func addGroup() {
        if model.addFoldGroup(named: model.newGroupName) {
            model.newGroupName = ""
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("MenuFold")
                    .font(.title2.bold())
                Text("把菜单栏留给真正需要的内容")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.scanNow(animated: true)
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(model.scanPhase == .scanning)
        }
    }

    private var permissions: some View {
        SettingsSection(title: "权限", subtitle: "权限只用于识别、显示和点击本机菜单栏项目。") {
            PermissionCard(
                title: "辅助功能",
                detail: "识别、移动并点击菜单栏项目",
                granted: model.hasAccessibilityAccess,
                action: model.requestAccessibility
            )
        }
    }

    private var behavior: some View {
        SettingsSection(title: "外观与行为", subtitle: "展开面板始终位于当前屏幕菜单栏下方，不会压进刘海区域。") {
            VStack(spacing: 0) {
                SettingRow(title: "自身菜单栏内容", detail: "MenuFold 图标旁显示的内容") {
                    Picker("", selection: Binding(
                        get: { model.preferences.statusContent },
                        set: { model.setStatusContent($0) }
                    )) {
                        ForEach(StatusContent.allCases) { content in
                            Text(content.title).tag(content)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                Divider()
                SettingRow(title: "展开面板信息", detail: "日期、电池和内存概览") {
                    Toggle("", isOn: Binding(
                        get: { model.preferences.showDashboard },
                        set: { model.setShowDashboard($0) }
                    ))
                    .labelsHidden()
                }

                Divider()
                SettingRow(
                    title: "失焦后自动关闭",
                    detail: model.preferences.panelAutoCloseEnabled
                        ? "点击其他位置或切换应用后开始倒计时"
                        : "不关闭"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.preferences.panelAutoCloseEnabled },
                        set: { model.setPanelAutoCloseEnabled($0) }
                    ))
                    .labelsHidden()
                }

                if model.preferences.panelAutoCloseEnabled {
                    Divider()
                    SettingRow(title: "关闭延迟", detail: "可设置 1–30 秒") {
                        Stepper(
                            value: Binding(
                                get: { model.preferences.panelAutoCloseDelay },
                                set: { model.setPanelAutoCloseDelay($0) }
                            ),
                            in: 1 ... 30,
                            step: 1
                        ) {
                            Text("\(Int(model.preferences.panelAutoCloseDelay)) 秒")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                Divider()
                SettingRow(title: "登录时启动", detail: "进入桌面后自动整理菜单栏") {
                    Toggle("", isOn: Binding(
                        get: { model.preferences.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                }
            }
        }
    }

    private var itemList: some View {
        SettingsSection(
            title: "菜单栏项目",
            subtitle: "始终显示保留原图标；折叠会放入下方展开栏；彻底隐藏不会出现在展开栏。"
        ) {
            VStack(spacing: 12) {
                MenuBarUsageTip()
                ScanStatusCard(model: model)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索项目", text: $model.searchText)
                        .textFieldStyle(.plain)
                    Text("\(model.items.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(9)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                if model.filteredItems.isEmpty {
                    ContentUnavailableView(
                        "没有检测到项目",
                        systemImage: "menubar.rectangle",
                        description: Text("确认菜单栏中已有第三方或系统图标，然后点“重新扫描”。")
                    )
                    .frame(minHeight: 130)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                            ItemPreferenceRow(item: item, model: model)
                            if index < model.filteredItems.count - 1 { Divider() }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator.opacity(0.5), lineWidth: 1)
                    }
                }
            }
        }
    }
}

private struct MenuBarUsageTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("菜单栏图标说明", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chevron.left.2")
                    .frame(width: 24, height: 20)
                Text("菜单栏最左侧的折叠标记仅用于遮罩和划分隐藏区域，无需点击。")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "rectangle.3.group")
                    .frame(width: 24, height: 20)
                Text("请点击 MenuFold 软件图标打开或关闭折叠抽屉。")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption)
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct ScanStatusCard: View {
    @ObservedObject var model: AppModel

    private var statusColor: Color {
        switch model.scanPhase {
        case .idle: .secondary
        case .scanning: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.scanPhase.symbol)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.rotate, isActive: model.scanPhase == .scanning)
                Text(model.scanPhase.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(model.scanProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: model.scanProgress, total: 1)
                .tint(statusColor)

            Text(model.scanMessage)
                .font(.caption)
                .foregroundStyle(model.scanPhase == .failed ? .red : .secondary)
        }
        .padding(12)
        .background(statusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}

private struct PermissionCard: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(granted ? "已允许" : detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("允许", action: action)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 10)
    }
}

private struct ItemPreferenceRow: View {
    let item: MenuBarItem
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let symbol = item.systemSymbolName {
                    Image(systemName: symbol).resizable().scaledToFit().padding(4)
                } else if let icon = item.appIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit().padding(4)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).lineLimit(1)
                if item.displayName != item.ownerName {
                    Text(item.ownerName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.isMovable {
                VStack(alignment: .trailing, spacing: 6) {
                    Picker("显示方式", selection: Binding(
                        get: { model.visibility(for: item) },
                        set: { model.setVisibility($0, for: item) }
                    )) {
                        ForEach(ItemVisibility.allCases) { visibility in
                            Label(visibility.title, systemImage: visibility.symbol).tag(visibility)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 132)

                    if model.visibility(for: item) == .collapsed,
                       !model.preferences.foldGroups.isEmpty {
                        Picker("所属分组", selection: Binding(
                            get: { model.groupID(for: item) ?? "" },
                            set: { model.assign(item, toGroupID: $0.isEmpty ? nil : $0) }
                        )) {
                            Text("未分组").tag("")
                            ForEach(model.preferences.foldGroups) { group in
                                Label(group.name, systemImage: "folder").tag(group.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 132)
                        .help("选择折叠抽屉中的分组")
                    }
                }
            } else {
                Text("系统锁定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 132, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct FoldGroupRow: View {
    let group: FoldGroup
    let index: Int
    let groupCount: Int
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
            TextField("分组名称", text: Binding(
                get: { model.groupNameDrafts[group.id] ?? group.name },
                set: { model.groupNameDrafts[group.id] = $0 }
            ))
                .textFieldStyle(.plain)
                .onSubmit(save)
            Text("\(itemCount) 项")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: save) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(trimmedName == group.name || trimmedName.isEmpty)
            .help("保存名称")
            Button {
                model.moveFoldGroup(id: group.id, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("上移分组")
            Button {
                model.moveFoldGroup(id: group.id, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index >= groupCount - 1)
            .help("下移分组")
            Button(role: .destructive) {
                model.deleteFoldGroup(id: group.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除分组")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var trimmedName: String {
        (model.groupNameDrafts[group.id] ?? group.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemCount: Int {
        model.collapsedItems.filter { model.groupID(for: $0) == group.id }.count
    }

    private func save() {
        if model.renameFoldGroup(id: group.id, to: trimmedName) {
            model.groupNameDrafts.removeValue(forKey: group.id)
        }
    }
}
