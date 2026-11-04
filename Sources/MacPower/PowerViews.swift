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

enum PowerPanelLayout {
    static let size = NSSize(width:320,height:620)
}

extension EnergyMode {
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
    @ViewState<TrendKind> private var trendKind: TrendKind = .level
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Image(systemName:"bolt.fill").font(.system(size:16,weight:.bold)).foregroundStyle(.white)
                    .frame(width:24,height:24).background(Palette.blue,in:RoundedRectangle(cornerRadius:6))
                Text("MacPower").font(.system(size:16,weight:.bold))
                Spacer()
                Button { store.showSettings?() } label: { Image(systemName:"gearshape.fill").font(.system(size:16)).frame(width:24,height:24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("打开设置").accessibilityLabel("打开设置")
            }.padding(.bottom,6)
            HStack(spacing:5) {
                Circle().fill(store.isStale ? Palette.warning : Palette.teal).frame(width:5,height:5)
                Text(store.isStale ? "等待有效数据" : "本机实时数据").font(.system(size:11))
                Spacer()
                Text(store.snapshot.timestamp,style:.time).font(.system(size:10)).monospacedDigit()
            }.foregroundStyle(Palette.secondary).padding(.bottom,8)
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
                    case .live: LivePanel(store:store,onTrends:{trendKind = .power; page = .trends},onLevelTrends:{trendKind = .level; page = .trends},onHealth:{page = .health})
                    case .trends: HistoryPanel(store:store,kind:trendKind)
                    case .health: HealthPanel(store:store)
                    }
                }.frame(maxWidth:.infinity)
            }.scrollIndicators(.automatic)
        }.padding(.horizontal,16).padding(.vertical,14).frame(width:PowerPanelLayout.size.width).frame(maxHeight:.infinity)
            .background(Palette.surface).foregroundStyle(Palette.text)
    }
}

struct LivePanel: View {
    @ObservedObject var store: AppStore
    var onTrends: () -> Void
    var onLevelTrends: () -> Void
    var onHealth: () -> Void
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:6) {
                if store.state == .supplement || store.isStale { Image(systemName:"exclamationmark.circle") }
                Text(store.state.title).font(.system(size:14,weight:.semibold))
                Spacer(minLength:6)
                if store.state.showsEnergyMode {
                    HStack(spacing:4) {
                        Image(systemName:store.energyMode.symbol)
                        Text(store.energyMode.title)
                    }.font(.system(size:11,weight:.medium)).foregroundStyle(store.energyMode.panelColor)
                        .padding(.horizontal,7).padding(.vertical,4)
                        .background(store.energyMode.panelColor.opacity(0.08),in:RoundedRectangle(cornerRadius:6))
                        .fixedSize()
                        .help("能源模式 · \(store.energyMode.title)\n\(store.energyModeSource) · 只读\n系统选择的能源策略，不代表即时性能。")
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel("能源模式 · \(store.energyMode.title)，\(store.energyModeSource)，只读")
                }
            }.foregroundStyle(store.state == .supplement ? Palette.warning : Palette.text).padding(.top,12).padding(.bottom,10)
            if !store.snapshot.hasBattery {
                ContentUnavailableView("未检测到内置电池",systemImage:"battery.0percent",description:Text("当前版本面向 MacBook。若设备有电池，可重新读取。"))
                Button("重新读取") { store.sample() }.padding(.bottom,20)
            } else {
                PowerFlowView(store:store)
                Text(store.isStale ? "最新读数暂不可用" : "\(store.snapshot.input.quality.label) · 点击功率查看来源")
                    .font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.top,6).padding(.bottom,12)
                Divider().overlay(Palette.line)
                BatteryChargeSection(store:store,onOpenTrend:onLevelTrends)
                Divider().overlay(Palette.line)
                Button(action:onTrends) {
                    VStack(alignment:.leading,spacing:6) {
                        HStack {
                            Text("电池功率 · 最近 15 分钟").font(.system(size:11,weight:.medium))
                            Spacer()
                            Image(systemName:"chevron.right").font(.system(size:10))
                        }.foregroundStyle(Palette.secondary)
                        PowerChart(points:store.selectedChartPoints(minutes:15),minutes:15,series:[.battery],endDate:store.chartTimestamp,compact:true)
                            .equatable()
                            .frame(height:54)
                    }.contentShape(Rectangle()).padding(.vertical,12)
                }.buttonStyle(.plain).accessibilityLabel("查看最近 15 分钟电池功率趋势")
                Divider().overlay(Palette.line)
                Button(action:onHealth) {
                    HStack(spacing:10) {
                        Image(systemName:"heart").font(.system(size:21)).foregroundStyle(Palette.secondary)
                        VStack(alignment:.leading,spacing:3) {
                            HStack {
                                Text("电池健康").font(.system(size:12,weight:.semibold))
                                Spacer(minLength:4)
                                Text(store.snapshot.cycleCount.map{"\($0) 次循环"} ?? "循环次数未提供")
                                    .font(.system(size:10)).foregroundStyle(Palette.secondary)
                            }
                            Text(healthSummary).font(.system(size:11)).foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal:false,vertical:true)
                        }
                        Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Palette.secondary)
                    }.contentShape(Rectangle()).padding(.vertical,12)
                }.buttonStyle(.plain)
            }
        }
    }
    private var healthSummary: String {
        let percent = store.health?.maximumCapacity.map{"\($0)%"} ?? "最大容量未提供"
        return "\(percent) · \(store.health?.conditionLabel ?? "正在读取")"
    }

}

