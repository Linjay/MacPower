import SwiftUI
import Charts
import PowerCore

enum Palette {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor:NSColor(name:nil) { appearance in
            let value = appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed:CGFloat((value >> 16)&255)/255,green:CGFloat((value >> 8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
        })
    }
    static let surface = color(0xF3F6FA,0x252D38)
    static let secondarySurface = color(0xE8EEF5,0x202733)
    static let text = color(0x202632,0xF2F5FA)
    static let secondary = color(0x606C7E,0xB5BFCC)
    static let line = color(0xD4DCE7,0x414B59)
    static let blue = color(0x316BCF,0x83ACFF)
    static let teal = color(0x147E76,0x77D4C3)
    static let warning = color(0x98600D,0xF0BD72)
}

enum PanelPage: String, CaseIterable { case live = "实时", trends = "趋势", health = "健康" }

extension EnergyMode {
    var menuColor: NSColor {
        switch self {
        case .automatic: return .systemBlue
        case .lowPower: return .systemGreen
        case .highPower: return .systemOrange
        case .unknown: return .labelColor
        }
    }
    var panelColor: Color {
        switch self {
        case .automatic: return Palette.blue
        case .lowPower: return Palette.teal
        case .highPower: return Palette.warning
        case .unknown: return Palette.secondary
        }
    }
}

