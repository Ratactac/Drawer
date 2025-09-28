// DrawerApp_NotesAndPrefs.swift
// Notes Panel et Préférences

import SwiftUI
import AppKit

// MARK: - 🆕 GESTIONNAIRE CENTRALISÉ DES FENÊTRES DE PRÉFÉRENCES

class PreferencesWindowManager: ObservableObject {
    static let shared = PreferencesWindowManager()
    
    // Fenêtres gérées
    weak var preferencesWindow: NSWindow?
    weak var blurSettingsPanel: NSWindow?
    weak var colorPanel: NSWindow?
    
    private init() {}
    
    // MARK: - Navigation Blur Settings Panel
    
    func showNavigationBlurSettings() {
        // Vérifier si le panneau existe déjà
        if let existingPanel = blurSettingsPanel, existingPanel.isVisible {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }
        
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "Navigation Blur Settings"
        panel.contentView = NSHostingView(
            rootView: MinimalBlurDebugPanel(manager: MinimalNavigationBlurManager.shared)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        panel.level = NSWindow.Level(rawValue: 103)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        
        // 🆕 Attacher comme fenêtre enfant
        if let prefsWindow = preferencesWindow,
           let blurPanel = blurSettingsPanel {
            // Lier les fenêtres
            prefsWindow.addChildWindow(blurPanel, ordered: .above)
        }
        
        
        // Positionnement à droite de Preferences
        positionBlurPanel(panel)
        
        panel.makeKeyAndOrderFront(nil)
        blurSettingsPanel = panel
        
        // 🆕 Observer aussi le redimensionnement
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: preferencesWindow,
            queue: .main
        ) { _ in
            self.synchronizePanelsPosition()
        }
        
        // ✅ Observer la fermeture du panneau Blur
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // ✅ CORRECTION : Utiliser Task pour accéder au MainActor
            Task { @MainActor in
                MinimalNavigationBlurManager.shared.isSimulating = false
                MinimalNavigationBlurManager.shared.activeZone = .none
            }
            self?.blurSettingsPanel = nil
        }
        
        // Activer la démo
        activateBlurDemo()
        
        // Observer les mouvements
        observeWindowMovement(panel)
    }
    
    // MARK: - Color Panel Management
    func ensureColorPanelIsPositioned() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Accès direct au panel partagé
            let sharedColorPanel = NSColorPanel.shared
            
            // S'assurer qu'il est visible
            if !sharedColorPanel.isVisible {
                sharedColorPanel.makeKeyAndOrderFront(nil)
            }
            
            // Capturer la référence
            self.colorPanel = sharedColorPanel
            
            // Configuration du panel
            sharedColorPanel.level = NSWindow.Level(rawValue: 103)
            sharedColorPanel.isFloatingPanel = false
            sharedColorPanel.hidesOnDeactivate = false
            sharedColorPanel.worksWhenModal = true
            
            // ✅ POSITIONNEMENT PRÉCIS
            if let prefsWindow = self.preferencesWindow {
                let prefsFrame = prefsWindow.frame
                
                // Calculer la position à gauche
                let colorPanelWidth = sharedColorPanel.frame.width
                let spacing: CGFloat = 10
                
                // Position X : à gauche de Preferences avec espacement
                let newX = prefsFrame.minX - colorPanelWidth - spacing
                
                // Position Y : aligner le haut des deux fenêtres
                let newY = prefsFrame.maxY - sharedColorPanel.frame.height
                
                // Vérifier que ça reste dans l'écran
                if let screen = prefsWindow.screen {
                    var finalX = newX
                    var finalY = newY
                    
                    // Si ça sort à gauche, mettre à droite
                    if finalX < screen.visibleFrame.minX {
                        finalX = prefsFrame.maxX + spacing
                    }
                    
                    // Ajuster Y si nécessaire
                    if finalY < screen.visibleFrame.minY {
                        finalY = screen.visibleFrame.minY
                    }
                    
                    // Appliquer la position
                    sharedColorPanel.setFrameTopLeftPoint(NSPoint(x: finalX, y: prefsFrame.maxY))
                }
                
                // Lier comme fenêtre enfant
                prefsWindow.addChildWindow(sharedColorPanel, ordered: .above)
            }
        }
    }
    
    // MARK: - Positioning Methods
    private func positionBlurPanel(_ panel: NSWindow) {
        guard let prefsFrame = preferencesWindow?.frame else {
            panel.center()
            return
        }
        
        let x = prefsFrame.maxX + 10
        let y = prefsFrame.minY
        panel.setFrame(
            NSRect(x: x, y: y, width: 350, height: min(600, prefsFrame.height)),
            display: true
        )
    }
    
    private func positionColorPanel(_ panel: NSWindow) {
        guard let prefsFrame = preferencesWindow?.frame else { return }
        
        panel.level = NSWindow.Level(rawValue: 103)
        panel.setFrame(NSRect(
            x: prefsFrame.minX - panel.frame.width - 10,
            y: prefsFrame.minY,
            width: panel.frame.width,
            height: panel.frame.height
        ), display: true)
    }
    
    // MARK: - Synchronization
    func synchronizePanelsPosition() {
        guard let prefsFrame = preferencesWindow?.frame else { return }
        
        // Blur panel à droite
        if let blur = blurSettingsPanel, blur.isVisible {
            let spacing: CGFloat = 10
            let newX = prefsFrame.maxX + spacing
            let newY = prefsFrame.minY
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                blur.animator().setFrame(
                    NSRect(x: newX, y: newY, width: blur.frame.width, height: min(600, prefsFrame.height)),
                    display: true
                )
            }
        }
        
        // ✅ ColorPanel à gauche - Utiliser directement NSColorPanel.shared
        let colorPanel = NSColorPanel.shared
        if colorPanel.isVisible {
            let newX = prefsFrame.minX - colorPanel.frame.width - 10
            let newY = prefsFrame.minY
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                colorPanel.animator().setFrame(
                    NSRect(x: newX, y: newY, width: colorPanel.frame.width, height: colorPanel.frame.height),
                    display: true
                )
            }
        }
    }
    
    // MARK: - Cleanup
    func closeAllPanels() {
        Task { @MainActor in
            MinimalNavigationBlurManager.shared.isSimulating = false
            MinimalNavigationBlurManager.shared.activeZone = .none
        }
        
        // Fermer Blur Settings
        if let blur = blurSettingsPanel {
            DispatchQueue.main.async { [weak self] in
                blur.close()
                self?.blurSettingsPanel = nil
            }
        }
        
        // ✅ FORCER la fermeture du ColorPanel
        DispatchQueue.main.async {
            NSColorPanel.shared.orderOut(nil)
            NSColorPanel.shared.close()
            self.colorPanel = nil
        }
    }
    
    // MARK: - Private Helpers
    private func activateBlurDemo() {
        // ✅ NOUVEAU : Afficher TOUTES les zones en permanence
        Task { @MainActor in
            let manager = MinimalNavigationBlurManager.shared
            
            // Active le mode simulation
            manager.isSimulating = true
            
            // ✅ IMPORTANT : Activer un nouveau mode qui montre TOUTES les zones
            manager.activeZone = .all  // Nouveau mode !
        }
    }
    
    private func observeWindowMovement(_ window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { _ in
            // Ne rien faire ici, la synchronisation se fait depuis le delegate principal
        }
    }
}

