import SwiftUI
import PowerCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance = "外观与显示", data = "数据记录", reminders = "提醒", about = "关于"
    var id: String { rawValue }
    var icon: String { self == .appearance ? "sun.max" : self == .data ? "externaldrive" : self == .reminders ? "bell" : "info.circle" }
}

struct SettingsPanel: View {
    @ObservedObject var store: AppStore
    @ViewState<SettingsPage> private var page: SettingsPage = .appearance
    var body: some View {
        HStack(spacing:0) {
            VStack(spacing:6) {
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        HStack(spacing:9) { Image(systemName:item.icon).frame(width:18);Text(item.rawValue);Spacer(minLength:0) }
                            .font(.system(size:12)).padding(11).contentShape(Rectangle())
                            .foregroundStyle(page == item ? Palette.blue : Palette.secondary)
                            .background(page == item ? Palette.blue.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:6))
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                }
                Spacer()
            }.padding(.horizontal,10).padding(.top,20).frame(width:156).background(Palette.secondarySurface)
            Divider().overlay(Palette.line)
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    switch page {
                    case .appearance: appearance
                    case .data: data
                    case .reminders: reminders
                    case .about: about
                    }
                    if let message = store.message { Text(message).font(.system(size:11)).foregroundStyle(Palette.warning).padding(.top,20).textSelection(.enabled) }
                }.padding(27).frame(maxWidth:.infinity,alignment:.leading)
            }.frame(maxWidth:.infinity)
        }.frame(width:690,height:570).background(Palette.surface).foregroundStyle(Palette.text)
    }
    private var appearance: some View {
        VStack(alignment:.leading,spacing:0) {
            heading("外观",subtitle:"选择熟悉的色彩，让查看更舒适。")
            HStack(spacing:10) {
                ForEach(AppearanceMode.allCases,id:\.self) { mode in
                    Button { store.preferences.appearance = mode } label: {
                        VStack(spacing:13) {
                            Image(systemName:mode == .system ? "circle.lefthalf.filled" : mode == .light ? "sun.max" : "moon").font(.system(size:28,weight:.light))
                            Text(mode.title).font(.system(size:12))
                        }.frame(maxWidth:.infinity).frame(height:110)
                            .background(store.preferences.appearance == mode ? Palette.blue.opacity(0.13) : Palette.secondarySurface.opacity(0.55),in:RoundedRectangle(cornerRadius:9))
                            .overlay(RoundedRectangle(cornerRadius:9).stroke(store.preferences.appearance == mode ? Palette.blue : Palette.line,lineWidth:1.5))
                            .overlay(alignment:.topTrailing) { if store.preferences.appearance == mode { Image(systemName:"checkmark.circle.fill").font(.system(size:12)).padding(8) } }
                    }.buttonStyle(.plain).foregroundStyle(store.preferences.appearance == mode ? Palette.blue : Palette.secondary)
                        .accessibilityLabel(mode.title).accessibilityAddTraits(store.preferences.appearance == mode ? .isSelected : [])
                }
            }
            Text(store.preferences.appearance == .system ? "跟随 macOS 自动切换；无需重新打开应用。" : "始终使用\(store.preferences.appearance.title)外观，不受系统外观变化影响。")
                .font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.top,15).padding(.bottom,27)
            Text("菜单栏").font(.system(size:13,weight:.semibold))
            row("显示指标") { Picker("显示指标",selection:$store.preferences.menuMetric) { ForEach(MenuMetric.allCases,id:\.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width:140) }
            row("同时显示电量") { Toggle("同时显示电量",isOn:$store.preferences.showPercent).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            row("登录时启动") { Toggle("登录时启动",isOn:Binding(get:{store.loginEnabled},set:{store.setLogin($0)})).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            Label("设置自动保存，即时生效",systemImage:"checkmark").font(.system(size:10)).foregroundStyle(Palette.secondary).padding(.top,20)
        }
    }
    private var data: some View {
        VStack(alignment:.leading,spacing:0) {
            heading("数据记录",subtitle:"记录只保存在这台 Mac，不上传设备数据。")
            row("记录本地历史") { Toggle("记录本地历史",isOn:$store.preferences.recordHistory).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            row("保留功率历史") { Picker("保留功率历史",selection:$store.preferences.retentionDays) { Text("7 天").tag(7);Text("30 天").tag(30);Text("90 天").tag(90) }.labelsHidden().frame(width:110) }
            row("收起时降低采样频率") { Toggle("收起时降低采样频率",isOn:$store.preferences.energySaving).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            Text("面板打开时每秒读取；收起后每 5 秒读取，省电时每 15 秒。睡眠暂停，唤醒重新采集。历史按分钟汇总，健康记录最多保留 90 天。").font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(5).padding(.vertical,20)
            Button { store.export(minutes:1440) } label: { Label("导出最近 24 小时 CSV",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity) }.controlSize(.large)
            Button(role:.destructive) { store.clearHistory() } label: { Label("清除全部本地历史…",systemImage:"trash").frame(maxWidth:.infinity) }.controlSize(.large).padding(.top,12)
            Text("关闭记录保留已有历史，并停止保存新数据。读数缺失、睡眠和来源变化处不会补线。").font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(5).padding(.top,20)
        }
    }
    private var reminders: some View {
        VStack(alignment:.leading,spacing:0) {
            heading("提醒",subtitle:"只在满足条件时提醒，默认全部关闭。")
            row("低电量提醒") { reminderToggle("低电量提醒",key:\.lowBatteryReminder) }
            if store.preferences.lowBatteryReminder { row("提醒电量") { Stepper("\(store.preferences.lowThreshold)%",value:$store.preferences.lowThreshold,in:5...40,step:5).frame(width:110) } }
            row("充至指定电量") { reminderToggle("充至指定电量",key:\.chargeReminder) }
            if store.preferences.chargeReminder { row("提醒电量") { Stepper("\(store.preferences.chargeThreshold)%",value:$store.preferences.chargeThreshold,in:50...100,step:5).frame(width:110) } }
            row("插电后持续放电") { reminderToggle("插电后持续放电",key:\.supplementReminder) }
            Text(store.notificationStatus).font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(5).padding(.top,20)
            Label("MacPower 不控制充电，也不会改变系统电池保护策略。",systemImage:"info.circle").font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.top,22)
        }
    }
    private var about: some View {
        VStack(alignment:.leading,spacing:18) {
            Image(systemName:"bolt.fill").font(.system(size:30)).foregroundStyle(Palette.blue)
            Text("MacPower").font(.system(size:27,weight:.bold))
            Text("0.1.0 · 本地开发版").font(.system(size:12)).foregroundStyle(Palette.secondary)
            Text("看清进入 Mac、流入电池和设备运行的功率。").font(.system(size:14)).lineSpacing(5)
            Text("SwiftUI / AppKit 原生应用。采集为只读，无管理员辅助程序。当前优先验证 Apple Silicon MacBook；部分硬件字段不可用时保留为空。").font(.system(size:12)).foregroundStyle(Palette.secondary).lineSpacing(5)
            Divider()
            Text("数据来源：IOPowerSources、AppleSmartBattery、macOS 系统健康报告。未提供温度和原始容量时不猜测单位。充电器供电能力不等于实时输入。").font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(5)
            Button("退出 MacPower") { store.quit?() }.controlSize(.large)
        }
    }
    private func heading(_ title:String,subtitle:String) -> some View { VStack(alignment:.leading,spacing:9) { Text(title).font(.system(size:17,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(Palette.secondary) }.padding(.bottom,25) }
    private func row<Content:View>(_ label:String,@ViewBuilder content:() -> Content) -> some View { VStack(spacing:0) { HStack(spacing:15) { Text(label).font(.system(size:12));Spacer();content() }.padding(.vertical,14);Divider().overlay(Palette.line) } }
    private func reminderToggle(_ title:String,key:WritableKeyPath<Preferences,Bool>) -> some View {
        Toggle(title,isOn:Binding(get:{store.preferences[keyPath:key]},set:{store.setReminder(key,enabled:$0)})).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}