struct PowerPanel: View {
    @ObservedObject var store: AppStore
    @ViewState<PanelPage> private var page: PanelPage = .live
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"bolt.fill").font(.system(size:20,weight:.bold)).foregroundStyle(.white)
                    .frame(width:29,height:29).background(Palette.blue,in:RoundedRectangle(cornerRadius:7))
                Text("MacPower").font(.system(size:19,weight:.bold))
                Spacer()
                Button { store.showOverview?() } label: { Image(systemName:"pin").font(.system(size:16)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("在窗口中打开").accessibilityLabel("在窗口中打开")
                Button { store.showSettings?() } label: { Image(systemName:"gearshape.fill").font(.system(size:20)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("打开设置").accessibilityLabel("打开设置")
            }.padding(.bottom,10)
            HStack(spacing:5) {
                Circle().fill(store.isStale ? Palette.warning : Palette.teal).frame(width:5,height:5)
                Text(store.isStale ? "等待有效数据" : "本机实时数据").font(.system(size:11))
                Spacer()
                Text(store.snapshot.timestamp,style:.time).font(.system(size:10)).monospacedDigit()
            }.foregroundStyle(Palette.secondary).padding(.bottom,12)
            Picker("电源信息页面",selection:$page) { ForEach(PanelPage.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding(.bottom,6)
            ScrollView {
                VStack(spacing:0) {
                    if let message = store.message {
                        HStack(alignment:.top) {
                            Text(message).font(.system(size:11)).textSelection(.enabled)
                            Spacer(minLength:4)
                            Button { store.message = nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("关闭提示")
                        }.padding(10).background(Palette.blue.opacity(0.1),in:RoundedRectangle(cornerRadius:6)).padding(.top,10)
                    }
                    switch page {
                    case .live: LivePanel(store:store,onTrends:{page = .trends},onHealth:{page = .health})
                    case .trends: HistoryPanel(store:store)
                    case .health: HealthPanel(store:store)
                    }
                }.frame(maxWidth:.infinity)
            }.scrollIndicators(.automatic)
        }.padding(20).frame(width:416).frame(maxHeight:.infinity)
            .background(Palette.surface).foregroundStyle(Palette.text)
    }
}

struct LivePanel: View {
    @ObservedObject var store: AppStore
    var onTrends: () -> Void
    var onHealth: () -> Void
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:6) {
                if store.state == .supplement || store.isStale { Image(systemName:"exclamationmark.circle") }
                Text(store.state.title).font(.system(size:15,weight:.semibold))
                Spacer()
            }.foregroundStyle(store.state == .supplement ? Palette.warning : Palette.text).padding(.top,19).padding(.bottom,15)
            if !store.snapshot.hasBattery {
                ContentUnavailableView("未检测到内置电池",systemImage:"battery.0percent",description:Text("当前版本面向 MacBook。若设备有电池，可重新读取。"))
                Button("重新读取") { store.sample() }.padding(.bottom,20)
            } else {
                if store.state.showsEnergyMode {
                    HStack(spacing:7) {
                        Image(systemName:store.energyMode.symbol)
                        Text("能源模式 · \(store.energyMode.title)").fontWeight(.medium)
                        Spacer()
                        Text("系统设置").font(.system(size:10)).foregroundStyle(Palette.secondary)
                    }.font(.system(size:12)).foregroundStyle(store.energyMode.panelColor)
                        .padding(.horizontal,10).padding(.vertical,8)
                        .background(store.energyMode.panelColor.opacity(0.08),in:RoundedRectangle(cornerRadius:7))
                        .padding(.bottom,14)
                        .help("\(store.energyModeSource) · 只读\n系统选择的能源策略，不代表即时性能。菜单栏：自动为蓝色、节能为绿色、高性能为橙色；未提供时保持默认颜色。")
                        .accessibilityElement(children:.combine)
                }
                PowerFlowView(store:store)
                Text(store.isStale ? "最新读数暂不可用" : "\(store.snapshot.input.quality.label) · 点击功率查看来源")
                    .font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.top,4).padding(.bottom,16)
                Divider().overlay(Palette.line)
                HStack(spacing:8) {
                    Image(systemName:store.batterySymbol).font(.system(size:23)).foregroundStyle(Palette.secondary)
                    Text("电量").font(.system(size:13,weight:.semibold))
                    Text(store.snapshot.percent.map{"\($0)%"} ?? "—").font(.system(size:21,weight:.semibold)).monospacedDigit()
                    Spacer()
                    Text(chargeLabel).font(.system(size:12)).foregroundStyle(store.state == .supplement ? Palette.warning : Palette.teal)
                }.padding(.top,17).padding(.bottom,11)
                ProgressView(value:Double(store.snapshot.percent ?? 0),total:100).progressViewStyle(BatteryProgressStyle())
                    .accessibilityLabel("电池电量").accessibilityValue(store.snapshot.percent.map{"\($0)%"} ?? "不可用")
                Text(timeLabel).font(.system(size:11)).foregroundStyle(Palette.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8).padding(.bottom,17)
                Divider().overlay(Palette.line)
                Button(action:onTrends) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("电池功率 · 最近 15 分钟").font(.system(size:12,weight:.medium)).foregroundStyle(Palette.secondary)
                        PowerChart(points:store.selectedPoints(minutes:15),minutes:15,series:[.battery],compact:true)
                            .frame(height:70)
                    }.padding(.vertical,17)
                }.buttonStyle(.plain).accessibilityLabel("查看最近 15 分钟电池功率趋势")
                Divider().overlay(Palette.line)
                Button(action:onHealth) {
                    HStack(spacing:13) {
                        Image(systemName:"heart").font(.system(size:25)).foregroundStyle(Palette.secondary)
                        VStack(alignment:.leading,spacing:4) {
                            Text("电池健康").font(.system(size:13,weight:.semibold))
                            Text(healthSummary).font(.system(size:12)).foregroundStyle(Palette.secondary)
                        }
                        Spacer(); Image(systemName:"chevron.right").font(.system(size:12)).foregroundStyle(Palette.secondary)
                    }.padding(.vertical,17)
                }.buttonStyle(.plain)
                HStack {
                    Text(store.snapshot.cycleCount.map{"\($0) 次循环"} ?? "循环次数未提供")
                    Spacer(); Button(action:onTrends) { Label("查看趋势",systemImage:"arrow.up.right") }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                }.font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.bottom,3)
            }
        }
    }
    private var healthSummary: String {
        let percent = store.health?.maximumCapacity.map{"\($0)%"} ?? "最大容量未提供"
        return "\(percent) · \(store.health?.conditionLabel ?? "正在读取")"
    }
    private var chargeLabel: String {
        switch store.state { case .charging: return "正在充电"; case .battery,.supplement: return "正在放电"; case .full: return "已充满"; case .idle: return "未充电"; default: return "正在更新" }
    }
    private var timeLabel: String {
        if store.isStale { return "等待新的有效读数" }
        if store.state == .idle { return "系统未提供未充电的原因" }
        if store.state == .full { return "当前由外接电源供电" }
        guard let minutes = store.snapshot.minutesRemaining else { return "剩余时间正在估算" }
        let time = minutes >= 60 ? "\(minutes/60) 小时 \(minutes%60) 分钟" : "\(minutes) 分钟"
        return "\(store.state == .charging ? "预计充满" : "预计可用")约 \(time) · 估算"
    }
}