// MARK: - Preferences View (Version complète restaurée)
struct PreferencesView: View {
    @AppStorage("hideDelay") private var hideDelay: Double = 0.5
     @AppStorage("triggerMode") private var triggerMode: String = "click"
    @AppStorage("notesEnabled") private var notesEnabled: Bool = false
    @AppStorage("notesPanelWidth") private var notesPanelWidth: Double = 300
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("drawerWidth") private var drawerWidth: Double = 0.5
    @AppStorage("drawerWidthDouble") private var drawerWidthDouble: Double = 0.85
    @AppStorage("drawerHeightPercent") private var drawerHeightPercent: Double = 0.6
    @AppStorage("showDelay") private var showDelay: Double = 0.01
    @AppStorage("triggerZoneWidth") private var triggerZoneWidth: Double = 20.0
    @AppStorage("notesColor") private var notesColor: String = "yellow"
    
    @AppStorage("minimalTextWhite") private var minimalTextWhite: Bool = true  // true = blanc, false = noir
    
    @AppStorage("displayMode") private var displayModeString: String = "single"
    @State private var selectedTab: Int
    
    // 🆕 Nouvelles variables
    @AppStorage("menuBarIcon") private var menuBarIcon: Bool = true
    
    // Pour Dark mode
    @AppStorage("minimalBackgroundDarkR") private var bgDarkR: Double = 0.15
    @AppStorage("minimalBackgroundDarkG") private var bgDarkG: Double = 0.15
    @AppStorage("minimalBackgroundDarkB") private var bgDarkB: Double = 0.17
    
    // Pour Light mode
    @AppStorage("minimalBackgroundLightR") private var bgLightR: Double = 0.9
    @AppStorage("minimalBackgroundLightG") private var bgLightG: Double = 0.9
    @AppStorage("minimalBackgroundLightB") private var bgLightB: Double = 0.9
    
    // Variables pour la largeur adaptative selon le mode
    @AppStorage("singleWidth") private var singleWidth: Double = 0.5
    @AppStorage("doubleWidth") private var doubleWidth: Double = 0.85
    @AppStorage("minimalWidth") private var minimalWidth: Double = 0.6
    
    // Transparence/Blur pour chaque mode
    @AppStorage("singleBlur") private var singleBlur: Double = 0.95
    @AppStorage("doubleBlur") private var doubleBlur: Double = 0.95
    @AppStorage("minimalBlur") private var minimalBlur: Double = 1.0
    
