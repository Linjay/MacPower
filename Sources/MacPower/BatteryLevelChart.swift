import SwiftUI
import Charts
import PowerCore

struct BatteryLevelChart: View, Equatable {
    var trend: BatteryLevelTrend
    var minutes: Int
    var endDate: Date
    var hasBattery: Bool
    @ViewState<Date?> private var selectedDate: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.trend == rhs.trend && lhs.minutes == rhs.minutes && lhs.endDate == rhs.endDate && lhs.hasBattery == rhs.hasBattery
    }
    private var selected: BatteryLevelRecord? { selectedDate.flatMap { trend.nearest(to:$0) } }
    var body: some View {
        if trend.records.isEmpty {
            VStack(spacing:8) {
                Image(systemName:"chart.xyaxis.line").font(.system(size:28))
                Text(hasBattery ? "还没有电量记录" : "未检测到内置电池").font(.system(size:13,weight:.medium))
                Text(hasBattery ? "从本次运行开始积累，旧功率记录不含电量。" : "电量曲线需要 Mac 的内置电池数据。")
                    .font(.system(size:11)).multilineTextAlignment(.center)
            }.foregroundStyle(Palette.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
        } else {
            VStack(alignment:.leading,spacing:9) {
                HStack(spacing:6) {
                    if let selected {
                        Text(selected.sampledAt.formatted(date:.omitted,time:.standard))
                        Text("\(selected.percent)%").fontWeight(.semibold).foregroundStyle(Palette.teal)
                    } else {
                        Text(trend.records.count == 1 ? "已记录一个读数，等待更多记录" : "悬停或拖动查看电量")
                    }
                }.font(.system(size:11)).monospacedDigit().foregroundStyle(Palette.secondary).frame(height:16)
                    .accessibilityElement(children:.combine)
                let counts = Dictionary(grouping:trend.records,by:\.segment).mapValues(\.count)
                Chart {
                    ForEach(trend.records) { record in
                        LineMark(x:.value("时间",record.sampledAt),y:.value("电量 %",record.percent),series:.value("记录段",record.segment.uuidString))
                            .foregroundStyle(Palette.teal).lineStyle(StrokeStyle(lineWidth:2)).interpolationMethod(.linear)
                        if counts[record.segment] == 1 {
                            PointMark(x:.value("时间",record.sampledAt),y:.value("电量 %",record.percent)).foregroundStyle(Palette.teal).symbolSize(22)
                        }
                    }
                    if let selected {
                        RuleMark(x:.value("查看时间",selected.sampledAt)).foregroundStyle(Palette.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth:1,dash:[3,3]))
                        PointMark(x:.value("时间",selected.sampledAt),y:.value("电量 %",selected.percent)).foregroundStyle(Palette.teal).symbolSize(38)
                    }
                }.chartLegend(.hidden).chartYScale(domain:0...100,range:.plotDimension(padding:5))
                    .chartXScale(domain:endDate.addingTimeInterval(-Double(minutes)*60)...endDate)
                    .chartXAxis { AxisMarks(values:.automatic(desiredCount:4)) { _ in
                        AxisValueLabel(format:.dateTime.hour().minute()).font(.system(size:9))
                    } }
                    .chartYAxis { AxisMarks(position:.trailing,values:[0,25,50,75,100]) { value in
                        AxisGridLine().foregroundStyle(Palette.line.opacity(0.7))
                        AxisValueLabel { if let percent = value.as(Int.self) { Text("\(percent)%").font(.system(size:9)) } }
                    } }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location): select(at:location,proxy:proxy,geometry:geometry)
                                    case .ended: selectedDate = nil
                                    }
                                }
                                .gesture(DragGesture(minimumDistance:0).onChanged { select(at:$0.location,proxy:proxy,geometry:geometry) })
                        }
                    }
                    .accessibilityLabel("电池剩余电量趋势，\(trend.records.count) 条实际记录，纵轴零至百分之一百，中断处断线")
            }
        }
    }
    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { selectedDate = nil; return }
        let frame = geometry[anchor]
        guard frame.contains(location) else { selectedDate = nil; return }
        selectedDate = proxy.value(atX:location.x-frame.minX,as:Date.self)
    }
}