struct BatteryChargeSection: View {
    @ObservedObject var store: AppStore
    var onOpenTrend: () -> Void
    private var isFull: Bool { store.state == .full && !store.isStale }
    private var percentLabel: String { store.isStale ? "—" : store.snapshot.percent.map { "\($0)%" } ?? "—" }

    var body: some View {
        VStack(spacing:0) {
            Button(action:onOpenTrend) {
                HStack(spacing:8) {
                    BatteryStateIcon(symbol:store.batterySymbol,isFull:false,size:20)
                        .foregroundStyle(isFull ? Palette.teal : Palette.secondary)
                    Text("电量").font(.system(size:13,weight:.semibold))
                    Text(percentLabel).font(.system(size:20,weight:.semibold)).monospacedDigit()
                    Spacer(minLength:4)
                    if !isFull {
                        Text(chargeLabel).font(.system(size:12)).foregroundStyle(store.state == .supplement ? Palette.warning : Palette.teal)
                    }
                    Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Palette.secondary)
                }.contentShape(Rectangle()).padding(.top,12).padding(.bottom,8)
            }.buttonStyle(.plain).help("查看电量趋势")
                .accessibilityLabel("电量 \(percentLabel)，\(chargeLabel)，查看电量趋势")
            if !store.isStale, let percent = store.snapshot.percent {
                ProgressView(value:Double(percent),total:100).progressViewStyle(BatteryProgressStyle())
                    .accessibilityLabel("电池电量").accessibilityValue("\(percent)%")
            } else {
                Capsule().fill(Palette.line).frame(height:6).accessibilityLabel("电池电量未提供")
            }
            Text(timeLabel).font(.system(size:11)).foregroundStyle(Palette.secondary)
                .frame(maxWidth:.infinity,alignment:.leading).padding(.top,6).padding(.bottom,12)
        }
    }
    private var chargeLabel: String {
        switch store.state { case .charging: return "正在充电"; case .battery,.supplement: return "正在放电"; case .full: return "已充满"; case .idle: return "未充电"; default: return "正在更新" }
    }
    private var timeLabel: String {
        if store.isStale { return "等待新的有效读数" }
        if store.state == .idle { return "系统未提供未充电的原因" }
        if isFull { return "当前由外接电源供电" }
        guard let minutes = store.snapshot.minutesRemaining else { return "剩余时间正在估算" }
        let time = minutes >= 60 ? "\(minutes/60) 小时 \(minutes%60) 分钟" : "\(minutes) 分钟"
        return "\(store.state == .charging ? "预计充满" : "预计可用")约 \(time) · 估算"
    }
}

struct BatteryStateIcon: View {
    var symbol: String
    var isFull: Bool
    var size: CGFloat