struct PowerFlowView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing:0) {
            Button { store.showMetric?("input") } label: {
                HStack(spacing:11) {
                    Image(systemName:"powerplug.fill").font(.system(size:38)).rotationEffect(.degrees(-90))
                    VStack(alignment:.leading,spacing:1) {
                        Text("电源输入").font(.system(size:12)).foregroundStyle(Palette.secondary)
                        if store.snapshot.externalConnected == false { Text("未接入").font(.system(size:25,weight:.semibold)) }
                        else { value(store.snapshot.input,fontSize:32) }
                    }
                }.foregroundStyle(Palette.blue)
            }.buttonStyle(.plain).help("查看输入功率来源").accessibilityLabel("电源输入 \(reading(store.snapshot.input)) 瓦，查看说明")
            Button { store.showMetric?("adapter") } label: {
                HStack(spacing:4) {
                    Text(store.snapshot.adapterWatts.map{String(format:"供电能力 %.0f W",$0)} ?? (store.snapshot.externalConnected == false ? "当前由电池供电" : "供电能力未提供"))
                    if store.snapshot.adapterWatts != nil { Text("· 系统报告").foregroundStyle(Palette.blue); Image(systemName:"chevron.right").font(.system(size:9)) }
                }.font(.system(size:11)).foregroundStyle(Palette.secondary)
            }.buttonStyle(.plain).padding(.top,9)
            FlowBranches(external:store.snapshot.externalConnected == true,battery:(store.snapshot.battery.value ?? 0),active:!store.isStale)
                .frame(height:44).padding(.horizontal,55)
            HStack(alignment:.top) {
                metric(label:"整机耗电",icon:"laptopcomputer",power:store.snapshot.system,color:Palette.text,key:"system")
                Spacer(minLength:10)
                metric(label:store.snapshot.batteryLabel,icon:store.batterySymbol,power:store.snapshot.battery,color:store.state == .supplement ? Palette.warning : Palette.teal,key:"battery")
            }.padding(.horizontal,15)
        }
    }
    private func reading(_ metric: PowerMetric,signed:Bool=false) -> String { store.isStale ? "—" : metric.formatted(signed:signed) }
    private func value(_ metric: PowerMetric,fontSize:CGFloat,signed:Bool=false) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:3) { Text(reading(metric,signed:signed)).font(.system(size:fontSize,weight:.semibold)).monospacedDigit();Text("W").font(.system(size:14,weight:.medium)) }
    }
    private func metric(label:String,icon:String,power:PowerMetric,color:Color,key:String) -> some View {
        Button { store.showMetric?(key) } label: {
            VStack(spacing:4) {
                Image(systemName:icon).font(.system(size:33,weight:.light)).frame(height:35).foregroundStyle(key == "system" ? Palette.secondary : color)
                Text(label).font(.system(size:12)).foregroundStyle(Palette.secondary)
                value(power,fontSize:27,signed:key == "battery").foregroundStyle(color)
                Text(power.quality == .estimated ? "估算" : " ").font(.system(size:10)).foregroundStyle(Palette.secondary)
            }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain).help("查看\(label)的来源和解释").accessibilityLabel("\(label) \(reading(power,signed:key == "battery")) 瓦，\(power.quality.label)")
    }
}

struct FlowBranches: View {
    var external: Bool
    var battery: Double
    var active: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            if active {
                Path { p in
                    if external {
                        p.move(to:CGPoint(x:w/2,y:4)); p.addLine(to:CGPoint(x:w/2,y:13))
                        p.addQuadCurve(to:CGPoint(x:w/2-9,y:22),control:CGPoint(x:w/2,y:22));p.addLine(to:CGPoint(x:10,y:22))
                        p.addQuadCurve(to:CGPoint(x:0,y:32),control:CGPoint(x:0,y:22));p.addLine(to:CGPoint(x:0,y:38))
                        if battery > 0.5 {
                            p.move(to:CGPoint(x:w/2,y:13));p.addQuadCurve(to:CGPoint(x:w/2+9,y:22),control:CGPoint(x:w/2,y:22))
                            p.addLine(to:CGPoint(x:w-10,y:22));p.addQuadCurve(to:CGPoint(x:w,y:32),control:CGPoint(x:w,y:22));p.addLine(to:CGPoint(x:w,y:38))
                        }
                    }
                }.stroke(Palette.blue,style:StrokeStyle(lineWidth:1.4,lineCap:.round))
                if external { Image(systemName:"arrowtriangle.down.fill").font(.system(size:8)).foregroundStyle(Palette.blue).position(x:0,y:38) }
                if external && battery > 0.5 { Image(systemName:"arrowtriangle.down.fill").font(.system(size:8)).foregroundStyle(Palette.blue).position(x:w,y:38) }
                if battery < -0.5 {
                    HStack(spacing:0) { Image(systemName:"arrowtriangle.left.fill").font(.system(size:8)); Rectangle().frame(height:1.4) }
                        .foregroundStyle(external ? Palette.warning : Palette.teal).frame(width:w-30).position(x:w/2,y:35)
                }
            }
        }.accessibilityHidden(true)
    }
}

