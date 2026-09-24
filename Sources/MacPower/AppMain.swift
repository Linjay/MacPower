import AppKit
import SwiftUI
import Combine
import PowerCore

@main struct MacPowerApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    let store = AppStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var detailWindow: NSWindow?
    private var overviewWindow: NSWindow?
    private var appearanceObserver: NSKeyValueObservation?
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu(title:"MacPower")
        appMenu.addItem(withTitle:"设置…",action:#selector(settingsAction),keyEquivalent:",").target = self
        appMenu.addItem(withTitle:"检查更新…",action:#selector(checkForUpdatesAction),keyEquivalent:"").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"退出 MacPower",action:#selector(quitAction),keyEquivalent:"q").target = self
        appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
        let editItem = NSMenuItem(), editMenu = NSMenu(title:"编辑")
        for (title,action,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("拷贝","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            editMenu.addItem(withTitle:title,action:Selector(action),keyEquivalent:key)
        }
        editItem.submenu = editMenu; menu.addItem(editItem)
        let windowItem = NSMenuItem(), windowMenu = NSMenu(title:"窗口")
        windowMenu.addItem(withTitle:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        windowMenu.addItem(withTitle:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowItem.submenu = windowMenu; menu.addItem(windowItem); NSApp.windowsMenu = windowMenu
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePopover)
            button.sendAction(on:[.leftMouseUp,.rightMouseUp])
            button.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = NSSize(width:416,height:780)
        store.onUpdate = { [weak self] in self?.updateAppearance(); self?.updateStatus() }
        store.showSettings = { [weak self] in self?.openSettings() }
        store.showOverview = { [weak self] in self?.openOverview() }
        store.showHistory = { [weak self] minutes, series in self?.openHistory(minutes:minutes,series:series) }
        store.showMetric = { [weak self] key in self?.openMetric(key) }
        store.quit = { NSApp.terminate(nil) }
        appearanceObserver = NSApp.observe(\.effectiveAppearance,options:[.new]) { [weak self] _,_ in
            Task { @MainActor in self?.updateStatus() }
        }
        updateAppearance(); updateStatus(); store.start()
        store.updater.checkIfDue()
        updateTimer = Timer.scheduledTimer(withTimeInterval:3600,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.store.updater.checkIfDue() }
        }
        updateTimer?.tolerance = 300
        // Opening the app gives an immediately discoverable panel; closing it leaves only the status item.
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in
            guard let self,
                  ![self.settingsWindow,self.historyWindow,self.detailWindow,self.overviewWindow].compactMap({$0}).contains(where:{$0.isVisible}) else { return }
            self.showPopover()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { updateTimer?.invalidate(); store.updater.cancel(); store.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder's Open operation offers a stable window even when menu extras are hidden or crowded.
        openOverview()
        return true
    }
    private func updateAppearance() {
        let appearance: NSAppearance?
        switch store.preferences.appearance {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named:.aqua)
        case .dark: appearance = NSAppearance(named:.darkAqua)
        }
        // A manual app appearance does not change the system menu bar; its icon remains a template.
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
        popover.appearance = appearance
        for window in [settingsWindow,historyWindow,detailWindow,overviewWindow].compactMap({$0}) { window.appearance = appearance }
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let icon = NSImage(systemSymbolName:store.batterySymbol,accessibilityDescription:nil); icon?.isTemplate = true
        icon?.size = NSSize(width:18,height:10)
        button.image = icon
        let extra = store.preferences.showPercent && store.preferences.menuMetric != .percent ? store.snapshot.percent.map { " \($0)%" } ?? "" : ""
        let compactText = store.menuText.replacingOccurrences(of:" W",with:"W") + extra
        let color = store.state.showsEnergyMode ? store.energyMode.menuColor : NSColor.labelColor
        button.attributedTitle = NSAttributedString(string:compactText,attributes:[
            .font: NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium), .foregroundColor: color
        ])
        statusItem.length = NSStatusItem.variableLength
        let mode = store.state.showsEnergyMode ? "，能源模式：\(store.energyMode.title)（\(store.energyModeSource)）" : ""
        let description = "\(store.preferences.menuMetric.title) \(store.menuText)，\(store.state.title)\(mode)"
        button.toolTip = "MacPower · \(description)\n更新于 \(store.snapshot.timestamp.formatted(date:.omitted,time:.standard))"
        button.setAccessibilityLabel("MacPower，\(description)")
    }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle:"打开 MacPower",action:#selector(showPopoverAction),keyEquivalent:"").target = self
            menu.addItem(withTitle:"在窗口中打开",action:#selector(overviewAction),keyEquivalent:"").target = self
            menu.addItem(withTitle:"设置…",action:#selector(settingsAction),keyEquivalent:",").target = self
            let updateTitle: String
            if case .available(let release) = store.updater.state { updateTitle = "发现新版本 \(release.version.number)…" }
            else { updateTitle = "检查更新…" }
            menu.addItem(withTitle:updateTitle,action:#selector(checkForUpdatesAction),keyEquivalent:"").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle:"退出 MacPower",action:#selector(quitAction),keyEquivalent:"q").target = self
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    @objc private func showPopoverAction() { showPopover() }
    @objc private func settingsAction() { openSettings() }
    @objc private func checkForUpdatesAction() {
        store.settingsPage = .updates
        openSettings()
        // Keep an already discovered release visible when opening the update entry.
        if case .available = store.updater.state { return }
        store.updater.check()
    }
    @objc private func overviewAction() { openOverview() }
    @objc private func quitAction() { NSApp.terminate(nil) }
    private func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        if popover.contentViewController == nil {
            let panel = NSHostingController(rootView:PowerPanel(store:store))
            // ScrollView's intrinsic height changes between tabs. AppKit owns these fixed-size surfaces.
            panel.sizingOptions = []
            popover.contentViewController = panel
        }
        NSApp.activate(ignoringOtherApps:true)
        let available = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        popover.contentSize = NSSize(width:416,height:min(780,max(500,available-50)))
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        popover.contentViewController?.view.window?.makeKey()
        updateSamplingVisibility()
    }
    func popoverDidClose(_ notification: Notification) {
        // Hidden charts must not keep observing every sample or retain their rendering resources.
        if !popover.isShown { popover.contentViewController = nil }
        updateSamplingVisibility()
    }
    private func makeWindow(title: String, size: NSSize, root: some View) -> NSWindow {
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = title; window.isReleasedWhenClosed = false; window.delegate = self
        let hosting = NSHostingController(rootView:root.frame(width:size.width,height:size.height))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.center(); return window
    }
    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil { settingsWindow = makeWindow(title:"MacPower 设置",size:NSSize(width:690,height:570),root:SettingsPanel(store:store)) }
        activate(settingsWindow!)
    }
    private func openOverview() {
        popover.performClose(nil)
        if overviewWindow == nil {
            overviewWindow = makeWindow(title:"MacPower 电源概览",size:NSSize(width:416,height:780),root:PowerPanel(store:store))
        }
        activate(overviewWindow!)
    }
    private func openHistory(minutes: Int, series: Set<ChartSeries>) {
        popover.performClose(nil)
        historyWindow?.close()
        historyWindow = makeWindow(title:"MacPower 功率趋势",size:NSSize(width:800,height:650),root:HistoryPanel(store:store,expanded:true,minutes:minutes,series:series).padding(26).background(Palette.surface))
        activate(historyWindow!)
    }
    private func openMetric(_ key: String) {
        popover.performClose(nil)
        if let detailWindow { detailWindow.close() }
        detailWindow = makeWindow(title:"MacPower · 指标说明",size:NSSize(width:420,height:360),root:MetricDetail(store:store,kind:key))
        activate(detailWindow!)
    }
    private func activate(_ window: NSWindow) {
        updateAppearance(); NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil); updateSamplingVisibility()
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.settingsWindow === closing { self.settingsWindow = nil }
            if self.historyWindow === closing { self.historyWindow = nil }
            if self.detailWindow === closing { self.detailWindow = nil }
            if self.overviewWindow === closing { self.overviewWindow = nil }
            closing.contentViewController = nil
            self.updateSamplingVisibility()
        }
    }
    private func updateSamplingVisibility() {
        store.setVisible(popover.isShown || [settingsWindow,historyWindow,detailWindow,overviewWindow].compactMap({$0}).contains(where:{$0.isVisible}))
    }
}
