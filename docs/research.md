# GitHub 调研与数据可行性

调研日期：2026-09-23。证据分为项目 README、已读取源码、本机观察和产品推论；未安装或运行第三方程序。

## 判断

已经存在相似开源工具，MacPower 无需重新发明采集方式。可借鉴 Powerflow 的电力主题、Stats 的采集组织、WhatWatt 的指标解释与 WattMeter 的极简入口。产品差异应是**功率含义清楚、状态完整、缺失时诚实、日常查看轻量**。

建议自主组织一个小型 SwiftUI/AppKit 产品，先验证数据契约，再选择性复用代码。仓库许可证与可维护性需要针对最终选用的提交再核对；本轮没有复制第三方实现进产品。

## 参考项目

| 项目 | 本次确认的能力与技术 | 可借鉴的部分 | 需要区别对待的部分 |
|---|---|---|---|
| [Powerflow](https://github.com/lzt1008/powerflow) | README 描述实时功率与充电历史；目录包含 Vue 前端、Tauri 与 Rust tpower；MIT | 功率为中心的信息架构、历史查看 | 本轮未运行；不能由 README 推定所有硬件均支持 |
| [Stats](https://github.com/exelban/stats) | macOS 菜单栏系统监测；已读 Battery/readers.swift；MIT | 原生菜单栏、事件触发采样、电池与适配器分开读 | 监测范围远大于本项目，首版不引入 CPU/风扇等全套模块 |
| [ChargeWatch](https://github.com/TY-teo/ChargeWatching) | README 描述 SwiftUI 功率监测、历史、充电上限；MIT；已查看仓库浅色截图 | 三路功率并列、中文界面、历史入口 | 充电控制不属于本次首版；“墙插输出”的命名不能直接沿用到 Mac 端遥测 |
| [WhatWatt](https://github.com/SomeInterestingUserName/WhatWatt) | README 明确说它报告系统请求的供电模式，不等同实际测量；MIT | 克制的菜单栏入口、供电能力说明 | 不能单靠该数据获得电池充放电或整机实时功率 |
| [WattMeter](https://github.com/ilikeafrica/wattmeter) | 已读 main.swift：IORegistry 取输入功率、电压电流，派生系统耗电；MIT | 单个菜单栏入口、缺少输入时显示不可用 | 源码把缺失电压/电流默认成 0，并混合不同来源计算；MacPower 应显式建模缺失与时间一致性 |

以上为本次读取时的项目状态，不以 Star 数或宣传语推定准确性、稳定性或安全性。

## 源码提供的具体启发

[Stats 的电池采集代码](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift) 同时使用电源变化通知、IOPowerSources、IORegistry 与 SMC；区分适配器报告功率和电池功率。这为“事件补采 + 周期采样”提供了实现参考。其容量字段也存在架构相关分支，因此不能把所有名为 MaxCapacity 的值一律当作 mAh。

[WattMeter 的 main.swift](https://github.com/ilikeafrica/wattmeter/blob/main/main.swift) 使用 `PowerTelemetryData.SystemPowerIn / 1000` 得到输入瓦数，再以电池电压 × 电流计算净功率。代码展示了最小可行路径，也暴露出应改进的地方：零值与缺失要分开；派生差值应带来源和质量标记；不应将负的计算结果简单裁成 0 后作为可信读数。

上述是源码观察，不代表已验证其产品精度。`PowerTelemetryData` 各键不是可假设跨机器稳定的公开契约，需按机型与系统版本实测。

## 本机只读核对

本次读取确认设备为 MacBook Pro，Mac16,8，Apple M4 Pro，48 GB。没有修改系统设置，也没有安装采集程序。

| 数据 | 会话中读到的示例 | 证据含义 |
|---|---:|---|
| 系统报告供电能力 | 65 W | AdapterDetails.Watts；不是充电器铭牌的独立识别结果 |
| 外接电源 / 正在充电 | 是 / 是 | 当次状态标志 |
| 电量 | 65% | 当次系统报告 |
| 最大容量 / 电池状况 | 100% / Good | 系统信息报告；不表示电池没有老化 |
| 循环次数 | 144 | 系统信息与电池字段一致 |
| SystemPowerIn | 61,605 mW | 在该次遥测字典中可读；约 61.6 W |
| BatteryPower | 27,639 mW | 同一字典字段；符号和其他供电状态仍待验证 |
| SystemLoad | 33,966 mW | 同一字典字段；需确认测量边界 |
| Voltage × Amperage | 12.345 V × 2.655 A ≈ 32.78 W | 与 BatteryPower 不同，不能混当同一时刻同一口径 |

该次遥测满足 61.605 = 27.639 + 33.966，但一个相等样本不能证明所有工况下严格守恒或三个字段都是独立测量。系统、适配器和电池的读取也不是统一原子快照。

本机此次顶层字段没有提供可直接使用的 Temperature、DesignCapacity、AppleRawMaxCapacity。产品必须允许温度和原始容量缺失；健康度仍可显示系统报告结果。

视觉图沿用上述量级并取一位小数，统一标注“示例数据”。图中的历史曲线和充满时间是交互展示样例，不是本机历史测量。

### 验证范围

已证实：此机在当前插电充电状态下可读取核心遥测与系统健康信息。

尚未证实：拔电、暂停充电、满电、外接低功率电源、双路接入、睡眠唤醒、Intel、其他 Apple Silicon 机型的行为；没有 USB 功率表对照；没有测量监测程序本身的能耗。

因此不能将这份结果称为全机型兼容或功率精度验证完成。

## Apple 原始资料

- [IOPSCopyExternalPowerAdapterDetails](https://developer.apple.com/documentation/iokit/1523866-iopscopyexternalpoweradapterdeta)：描述接入的外部电源，无适配器或发生错误时可能返回空值。空值本身不足以判断“已拔电”。
- [IOPowerSources.h](https://developer.apple.com/documentation/iokit/iopowersources_h?changes=_4)：电源状态与变化通知的公开接口入口，实施时以当前 SDK 头文件核验。
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)：SwiftUI 菜单栏入口；复杂弹层也可采用 NSStatusItem + NSPopover。
- [给 Mac 笔记本充电](https://support.apple.com/en-gb/102397)：Mac 同时只通过一个端口充电，不把 MagSafe 与 USB-C 的功率相加。
- [电池循环次数](https://support.apple.com/en-us/102888)：循环按累计使用电量计算，不等同插拔次数；循环上限与机型有关。

## 技术方向

推荐 Swift + SwiftUI，必要处用 AppKit 管理菜单栏与独立窗口。以 IOPowerSources 处理公开的电源状态与通知；以能力探测方式补充 IORegistry 遥测。首版不要求管理员权限，也不把高频调用 system_profiler 或 powermetrics 作为常驻采集方案。

健康度的低频系统报告读取需独立于实时功率通道。若原生接口取不到与系统一致的健康字段，可验证低频系统报告方案；执行时间、沙盒和分发约束须在技术验证中记录，不承诺已适配 Mac App Store。

SMC 为可选研究方向，首版核心价值不能依赖安装特权辅助程序。分发暂按签名、公证的独立应用设计；App Store 可行性另行核验。