enum ChartSeries: String, CaseIterable, Identifiable {
    case input, system, battery
    var id: String { rawValue }
    var label: String { self == .input ? "电源输入" : self == .system ? "整机耗电" : "电池净功率" }
    var color: Color { self == .input ? Palette.blue : self == .battery ? Palette.teal : Palette.secondary }
    func metric(_ point: HistoryPoint) -> MetricSummary { self == .input ? point.input : self == .battery ? point.battery : point.system }
}

struct PowerChart: View {
    var points: [HistoryPoint]
    var minutes: Int
    var series: Set<ChartSeries>
    var compact = false
    var body: some View {
        if points.isEmpty {
            VStack(spacing:6) { Image(systemName:"chart.xyaxis.line").font(.system(size:compact ? 20 : 30));Text("正在积累记录").font(.system(size:12));if !compact { Text("只绘制实际采集的数据，不填补中断。").font(.system(size:11)) } }
                .foregroundStyle(Palette.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
        } else {
            Chart {
                RuleMark(y:.value("零",0)).foregroundStyle(Palette.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth:0.7))
                ForEach(ChartSeries.allCases.filter{series.contains($0)}) { item in
                    ForEach(points) { point in
                        if let value = item.metric(point).mean {
                            LineMark(x:.value("时间",point.date),y:.value("功率 W",value),series:.value("记录段",item.rawValue+point.segment.uuidString))
                                .foregroundStyle(item.color).lineStyle(StrokeStyle(lineWidth:compact ? 1.5 : 2,dash:item == .system ? [4,3] : []))
                            if points.count < 8 { PointMark(x:.value("时间",point.date),y:.value("功率 W",value)).foregroundStyle(item.color).symbolSize(compact ? 8 : 20) }
                        }
                    }
                }
            }.chartLegend(.hidden).chartYScale(domain:domain)
                .chartXScale(domain:Date().addingTimeInterval(-Double(minutes)*60)...Date())
                .chartXAxis { AxisMarks(values:.automatic(desiredCount:compact ? 2 : 4)) { value in
                    AxisValueLabel(format:.dateTime.hour().minute(),anchor:value.index == 0 ? .topLeading : value.index == value.count-1 ? .topTrailing : .top)
                        .font(.system(size:9))
                } }
                .chartYAxis { AxisMarks(position:.trailing,values:.automatic(desiredCount:compact ? 2 : 4)) { _ in AxisGridLine().foregroundStyle(Palette.line.opacity(0.7));AxisValueLabel().font(.system(size:9)) } }
                .accessibilityLabel("功率趋势，\(points.count) 条实际分钟记录，单位瓦")
        }
    }
    private var domain: ClosedRange<Double> {
        let values = points.flatMap { p in series.compactMap { $0.metric(p).mean } }
        let low = min(0,floor((values.min() ?? 0)/10)*10)
        let high = max(10,ceil((values.max() ?? 0)/10)*10)
        return low...high
    }
}

struct BatteryProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Palette.line).overlay(alignment:.leading) {
                Capsule().fill(Palette.teal).frame(width:geometry.size.width * CGFloat(configuration.fractionCompleted ?? 0))
            }
        }.frame(height:6)
    }
}

