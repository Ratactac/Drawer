// DrawerApp_MinimalNavigationBlur.swift
// Système de navigation par blur avec Shift pour Minimal View
// Version avec couleurs séparées Navigation/Favoris

import SwiftUI
import AppKit

// MARK: - Manager de Navigation
@MainActor
class MinimalNavigationBlurManager: ObservableObject {
    static let shared = MinimalNavigationBlurManager()  // SINGLETON
    
    @Published var isShiftPressed = false
    @Published var mousePosition: CGPoint = .zero
    @Published var activeZone: ActiveZone = .none
    @Published var showDebugPanel = false
    @Published var showIconMenu = false
    @Published var iconMenuSide: Side = .left
    @Published var isSimulating = false
    
    // Paramètres DEBUG ajustables
    @AppStorage("blurIntensityNavigation") var blurIntensityNavigation: Double = 12
    @AppStorage("blurIntensityFavorite") var blurIntensityFavorite: Double = 20
    @AppStorage("backgroundOpacityNavigation") var backgroundOpacityNavigation: Double = 0.7
    @AppStorage("backgroundOpacityFavorite") var backgroundOpacityFavorite: Double = 0.85
    @AppStorage("blurOpacityNavigation") var blurOpacityNavigation: Double = 0.9
    @AppStorage("blurOpacityFavorite") var blurOpacityFavorite: Double = 0.95
    
    // 🎯 COULEURS SÉPARÉES NAVIGATION/FAVORIS
    // Navigation (bleu par défaut)
    @AppStorage("blurColorNavR") var colorNavR: Double = 0.05
    @AppStorage("blurColorNavG") var colorNavG: Double = 0.05
    @AppStorage("blurColorNavB") var colorNavB: Double = 0.1
    
    // Favoris (violet par défaut pour différencier)
    @AppStorage("blurColorFavR") var colorFavR: Double = 0.1
    @AppStorage("blurColorFavG") var colorFavG: Double = 0.05
    @AppStorage("blurColorFavB") var colorFavB: Double = 0.1
    
    // Propriétés calculées pour les couleurs
    var navigationColor: Color {
        Color(red: colorNavR, green: colorNavG, blue: colorNavB)
    }
    
    var favoritesColor: Color {
        Color(red: colorFavR, green: colorFavG, blue: colorFavB)
    }
    
    // Autres paramètres
    @AppStorage("navigationAnimationDuration") var navigationAnimationDuration: Double = 0.2
    @AppStorage("favoriteAnimationDuration") var favoriteAnimationDuration: Double = 0.4
    @AppStorage("favoriteAnimationDelay") var favoriteAnimationDelay: Double = 0.3
    @AppStorage("favoriteActivationTime") var favoriteActivationTime: Double = 0.3
    
    @AppStorage("navigationCornerRadius") var navigationCornerRadius: Double = 40
    @AppStorage("centerCircleRadius") var centerCircleRadius: Double = 60
    @AppStorage("navigationZoneWidth") var navigationZoneWidth: Double = 0.35
    
    enum ActiveZone: String {
        case none = "Aucune"
        case back = "Retour (←)"
        case forward = "Avancer (→)"
        case addFavorite = "Ajouter Favori"
        case all = "Toutes les zones"
    }
    
    enum Side {
        case left, right
    }
    
    private var eventMonitor: Any?
    private var clickMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var drawerWidth: CGFloat = 0
    private var favoriteTimer: Timer?
    private var pendingFavoriteActivation = false
    