    var body: some View {
        Image(systemName:isFull ? "battery.100percent" : symbol)
            .font(.system(size:size,weight:.light))
            .overlay {
                if isFull {
                    Image(systemName:"checkmark")
                        .font(.system(size:size * 0.36,weight:.bold))
                        .offset(x:-size * 0.06)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .accessibilityHidden(true)
    }
}

struct PowerFlowView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing:0) {
            Button { store.showMetric?("input") } label: {
                HStack(spacing:9) {
                    Image(systemName:"powerplug.fill").font(.system(size:30)).rotationEffect(.degrees(-90))
                    VStack(alignment:.leading,spacing:1) {
                        Text("电源输入").font(.system(size:12)).foregroundStyle(Palette.secondary)
                        if store.snapshot.externalConnected == false { Text("未接入").font(.system(size:23,weight:.semibold)) }
                        else { value(store.snapshot.input,fontSize:28) }
                    }
                }.foregroundStyle(Palette.blue)
            }.buttonStyle(.plain).help("查看输入功率来源").accessibilityLabel("电源输入 \(reading(store.snapshot.input)) 瓦，查看说明")
            Button { store.showMetric?("adapter") } label: {
                HStack(spacing:4) {
                    Text(store.snapshot.adapterWatts.map{String(format:"供电能力 %.0f W",$0)} ?? (store.snapshot.externalConnected == false ? "当前由电池供电" : "供电能力未提供"))
                    if store.snapshot.adapterWatts != nil { Text("· 系统报告").foregroundStyle(Palette.blue); Image(systemName:"chevron.right").font(.system(size:9)) }
                }.font(.system(size:11)).foregroundStyle(Palette.secondary)
            }.buttonStyle(.plain).padding(.top,5)
            FlowBranches(charging:store.state != .full && (store.snapshot.battery.value.map { $0 > 0.5 } ?? false),active:!store.isStale && store.snapshot.externalConnected == true)
                .frame(height:store.snapshot.externalConnected == true ? 36 : 16)
                .padding(.horizontal,8)
            HStack(alignment:.top,spacing:0) {
                metric(label:"整机耗电",icon:"laptopcomputer",power:store.snapshot.system,color:Palette.text,key:"system")
                BatteryFlowArrow(active:!store.isStale && (store.snapshot.battery.value.map { $0 < -0.5 } ?? false),supplement:store.state == .supplement)
                    .frame(width:PowerFlowLayout.columnGap,height:PowerFlowLayout.iconHeight)
                metric(label:store.state == .full ? "电池净功率" : store.snapshot.batteryLabel,icon:store.batterySymbol,power:store.snapshot.battery,color:store.state == .supplement ? Palette.warning : Palette.teal,key:"battery")
            }.padding(.horizontal,8)
        }
    }
    private func reading(_ metric: PowerMetric,signed:Bool=false) -> String { store.isStale ? "—" : metric.formatted(signed:signed) }
    private func value(_ metric: PowerMetric,fontSize:CGFloat,signed:Bool=false) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:3) { Text(reading(metric,signed:signed)).font(.system(size:fontSize,weight:.semibold)).monospacedDigit();Text("W").font(.system(size:14,weight:.medium)) }
    }
    private func metric(label:String,icon:String,power:PowerMetric,color:Color,key:String) -> some View {
        Button { store.showMetric?(key) } label: {
            VStack(spacing:4) {
                Group {
                    if key == "battery" {
                        BatteryStateIcon(symbol:icon,isFull:store.state == .full && !store.isStale,size:27)
                    } else {
                        Image(systemName:icon).font(.system(size:27,weight:.light))
                    }
                }.frame(height:PowerFlowLayout.iconHeight).foregroundStyle(key == "system" ? Palette.secondary : color)
                Text(label).font(.system(size:12)).foregroundStyle(Palette.secondary)
                let fullBattery = key == "battery" && store.state == .full && !store.isStale
                value(power,fontSize:24,signed:key == "battery").foregroundStyle(fullBattery ? Palette.text : color)
                if fullBattery {
                    Text(power.quality == .estimated ? "已充满 · 估算" : power.quality == .unavailable ? "已充满 · 未提供" : "已充满")
                        .font(.system(size:11)).foregroundStyle(Palette.secondary)
                } else if power.quality == .estimated {
                    Text("估算").font(.system(size:10)).foregroundStyle(Palette.secondary)
                }
            }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain).frame(maxWidth:.infinity).help("查看\(label)的来源和解释")
            .accessibilityLabel("\(key == "battery" && store.state == .full && !store.isStale ? "电池已充满，电池净功率" : label) \(reading(power,signed:key == "battery")) 瓦，\(power.quality.label)")
    }
}

private enum PowerFlowLayout {
    static let columnGap: CGFloat = 44
    static let iconHeight: CGFloat = 29
}

