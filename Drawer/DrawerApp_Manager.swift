// DrawerApp_Manager.swift
// UNIQUE DrawerManager - Fusion de Enhanced + Refactored

import SwiftUI
import AppKit

// MARK: - Mode d'affichage
enum DrawerDisplayMode: String, CaseIterable {
    case single = "Simple View"
    case double = "Double View"
    case minimal = "Minimal View"
    
    var icon: String {
        switch self {
        case .single: return "rectangle.split.2x1"
        case .double: return "square.grid.2x2.fill"
        case .minimal: return "rectangle"
        }
    }
}

// MARK: - DrawerManager UNIQUE (ex-EnhancedDrawerManager)
@MainActor
class DrawerManager: ObservableObject {
    static let shared = DrawerManager()
    
    private var mainDrawerPanel: DrawerPanel?
    private var bridgePanel: NSPanel?
    @Published var isDrawerVisible = false
    @Published var displayMode: DrawerDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode")
        }
    }
    @Published var selectedItems: Set<AsyncFileItem> = []
    @Published var isLockedOpen: Bool = false
    @Published var preferencesOpen = false
    
    @Published private var keepOpenTimer: Timer?
    // Settings
    @AppStorage("notesEnabled") var notesEnabled = false
    @AppStorage("notesPanelWidth") var notesPanelWidth: Double = 250
    @AppStorage("drawerWidth") var drawerWidth: Double = 0.6
    @AppStorage("drawerWidthDouble") var drawerWidthDouble: Double = 0.85
    @AppStorage("hideDelay") private var hideDelay: Double = 0.01
    @AppStorage("drawerHeightPercent") var drawerHeightPercent: Double = 0.6
    @AppStorage("currentBlur") var currentBlur: Double = 0.8
    
    private let menuBarOffset: CGFloat = 24
    private var mouseMonitor: Any?
    private var hideTimer: Timer?
    
    var drawerWindow: NSWindow? {
        return mainDrawerPanel
    }
    
    
    var drawerFrame: NSRect? {
        mainDrawerPanel?.frame
    }
    
    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? "single"
        self.displayMode = DrawerDisplayMode(rawValue: savedMode) ?? .single
        
        setupPanel()
        startMonitoring()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func userDefaultsChanged() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? "single"
        if let newMode = DrawerDisplayMode(rawValue: savedMode), newMode != displayMode {
            setDisplayMode(newMode)
        }
    }
    
    func setupPanel() {
        guard let screen = NSScreen.main else { return }
        
        // 🆕 VERSION CORRIGÉE avec support Minimal
        let baseWidth: CGFloat
        switch displayMode {
        case .single:
            baseWidth = screen.frame.width * drawerWidth
        case .double:
            baseWidth = screen.frame.width * drawerWidthDouble
        case .minimal:
            let minimalWidthSetting = UserDefaults.standard.double(forKey: "minimalWidth")
            baseWidth = screen.frame.width * (minimalWidthSetting > 0 ? minimalWidthSetting : 0.6)
        }
        
        let totalWidth = notesEnabled && displayMode == .single ?
            baseWidth + CGFloat(notesPanelWidth) : baseWidth
        
        let contentHeight = screen.frame.height * CGFloat(drawerHeightPercent)
        
        if let existingPanel = mainDrawerPanel, isDrawerVisible {
            updateContent()
            return
        }
    
        
        mainDrawerPanel = DrawerPanel(
            contentRect: NSRect(
                x: (screen.frame.width - totalWidth) / 2,
                y: screen.frame.maxY,
                width: totalWidth,
                height: contentHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        mainDrawerPanel?.isOpaque = false
        mainDrawerPanel?.backgroundColor = .clear
        mainDrawerPanel?.level = .popUpMenu  // Toujours popUpMenu
        mainDrawerPanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        mainDrawerPanel?.isMovable = false
        mainDrawerPanel?.hasShadow = true
        mainDrawerPanel?.acceptsMouseMovedEvents = true
            
        setupBridgePanel()
        updateContent()
    }
    
    private func setupBridgePanel() {
        guard let screen = NSScreen.main else { return }
        
        let baseWidth = displayMode == .double ?
            screen.frame.width * drawerWidthDouble :
            screen.frame.width * drawerWidth
        
        let totalWidth = notesEnabled && displayMode == .single ?
            baseWidth + CGFloat(notesPanelWidth) : baseWidth
        
        bridgePanel = NSPanel(
            contentRect: NSRect(
                x: (screen.frame.width - totalWidth) / 2,
                y: screen.frame.maxY - menuBarOffset,
                width: totalWidth,
                height: menuBarOffset + 10
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        bridgePanel?.isOpaque = false
        bridgePanel?.backgroundColor = .clear
        bridgePanel?.level = .popUpMenu
        
        if preferencesOpen {
            bridgePanel?.level = .normal
        } else {
            bridgePanel?.level = .popUpMenu
        }
        
        bridgePanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        bridgePanel?.ignoresMouseEvents = false
        bridgePanel?.hasShadow = false
        bridgePanel?.alphaValue = 0.001
    }
    
    func updateContent() {
        let mainContent = Group {
            if displayMode == .minimal {
                // 🆕 Minimal View sans barre de mode
                MinimalViewContent()
                    .environmentObject(self)
            } else {
                // Vues normales avec barre de mode
                VStack(spacing: 0) {
                    ModeSelectorBar(
                        currentMode: displayMode,
                        onModeChange: { [weak self] newMode in
                            self?.setDisplayMode(newMode)
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.15))
                    
                    Divider()
                    
                    if displayMode == .single {
                        if notesEnabled {
                            HStack(spacing: 0) {
                                SingleViewContent()
                                    .environmentObject(self)
                                Divider()
                                    .background(Color.gray.opacity(0.5))
                                NotesPanel()
                                    .frame(width: CGFloat(notesPanelWidth))
                            }
                        } else {
                            SingleViewContent()
                                .environmentObject(self)
                        }
                    } else {
                        DoubleViewContent()
                    }
                }
            }
        }
        
        let contentView = AnyView(
            mainContent
                .background(
                    VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                        .opacity(currentBlur)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
        
        mainDrawerPanel?.contentView = NSHostingView(rootView: contentView)
    }
    
    // Modifiez la méthode setDisplayMode
    func setDisplayMode(_ mode: DrawerDisplayMode) {
        let oldMode = self.displayMode
        
        // Changer de mode
        self.displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "displayMode")
        
        // Reconstruire le panel avec les nouvelles dimensions
        setupPanel()
        
        // Si on change de mode, annuler l'ancien timer et en créer un nouveau
        if oldMode != mode {
            // Annuler le timer de fermeture automatique s'il existe
            keepOpenTimer?.invalidate()
            keepOpenTimer = nil
            
            // Créer un nouveau timer de 2 secondes
            keepOpenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                // Après 2 secondes, permettre au drawer de se fermer normalement
                // (ne rien faire ici, juste libérer le timer)
                self.keepOpenTimer = nil
            }
        }
    }
    
    private func hideDrawerImmediately() {
        guard let panel = mainDrawerPanel else { return }
        
        isDrawerVisible = false
        panel.orderOut(nil)
        bridgePanel?.orderOut(nil)
        cancelHideTimer()
    }
    
    func setNotesEnabled(_ enabled: Bool) {
        notesEnabled = enabled
        
        // Animation fluide du changement de largeur
        if isDrawerVisible {
            guard let panel = mainDrawerPanel, let screen = NSScreen.main else { return }
            
            let baseWidth = displayMode == .double ?
                screen.frame.width * drawerWidthDouble :
                screen.frame.width * drawerWidth
            
            let totalWidth = enabled && displayMode == .single ?
                baseWidth + CGFloat(notesPanelWidth) : baseWidth
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2  // Animation douce de 200ms
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                var frame = panel.frame
                frame.size.width = totalWidth
                frame.origin.x = (screen.frame.width - totalWidth) / 2
                panel.animator().setFrame(frame, display: true)
                
                if let bridge = bridgePanel {
                    var bridgeFrame = bridge.frame
                    bridgeFrame.size.width = totalWidth
                    bridgeFrame.origin.x = (screen.frame.width - totalWidth) / 2
                    bridge.animator().setFrame(bridgeFrame, display: true)
                }
            } completionHandler: {
                // Mettre à jour le contenu après l'animation
                self.updateContent()
            }
        } else {
            // Si le drawer n'est pas visible, juste mettre à jour
            setupPanel()
            updateContent()
        }
    }
    
    func showDrawer() {
        guard !isDrawerVisible, let panel = mainDrawerPanel, let screen = NSScreen.main else { return }
        
        let baseWidth = displayMode == .double ?
            screen.frame.width * drawerWidthDouble :
            screen.frame.width * drawerWidth
        
        let totalWidth = notesEnabled && displayMode == .single ?
            baseWidth + CGFloat(notesPanelWidth) : baseWidth
        let totalHeight = panel.frame.height
        
        let finalY = screen.frame.maxY - totalHeight - menuBarOffset
        
        panel.setFrame(
            NSRect(
                x: (screen.frame.width - totalWidth) / 2,
                y: screen.frame.maxY,
                width: totalWidth,
                height: totalHeight
            ),
            display: false
        )
        
        bridgePanel?.setFrame(
            NSRect(
                x: (screen.frame.width - totalWidth) / 2,
                y: finalY + totalHeight - 5,
                width: totalWidth,
                height: menuBarOffset + 10
            ),
            display: false
        )
        
        bridgePanel?.orderFront(nil)
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            panel.animator().setFrame(
                NSRect(
                    x: panel.frame.origin.x,
                    y: finalY,
                    width: panel.frame.width,
                    height: totalHeight
                ),
                display: true
            )
        } 
        
        isDrawerVisible = true
        NotificationCenter.default.post(name: NSNotification.Name("DrawerVisibilityChanged"), object: nil)
        
        // ✅ AJOUTEZ CES LIGNES À LA FIN
        // Donner le focus au drawer immédiatement
        DispatchQueue.main.async {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
            NSApp.activate(ignoringOtherApps: false)
            
            // Notifier le système de blur que le drawer est prêt
            NotificationCenter.default.post(
                name: NSNotification.Name("DrawerDidOpen"),
                object: nil
            )
        }
    }
    
    
    func hideDrawer() {
        guard isDrawerVisible, let panel = mainDrawerPanel, let screen = NSScreen.main else { return }
        
        isDrawerVisible = false
        NotificationCenter.default.post(name: NSNotification.Name("DrawerVisibilityChanged"), object: nil)
        bridgePanel?.orderOut(nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            panel.animator().setFrame(
                NSRect(
                    x: panel.frame.origin.x,
                    y: screen.frame.maxY,
                    width: panel.frame.width,
                    height: panel.frame.height
                ),
                display: true
            )
        }) {
            panel.orderOut(nil)
        }
    }
    
    private func startMonitoring() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.checkMousePosition()
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.checkMousePosition()
            return event
        }
    }
    
    private func checkMousePosition() {
        guard isDrawerVisible, let panel = mainDrawerPanel else { return }
        
        // Si on est dans la période de 2 secondes, ne pas fermer
        if keepOpenTimer != nil || isLockedOpen {
            cancelHideTimer()
            return
        }
        
        let mouseLocation = NSEvent.mouseLocation
        
        let drawerFrame = panel.frame.insetBy(dx: -10, dy: -10)
        let bridgeFrame = bridgePanel?.frame ?? .zero
        
        if let screen = NSScreen.main {
            let triggerHeight: Double = 25.0
            let triggerWidth = UserDefaults.standard.double(forKey: "triggerZoneWidth") / 100.0
            let zoneWidthPixels = screen.frame.width * triggerWidth
            let zoneX = (screen.frame.width - zoneWidthPixels) / 2
            
            let triggerFrame = NSRect(
                x: zoneX,
                y: screen.frame.maxY - (triggerHeight > 0 ? triggerHeight : 10),
                width: zoneWidthPixels,
                height: triggerHeight > 0 ? triggerHeight : 10
            )
            
            if drawerFrame.contains(mouseLocation) ||
               bridgeFrame.contains(mouseLocation) ||
               triggerFrame.contains(mouseLocation) {
                cancelHideTimer()
            } else {
                if hideTimer == nil {
                    startHideTimer()
                }
            }
        }
    }
    
    private func startHideTimer() {
        cancelHideTimer()
        let delay = hideDelay > 0 ? hideDelay : 0.5
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideDrawer()
            }
        }
    }
    
    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
    
    func updateDrawerWidth() {
        guard let panel = mainDrawerPanel, let screen = NSScreen.main, isDrawerVisible else { return }
        
        // Utiliser la largeur appropriée selon le mode actuel
        let baseWidth: CGFloat
        switch displayMode {
        case .single:
            baseWidth = screen.frame.width * drawerWidth
        case .double:
            baseWidth = screen.frame.width * drawerWidthDouble
        case .minimal:
            let minimalWidthSetting = UserDefaults.standard.double(forKey: "minimalWidth")
            baseWidth = screen.frame.width * (minimalWidthSetting > 0 ? minimalWidthSetting : 0.6)
        }
        
        let totalWidth = notesEnabled && displayMode == .single ?
            baseWidth + CGFloat(notesPanelWidth) : baseWidth
        
        var frame = panel.frame
        frame.size.width = totalWidth
        frame.origin.x = (screen.frame.width - totalWidth) / 2
        
        panel.setFrame(frame, display: true, animate: false)
        
        // Mettre à jour aussi le bridge panel
        if let bridge = bridgePanel {
            var bridgeFrame = bridge.frame
            bridgeFrame.size.width = totalWidth
            bridgeFrame.origin.x = (screen.frame.width - totalWidth) / 2
            bridge.setFrame(bridgeFrame, display: true, animate: false)
        }
    }

    // Méthode pour mettre à jour la hauteur
    func updateDrawerHeight() {
        guard let panel = mainDrawerPanel, let screen = NSScreen.main, isDrawerVisible else { return }
        
        // Calculer la nouvelle hauteur
        let newHeight = screen.frame.height * drawerHeightPercent
        
        // Calculer la nouvelle position Y (le drawer descend depuis le haut)
        let newY = screen.frame.maxY - newHeight - menuBarOffset
        
        // Mettre à jour le frame du drawer
        var frame = panel.frame
        frame.size.height = newHeight
        frame.origin.y = newY
        
        panel.setFrame(frame, display: true, animate: false)
        
        // Mettre à jour le bridge panel pour qu'il reste collé au drawer
        if let bridge = bridgePanel {
            var bridgeFrame = bridge.frame
            bridgeFrame.origin.y = newY + newHeight - 5
            bridge.setFrame(bridgeFrame, display: true, animate: false)
        }
    }
    
       
    func setDrawerLevel(_ level: NSWindow.Level) {
        mainDrawerPanel?.level = level
        bridgePanel?.level = level
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
    
// MARK: - ModeSelectorBar
struct ModeSelectorBar: View {
    let currentMode: DrawerDisplayMode
    let onModeChange: (DrawerDisplayMode) -> Void
    @State private var isChanging = false
    @AppStorage("notesEnabled") private var notesEnabled: Bool = false
    @State private var showingPreferences = false  // Pour l'animation du gear
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
            
            Text("Files Browser")
                .font(.system(size: 13, weight: .medium))
            
            Spacer()
            
            HStack(spacing: 8) {
                // Bouton Notes - visible uniquement en mode Simple
                if currentMode == .single {
                    Button(action: {
                        notesEnabled.toggle()
                        Task { @MainActor in
                            DrawerManager.shared.setNotesEnabled(notesEnabled)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: notesEnabled ? "note.text.badge.plus" : "note.text")
                                .font(.system(size: 12))
                            Text("Notes")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            notesEnabled ?
                            Color.orange.opacity(0.9) :
                                Color.gray.opacity(0.2)
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Boutons de mode avec Préférences
                HStack(spacing: 4) {
                   
                    // Bouton Minimal
                    Button(action: {
                        onModeChange(.minimal)
                    }) {
                        Image(systemName: DrawerDisplayMode.minimal.icon)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 20)
                            .background(
                                currentMode == .minimal ?
                                    Color.accentColor.opacity(0.2) :
                                    Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Minimal View")
                    
                    // Bouton Single
                    Button(action: {
                        onModeChange(.single)
                    }) {
                        Image(systemName: DrawerDisplayMode.single.icon)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 20)
                            .background(
                                currentMode == .single ?
                                    Color.accentColor.opacity(0.2) :
                                    Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Single View")
                    
                    // Bouton Double
                    Button(action: {
                        onModeChange(.double)
                    }) {
                        Image(systemName: DrawerDisplayMode.double.icon)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 20)
                            .background(
                                currentMode == .double ?
                                    Color.accentColor.opacity(0.2) :
                                    Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Double View")
                    
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    // 🆕 Bouton Préférences À GAUCHE
                    Button(action: {
                        // MÉTHODE QUI FONCTIONNE À 100% - Comme dans MinimalView
                        NSApplication.shared.sendAction(
                            #selector(DrawerAppDelegate.showPreferences),
                            to: nil,
                            from: nil
                        )
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 20)
                            .background(Color.clear)
                            .cornerRadius(4)
                            .rotationEffect(.degrees(showingPreferences ? 90 : 0))
                            .animation(.easeInOut(duration: 0.3), value: showingPreferences)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Preferences")
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingPreferences = hovering
                        }
                    }
                    

                }
                .padding(2)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.15))
        // PAS de .sheet ici - on utilise NSApplication.shared.sendAction
    }
}
        


