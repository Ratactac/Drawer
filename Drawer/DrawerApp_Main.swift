// DrawerApp_Main.swift
// Point d'entrée principal de l'application - Version corrigée

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
    // Fenêtres et managers
    var statusBarItem: NSStatusItem?
    var preferencesWindow: NSWindow?
    var drawerManager: DrawerManager?
    
    // Monitors pour la trigger zone
    var triggerMonitor: Any?          // Monitor global principal
    var localHoverMonitor: Any?       // Monitor local pour le mode hover
    
    // État et timers
    var showDelayTimer: Timer?
    private var wasInTriggerZone = false  // Pour tracker si on était dans la zone (mode hover)
    
    // MARK: - Computed Property pour menuBarIcon (SOLUTION)
    private var menuBarIcon: Bool {
        // Si aucune valeur n'existe, initialiser à true et retourner true
        if UserDefaults.standard.object(forKey: "menuBarIcon") == nil {
            UserDefaults.standard.set(true, forKey: "menuBarIcon")
            return true
        }
        return UserDefaults.standard.bool(forKey: "menuBarIcon")
    }
    
    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Application launched")
        print("📍 Bundle Identifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        
        // Mode accessoire (pas dans le Dock)
        NSApp.setActivationPolicy(.accessory)
        
        // NOUVEAU : Synchroniser l'état du login item avec UserDefaults au premier lancement
        syncLoginItemState()
        
       
        // SOLUTION : Toujours créer le statusBarItem
        setupStatusBar()
        
        // Puis mettre à jour sa visibilité selon les préférences
        updateMenuBarVisibility()
        
        // Observer pour les changements de menuBarIcon via KVO
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: "menuBarIcon",
            options: [.new],
            context: nil
        )
        
        // Observer pour l'icône de la barre de menu (notification custom)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarIconToggle(_:)),
            name: NSNotification.Name("MenuBarIconToggled"),
            object: nil
        )
        
        // Observer pour les changements de triggerMode
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: "triggerMode",
            options: .new,
            context: nil
        )
        
        // Initialiser le drawer manager et la trigger zone
        Task { @MainActor in
            drawerManager = DrawerManager.shared
            setupTriggerZone()
        }
    }
    
    // MARK: - Menu Bar Visibility Management (SOLUTION)
    private func updateMenuBarVisibility() {
        let shouldShow = UserDefaults.standard.object(forKey: "menuBarIcon") as? Bool ?? true
        
        if shouldShow {
            statusBarItem?.isVisible = true
            // Si le statusBarItem n'existe pas encore, le créer
            if statusBarItem == nil {
                setupStatusBar()
            }
        } else {
            statusBarItem?.isVisible = false
        }
        
        print("📊 Menu bar visibility updated: \(shouldShow)")
    }
    
    // MARK: - KVO Observer
    override func observeValue(forKeyPath keyPath: String?,
                              of object: Any?,
                              change: [NSKeyValueChangeKey : Any]?,
                              context: UnsafeMutableRawPointer?) {
        
        if keyPath == "menuBarIcon" {
            // Mettre à jour la visibilité quand la préférence change
            DispatchQueue.main.async { [weak self] in
                self?.updateMenuBarVisibility()
            }
        } else if keyPath == "triggerMode" {
            print("🔄 Trigger mode changed via preferences!")
            DispatchQueue.main.async { [weak self] in
                self?.updateTriggerMode()
            }
        }
    }
    
    // MARK: - Trigger Zone Management
    func setupTriggerZone() {
        // Ne pas réinitialiser si les préférences sont ouvertes
        if preferencesWindow?.isVisible == true {
            return
        }
        
        // Nettoyer tous les anciens monitors
        cleanupAllMonitors()
        
        // Réinitialiser l'état
        wasInTriggerZone = false
        showDelayTimer?.invalidate()
        showDelayTimer = nil
        
        // Créer les nouveaux monitors après un petit délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupNewMonitor()
        }
    }
    
    private func setupNewMonitor() {
        let triggerMode = UserDefaults.standard.string(forKey: "triggerMode") ?? "hover"
        print("🎯 Setting up monitor for mode: \(triggerMode)")
        
        switch triggerMode {
        case "click":
            // Monitor pour les clics
            triggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self = self else { return }
                
                let location = NSEvent.mouseLocation
                if self.isInTriggerZone(location) {
                    print("🔵 Click detected in trigger zone")
                    self.triggerDrawer()
                }
            }
            
        case "scroll":
            // Monitor pour le scroll
            triggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self = self else { return }
                
                let location = NSEvent.mouseLocation
                if event.deltaY > 0 && self.isInTriggerZone(location) {
                    print("📜 Scroll detected in trigger zone")
                    self.triggerDrawer()
                }
            }
            
        case "hover":
            // Réinitialiser l'état
            self.wasInTriggerZone = false
            
            // Monitor GLOBAL (quand l'app n'a pas le focus)
            triggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                guard let self = self else { return }
                self.handleHoverEvent()
            }
            
            // Monitor LOCAL (quand l'app a le focus)
            localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                guard let self = self else { return event }
                self.handleHoverEvent()
                return event
            }
            
        default:
            print("❌ Unknown trigger mode: \(triggerMode)")
            break
        }
    }
    
    // Gérer les événements hover
    private func handleHoverEvent() {
        let location = NSEvent.mouseLocation
        let isInZone = self.isInTriggerZone(location)
        
        // Détecter l'entrée dans la zone
        if isInZone && !self.wasInTriggerZone {
            print("🎯 Mouse entered trigger zone")
            self.triggerDrawer()
            self.wasInTriggerZone = true
        }
        // Détecter la sortie de la zone
        else if !isInZone && self.wasInTriggerZone {
            print("👋 Mouse left trigger zone")
            self.wasInTriggerZone = false
        }
    }
    
    // Mettre à jour le mode trigger (appelé quand on change dans les préférences)
    func updateTriggerMode() {
        print("🔄 Updating trigger mode...")
        
        // Nettoyer tous les monitors existants
        cleanupAllMonitors()
        
        // Réinitialiser l'état
        wasInTriggerZone = false
        showDelayTimer?.invalidate()
        showDelayTimer = nil
        
        // Recréer les monitors avec le nouveau mode
        setupNewMonitor()
    }
    
    // Nettoyer tous les monitors
    private func cleanupAllMonitors() {
        if let monitor = triggerMonitor {
            NSEvent.removeMonitor(monitor)
            triggerMonitor = nil
        }
        
        if let local = localHoverMonitor {
            NSEvent.removeMonitor(local)
            localHoverMonitor = nil
        }
    }
    
    // Déclencher l'ouverture du drawer
    private func triggerDrawer() {
        showDelayTimer?.invalidate()
        
        Task { @MainActor in
            guard let manager = self.drawerManager else { return }
            
            // Ne pas ouvrir si déjà visible
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
    
    // Vérifier si la position est dans la trigger zone
    private func isInTriggerZone(_ location: NSPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        let triggerZoneHeight: Double = 25.0  // Hauteur fixe
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
    
    // MARK: - Status Bar (MODIFIÉ pour toujours créer mais gérer la visibilité)
    func setupStatusBar() {
        // Ne pas recréer si elle existe déjà
        if statusBarItem != nil {
            return
        }
        
        // Créer la nouvelle icône
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
                
                // Intérieur avec transparence
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                let cutoutRect = NSRect(x: rect.minX + 3, y: rect.minY + 3, width: rect.width - 6.5, height: 7)
                NSBezierPath(roundedRect: cutoutRect, xRadius: 0, yRadius: 0).fill()
                NSGraphicsContext.restoreGraphicsState()
                
                // Poignée du tiroir
                NSColor.labelColor.setFill()
                let notchRect = NSRect(x: rect.midX - 4, y: rect.minY + 6, width: 8, height: 2)
                NSBezierPath(roundedRect: notchRect, xRadius: 1, yRadius: 1).fill()
                
                return true
            }
            button.image?.isTemplate = true
        }
        
        // Créer le menu
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
        
        let minimalViewItem = NSMenuItem(title: "Minimal View", action: #selector(setMinimalView), keyEquivalent: "3")
        minimalViewItem.target = self
        submenu.addItem(minimalViewItem)
        
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
    
    // MARK: - Menu Actions
    @objc private func showDrawer() {
        Task { @MainActor in
            drawerManager?.showDrawer()
        }
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
    
    @objc private func setMinimalView() {
        Task { @MainActor in
            drawerManager?.setDisplayMode(.minimal)
        }
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = sender.state != .on
        sender.state = newState ? .on : .off
        DrawerAppDelegate.setLaunchAtLogin(newState)
    }
    
    @objc private func handleMenuBarIconToggle(_ notification: Notification) {
        // Cette méthode est pour la compatibilité avec l'ancienne notification custom
        // La vraie gestion se fait maintenant via KVO
        if let enabled = notification.userInfo?["enabled"] as? Bool {
            UserDefaults.standard.set(enabled, forKey: "menuBarIcon")
            updateMenuBarVisibility()
        }
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
        
        // Enregistrer la fenêtre dans le manager
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
    
    // MARK: - Launch at Login
    private func configureLaunchAtLoginIfNeeded() {
        let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        
        if #available(macOS 13.0, *) {
            let currentStatus = SMAppService.mainApp.status
            
            // Ne modifier que si nécessaire
            if launchAtLogin {
                // Activer uniquement si pas déjà activé
                if currentStatus != .enabled {
                    do {
                        try SMAppService.mainApp.register()
                        print("✅ Launch at login enabled")
                    } catch {
                        print("❌ Failed to enable launch at login: \(error)")
                    }
                } else {
                    print("✅ Launch at login already enabled")
                }
            } else {
                // Désactiver uniquement si actuellement activé
                if currentStatus == .enabled {
                    do {
                        try SMAppService.mainApp.unregister()
                        print("🔴 Launch at login disabled")
                    } catch {
                        print("❌ Failed to disable launch at login: \(error)")
                    }
                }
            }
        }
    }
    
    private func syncLoginItemState() {
        if #available(macOS 13.0, *) {
            let currentStatus = SMAppService.mainApp.status
            let savedPreference = UserDefaults.standard.bool(forKey: "launchAtLogin")
            
            // Si l'état réel ne correspond pas à la préférence sauvegardée
            if currentStatus == .enabled && !savedPreference {
                // L'app est dans les login items mais pas dans les préférences
                UserDefaults.standard.set(true, forKey: "launchAtLogin")
                print("📝 Synced: Launch at login was enabled externally")
            } else if currentStatus != .enabled && savedPreference {
                // La préférence dit qu'elle devrait être activée mais elle ne l'est pas
                do {
                    try SMAppService.mainApp.register()
                    print("✅ Launch at login re-enabled on sync")
                } catch {
                    print("❌ Failed to sync launch at login: \(error)")
                    UserDefaults.standard.set(false, forKey: "launchAtLogin")
                }
            } else {
                print("✅ Launch at login state is synchronized")
            }
        }
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        
        if #available(macOS 13.0, *) {
            let currentStatus = SMAppService.mainApp.status
            
            if enabled {
                // Activer uniquement si pas déjà activé
                if currentStatus != .enabled {
                    do {
                        try SMAppService.mainApp.register()
                        print("✅ Launch at login enabled from preferences")
                    } catch {
                        print("❌ Failed to enable launch at login: \(error)")
                    }
                }
            } else {
                // Désactiver uniquement si actuellement activé
                if currentStatus == .enabled {
                    do {
                        try SMAppService.mainApp.unregister()
                        print("🔴 Launch at login disabled from preferences")
                    } catch {
                        print("❌ Failed to disable launch at login: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Cleanup
    func applicationWillTerminate(_ notification: Notification) {
        // Nettoyer tous les monitors
        cleanupAllMonitors()
        
        // Nettoyer les timers
        showDelayTimer?.invalidate()
        
        // Retirer les observers KVO
        UserDefaults.standard.removeObserver(self, forKeyPath: "menuBarIcon")
        UserDefaults.standard.removeObserver(self, forKeyPath: "triggerMode")
    }
    
    // MARK: - Deinit
    deinit {
        // Sécurité supplémentaire pour les observers
        UserDefaults.standard.removeObserver(self, forKeyPath: "menuBarIcon", context: nil)
        UserDefaults.standard.removeObserver(self, forKeyPath: "triggerMode", context: nil)
    }
}

// MARK: - NSWindowDelegate
extension DrawerAppDelegate: NSWindowDelegate {
    
    @objc private func preferencesWindowDidMove(_ notification: Notification) {
        PreferencesWindowManager.shared.synchronizePanelsPosition()
    }
    
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == preferencesWindow {
            Task { @MainActor in
                // Arrêter la visualisation de la trigger zone
                NotificationCenter.default.post(
                    name: Notification.Name("StopTriggerZoneVisualization"),
                    object: nil
                )
                
                // Désactiver les simulations de blur
                MinimalNavigationBlurManager.shared.isSimulating = false
                MinimalNavigationBlurManager.shared.activeZone = .none
                
                // Fermer le color panel
                NSColorPanel.shared.orderOut(nil)
                NSColorPanel.shared.close()
                
                // Fermer tous les panneaux
                PreferencesWindowManager.shared.closeAllPanels()
                
                // Réinitialiser l'état du drawer
                DrawerManager.shared.preferencesOpen = false
                DrawerManager.shared.isLockedOpen = false
            }
        }
    }
}