struct FlowBranches: View {
    var charging: Bool
    var active: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Use the same equal columns and center gap as the metric row below.
            let columnWidth = (w - PowerFlowLayout.columnGap) / 2
            let left = columnWidth / 2
            let right = w - left
            let middle = geo.size.height / 2
            let bottom = geo.size.height - 6
            let radius: CGFloat = 7
            if active {
                Path { p in
                    p.move(to:CGPoint(x:w/2,y:3)); p.addLine(to:CGPoint(x:w/2,y:middle-radius))
                    p.addQuadCurve(to:CGPoint(x:w/2-radius,y:middle),control:CGPoint(x:w/2,y:middle));p.addLine(to:CGPoint(x:left+radius,y:middle))
                    p.addQuadCurve(to:CGPoint(x:left,y:middle+radius),control:CGPoint(x:left,y:middle));p.addLine(to:CGPoint(x:left,y:bottom))
                    if charging {
                        p.move(to:CGPoint(x:w/2,y:middle-radius));p.addQuadCurve(to:CGPoint(x:w/2+radius,y:middle),control:CGPoint(x:w/2,y:middle))
                        p.addLine(to:CGPoint(x:right-radius,y:middle));p.addQuadCurve(to:CGPoint(x:right,y:middle+radius),control:CGPoint(x:right,y:middle));p.addLine(to:CGPoint(x:right,y:bottom))
                    }
                }.stroke(Palette.blue,style:StrokeStyle(lineWidth:1.5,lineCap:.round))
                Image(systemName:"arrowtriangle.down.fill").font(.system(size:8)).foregroundStyle(Palette.blue).position(x:left,y:bottom)
                if charging { Image(systemName:"arrowtriangle.down.fill").font(.system(size:8)).foregroundStyle(Palette.blue).position(x:right,y:bottom) }
            }
        }.accessibilityHidden(true)
    }
}