struct HistoryPanel: View {
    @ObservedObject var store: AppStore
    var expanded = false
    @ViewState<Int> private var minutes = 15
    @ViewState<Set<ChartSeries>> private var series: Set<ChartSeries> = [.input,.battery]
    init(store: AppStore, expanded: Bool = false, minutes: Int = 15, series: Set<ChartSeries> = [.input,.battery]) {
        self.store = store; self.expanded = expanded
        self._minutes = ViewState(initialValue:minutes)
        self._series = ViewState(initialValue:series)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:17) {
            HStack {
                VStack(alignment:.leading,spacing:5) { Text("功率趋势").font(.system(size:19,weight:.semibold));Text("每一分钟，来自真实记录。").font(.system(size:11)).foregroundStyle(Palette.secondary) }
                Spacer()
                Button { store.export(minutes:minutes) } label: { Image(systemName:"square.and.arrow.up").font(.system(size:18)) }.buttonStyle(.plain).help("导出当前时段 CSV").accessibilityLabel("导出当前时段 CSV").disabled(points.isEmpty)
            }.padding(.top,18)
            Picker("趋势时段",selection:$minutes) { Text("15 分钟").tag(15);Text("1 小时").tag(60);Text("24 小时").tag(1440) }.pickerStyle(.segmented).labelsHidden()
            HStack { Text("功率 / W");Spacer();Text("分钟均值") }.font(.system(size:10)).foregroundStyle(Palette.secondary)
            PowerChart(points:points,minutes:minutes,series:series).frame(height:expanded ? 270 : 210)
            HStack(spacing:15) {
                ForEach(ChartSeries.allCases) { item in
                    Button {
                        if series.contains(item) { if series.count > 1 { series.remove(item) } } else { series.insert(item) }
                    } label: { Label(item.label,systemImage:series.contains(item) ? "checkmark.circle.fill" : "circle").font(.system(size:10)).foregroundStyle(item.color).opacity(series.contains(item) ? 1 : 0.5) }
                        .buttonStyle(.plain).accessibilityValue(series.contains(item) ? "显示" : "隐藏")
                }
            }
            Divider().overlay(Palette.line)
            HStack {
                summary("充入电池",value:String(format:"%.2f Wh",points.reduce(0){$0+$1.chargedWh}))
                Spacer();summary("电池放出",value:String(format:"%.2f Wh",points.reduce(0){$0+$1.dischargedWh}))
            }
            Text("记录覆盖 \(coverage)% · \(points.count) 条分钟记录\n中断与来源变化处断线，缺口不计入电量。").font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(5)
            if !store.preferences.recordHistory { Label("历史记录已关闭",systemImage:"pause.circle").font(.system(size:11)).foregroundStyle(Palette.warning) }
            if !expanded { Button { store.showHistory?(minutes,series) } label: { Label("打开完整趋势",systemImage:"arrow.up.right") }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size:12)).padding(.bottom,10) }
        }.foregroundStyle(Palette.text)
    }
    private var points: [HistoryPoint] { store.selectedPoints(minutes:minutes) }
    private var coverage: Int { min(100,Int(points.reduce(0){$0+$1.coveredSeconds}/Double(minutes*60)*100)) }
    private func summary(_ title:String,value:String) -> some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.system(size:11)).foregroundStyle(Palette.secondary);Text(value).font(.system(size:23,weight:.semibold)).monospacedDigit() } }
}

struct HealthPanel: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { Text("电池健康").font(.system(size:19,weight:.semibold));Spacer();Image(systemName:"heart").font(.system(size:24)).foregroundStyle(Palette.teal) }.padding(.top,20)
            Text("关注长期状态，安心使用。").font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.top,7)
            VStack(spacing:11) {
                Text(store.health?.conditionLabel ?? "正在读取").font(.system(size:11)).foregroundStyle(Palette.teal).padding(.horizontal,10).padding(.vertical,5).background(Palette.teal.opacity(0.1),in:Capsule())
                HStack(alignment:.firstTextBaseline,spacing:2) { Text(store.health?.maximumCapacity.map(String.init) ?? "—").font(.system(size:61,weight:.semibold));Text("%").font(.system(size:26)) }.monospacedDigit()
                Text("最大容量 · 系统报告").font(.system(size:12)).foregroundStyle(Palette.secondary)
                Button("这与剩余电量有什么区别？") { store.showMetric?("health") }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size:11))
            }.frame(maxWidth:.infinity).padding(.vertical,27)
            row("循环次数",value:(store.health?.cycleCount ?? store.snapshot.cycleCount).map{"\($0) 次"} ?? "未提供")
            row("电池温度",value:"未提供")
            row("满充容量",value:"未验证")
            row("设计容量",value:"未验证")
            Divider().overlay(Palette.line)
            Text("容量变化").font(.system(size:13,weight:.medium)).padding(.top,19)
            if store.healthHistory.count < 2 {
                VStack(spacing:8) { Image(systemName:"chart.xyaxis.line").font(.system(size:25));Text("从今天开始，了解电池的变化。").font(.system(size:12));Text("积累至少两天记录后可查看趋势。").font(.system(size:10)) }.foregroundStyle(Palette.secondary).frame(maxWidth:.infinity).padding(.vertical,25)
            } else {
                Chart(store.healthHistory,id:\.date) { item in
                    if let value = item.maximumCapacity { LineMark(x:.value("日期",item.date),y:.value("最大容量 %",value),series:.value("来源",item.source)).foregroundStyle(Palette.teal);PointMark(x:.value("日期",item.date),y:.value("最大容量 %",value)).foregroundStyle(Palette.teal) }
                }.chartYScale(domain:0...100).frame(height:130).padding(.vertical,18)
            }
            Text("循环次数按累计使用电量计算，并非插电次数。").font(.system(size:10)).foregroundStyle(Palette.secondary)
            if let date = store.health?.date { Text("健康报告更新于 \(date.formatted(date:.abbreviated,time:.shortened))").font(.system(size:10)).foregroundStyle(Palette.secondary).padding(.top,9) }
            if let error = store.healthMessage { Text(error).font(.system(size:11)).foregroundStyle(Palette.warning).padding(.top,9) }
            HStack { Button("重新读取健康报告") { store.refreshHealth() };Spacer();Button("系统电池设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.battery")!) } }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size:11)).padding(.vertical,20)
        }
    }
    private func row(_ title:String,value:String) -> some View { VStack(spacing:0) { Divider().overlay(Palette.line);HStack { Text(title).foregroundStyle(Palette.secondary);Spacer();Text(value).monospacedDigit() }.font(.system(size:12)).padding(.vertical,13) } }
}