    @StateObject private var windowManager = PreferencesWindowManager.shared
    
    // Computed property pour la conversion
    private var currentDisplayMode: DrawerDisplayMode {
        get {
            DrawerDisplayMode(rawValue: displayModeString) ?? .single
        }
        set {
            displayModeString = newValue.rawValue
            // La synchronisation avec DrawerManager se fait automatiquement
            // grâce au listener userDefaultsChanged() dans DrawerManager
        }
    }
    
    
    // Computed property pour la largeur actuelle
    var currentWidth: Binding<Double> {
        switch currentDisplayMode {
        case .single:
            return $singleWidth
        case .double:
            return $doubleWidth
        case .minimal:
            return $minimalWidth
        }
    }
    
    // Computed property pour le blur actuel
    var currentBlur: Binding<Double> {
        switch currentDisplayMode {
        case .single:
            return $singleBlur
        case .double:
            return $doubleBlur
        case .minimal:
            return $minimalBlur
        }
    }
    
    init(initialTab: Int = 0) {
        self._selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
         TabView(selection: $selectedTab) {
             // ONGLET GÉNÉRAL
             VStack(spacing: 24) {
                 // Display Mode avec Minimal
                 GroupBox {
                     VStack(spacing: 20) {
                         HStack {
                             Image(systemName: "rectangle.split.2x1")
                                 .foregroundColor(.secondary)
                             Text("Display Mode")
                                 .font(.system(size: 14, weight: .semibold))
                             Spacer()
                         }
                         
                         HStack(spacing: 30) {
                             ForEach([
                                 (DrawerDisplayMode.minimal, "rectangle", "Minimal"),
                                 (DrawerDisplayMode.single, "rectangle.split.2x1", "Simple"),
                                 (DrawerDisplayMode.double, "square.grid.2x2.fill", "Double")
                             ], id: \.0) { (mode, icon, label) in
                                 VStack(spacing: 10) {
                                     ZStack {
                                         Circle()
                                             .fill(currentDisplayMode == mode ?
                                                   Color.accentColor : Color.gray.opacity(0.2))
                                             .frame(width: 56, height: 56)
                                         
                                         Image(systemName: icon)
                                             .font(.system(size: 24))
                                             .foregroundColor(currentDisplayMode == mode ? .white : .primary)
                                     }
                                     
                                     Text(label)
                                         .font(.system(size: 11))
                                         .foregroundColor(currentDisplayMode == mode ? .primary : .secondary)
                                 }
                                 .onTapGesture {
                                     withAnimation(.easeInOut(duration: 0.2)) {
                                         displayModeString = mode.rawValue
                                         
                                         Task { @MainActor in
                                             DrawerManager.shared.setDisplayMode(mode)
                                         }
                                     }
                                 }
                             }
                         }
                         .frame(maxWidth: .infinity)
                     }
                     .padding()
                 }
                 
                 // APPEARANCE SECTION - 🔥 SECTION MODIFIÉE
                 GroupBox {
                     VStack(alignment: .leading, spacing: 16) {
                         HStack {
                             Image(systemName: "paintbrush.pointed")
                                 .foregroundColor(.secondary)
                             Text("Appearance")
                                 .font(.system(size: 14, weight: .semibold))
                             Spacer()
                         }
                         
                         if currentDisplayMode == .minimal {
                             HStack(spacing: 30) {
                                 // Light Mode Color
                                 VStack(alignment: .leading, spacing: 8) {
                                     Label("Background (Light)", systemImage: "sun.max")
                                         .font(.system(size: 11))
                                         .foregroundColor(.secondary)
                                     
                                     ColorPicker("", selection: Binding(
                                         get: { Color(red: bgLightR, green: bgLightG, blue: bgLightB) },
                                         set: { newColor in
                                             if let components = NSColor(newColor).cgColor.components {
                                                 bgLightR = Double(components[0])
                                                 bgLightG = Double(components[1])
                                                 bgLightB = Double(components[2])
                                                 DrawerManager.shared.updateContent()
                                             }
                                         }
                                     ))
                                     .labelsHidden()
                                     .scaleEffect(1.2)
                                     .onChange(of: bgLightR) { _, _ in
                                         windowManager.ensureColorPanelIsPositioned()
                                     }
                                     .onChange(of: bgLightG) { _, _ in
                                         windowManager.ensureColorPanelIsPositioned()
                                     }
                                     .onChange(of: bgLightB) { _, _ in
                                         windowManager.ensureColorPanelIsPositioned()
                                     }
                                 }
                                 
                                 // Dark Mode Color
                                 VStack(alignment: .leading, spacing: 8) {
                                     Label("Background (Dark)", systemImage: "moon.fill")
                                         .font(.system(size: 11))
                                         .foregroundColor(.secondary)
                                     
                                     ColorPicker("", selection: Binding(
                                         get: { Color(red: bgDarkR, green: bgDarkG, blue: bgDarkB) },
                                         set: { newColor in
                                             if let components = NSColor(newColor).cgColor.components {
                                                 bgDarkR = Double(components[0])
                                                 bgDarkG = Double(components[1])
                                                 bgDarkB = Double(components[2])
                                                 DrawerManager.shared.updateContent()
                                             }
                                         }
                                     ))
                                     .labelsHidden()
                                     .scaleEffect(1.2)
                                     .onChange(of: bgDarkR) { _, _ in
                                         windowManager.ensureColorPanelIsPositioned()
                                     }
                                     .onChange(of: bgDarkG) { _, _ in
                                         windowManager.ensureColorPanelIsPositioned()
                                     }
                                     .onChange(of: bgDarkB) { _, _ in
                                         windowManager.ensureColorPanelIsPositioned()
                                     }
                                 }
                                 
                                 // 🔥 BOUTON MODIFIÉ - Navigation Blur Settings
                                 VStack(alignment: .leading, spacing: 8) {
                                     Label("Navigation Blur", systemImage: "drop.fill")
                                         .font(.system(size: 11))
                                         .foregroundColor(.secondary)
                                     
                                     Button(action: {
                                         // 🔥 CHANGÉ: Appel via windowManager au lieu du code inline
                                         windowManager.showNavigationBlurSettings()
                                     }) {
                                         Image(systemName: "slider.horizontal.3")
                                             .font(.system(size: 20))
                                             .frame(width: 44, height: 44)
                                             .background(
                                                 RoundedRectangle(cornerRadius: 8)
                                                     .fill(Color.blue.opacity(0.2))
                                                     .overlay(
                                                         RoundedRectangle(cornerRadius: 8)
                                                             .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                                     )
                                             )
                                     }
                                     .buttonStyle(PlainButtonStyle())
                                 }
                             }
                         } else {
                             Text("Appearance settings for \(currentDisplayMode.rawValue) mode")
                                 .font(.system(size: 12))
                                 .foregroundColor(.secondary)
                                 .padding(.vertical, 20)
                         }
                     }
                     .padding()
                 }
                 
                 // DRAWER SIZE adaptatif - PAS DE CHANGEMENT
                 GroupBox {
                     VStack(alignment: .leading, spacing: 16) {
                         HStack {
                             Image(systemName: currentDisplayMode == .minimal ? "square.grid.2x2.fill" :
                                             currentDisplayMode == .double ? "rectangle.split.2x1" : "rectangle")
                                 .foregroundColor(.secondary)
                             Text("Drawer Size")
                                 .font(.system(size: 14, weight: .semibold))
                             Spacer()
                         }
                         
                         VStack(spacing: 12) {
                             HStack {
                                 Image(systemName: "arrow.left.and.right")
                                     .foregroundColor(.secondary)
                                     .frame(width: 20)
                                 Text("Width:")
                                     .frame(width: 60, alignment: .leading)
                                 
                                 Slider(value: currentWidth, in: currentDisplayMode == .double ? 0.65...0.95 : 0.4...0.8)
                                     .onChange(of: currentWidth.wrappedValue) { _, newValue in
                                         switch currentDisplayMode {
                                         case .single:
                                             DrawerManager.shared.drawerWidth = newValue
                                         case .double:
                                             DrawerManager.shared.drawerWidthDouble = newValue
                                         case .minimal:
                                             // 🆕 AJOUTER CES LIGNES
                                             UserDefaults.standard.set(newValue, forKey: "minimalWidth")
                                             DrawerManager.shared.drawerWidth = newValue  // Utiliser drawerWidth pour minimal aussi
                                         }
                                         if DrawerManager.shared.isDrawerVisible {
                                             DrawerManager.shared.updateDrawerWidth()
                                         }
                                     }
                                 
                                 Text("\(Int(currentWidth.wrappedValue * 100))%")
                                     .font(.system(size: 11, design: .monospaced))
                                     .frame(width: 40)
                             }
                             
                             HStack {
                                 Image(systemName: "arrow.up.and.down")
                                     .foregroundColor(.secondary)
                                     .frame(width: 20)
                                 Text("Height:")
                                     .frame(width: 60, alignment: .leading)
                                 
                                 Slider(value: $drawerHeightPercent, in: 0.3...0.7)
                                     .onChange(of: drawerHeightPercent) { _, newValue in
                                         DrawerManager.shared.drawerHeightPercent = newValue
                                         if DrawerManager.shared.isDrawerVisible {
                                             DrawerManager.shared.updateDrawerHeight()
                                         }
                                     }
                                 
                                 Text("\(Int(drawerHeightPercent * 100))%")
                                     .font(.system(size: 11, design: .monospaced))
                                     .frame(width: 40)
                             }
                         }
                     }
                     .padding()
                 }
                 
                 Spacer()
                 
                 Divider()
                 
                 // Toggles en bas - PAS DE CHANGEMENT
                 HStack(spacing: 24) {
                     Toggle("Launch at startup", isOn: $launchAtLogin)
                         .onChange(of: launchAtLogin) { _, newValue in
                             if #available(macOS 13.0, *) {
                                 DrawerAppDelegate.setLaunchAtLogin(newValue)
                             }
                         }
                     
                     Toggle("Menu bar icon", isOn: $menuBarIcon)
                         .onChange(of: menuBarIcon) { _, newValue in
                             // Utiliser NotificationCenter car AppDelegate non accessible
                             NotificationCenter.default.post(
                                 name: NSNotification.Name("MenuBarIconToggled"),
                                 object: nil,
                                 userInfo: ["enabled": newValue]
                             )
                         }
                                         
                     Spacer()
                 }
                 .font(.system(size: 12))
             }
             .padding()
             .frame(minWidth: 600, minHeight: 500)
             .tabItem {
                 Label("General", systemImage: "gear")
             }
             .tag(0)
             
             .onAppear {
                 // Synchroniser à l'apparition
                 let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? "single"
                 if let mode = DrawerDisplayMode(rawValue: savedMode) {
                     displayModeString = savedMode
                 }
             }
             .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                 // Écouter les changements de UserDefaults
                 let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? "single"
                 if savedMode != displayModeString {
                     withAnimation(.easeInOut(duration: 0.2)) {
                         displayModeString = savedMode
                     }
                 }
             }
             // Les autres onglets restent EXACTEMENT pareils
             TriggerZoneTab(
                 triggerMode: $triggerMode,
                 triggerZoneWidth: $triggerZoneWidth,
                 showDelay: $showDelay,
                 hideDelay: $hideDelay
             )
             .tabItem {
                 Label("Trigger Zone", systemImage: "hand.tap")
             }
             .tag(1)
             
