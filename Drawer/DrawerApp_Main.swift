// DrawerApp_Main.swift
// Point d'entrée principal de l'application

import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Main App
@main
struct DrawerApp: App {
    @NSApplicationDelegateAdaptor(DrawerAppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
class DrawerAppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var preferencesWindow: NSWindow?
    var drawerManager: DrawerManager?
    var triggerMonitor: Any?
    var showDelayTimer: Timer?
    private var wasInTriggerZone = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Mode accessoire (pas dans le Dock)
        NSApp.setActivationPolicy(.accessory)
        
        // Configurer le lancement au démarrage si activé
        configureLaunchAtLoginIfNeeded()
        
        // ✅ AJOUTER CET OBSERVER
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarIconToggle(_:)),
            name: NSNotification.Name("MenuBarIconToggled"),
            object: nil
        )
        
        // Initialiser le drawer manager
        Task { @MainActor in
            drawerManager = DrawerManager.shared
            
            // Lire la préférence et créer l'icône si true
            if UserDefaults.standard.bool(forKey: "menuBarIcon") {
                setupStatusBar()
            }
            
            setupTriggerZone()
        }
    }
    
    @objc private func showDrawer() {
        Task { @MainActor in
            drawerManager?.showDrawer()
        }
    }
    
    @objc private func handleMenuBarIconToggle(_ notification: Notification) {
        if let enabled = notification.userInfo?["enabled"] as? Bool {
            if enabled {
                setupStatusBar()
            } else {
                if let item = statusBarItem {
                    NSStatusBar.system.removeStatusItem(item)
                    statusBarItem = nil
                }
            }
        }
    }
    
    // MARK: - Launch at Login
    private func configureLaunchAtLoginIfNeeded() {
        let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        
        if #available(macOS 13.0, *) {
            // D'ABORD nettoyer les doublons existants
            cleanupLoginItemDuplicates()
            
            // ENSUITE configurer proprement
            if launchAtLogin {
                // Vérifier le statut actuel
                let status = SMAppService.mainApp.status
                
                // Ne l'ajouter QUE si elle n'est pas déjà activée
                if status != .enabled {
                    do {
                        try SMAppService.mainApp.register()
                    } catch {
                        print("Failed to enable launch at login: \(error)")
                    }
                }
            } else {
                // Si désactivé, s'assurer qu'elle est bien retirée
                do {
                    try SMAppService.mainApp.unregister()
                } catch {
                    // Ignorer l'erreur si déjà non enregistrée
                }
            }
        }
    }

    // Nouvelle fonction pour nettoyer les doublons
    private func cleanupLoginItemDuplicates() {
        if #available(macOS 13.0, *) {
            // Désactiver complètement d'abord
            try? SMAppService.mainApp.unregister()
            
            // Petite pause pour laisser le système se mettre à jour
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        
        if #available(macOS 13.0, *) {
            // TOUJOURS désactiver d'abord pour éviter les doublons
            try? SMAppService.mainApp.unregister()
            
            if enabled {
                do {
                    // Petite pause avant de réactiver
                    Thread.sleep(forTimeInterval: 0.1)
                    try SMAppService.mainApp.register()
                } catch {
                    print("Failed to enable launch at login: \(error)")
                }
            }
        }
    }
    
    // MARK: - Status Bar
    func setupStatusBar() {
        // Supprimer l'ancienne si elle existe
        if let existingItem = statusBarItem {
            NSStatusBar.system.removeStatusItem(existingItem)
            statusBarItem = nil
        }
        
        // Créer la nouvelle
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            button.image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                NSColor.labelColor.setFill()
                
                // Barre du haut
                let handleRect = NSRect(x: rect.minX + 1, y: rect.maxY - 5, width: rect.width - 2, height: 2)
                NSBezierPath(roundedRect: handleRect, xRadius: 0, yRadius: 0).fill()
                
                // Corps du drawer
                let drawerRect = NSRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: 11)
                NSBezierPath(roundedRect: drawerRect, xRadius: 1, yRadius: 2).fill()
                
                // Intérieur avec transparence pour simuler le noir
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                let cutoutRect = NSRect(x: rect.minX + 3, y: rect.minY + 3, width: rect.width - 6.5, height: 7)
                NSBezierPath(roundedRect: cutoutRect, xRadius: 0, yRadius: 0).fill()
                NSGraphicsContext.restoreGraphicsState()
                
                // Poignée du tiroir (restera visible car dessinée après)
                NSColor.labelColor.setFill()
                let notchRect = NSRect(x: rect.midX - 4, y: rect.minY + 6, width: 8, height: 2)
                NSBezierPath(roundedRect: notchRect, xRadius: 1, yRadius: 1).fill()
                
                return true
            }
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 200
        
        let openItem = NSMenuItem(title: "Open the drawer", action: #selector(showDrawer), keyEquivalent: "o")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Menu pour changer de mode
        let modeMenu = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let singleViewItem = NSMenuItem(title: "Simple View", action: #selector(setSingleView), keyEquivalent: "1")
        singleViewItem.target = self
        submenu.addItem(singleViewItem)
        
        let doubleViewItem = NSMenuItem(title: "Double View", action: #selector(setDoubleView), keyEquivalent: "2")
        doubleViewItem.target = self
        submenu.addItem(doubleViewItem)
        
        modeMenu.submenu = submenu
        menu.addItem(modeMenu)
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.isEnabled = true
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Option de lancement au démarrage
        if #available(macOS 13.0, *) {
            let launchAtLoginItem = NSMenuItem(
                title: "Launch at startup",
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            launchAtLoginItem.target = self
            launchAtLoginItem.state = UserDefaults.standard.bool(forKey: "launchAtLogin") ? .on : .off
            menu.addItem(launchAtLoginItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        
        menu.update()
        statusBarItem?.menu = menu
    }
    
    @objc private func setSingleView() {
        Task { @MainActor in
            drawerManager?.setDisplayMode(.single)
        }
    }
    
    @objc private func setDoubleView() {
        Task { @MainActor in
            drawerManager?.setDisplayMode(.double)
        }
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = sender.state != .on
        sender.state = newState ? .on : .off
        DrawerAppDelegate.setLaunchAtLogin(newState)
    }
    
    // MARK: - Trigger Zone
    func setupTriggerZone() {
        // Ne PAS réinitialiser si les préférences sont ouvertes
        if preferencesWindow?.isVisible == true {
            return
        }
        
        if let oldMonitor = triggerMonitor {
            NSEvent.removeMonitor(oldMonitor)
            triggerMonitor = nil
        }
        
        wasInTriggerZone = false
        showDelayTimer?.invalidate()
        showDelayTimer = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupNewMonitor()
        }
    }
    
    private func setupNewMonitor() {
        let triggerMode = UserDefaults.standard.string(forKey: "triggerMode") ?? "click"
        
        switch triggerMode {
        case "click":
            triggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self = self else { return }
                
                let location = NSEvent.mouseLocation
                if self.isInTriggerZone(location) {
                    self.triggerDrawer()
                }
            }
            
        case "scroll":
            triggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self = self else { return }
                
                let location = NSEvent.mouseLocation
                if event.deltaY > 0 && self.isInTriggerZone(location) {
                    self.triggerDrawer()
                }
            }
            
        case "hover":
            self.wasInTriggerZone = false
            
            triggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                guard let self = self else { return }
                
                let location = NSEvent.mouseLocation
                let isInZone = self.isInTriggerZone(location)
                
                if isInZone && !self.wasInTriggerZone {
                    self.triggerDrawer()
                }
                
                self.wasInTriggerZone = isInZone
            }
            
        default:
            break
        }
    }
    
    private func triggerDrawer() {
        showDelayTimer?.invalidate()
        
        Task { @MainActor in
            guard let manager = self.drawerManager else { return }
            
            // Simple : ouvrir si fermé
            if manager.isDrawerVisible {
                return
            }
            
            let showDelay = UserDefaults.standard.double(forKey: "showDelay")
            let delay = showDelay > 0 ? showDelay : 0.01
            
            if delay < 0.05 {
                manager.showDrawer()
            } else {
                self.showDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                    Task { @MainActor in
                        if !manager.isDrawerVisible {
                            manager.showDrawer()
                        }
                    }
                }
            }
        }
    }
    
    private func isInTriggerZone(_ location: NSPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        let triggerZoneHeight: Double = 25.0  // Toujours 25 pixels
        let triggerZoneWidth = UserDefaults.standard.double(forKey: "triggerZoneWidth")
        
        let effectiveWidth = triggerZoneWidth > 0 ? triggerZoneWidth / 100.0 : 0.1
        
        let zoneWidthPixels = screen.frame.width * effectiveWidth
        let zoneX = (screen.frame.width - zoneWidthPixels) / 2
        
        let triggerZone = NSRect(
            x: zoneX,
            y: screen.frame.maxY - triggerZoneHeight - 1,
            width: zoneWidthPixels,
            height: triggerZoneHeight + 2
        )
        
        return triggerZone.contains(location)
    }
    
    func updateTriggerMode() {
        // Toujours nettoyer l'ancien monitor
        if let oldMonitor = triggerMonitor {
            NSEvent.removeMonitor(oldMonitor)
            triggerMonitor = nil
        }
        
        // Reset l'état
        wasInTriggerZone = false
        showDelayTimer?.invalidate()
        showDelayTimer = nil
        
        // Recréer immédiatement le nouveau monitor
        setupNewMonitor()
    }
    
    // MARK: - Preferences Window
    @objc func showPreferences() {
        let newWidth: CGFloat = 800
        let newHeight: CGFloat = 600
        
        if preferencesWindow == nil {
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(preferencesWindowDidMove(_:)),
                name: NSWindow.didMoveNotification,
                object: preferencesWindow
            )
            
            let preferencesView = PreferencesView(initialTab: 0)
            
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            preferencesWindow?.title = "Preferences"
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.level = NSWindow.Level(rawValue: 102)
            preferencesWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            preferencesWindow?.delegate = self
        } else {
            let preferencesView = PreferencesView(initialTab: 0)
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
            
            var frame = preferencesWindow!.frame
            frame.size = NSSize(width: newWidth, height: newHeight)
            preferencesWindow?.setFrame(frame, display: true)
        }
        
        // 🆕 Enregistrer la fenêtre dans le manager
        PreferencesWindowManager.shared.preferencesWindow = preferencesWindow
        
        Task { @MainActor in
            DrawerManager.shared.preferencesOpen = true
            
            if !DrawerManager.shared.isDrawerVisible {
                DrawerManager.shared.showDrawer()
            }
            
            if let screen = NSScreen.main,
               let window = self.preferencesWindow {
                let drawerHeight = screen.frame.height * DrawerManager.shared.drawerHeightPercent
                let x = (screen.frame.width - newWidth) / 2
                let y = screen.frame.maxY - drawerHeight - 200 - newHeight
                window.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                self.preferencesWindow?.center()
            }
            
            self.preferencesWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    // MARK: - Cleanup
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = triggerMonitor {
            NSEvent.removeMonitor(monitor)
            triggerMonitor = nil
        }
        showDelayTimer?.invalidate()
    }
}

// MARK: - NSWindowDelegate (MISE À JOUR)
extension DrawerAppDelegate: NSWindowDelegate {
    
    @objc private func preferencesWindowDidMove(_ notification: Notification) {
        PreferencesWindowManager.shared.synchronizePanelsPosition()
    }
    
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == preferencesWindow {
            Task { @MainActor in
                // Désactiver les simulations
                MinimalNavigationBlurManager.shared.isSimulating = false
                MinimalNavigationBlurManager.shared.activeZone = .none
                
                // ✅ FERMER LE COLOR PANEL
                NSColorPanel.shared.orderOut(nil)
                NSColorPanel.shared.close()
                
                // Fermer les panneaux
                PreferencesWindowManager.shared.closeAllPanels()
                
                // Réinitialiser l'état du drawer
                DrawerManager.shared.preferencesOpen = false
                DrawerManager.shared.isLockedOpen = false
            }
        }
    }
}

