import AppKit
import SwiftUI
import UpdateCore

struct SoftwareUpdatePanel: View {
    @ObservedObject var updater: UpdateStore
    @ViewState private var openError: String?

    private var checking: Bool { updater.state == .checking }
    private var installing: Bool { updater.installationState.isBusy }
    var body: some View {
        VStack(alignment:.leading, spacing:18) {
            VStack(alignment:.leading, spacing:9) {
                Text("软件更新").font(.system(size:17,weight:.semibold))
                Text("当前版本 \(updater.currentVersion)").font(.system(size:12)).foregroundStyle(Palette.secondary)
            }
            VStack(alignment:.leading, spacing:12) {
                status
                if let date = updater.lastChecked {
                    Text("上次成功检查：\(date.formatted(date:.abbreviated,time:.shortened))")
                        .font(.system(size:10)).foregroundStyle(Palette.secondary)
                }
                HStack(spacing:12) {
                    Button(checking ? "正在检查…" : "检查更新") { openError = nil; updater.check() }
                        .disabled(checking || installing)
                    Button("所有发布版本 ↗") { open(ReleaseClient.releasesURL) }.disabled(installing)
                }.controlSize(.large)
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                .background(Palette.secondarySurface,in:RoundedRectangle(cornerRadius:9))

            Toggle("自动检查更新",isOn:$updater.automaticChecks).font(.system(size:12)).disabled(installing)
            Text("开启后每天检查一次，结果显示在这里和菜单栏右键菜单中。").font(.system(size:11)).foregroundStyle(Palette.secondary)
            Toggle("包含预览版",isOn:$updater.includingPreviews).font(.system(size:12)).disabled(checking || installing)
            Text("MacPower 目前以预览版发布；关闭后只检查正式版。").font(.system(size:11)).foregroundStyle(Palette.secondary)
            Divider().overlay(Palette.line)
            Text("点击“更新”后会自动下载、校验并安装，完成后重新启动 MacPower，本地历史和设置会保留。检查与下载连接 GitHub，不发送功率记录或硬件标识。")
                .font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(4)
            if case .failed(let message) = updater.installationState {
                Label("更新未完成",systemImage:"exclamationmark.triangle").font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.warning)
                Text(message).font(.system(size:11)).foregroundStyle(Palette.secondary).lineSpacing(4)
            }
            if let openError { Text(openError).font(.system(size:11)).foregroundStyle(Palette.warning) }
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            Label("查看是否有新版本",systemImage:"arrow.down.circle").font(.system(size:13,weight:.semibold))
        case .checking:
            HStack(spacing:10) { ProgressView().controlSize(.small);Text("正在连接 GitHub…").font(.system(size:13)) }
        case .noReleases:
            Label("暂无可用\(updater.includingPreviews ? "" : "正式")版本",systemImage:"info.circle").font(.system(size:13,weight:.semibold))
        case .upToDate(let release):
            Label("当前没有更新版本",systemImage:"checkmark.circle").font(.system(size:13,weight:.semibold)).foregroundStyle(Palette.teal)
            Text("发布版本：\(release.version.number)\(release.isPrerelease ? " · 预览版" : "")").font(.system(size:11)).foregroundStyle(Palette.secondary)
        case .available(let release):
            Label("发现新版本 \(release.version.number)\(release.isPrerelease ? " · 预览版" : "")",systemImage:"arrow.down.circle.fill")
                .font(.system(size:13,weight:.semibold)).foregroundStyle(Palette.blue)
            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes).font(.system(size:11)).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                }.frame(maxHeight:130)
            }
            HStack(spacing:12) {
                if release.downloadURL != nil && !installing {
                    Button("更新") { updater.installUpdate() }.buttonStyle(.borderedProminent).tint(Palette.blue)
                }
                Button("发行说明 ↗") { open(release.pageURL) }.disabled(installing)
            }.controlSize(.large)
            if installing {
                HStack(spacing:10) {
                    ProgressView().controlSize(.small)
                    Text(installationTitle).font(.system(size:12,weight:.semibold))
                }.foregroundStyle(Palette.blue)
            }
            if release.downloadURL == nil {
                Text("此版本未提供当前架构的安装包，请在发行说明中查看支持范围。").font(.system(size:11)).foregroundStyle(Palette.warning)
            }
        case .failed(let message):
            Label("暂时无法检查更新",systemImage:"exclamationmark.triangle").font(.system(size:13,weight:.semibold)).foregroundStyle(Palette.warning)
            Text(message).font(.system(size:11)).lineSpacing(4).textSelection(.enabled)
        }
    }

    private func open(_ url: URL) {
        openError = NSWorkspace.shared.open(url) ? nil : "无法打开浏览器，请稍后重试。"
    }

    private var installationTitle: String {
        switch updater.installationState {
        case .downloading: return "正在下载更新…"
        case .verifying: return "正在校验更新…"
        case .restarting: return "正在安装并重新启动…"
        default: return ""
        }
    }
}