struct BatteryFlowArrow: View {
    var active: Bool
    var supplement: Bool
    var body: some View {
        ZStack {
            if active {
                HStack(spacing:0) {
                    Image(systemName:"arrowtriangle.left.fill").font(.system(size:8))
                    Capsule().frame(height:1.5)
                }.foregroundStyle(supplement ? Palette.warning : Palette.teal)
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

struct PowerChart: View, Equatable {
    var points: [HistoryPoint]
    var minutes: Int
    var series: Set<ChartSeries>
    var endDate: Date
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
                .chartXScale(domain:endDate.addingTimeInterval(-Double(minutes)*60)...endDate)
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

enum TrendKind: String, CaseIterable { case level = "电量", power = "功率" }

struct TrendToolbar: View {
    @Binding var kind: TrendKind
    @Binding var minutes: Int
    var expanded: Bool
    var canExport: Bool
    var onExport: () -> Void

    private var intervalTitle: String {
        switch minutes {
        case 15: return "15 分钟"
        case 60: return "1 小时"
        default: return "24 小时"
        }
    }

    var body: some View {
        HStack(spacing:8) {
            Menu("\(kind.rawValue)趋势") {
                Picker("趋势指标",selection:$kind) {
                    ForEach(TrendKind.allCases,id:\.self) { Text("\($0.rawValue)趋势").tag($0) }
                }.pickerStyle(.inline)
            }
            .font(.system(size:expanded ? 15 : 13,weight:.semibold))
                .modifier(TrendSelectorChrome())
                .help("切换电量或功率趋势").accessibilityLabel("趋势指标").accessibilityValue(kind.rawValue)
            Spacer(minLength:0)
            Menu {
                Picker("趋势时段",selection:$minutes) {
                    Text("最近 15 分钟").tag(15)
                    Text("最近 1 小时").tag(60)
                    Text("最近 24 小时").tag(1440)
                }.pickerStyle(.inline)
            } label: {
                Label(intervalTitle,systemImage:"clock")
            }
            .font(.system(size:expanded ? 14 : 12,weight:.medium))
                .modifier(TrendSelectorChrome())
                .help("选择趋势时段").accessibilityLabel("趋势时段").accessibilityValue("最近 \(intervalTitle)")
            Button(action:onExport) {
                Image(systemName:"square.and.arrow.up").font(.system(size:15)).frame(width:26,height:26).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Palette.secondary).disabled(!canExport)
                .help("导出当前时段 CSV").accessibilityLabel("导出当前时段 CSV")
        }
    }
}

private struct TrendSelectorChrome: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius:7)
        content.menuStyle(.borderlessButton).menuIndicator(.visible)
            .tint(Palette.secondary)
            .fixedSize()
            .padding(.horizontal,6)
            .frame(height:28)
            .background(Palette.secondarySurface,in:shape)
            .overlay { shape.strokeBorder(Palette.line).allowsHitTesting(false) }
    }
}

struct HistoryPanel: View {
    @ObservedObject var store: AppStore
    var expanded = false
    @ViewState<Int> private var minutes = 15
    @ViewState<Set<ChartSeries>> private var series: Set<ChartSeries> = [.input,.battery]
    @ViewState<TrendKind> private var kind: TrendKind = .level
    init(store: AppStore, expanded: Bool = false, minutes: Int = 15, series: Set<ChartSeries> = [.input,.battery], kind: TrendKind = .level) {
        self.store = store; self.expanded = expanded
        self._minutes = ViewState(initialValue:minutes)
        self._series = ViewState(initialValue:series)
        self._kind = ViewState(initialValue:kind)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:expanded ? 17 : 12) {
            TrendToolbar(kind:$kind,minutes:$minutes,expanded:expanded,canExport:!points.isEmpty) { store.export(minutes:minutes) }
                .padding(.top,12).padding(.bottom,4)
            if kind == .level {
                levelContent
            } else {
            HStack { Text("功率 / W");Spacer();Text("分钟均值") }.font(.system(size:10)).foregroundStyle(Palette.secondary)
            PowerChart(points:points,minutes:minutes,series:series,endDate:store.chartTimestamp).equatable().frame(height:expanded ? 270 : 220)
            HStack(spacing:expanded ? 15 : 10) {
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
            }
            if !store.preferences.recordHistory {
                HStack {
                    Label("历史记录已关闭",systemImage:"pause.circle").foregroundStyle(Palette.warning)
                    Spacer()
                    Button("前往开启") { store.settingsPage = .data; store.showSettings?() }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                }.font(.system(size:11))
            }
            if !expanded { Button { store.showHistory?(minutes,series,kind) } label: { Label("打开完整趋势",systemImage:"arrow.up.right") }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size:12)).padding(.bottom,10) }
        }.foregroundStyle(Palette.text)
    }
    private var points: [HistoryPoint] { store.selectedChartPoints(minutes:minutes) }
    private var levelContent: some View {
        let trend = store.selectedBatteryLevelTrend(minutes:minutes)
        return VStack(alignment:.leading,spacing:expanded ? 17 : 12) {
            HStack { Text("剩余电量 / %");Spacer();Text("每分钟末次读数") }.font(.system(size:10)).foregroundStyle(Palette.secondary)
            BatteryLevelChart(trend:trend,minutes:minutes,endDate:store.chartTimestamp,hasBattery:store.snapshot.hasBattery)
                .equatable().frame(height:expanded ? 270 : 220)
            Divider().overlay(Palette.line)
            HStack {
                levelSummary("首条记录",value:trend.first.map { "\($0.percent)%" } ?? "—")
                Spacer()
                levelSummary("末条记录",value:trend.last.map { "\($0.percent)%" } ?? "—")
                Spacer()
                levelSummary("变化",value:trend.change.map { $0 > 0 ? "+\($0)" : $0 < 0 ? "−\(abs($0))" : "0" } ?? "—",unit:trend.change == nil ? "" : "百分点")
            }
            VStack(alignment:.leading,spacing:5) {
                Text("电量记录覆盖 \(trend.coverage)% · \(trend.records.count) 条有效记录")
                if let first = trend.first, let last = trend.last {
                    Text("\(recordDate(first.sampledAt)) – \(recordDate(last.sampledAt))")
                }
                Text("系统电源信息 · 每分钟末次读数")
                Text("中断与缺失处断线；变化仅为首末读数之差。")
            }.font(.system(size:11)).foregroundStyle(Palette.secondary)
        }
    }
    private func recordDate(_ date:Date) -> String {
        minutes == 1440 ? date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()) : date.formatted(date:.omitted,time:.shortened)
    }
    private func levelSummary(_ title:String,value:String,unit:String = "") -> some View {
        VStack(alignment:.leading,spacing:expanded ? 8 : 5) {
            Text(title).font(.system(size:11)).foregroundStyle(Palette.secondary)
            HStack(alignment:.firstTextBaseline,spacing:3) {
                Text(value).font(.system(size:expanded ? 23 : 21,weight:.semibold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.system(size:10)).foregroundStyle(Palette.secondary) }
            }
        }.accessibilityElement(children:.combine)
    }
    private var coverage: Int { min(100,Int(points.reduce(0){$0+$1.coveredSeconds}/Double(minutes*60)*100)) }
    private func summary(_ title:String,value:String) -> some View { VStack(alignment:.leading,spacing:expanded ? 8 : 5) { Text(title).font(.system(size:11)).foregroundStyle(Palette.secondary);Text(value).font(.system(size:expanded ? 23 : 21,weight:.semibold)).monospacedDigit() } }
}