struct MetricDetail: View {
    @ObservedObject var store: AppStore
    var kind: String
    var body: some View {
        VStack(alignment:.leading,spacing:17) {
            Text(title).font(.system(size:19,weight:.semibold))
            if let metric {
                HStack(alignment:.firstTextBaseline,spacing:5) { Text(store.isStale ? "—" : metric.formatted(signed:kind == "battery")).font(.system(size:40,weight:.semibold));Text("W").font(.system(size:20)) }.foregroundStyle(Palette.blue).monospacedDigit()
                Text(explanation).font(.system(size:13)).lineSpacing(5)
                Divider()
                Text("\(metric.quality.label) · \(metric.source)").font(.system(size:11)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                Text("采样时间：\(metric.sampledAt.formatted(date:.omitted,time:.standard))").font(.system(size:11)).foregroundStyle(Palette.secondary)
                if let reason = metric.reason { Text(reason).font(.system(size:11)).foregroundStyle(Palette.warning) }
            } else { Text(explanation).font(.system(size:14)).lineSpacing(7) }
            Spacer(minLength:0)
        }.padding(26).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Palette.surface).foregroundStyle(Palette.text)
    }
    private var metric: PowerMetric? { kind == "input" ? store.snapshot.input : kind == "system" ? store.snapshot.system : kind == "battery" ? store.snapshot.battery : nil }
    private var title: String { kind == "adapter" ? "供电能力" : kind == "health" ? "读懂电池健康" : kind == "input" ? "电源输入" : kind == "system" ? "整机耗电" : "电池净功率" }
    private var explanation: String {
        switch kind {
        case "input": return "当前进入 Mac 的直流功率。它与充电器供电能力不同，也不等于墙上插座的交流耗电。遥测字段随硬件和系统版本可能变化。"
        case "system": return "Mac 当前运行消耗的设备侧功率。优先显示负载遥测；由电池或同批数据推导的结果标为估算。它不是 CPU/GPU 功率，也不保证包含所有转换损耗。"
        case "battery": return "正数表示电力充入电池，负数表示电池向外供电。缺少有效功率遥测时，以同次读取的电压 × 电流估算，并保留来源标签。"
        case "adapter": return "系统报告的当前适配器或连接供电档位：\(store.snapshot.adapterWatts.map{String(format:"%.0f W",$0)} ?? "未提供")。\n\n这不是当前实际输入，也不独立证明充电器或线材的铭牌能力。Mac 同时连接多个电源时不把功率相加。"
        default: return "最大容量描述电池当前可存储的电量相对全新状态的比例；剩余电量描述此刻还剩多少。两者含义不同。\n\n健康百分比采用 macOS 系统报告，不使用当前电量推算。100% 不代表电池完全没有老化，循环次数也不是剩余寿命倒计时。"
        }
    }
}