             NotesPreferencesTab(
                 notesEnabled: $notesEnabled,
                 notesPanelWidth: $notesPanelWidth,
                 notesColor: $notesColor
             )
             .tabItem {
                 Label("Notes", systemImage: "note.text")
             }
             .tag(2)
             
             TipsTab()
                 .tabItem {
                     Label("Tips", systemImage: "lightbulb")
                 }
                 .tag(3)
             
             InfoTab()
                 .tabItem {
                     Label("Info", systemImage: "info.circle")
                 }
                 .tag(4)
         }
         .frame(width: 650, height: 650)
         .onAppear {  // 🆕 AJOUT
             // Synchroniser avec le mode actuel du DrawerManager
             displayModeString = DrawerManager.shared.displayMode.rawValue
             
             Task { @MainActor in
                 DrawerManager.shared.isLockedOpen = true
                 if !DrawerManager.shared.isDrawerVisible {
                     DrawerManager.shared.showDrawer()
                 }
             }
             
             // 🆕 NOUVEAU - Enregistrer la fenêtre preferences dans le manager
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                 if let prefsWindow = NSApp.windows.first(where: { $0.title == "Preferences" }) {
                     windowManager.preferencesWindow = prefsWindow
                 }
             }
         }
         .onChange(of: selectedTab) { oldValue, newValue in
             // EXACTEMENT pareil qu'avant
             if oldValue == 1 && newValue != 1 {
                 NotificationCenter.default.post(
                     name: Notification.Name("StopTriggerZoneVisualization"),
                     object: nil
                 )
             }
             
             Task { @MainActor in
                 switch newValue {
                 case 0:
                     DrawerManager.shared.isLockedOpen = true
                     if !DrawerManager.shared.isDrawerVisible {
                         DrawerManager.shared.showDrawer()
                     }
                 case 1:
                     DrawerManager.shared.isLockedOpen = false
                     DrawerManager.shared.hideDrawer()
                 case 2:
                     if notesEnabled {
                         DrawerManager.shared.isLockedOpen = true
                         if !DrawerManager.shared.isDrawerVisible {
                             DrawerManager.shared.showDrawer()
                         }
                     } else {
                         DrawerManager.shared.isLockedOpen = false
                     }
                 case 3:
                     DrawerManager.shared.isLockedOpen = false
                 default:
                     DrawerManager.shared.isLockedOpen = false
                 }
             }
         }
     }
 }