struct HealthPanel: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { Text("电池健康").font(.system(size:17,weight:.semibold));Spacer();Image(systemName:"heart").font(.system(size:20)).foregroundStyle(healthColor) }.padding(.top,12)
            if let report = store.health, report.hasData {
                VStack(spacing:7) {
                    if report.condition != nil {
                        Text(report.conditionLabel).font(.system(size:11,weight:.medium)).foregroundStyle(healthColor)
                            .padding(.horizontal,10).padding(.vertical,5).background(healthColor.opacity(0.1),in:Capsule())
                    }
                    if let capacity = report.maximumCapacity {
                        HStack(alignment:.firstTextBaseline,spacing:2) {
                            Text("\(capacity)").font(.system(size:46,weight:.semibold))
                            Text("%").font(.system(size:20))
                        }.monospacedDigit()
                        Text("最大容量 · 系统报告").font(.system(size:12)).foregroundStyle(Palette.secondary)
                        Button("了解最大容量") { store.showMetric?("health") }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size:11))
                    } else {
                        Text("系统未提供最大容量").font(.system(size:12)).foregroundStyle(Palette.secondary)
                    }
                }.frame(maxWidth:.infinity).padding(.vertical,20)
                if let cycles = report.cycleCount {
                    row("循环次数",value:"\(cycles) 次")
                    Text("按累计使用电量计算，并非插电次数。").font(.system(size:10)).foregroundStyle(Palette.secondary).padding(.bottom,12)
                }
                Divider().overlay(Palette.line)
                Text("容量变化").font(.system(size:13,weight:.medium)).padding(.top,12)
                if store.healthHistory.count < 2 {
                    Label("积累至少两天记录后显示趋势",systemImage:"chart.xyaxis.line")
                        .font(.system(size:11)).foregroundStyle(Palette.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,20)
                } else {
                    Chart(store.healthHistory,id:\.date) { item in
                        if let value = item.maximumCapacity {
                            LineMark(x:.value("日期",item.date),y:.value("最大容量 %",value),series:.value("来源",item.source)).foregroundStyle(Palette.teal)
                            PointMark(x:.value("日期",item.date),y:.value("最大容量 %",value)).foregroundStyle(Palette.teal)
                        }
                    }.chartYScale(domain:0...100).frame(height:100).padding(.vertical,12)
                }
                Text("\(report.source) · \(report.date.formatted(date:.abbreviated,time:.shortened))")
                    .font(.system(size:10)).foregroundStyle(Palette.secondary).padding(.bottom,12)
            } else {
                VStack(spacing:10) {
                    Image(systemName:"heart.text.square").font(.system(size:32,weight:.light))
                    Text("暂无电池健康数据").font(.system(size:14,weight:.semibold)).foregroundStyle(Palette.text)
                    Text("macOS 暂未提供健康报告。\n可重新读取，或在系统电池设置中查看。")
                        .font(.system(size:11)).multilineTextAlignment(.center).lineSpacing(4)
                }.foregroundStyle(Palette.secondary).frame(maxWidth:.infinity).padding(.vertical,40)
            }
            if let error = store.healthMessage { Text(error).font(.system(size:11)).foregroundStyle(Palette.warning).padding(.bottom,12) }
            Divider().overlay(Palette.line)
            HStack {
                Button { store.refreshHealth() } label: { Label("重新读取",systemImage:"arrow.clockwise").frame(minHeight:28) }
                Spacer()
                Button("系统电池设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.battery")!) }.frame(minHeight:28)
            }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size:11)).padding(.top,8)
        }
    }
    private var healthColor: Color {
        guard let report = store.health, report.hasData else { return Palette.secondary }
        return report.conditionLabel == "建议维修" ? Palette.warning : report.conditionLabel == "正常" ? Palette.teal : Palette.secondary
    }
    private func row(_ title:String,value:String) -> some View { VStack(spacing:0) { Divider().overlay(Palette.line);HStack { Text(title).foregroundStyle(Palette.secondary);Spacer();Text(value).monospacedDigit() }.font(.system(size:12)).padding(.vertical,8) } }
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