    private init() {
        setupEventMonitors()
        setupNotifications()
        objectWillChange.send()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activateLeftBlur),
            name: NSNotification.Name("ActivateBlurLeft"),
            object: nil
        )
    }
    
    @objc private func activateLeftBlur() {
        simulateZone(.back)
    }
    
    func simulateZone(_ zone: ActiveZone) {
        isSimulating = true
        withAnimation(.easeInOut(duration: navigationAnimationDuration)) {
            activeZone = zone
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.isSimulating && !self.isShiftPressed {
                self.isSimulating = false
                withAnimation(.easeInOut(duration: 0.1)) {
                    self.activeZone = .none
                }
            }
        }
    }
    
    private func setupEventMonitors() {
        // Détection Shift
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                let wasPressed = self?.isShiftPressed ?? false
                self?.isShiftPressed = event.modifierFlags.contains(.shift)
                
                if wasPressed && !(self?.isShiftPressed ?? false) && !(self?.isSimulating ?? false) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        self?.activeZone = .none
                    }
                }
                
                if !wasPressed && (self?.isShiftPressed ?? false) {
                    self?.isSimulating = false
                }
            }
            return event
        }
        
        // Suivi souris
        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.isShiftPressed || self.isSimulating else { return }
                
                let location = NSEvent.mouseLocation
                if let window = NSApp.keyWindow {
                    let windowLocation = window.convertFromScreen(NSRect(origin: location, size: .zero)).origin
                    self.updateActiveZone(at: windowLocation, windowWidth: window.frame.width)
                }
            }
            return event
        }
        
        // Click detection
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                guard (self.isShiftPressed || self.isSimulating) && self.activeZone != .none else { return }
                self.handleClick()
            }
            return event
        }
    }
    
    private func updateActiveZone(at location: CGPoint, windowWidth: CGFloat) {
        if activeZone == .all {
            return
        }
        
        if isSimulating && activeZone != .all {
            return
        }
        
        drawerWidth = windowWidth
        let centerX = windowWidth / 2
        let x = location.x
        
        let topBarHeight: CGFloat = 44
        let bottomBarHeight: CGFloat = 44
        
        if location.y < topBarHeight || location.y > (NSApp.keyWindow?.frame.height ?? 600) - bottomBarHeight {
            withAnimation(.easeInOut(duration: 0.1)) {
                activeZone = .none
            }
            return
        }
        
        let distanceFromCenter = abs(x - centerX)
        
        // Zone centrale : AddFavorite avec TIMER
        if distanceFromCenter <= centerCircleRadius {
            if activeZone != .addFavorite && !pendingFavoriteActivation {
                pendingFavoriteActivation = true
                favoriteTimer?.invalidate()
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(favoriteActivationTime * 1_000_000_000))
                    
                    guard pendingFavoriteActivation else { return }
                    
                    withAnimation(.easeInOut(duration: favoriteAnimationDuration)
                        .delay(favoriteAnimationDelay)) {
                        activeZone = .addFavorite
                    }
                    pendingFavoriteActivation = false
                }
            }
        } else {
            pendingFavoriteActivation = false
            
            if x < centerX {
                withAnimation(.easeInOut(duration: navigationAnimationDuration)) {
                    activeZone = .back
                }
            } else {
                withAnimation(.easeInOut(duration: navigationAnimationDuration)) {
                    activeZone = .forward
                }
            }
        }
    }
    
    private func handleClick() {
        switch activeZone {
        case .back:
            navigateBack()
        case .forward:
            navigateForward()
        case .addFavorite:
            addCurrentFolderToFavorites()
        case .none, .all:
            break
        }
    }
    
    func addCurrentFolderToFavorites() {
        NotificationCenter.default.post(
            name: Notification.Name("AddCurrentToFavorites"),
            object: nil,
            userInfo: ["showMenu": true]
        )
    }
    
    func navigateBack() {
        NotificationCenter.default.post(
            name: Notification.Name("MinimalNavigateBack"),
            object: nil
        )
    }
    
    func navigateForward() {
        NotificationCenter.default.post(
            name: Notification.Name("MinimalNavigateForward"),
            object: nil
        )
    }
    
    func startDemoMode() {
        isSimulating = true
        
        Task { @MainActor in
            while isSimulating {
                activeZone = .back
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                if !isSimulating { break }
                activeZone = .forward
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                if !isSimulating { break }
                activeZone = .addFavorite
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            activeZone = .none
        }
    }
    
    func stopDemoMode() {
        isSimulating = false
        activeZone = .none
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Overlay de Blur avec couleurs séparées
struct MinimalNavigationBlurOverlay: View {
    @ObservedObject var manager: MinimalNavigationBlurManager
    let fileAreaFrame: CGRect
    
    var body: some View {
        GeometryReader { geometry in
            // ✅ Utiliser fileAreaFrame.width au lieu de geometry.size.width
            let width = fileAreaFrame.width
            let centerX = width / 2
            
            ZStack {
                if manager.activeZone == .all {
                    allZonesView(width: width, centerX: centerX)
                } else {
                    singleZoneView(width: width, centerX: centerX)
                }
            }
            .frame(width: width, height: fileAreaFrame.height)
            .clipped()  // ✅ Couper tout ce qui dépasse
        }
        .frame(width: fileAreaFrame.width, height: fileAreaFrame.height)
        .clipped()  // ✅ Double sécurité
    }
    
    @ViewBuilder
    private func allZonesView(width: CGFloat, centerX: CGFloat) -> some View {
        ZStack {
            // Zones navigation avec couleur navigation
            HStack(spacing: 0) {
                // Zone GAUCHE (Back)
                UnevenRoundedRectangle(
                    topLeadingRadius: manager.navigationCornerRadius,
                    bottomLeadingRadius: manager.navigationCornerRadius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(manager.navigationColor.opacity(manager.backgroundOpacityNavigation))  // 🎯 navigationColor
                .frame(width: centerX)
                .overlay(
                    VisualEffectBlur(
                        material: .hudWindow,
                        blendingMode: .withinWindow
                    )
                    .opacity(manager.blurOpacityNavigation)
                    .blur(radius: manager.blurIntensityNavigation)
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: manager.navigationCornerRadius,
                        bottomLeadingRadius: manager.navigationCornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
                .overlay(
                    Text("← Back")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                        .position(x: centerX / 2, y: fileAreaFrame.height / 2)
                )
                
                // Zone DROITE (Forward)
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: manager.navigationCornerRadius,
                    topTrailingRadius: manager.navigationCornerRadius
                )
                .fill(manager.navigationColor.opacity(manager.backgroundOpacityNavigation))  // 🎯 navigationColor
                .frame(width: centerX)
                .overlay(
                    VisualEffectBlur(
                        material: .hudWindow,
                        blendingMode: .withinWindow
                    )
                    .opacity(manager.blurOpacityNavigation)
                    .blur(radius: manager.blurIntensityNavigation)
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: manager.navigationCornerRadius,
                        topTrailingRadius: manager.navigationCornerRadius
                    )
                )
                .overlay(
                    Text("Forward →")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                        .position(x: centerX / 2, y: fileAreaFrame.height / 2)
                )
            }
            .animation(.easeInOut(duration: manager.navigationAnimationDuration), value: manager.activeZone)
            
            // Zone CENTRALE avec couleur favoris
            Circle()
                .fill(manager.favoritesColor.opacity(manager.backgroundOpacityFavorite))  // 🎯 favoritesColor
                .frame(width: manager.centerCircleRadius * 2, height: manager.centerCircleRadius * 2)
                .overlay(
                    VisualEffectBlur(
                        material: .hudWindow,
                        blendingMode: .withinWindow
                    )
                    .opacity(manager.blurOpacityFavorite)
                    .blur(radius: manager.blurIntensityFavorite)
                    .clipShape(Circle())
                )
                .overlay(
                    Text("★ Favorite")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                )
                .position(x: centerX, y: fileAreaFrame.height / 2)
                .animation(
                    .easeInOut(duration: manager.favoriteAnimationDuration)
                        .delay(manager.favoriteAnimationDelay),
                    value: manager.activeZone
                )
        }
    }
    
    @ViewBuilder
    private func singleZoneView(width: CGFloat, centerX: CGFloat) -> some View {
        ZStack {
            // ZONES NAVIGATION avec couleur navigation
            HStack(spacing: 0) {
                // Zone BACK
                if manager.activeZone == .back || manager.activeZone == .addFavorite {
                    UnevenRoundedRectangle(
                        topLeadingRadius: manager.navigationCornerRadius,
                        bottomLeadingRadius: manager.navigationCornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(manager.navigationColor.opacity(  // 🎯 navigationColor
                        manager.activeZone == .back ?
                        manager.backgroundOpacityNavigation :
                        manager.backgroundOpacityNavigation * 0.5
                    ))
                    .frame(width: centerX)
                    .overlay(
                        VisualEffectBlur(
                            material: .hudWindow,
                            blendingMode: .withinWindow
                        )
                        .opacity(manager.activeZone == .back ?
                                 manager.blurOpacityNavigation :
                                 manager.blurOpacityNavigation * 0.5)
                        .blur(radius: manager.activeZone == .back ?
                              manager.blurIntensityNavigation :
                              manager.blurIntensityNavigation * 0.5)
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: manager.navigationCornerRadius,
                            bottomLeadingRadius: manager.navigationCornerRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )
                } else {
                    Spacer().frame(width: centerX)
                }
                
                // Zone FORWARD
                if manager.activeZone == .forward || manager.activeZone == .addFavorite {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: manager.navigationCornerRadius,
                        topTrailingRadius: manager.navigationCornerRadius
                    )
                    .fill(manager.navigationColor.opacity(  // 🎯 navigationColor
                        manager.activeZone == .forward ?
                        manager.backgroundOpacityNavigation :
                        manager.backgroundOpacityNavigation * 0.5
                    ))
                    .frame(width: centerX)
                    .overlay(
                        VisualEffectBlur(
                            material: .hudWindow,
                            blendingMode: .withinWindow
                        )
                        .opacity(manager.activeZone == .forward ?
                                 manager.blurOpacityNavigation :
                                 manager.blurOpacityNavigation * 0.5)
                        .blur(radius: manager.activeZone == .forward ?
                              manager.blurIntensityNavigation :
                              manager.blurIntensityNavigation * 0.5)
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: manager.navigationCornerRadius,
                            topTrailingRadius: manager.navigationCornerRadius
                        )
                    )
                } else {
                    Spacer().frame(width: centerX)
                }
            }
            
            // ZONE FAVORITE avec couleur favoris
            if manager.activeZone == .addFavorite {
                Circle()
                    .fill(manager.favoritesColor.opacity(manager.backgroundOpacityFavorite))  // 🎯 favoritesColor
                    .frame(width: manager.centerCircleRadius * 2, height: manager.centerCircleRadius * 2)
                    .overlay(
                        VisualEffectBlur(
                            material: .hudWindow,
                            blendingMode: .withinWindow
                        )
                        .opacity(manager.blurOpacityFavorite)
                        .blur(radius: manager.blurIntensityFavorite)
                        .clipShape(Circle())
                    )
                    .position(x: centerX, y: fileAreaFrame.height/2)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                    .animation(
                        .easeInOut(duration: manager.favoriteAnimationDuration)
                            .delay(manager.favoriteAnimationDelay),
                        value: manager.activeZone == .addFavorite
                    )
            }
        }
    }
}

// MARK: - Debug Panel avec couleurs séparées
struct MinimalBlurDebugPanel: View {
    @ObservedObject var manager: MinimalNavigationBlurManager
    @State private var selectedColorTarget: ColorTarget = .navigation
    
    enum ColorTarget: String, CaseIterable {
        case navigation = "Navigation"
        case favorites = "Favoris"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Navigation Zones
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Navigation Zones", systemImage: "arrow.left.and.right")
                                .font(.caption.bold())
                            
                            SliderRow(value: $manager.blurIntensityNavigation, range: 0...30, label: "Blur Intensity", color: .green)
                            SliderRow(value: $manager.backgroundOpacityNavigation, range: 0...1, label: "Background", color: .blue)
                            SliderRow(value: $manager.blurOpacityNavigation, range: 0...1, label: "Blur Opacity", color: .purple)
                            SliderRow(value: $manager.navigationCornerRadius, range: 0...500, label: "Corner Radius", color: .orange)
                            
                            Divider()
                            SliderRow(value: $manager.navigationAnimationDuration, range: 0.01...0.5, label: "Animation Speed", color: .pink)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Favorite Zone
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Favorite Zone", systemImage: "star")
                                .font(.caption.bold())
                            
                            SliderRow(value: $manager.blurIntensityFavorite, range: 0...40, label: "Blur Intensity", color: .green)
                            SliderRow(value: $manager.backgroundOpacityFavorite, range: 0...1, label: "Background", color: .blue)
                            SliderRow(value: $manager.blurOpacityFavorite, range: 0...1, label: "Blur Opacity", color: .purple)
                            SliderRow(value: $manager.centerCircleRadius, range: 30...200, label: "Circle Radius", color: .orange)
                            
                            Divider()
                            SliderRow(value: $manager.favoriteAnimationDelay, range: 0...1, label: "Animation Delay", color: .purple)
                            SliderRow(value: $manager.favoriteAnimationDuration, range: 0.05...1, label: "Animation Speed", color: .indigo)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 🎯 COULEURS SÉPARÉES
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Couleurs", systemImage: "paintpalette")
                                .font(.caption.bold())
                            
                            // Sélecteur de cible
                            Picker("Cible", selection: $selectedColorTarget) {
                                ForEach(ColorTarget.allCases, id: \.self) { target in
                                    Text(target.rawValue).tag(target)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .padding(.bottom, 8)
                            
                            // Sliders selon la cible
                            if selectedColorTarget == .navigation {
                                // Navigation colors
                                SliderRow(value: $manager.colorNavR, range: 0...1, label: "Rouge Nav", color: .red)
                                SliderRow(value: $manager.colorNavG, range: 0...1, label: "Vert Nav", color: .green)
                                SliderRow(value: $manager.colorNavB, range: 0...1, label: "Bleu Nav", color: .blue)
                                
                                // Preview
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(manager.navigationColor)
                                    .frame(height: 30)
                                    .overlay(
                                        Text("Navigation")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                    )
                            } else {
                                // Favorites colors
                                SliderRow(value: $manager.colorFavR, range: 0...1, label: "Rouge Fav", color: .red)
                                SliderRow(value: $manager.colorFavG, range: 0...1, label: "Vert Fav", color: .green)
                                SliderRow(value: $manager.colorFavB, range: 0...1, label: "Bleu Fav", color: .blue)
                                
                                // Preview
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(manager.favoritesColor)
                                    .frame(height: 30)
                                    .overlay(
                                        Text("Favoris")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                    )
                            }
                            
                            // Presets
                            Divider()
                            
                            HStack {
                                Button("Bleu") {
                                    if selectedColorTarget == .navigation {
                                        manager.colorNavR = 0.05
                                        manager.colorNavG = 0.05
                                        manager.colorNavB = 0.15
                                    } else {
                                        manager.colorFavR = 0.05
                                        manager.colorFavG = 0.05
                                        manager.colorFavB = 0.15
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Violet") {
                                    if selectedColorTarget == .navigation {
                                        manager.colorNavR = 0.15
                                        manager.colorNavG = 0.05
                                        manager.colorNavB = 0.15
                                    } else {
                                        manager.colorFavR = 0.15
                                        manager.colorFavG = 0.05
                                        manager.colorFavB = 0.15
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Rouge") {
                                    if selectedColorTarget == .navigation {
                                        manager.colorNavR = 0.15
                                        manager.colorNavG = 0.05
                                        manager.colorNavB = 0.05
                                    } else {
                                        manager.colorFavR = 0.15
                                        manager.colorFavG = 0.05
                                        manager.colorFavB = 0.05
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Composants Helper
struct SliderRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let color: Color
    
    var formattedValue: String {
        if range.upperBound <= 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)
            
            Slider(value: $value, in: range)
                .accentColor(color)
            
            Text(formattedValue)
                .font(.caption.monospaced())
                .frame(width: 40)
        }
    }
}

// MARK: - Menu de sélection d'icônes
struct IconSelectionMenu: View {
    @Binding var isPresented: Bool
    let side: MinimalNavigationBlurManager.Side
    let onSelect: (String, String) -> Void
    
    @State private var selectedIcon = "folder"
    @State private var customName = ""
    
    let icons = [
        "folder", "folder.badge.plus", "desktopcomputer",
        "doc", "photo", "music.note", "play.rectangle",
        "paintbrush", "hammer", "wrench.and.screwdriver",
        "terminal", "globe", "heart", "star", "flag",
        "tag", "bookmark", "archivebox", "tray", "externaldrive"
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Add to Workspace")
                    .font(.headline)
                
                Spacer()
                
                Button("✕") {
                    isPresented = false
                }
            }
            
            TextField("Nom du dossier", text: $customName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button(action: {
                        selectedIcon = icon
                    }) {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIcon == icon ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedIcon == icon ? Color.blue : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider()
            
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                
                Spacer()
                
                Button("Ajouter") {
                    let name = customName.isEmpty ? "Nouveau dossier" : customName
                    onSelect(selectedIcon, name)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(customName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Vue principale avec Navigation Blur
struct MinimalNavigationBlurView: View {
    @StateObject private var blurManager = MinimalNavigationBlurManager.shared
    let content: AnyView
    let maxWidth: CGFloat?
    
    var body: some View {
        ZStack {
            content
            
            if blurManager.isShiftPressed || blurManager.isSimulating {
                GeometryReader { geometry in
                    let topBarHeight: CGFloat = 44
                    let bottomBarHeight: CGFloat = 44
                    let fileAreaY = topBarHeight
                    let fileAreaHeight = geometry.size.height - topBarHeight - bottomBarHeight
                    let effectiveWidth = maxWidth ?? geometry.size.width
                    
                    MinimalNavigationBlurOverlay(
                        manager: blurManager,
                        fileAreaFrame: CGRect(
                            x: 0,
                            y: 0,
                            width: effectiveWidth,
                            height: fileAreaHeight
                        )
                    )
                    .frame(width: effectiveWidth, height: fileAreaHeight)
                    .position(x: geometry.size.width / 2, y: fileAreaY + fileAreaHeight / 2)
                    .clipped()
                    .allowsHitTesting(true)
                }
            }
            
            if blurManager.showIconMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        blurManager.showIconMenu = false
                    }
                
                IconSelectionMenu(
                    isPresented: $blurManager.showIconMenu,
                    side: blurManager.iconMenuSide,
                    onSelect: { icon, name in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("AddCurrentToFavorites"),
                            object: nil,
                            userInfo: ["icon": icon, "name": name]
                        )
                        print("Favori à ajouter: \(name) avec icône \(icon)")
                    }
                )
                .zIndex(999)
            }
        }
        .overlay(alignment: .topTrailing) {
            if blurManager.showDebugPanel {
                MinimalBlurDebugPanel(manager: blurManager)
                    .padding()
                    .zIndex(1000)
            }
        }
    }
}

// MARK: - Extension pour MinimalView
extension View {
    func withNavigationBlur(maxWidth: CGFloat? = nil) -> some View {
        MinimalNavigationBlurView(content: AnyView(self), maxWidth: maxWidth)
    }
}