// 🆕 Composant pour le bouton de couleur
struct ColorButton: View {
    @Binding var color: Color
    
    var body: some View {
        ColorPicker("", selection: $color)
            .labelsHidden()
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
    }
}


// 🆕 Composant pour le contrôle de blur
struct BlurControl: View {
    @Binding var opacity: Double
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                
                // Indicateur visuel du niveau
                Circle()
                    .fill(Color.white.opacity(opacity * 0.8))
                    .frame(width: 30, height: 30)
                    .blur(radius: (1 - opacity) * 10)
                    .overlay(
                        Image(systemName: "drop.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    )
            }
            .onHover { hovering in
                isHovering = hovering
            }
            
            // Slider vertical caché qui apparaît au survol
            if isHovering {
                Slider(value: $opacity, in: 0.3...1.0)
                    .frame(width: 100)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 100)
            }
        }
    }
}


// 🆕 NOUVEL ONGLET TIPS
struct TipsTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "lightbulb")
                                .foregroundColor(.orange)
                            Text("Tips & Tricks")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 20) {
                            TipRow(
                                icon: "house",
                                title: "Custom Home Folder",
                                description: "Hold ⇧ Shift and click the Home 🏠 button to set the current folder as your custom home."
                            )
                            
                            Divider()
                            
                            TipRow(
                                icon: "star.square.on.square",
                                title: "Minimal View Navigation Magic",
                                description: "Hold ⇧ Shift in Minimal View to reveal navigation zones. Click the center zone to add the current folder to your favorites/workspaces."
                            )
                            
                            Divider()
                            
                            TipRow(
                                icon: "hand.draw",
                                title: "Minimal View Workspaces",
                                description: "Drag folders to the top bar in Minimal View to create workspaces for quick access."
                            )
                            
                            Divider()
                            
                            TipRow(
                                icon: "rectangle.and.hand.point.up.left",
                                title: "Multi-Selection",
                                description: "⌘+Click for multiple items\n⇧+Click for range selection\nDraw rectangle to select multiple files"
                            )
                            
                            Divider()
                            
                            TipRow(
                                icon: "sidebar.right",
                                title: "Notes Panel",
                                description: "Enable the Notes panel in Single View to keep quick notes alongside your files. Perfect for project documentation or file annotations."
                            )
                            
                            Divider()
                            
                            TipRow(
                                icon: "eye.slash",
                                title: "Quick Hide",
                                description: "Click anywhere outside the drawer or press Esc to quickly hide it. The drawer remembers your last location when you reopen it."
                            )
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
        .padding()
    }
}

struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}


// MARK: - Trigger Zone Tab avec visualisation live
struct TriggerZoneTab: View {
    @Binding var triggerMode: String
    @Binding var triggerZoneWidth: Double
    @Binding var showDelay: Double
    @Binding var hideDelay: Double
    
    private let fixedTriggerZoneHeight: Double = 25.0
    
    @State private var visualizationWindow: NSWindow?
    @State private var isVisualizingLive = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Mode de déclenchement
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "hand.tap")
                            .foregroundColor(.secondary)
                        Text("Trigger Mode")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    
                    HStack(spacing: 30) {
                        RadioButton(
                            title: "Click",
                            subtitle: "Click in the zone",
                            isSelected: triggerMode == "click",
                            action: {
                                // 🆕 REMPLACEZ juste par ces 2 lignes :
                                triggerMode = "click"
                                UserDefaults.standard.set("click", forKey: "triggerMode")
                            }
                        )

                        RadioButton(
                            title: "Scroll Wheel",
                            subtitle: "Scroll up in the zone",
                            isSelected: triggerMode == "scroll",
                            action: {
                                // 🆕 REMPLACEZ juste par ces 2 lignes :
                                triggerMode = "scroll"
                                UserDefaults.standard.set("scroll", forKey: "triggerMode")
                            }
                        )

                        RadioButton(
                            title: "Hover",
                            subtitle: "Simply hover over the zone",
                            isSelected: triggerMode == "hover",
                            action: {
                                // 🆕 REMPLACEZ juste par ces 2 lignes :
                                triggerMode = "hover"
                                UserDefaults.standard.set("hover", forKey: "triggerMode")
                            }
                        )                    }
                }
                .padding()
            }
            
            // Dimensions de la zone
            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundColor(.secondary)
                        Text("Zone Dimensions")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Text("Width:")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            
                            Slider(value: $triggerZoneWidth, in: 10...40, step: 5)
                                .onChange(of: triggerZoneWidth) { _, _ in
                                    updateLiveVisualization()
                                    // 🆕 Optionnel: Mettre à jour aussi la trigger zone en temps réel
                                    if let appDelegate = NSApp.delegate as? DrawerAppDelegate {
                                        appDelegate.updateTriggerMode()
                                    }
                                }
                            
                            Text("\(Int(triggerZoneWidth))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                    
                    // Note sur la visualisation
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: 11))
                        Text("The zone automatically appears at the top of the screen while you adjust the settings")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            // Délais
            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.secondary)
                        Text("Timing Settings")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Text("Show delay:")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            
                            Slider(value: $showDelay, in: 0...2, step: 0.1)
                            
                            Text(String(format: "%.1fs", showDelay))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                        
                        HStack {
                            Text("Hide delay:")
                                .font(.system(size: 12))
                                .frame(width: 80, alignment: .leading)
                            
                            Slider(value: $hideDelay, in: 0...2, step: 0.1)
                            
                            Text(String(format: "%.1fs", hideDelay))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                    
                    Text("Fine-tune how quickly the drawer responds")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            Spacer()
            
            // Bouton de test
            HStack {
                Spacer()
                
                Button(action: {
                    Task { @MainActor in
                        DrawerManager.shared.showDrawer()
                    }
                }) {
                    Label("Test the drawer", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startLiveVisualization()
        }
        .onDisappear {
            stopLiveVisualization()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("StopTriggerZoneVisualization")
        )) { _ in
            stopLiveVisualization()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSNotification.Name("DrawerVisibilityChanged")
        )) { _ in
            if DrawerManager.shared.isDrawerVisible {
                visualizationWindow?.orderOut(nil)
            } else if isVisualizingLive {
                showTriggerZoneIndicator()
            }
        }
    }
    
    private func startLiveVisualization() {
        isVisualizingLive = true
        showTriggerZoneIndicator()
    }
    
    private func stopLiveVisualization() {
        isVisualizingLive = false
        visualizationWindow?.orderOut(nil)
        visualizationWindow = nil
    }
    
    private func updateLiveVisualization() {
        if isVisualizingLive {
            visualizationWindow?.orderOut(nil)
            showTriggerZoneIndicator()
        }
    }
    
    private func showTriggerZoneIndicator() {
        guard let screen = NSScreen.main else { return }
        
        let zoneWidthPixels = screen.frame.width * (triggerZoneWidth / 100.0)
        let zoneX = (screen.frame.width - zoneWidthPixels) / 2
        
        if visualizationWindow == nil {
            visualizationWindow = NSWindow(
                contentRect: NSRect.zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            visualizationWindow?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3)
            visualizationWindow?.level = .screenSaver
            visualizationWindow?.ignoresMouseEvents = true
            visualizationWindow?.collectionBehavior = [.canJoinAllSpaces]
        }
        
        visualizationWindow?.setFrame(
            NSRect(
                x: zoneX,
                y: screen.frame.maxY - fixedTriggerZoneHeight - 1,
                width: zoneWidthPixels,
                height: fixedTriggerZoneHeight + 2
            ),
            display: true
        )
        
        visualizationWindow?.orderFront(nil)
    }
}
// MARK: - Notes Preferences Tab (version complète)
struct NotesPreferencesTab: View {
    @Binding var notesEnabled: Bool
    @Binding var notesPanelWidth: Double
    @Binding var notesColor: String
    @State private var isTogglingNotes = false
    
