import SwiftUI
import AppKit
import UserNotifications

// MARK: - 窗口代理 — 拦截关闭，隐藏而非销毁
class AppWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windowDelegates: [NSObject] = []
    var store: TargetStore?
    private let wipeService = WipeService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            for window in NSApp.windows {
                let delegate = AppWindowDelegate()
                self.windowDelegates.append(delegate)
                window.delegate = delegate
                window.isReleasedWhenClosed = false
            }
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "key.icloud", accessibilityDescription: "AIKeyWipe")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示主界面", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "清除所有", action: #selector(wipeAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func wipeAll() {
        guard let store = store, !store.targets.isEmpty else {
            showNotification(title: "AIKeyWipe", body: "列表为空，没有需要清除的内容")
            return
        }

        let targetsToWipe = store.targets.filter(\.enabled)
        guard !targetsToWipe.isEmpty else {
            showNotification(title: "AIKeyWipe", body: "所有目标已禁用")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let results = self.wipeService.executeWipe(on: targetsToWipe, backup: false) { _, _ in }

            let success = results.filter { r in
                if case .success = r.status { return true }
                return false
            }.count
            let failed = results.filter { r in
                if case .failed = r.status { return true }
                return false
            }.count

            DispatchQueue.main.async {
                self.showNotification(
                    title: "清除完成",
                    body: "成功: \(success) 个，失败: \(failed) 个，共 \(results.count) 个目标"
                )
                // 清除成功的目标从列表中移除
                let successIds = results.compactMap { r in
                    if case .success = r.status { return r.targetId }
                    return nil
                }
                for id in successIds {
                    if let target = store.targets.first(where: { $0.id == id }) {
                        store.remove(target)
                    }
                }
            }
        }
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - SwiftUI App Entry
@main
struct AIKeyWipeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = TargetStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 640, minHeight: 480)
                .onAppear {
                    // 传递 store 给 AppDelegate，供菜单栏"清除所有"使用
                    appDelegate.store = store
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
    }
}