    var currentNoteColor: Color {
        switch notesColor {
        case "yellow": return Color(red: 1, green: 0.98, blue: 0.82)
        case "blue": return Color(red: 0.88, green: 0.92, blue: 0.95)
        case "gray": return Color(red: 0.92, green: 0.92, blue: 0.92)
        case "green": return Color(red: 0.88, green: 0.95, blue: 0.88)
        case "black": return Color.black
        case "darkgray": return Color(white: 0.2)
        case "mediumgray": return Color(white: 0.35)
        case "charcoal": return Color(white: 0.15)
        default: return Color(red: 1, green: 0.98, blue: 0.82)
        }
    }

    var isDarkColor: Bool {
        ["black", "darkgray", "mediumgray", "charcoal"].contains(notesColor)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            // Colonne gauche - Paramètres
            VStack(spacing: 20) {
                // Activation
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundColor(.secondary)
                            Text("Notes Panel")
                                .font(.system(size: 14, weight: .semibold))
                            Text("(Only on single view)")
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                        }
                        
                        Toggle("Activer le panneau Notes", isOn: $notesEnabled)
                            .font(.system(size: 13, weight: .medium))
                            .disabled(isTogglingNotes)
                            .onChange(of: notesEnabled) { _, newValue in
                                if !isTogglingNotes {
                                    isTogglingNotes = true
                                    
                                    Task { @MainActor in
                                        DrawerManager.shared.setNotesEnabled(newValue)
                                        
                                        if newValue {
                                            // Activer : ouvrir et verrouiller le drawer
                                            DrawerManager.shared.isLockedOpen = true
                                            if !DrawerManager.shared.isDrawerVisible {
                                                DrawerManager.shared.showDrawer()
                                            }
                                        } else {
                                            // Désactiver : déverrouiller (le drawer se fermera selon le délai)
                                            DrawerManager.shared.isLockedOpen = false
                                        }
                                        
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        isTogglingNotes = false
                                    }
                                }
                            }
                    }
                    .padding()
                }
                
                if notesEnabled {
                    // Configuration largeur
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "arrow.left.and.right")
                                    .foregroundColor(.secondary)
                                Text("Size")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                            }
                            
                            HStack {
                                Text("Width:")
                                    .font(.system(size: 12))
                                    .frame(width: 70, alignment: .leading)
                                
                                Slider(value: $notesPanelWidth, in: 200...400, step: 10)
                                    .onChange(of: notesPanelWidth) { _, newValue in
                                        Task { @MainActor in
                                            DrawerManager.shared.notesPanelWidth = newValue
                                            DrawerManager.shared.setupPanel()
                                            DrawerManager.shared.updateContent()
                                        }
                                    }
                                
                                Text("\(Int(notesPanelWidth)) px")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 60)
                            }
                        }
                        .padding()
                    }
                    
                    // Sélection de couleur
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "paintpalette")
                                    .foregroundColor(.secondary)
                                Text("Note colors")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                            }
                            
                            VStack(spacing: 12) {
                                // Première ligne
                                HStack(spacing: 16) {
                                    ForEach([
                                        ("yellow", Color(red: 1, green: 0.98, blue: 0.82), "Yellow", false),
                                        ("blue", Color(red: 0.88, green: 0.92, blue: 0.95), "Blue", false),
                                        ("gray", Color(red: 0.92, green: 0.92, blue: 0.92), "Light gray", false),
                                        ("green", Color(red: 0.88, green: 0.95, blue: 0.88), "Green", false)
                                    ], id: \.0) { option in
                                        VStack(spacing: 8) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(option.1)
                                                    .frame(width: 50, height: 50)
                                                    .shadow(radius: 2)
                                                
                                                if notesColor == option.0 {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(option.3 ? .white : .blue)
                                                        .font(.system(size: 20))
                                                        .shadow(radius: 1)
                                                }
                                            }
                                            
                                            Text(option.2)
                                                .font(.system(size: 10))
                                                .foregroundColor(notesColor == option.0 ? .primary : .secondary)
                                        }
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                notesColor = option.0
                                            }
                                        }
                                    }
                                }
                                
                                // Deuxième ligne
                                HStack(spacing: 16) {
                                    ForEach([
                                        ("black", Color.black, "Black", true),
                                        ("darkgray", Color(white: 0.2), "Dark gray", true),
                                        ("mediumgray", Color(white: 0.35), "Mid gray", true),
                                        ("charcoal", Color(white: 0.15), "Charcoal", true)
                                    ], id: \.0) { option in
                                        VStack(spacing: 8) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(option.1)
                                                    .frame(width: 50, height: 50)
                                                    .shadow(radius: 2)
                                                
                                                if notesColor == option.0 {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(option.3 ? .white : .blue)
                                                        .font(.system(size: 20))
                                                        .shadow(radius: 1)
                                                }
                                            }
                                            
                                            Text(option.2)
                                                .font(.system(size: 10))
                                                .foregroundColor(notesColor == option.0 ? .primary : .secondary)
                                        }
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                notesColor = option.0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // Colonne droite - Aperçu
            if notesEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "eye")
                                .foregroundColor(.secondary)
                            Text("Preview")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        
                        // Simulation d'une note
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Sample note")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isDarkColor ? .white : .black.opacity(0.7))
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This is a sample note")
                                    .font(.system(size: 12))
                                    .foregroundColor(isDarkColor ? .white.opacity(0.9) : .black.opacity(0.8))
                                
                                Text("Notes will appear with this background color when you use the Notes panel in the drawer.")
                                    .font(.system(size: 11))
                                    .foregroundColor(isDarkColor ? .white.opacity(0.9) : .black.opacity(0.8))
                                    .lineLimit(3)
                                
                                Spacer()
                                
                                HStack {
                                    Text("Modified: Today, 2:30 PM")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(currentNoteColor)
                        .cornerRadius(8)
                        .animation(.easeInOut(duration: 0.3), value: notesColor)
                        
                        Text("Current width: \(Int(notesPanelWidth)) pixels")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: CGFloat(notesPanelWidth), alignment: .leading)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .padding()
                }
                .frame(minWidth: 300)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Info Tab (version complète)
struct InfoTab: View {
    var body: some View {
        VStack(spacing: 30) {
            GroupBox {
                Spacer()
                
                HStack(spacing: 30) {
                    // Logo
                    Group {
                        if let nsImage = NSImage(named: "AppIcon") {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.8, blue: 0.3),
                                            Color(red: 0.2, green: 0.5, blue: 0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                
                                Image(systemName: "rectangle.split.2x1.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .padding(30)
                            }
                        }
                    }
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    
                    // Infos
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DrawerApp")
                            .font(.system(size: 32, weight: .medium))
                        
                        Text("Version 2.4.2")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            Badge(text: "Special thanks", color: .blue)
                        }
                   
                        // Description
                        VStack(spacing: 16) {
                            Text("DrawerApp is a navigation drawer that appears at the top of the macOS screen to quickly access your files without leaving the current application. It makes it easy to add files to your work software with single or double panel modes, particularly useful for creative workflows requiring frequent access to resources.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(4)
                                .frame(maxWidth: 500)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 60)
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button("Used with care. This is a beta !") {
                        // Action donation
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                    .padding(.horizontal, 40)
                
                Text("Copyright 2025 DrawerApp")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// MARK: - Composants UI réutilisables
struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            )
    }
}



struct RadioButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.system(size: 16))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}
