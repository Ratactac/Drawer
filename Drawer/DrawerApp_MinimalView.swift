// DrawerApp_MinimalView.swift
// Vue minimale épurée pour DrawerApp

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Minimal View Content
struct MinimalViewContent: View {
    @StateObject private var fileManager = AsyncFileManager()
    @StateObject private var workspaceManager = MinimalWorkspaceManager.shared
    @StateObject private var navigationHistory = NavigationHistory()
    @State private var iconSize: CGFloat = 72
    @State private var showingWorkspaceMenu = false
    @State private var showingFromPlusButton = false
    @State private var hoveredWorkspace: WorkspaceFolder?
    
    @EnvironmentObject var drawerManager: DrawerManager
    @Environment(\.colorScheme) var colorScheme
    
    @AppStorage("minimalBackgroundDarkR") private var bgDarkR: Double = 0.15
    @AppStorage("minimalBackgroundDarkG") private var bgDarkG: Double = 0.15
    @AppStorage("minimalBackgroundDarkB") private var bgDarkB: Double = 0.17
    
    @AppStorage("minimalBackgroundLightR") private var bgLightR: Double = 0.9
    @AppStorage("minimalBackgroundLightG") private var bgLightG: Double = 0.9
    @AppStorage("minimalBackgroundLightB") private var bgLightB: Double = 0.9
    
    @AppStorage("minimalTextWhite") private var minimalTextWhite: Bool = true
    @AppStorage("minimalBlur") private var minimalBlur: Double = 0.8
    @AppStorage("notesEnabled") private var notesEnabled: Bool = false
    
    var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: bgDarkR, green: bgDarkG, blue: bgDarkB)
        } else {
            return Color(red: bgLightR, green: bgLightG, blue: bgLightB)
        }
    }
    
    var textColor: Color {
        return minimalTextWhite ? .white : .black
    }
    
    var body: some View {
        HStack(spacing: 0) {  // Changé de ZStack à HStack
            // Vue principale
            ZStack {
                // 1. FOND AVEC BLUR (comme Simple mode)
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    .opacity(minimalBlur)
                    .ignoresSafeArea()
                
                // 2. CONTENU EXISTANT
                VStack(spacing: 0) {
                    // Barre du haut existante
                    MinimalTopBar(
                        workspaceManager: workspaceManager,
                        showingMenu: $showingWorkspaceMenu,
                        showingFromPlusButton: $showingFromPlusButton,
                        currentPath: fileManager.currentPath,
                        backgroundColor: backgroundColor
                    )
                    .frame(height: 44)
                    
                    NativeFileGridView(
                        fileManager: fileManager,
                        selectionManager: SelectionManager(),
                        iconSize: iconSize,
                        onDoubleClick: handleItemOpen
                    )
                    .background(backgroundColor)
                    
                    MinimalBottomBar(
                        iconSize: $iconSize,
                        onSwitchView: { mode in
                            drawerManager.setDisplayMode(mode)
                        },
                        backgroundColor: backgroundColor
                    )
                    .frame(height: 44)
                }
                
                // Menu workspace overlay
                if showingWorkspaceMenu {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingWorkspaceMenu = false
                            showingFromPlusButton = false
                        }
                    
                    WorkspaceMenuView(
                        workspaceManager: workspaceManager,
                        onDismiss: {
                            showingWorkspaceMenu = false
                            showingFromPlusButton = false
                        },
                        fromPlusButton: showingFromPlusButton,
                        currentPath: fileManager.currentPath
                    )
                }
            }
            
            //.withNavigationBlur(maxWidth: mainAreaWidth - 20)
            
            // Panneau Notes à droite (comme dans SingleView)
            if notesEnabled {
                Divider()
                    .background(Color.gray.opacity(0.5))
                
                NotesPanel()
                    .frame(width: 250)
                    .background(backgroundColor.opacity(0.95))
            }
        }
        .onAppear {
            setupObservers()
            loadInitialDirectory()
        }
        .onChange(of: showingWorkspaceMenu) { _, isShowing in
            drawerManager.isLockedOpen = isShowing
        }
        .withNavigationBlur()
    }
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddCurrentToFavorites"),
            object: nil,
            queue: .main
        ) { _ in
            showingFromPlusButton = false
            showingWorkspaceMenu = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LoadWorkspaceFolder"),
            object: nil,
            queue: .main
        ) { notification in
            if let path = notification.userInfo?["path"] as? String {
                navigationHistory.add(path)
                fileManager.loadDirectory(at: path)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MinimalNavigateBack"),
            object: nil,
            queue: .main
        ) { _ in
            if let previousPath = navigationHistory.goBack() {
                fileManager.loadDirectory(at: previousPath)
                // Pas d'add ici, goBack gère le flag
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MinimalNavigateForward"),
            object: nil,
            queue: .main
        ) { _ in
            if let nextPath = navigationHistory.goForward() {
                fileManager.loadDirectory(at: nextPath)
            }
        }
    }
    
    private func loadInitialDirectory() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").path
        fileManager.loadDirectory(at: desktop)
        navigationHistory.add(desktop)  // ✅ AJOUTER le premier dossier
    }
    
    private func handleItemOpen(_ item: AsyncFileItem) {
        if item.isDirectory {
            fileManager.loadDirectory(at: item.path)
            navigationHistory.add(item.path)  // Add APRÈS loadDirectory
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}


// MARK: - WorkspaceMenuView (menu sombre stylisé)
struct WorkspaceMenuView: View {
    @ObservedObject var workspaceManager: MinimalWorkspaceManager
    let onDismiss: () -> Void
    let fromPlusButton: Bool
    let currentPath: String?
    
    @State private var workspaceName = ""
    @State private var selectedIcon = "folder"
    @State private var selectedPath = ""
    
    // 20 icônes → 5 colonnes x 4 lignes
    let iconOptions = [
        "folder", "folder.badge.plus", "desktopcomputer", "doc", "photo",
        "music.note", "play.rectangle", "paintbrush", "hammer", "wrench.and.screwdriver",
        "terminal", "globe", "heart", "star", "flag",
        "tag", "bookmark", "archivebox", "tray", "externaldrive"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("Add to Workspace")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white) // icône blanche
                        .frame(width: 22, height: 18)
                        .background(Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider().background(Color.white.opacity(0.08))
            
            // Contenu principal
            VStack(alignment: .leading, spacing: 14) {
                // Champ texte réduit (sans label)
                HStack(spacing: 8) {
                    TextField("", text: $workspaceName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    
                    // 🆕 BOUTON BROWSE
                    if fromPlusButton {
                        Button(action: {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.message = "Select a folder for workspace"
                            
                            // 🆕 UTILISER drawerWindow ICI
                            if let drawerPanel = DrawerManager.shared.drawerWindow {
                                panel.beginSheetModal(for: drawerPanel) { response in
                                    if response == .OK, let url = panel.url {
                                        workspaceName = url.lastPathComponent
                                        selectedPath = url.path
                                    }
                                }
                            } else {
                                // Fallback si pas de drawer
                                panel.level = .floating
                                panel.center()
                                if panel.runModal() == .OK, let url = panel.url {
                                    workspaceName = url.lastPathComponent
                                    selectedPath = url.path
                                }
                            }
                        }) {
                            Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 30, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Browse")
                    }
                }
                
                // Grille d’icônes élargie (occupe toute la largeur)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(.white) // icône toujours blanche
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 6) // carré avec coins arrondis
                                        .fill(selectedIcon == icon ? Color.blue.opacity(0.35) : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedIcon == icon ? Color.blue.opacity(0.9) : Color.clear, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider().background(Color.white.opacity(0.08))
                
                // Boutons d’action fins et proches du texte
                HStack {
                    Button("Annuler", action: onDismiss)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                        )
                        .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button("Ajouter") {
                        let finalPath = fromPlusButton && !selectedPath.isEmpty ?
                            selectedPath : (currentPath ?? "")
                        
                        if !workspaceName.isEmpty {
                            let workspace = WorkspaceFolder(
                                name: workspaceName,
                                path: finalPath.isEmpty ?
                                    FileManager.default.homeDirectoryForCurrentUser.path : finalPath,
                                icon: selectedIcon
                            )
                            workspaceManager.addWorkspace(workspace)
                            onDismiss()
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.35)) // même couleur que l'intérieur des icônes
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.9), lineWidth: 1) // contour bleu clair, comme les icônes sélectionnées
                    )
                    .disabled(workspaceName.isEmpty)
                    .opacity(workspaceName.isEmpty ? 0.5 : 1)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(16)
        }
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.14, green: 0.14, blue: 0.15))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 8)
        .onAppear {
            if !fromPlusButton, let path = currentPath {
                let url = URL(fileURLWithPath: path)
                workspaceName = url.lastPathComponent
            }
        }
    }
}


// MARK: - Nouveau Menu Favoris (repris de Untitled.swift)
struct FavoriteMenuView: View {
    @Binding var favoriteName: String
    @Binding var favoriteIconSelected: String
    let currentPath: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add to Favorites")
                .font(.headline)
            
            TextField("Name", text: $favoriteName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                ForEach(["star", "folder", "heart", "bookmark"], id: \.self) { icon in
                    Button(action: { favoriteIconSelected = icon }) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(favoriteIconSelected == icon ? .blue : .gray)
                    }
                }
            }
            
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                
                Button("Add") {
                    let url = URL(fileURLWithPath: currentPath)
                    let favorite = Favorite(
                        name: favoriteName.isEmpty ? url.lastPathComponent : favoriteName,
                        path: currentPath,
                        icon: favoriteIconSelected
                    )
                    FavoritesManager.shared.favorites.append(favorite)
                    
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 10)
        .frame(width: 300)
        .zIndex(999)
    }
}
// MARK: - Minimal Top Bar (Workspace Bar) - MODIFIÉE
struct MinimalTopBar: View {
    @ObservedObject var workspaceManager: MinimalWorkspaceManager
    @Binding var showingMenu: Bool
    @Binding var showingFromPlusButton: Bool  // AJOUT
    let currentPath: String
    let backgroundColor: Color
    @State private var isDraggingOver = false
    @State private var hoveredTab: WorkspaceFolder?
    
    var body: some View {
        HStack(spacing: 0) {
            // Tabs des workspaces
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(workspaceManager.workspaces) { workspace in
                        WorkspaceTab(
                            workspace: workspace,
                            isActive: workspaceManager.activeWorkspace?.id == workspace.id,
                            isHovered: hoveredTab?.id == workspace.id,
                            onTap: {
                                workspaceManager.setActive(workspace)
                            },
                            onClose: {
                                workspaceManager.removeWorkspace(workspace)
                            }
                        )
                        .onHover { isHovering in
                            hoveredTab = isHovering ? workspace : nil
                        }
                    }
                }
                .padding(.leading, 8)
            }
            .opacity(workspaceManager.workspaces.isEmpty ? 0 : 1)
            
            Spacer()
            
            // Bouton + pour ajouter workspace
            Button(action: {
                showingFromPlusButton = true  // Depuis le bouton +
                showingMenu = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    backgroundColor.opacity(0.95),
                    backgroundColor.opacity(0.85)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    DispatchQueue.main.async {
                        self.workspaceManager.addWorkspace(from: url)
                    }
                }
            }
        }
    }
}



// MARK: - Composant IconButton pour le menu
struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isSelected ?
                                    Color.clear : Color.white.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


// MARK: - Minimal Bottom Bar
struct MinimalBottomBar: View {
    @Binding var iconSize: CGFloat
    let onSwitchView: (DrawerDisplayMode) -> Void
    let backgroundColor: Color
    @AppStorage("notesEnabled") private var notesEnabled: Bool = false
    @State private var showingPreferences = false
    @AppStorage("displayMode") private var currentModeString: String = "minimal"
    
    private var currentMode: DrawerDisplayMode {
        DrawerDisplayMode(rawValue: currentModeString) ?? .minimal
    }
    
    var body: some View {
        HStack {
            // Slider pour la taille des icônes
            HStack(spacing: 8) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            iconSize = max(48, iconSize - 8)
                        }
                    }
                
                CustomIconSlider(value: $iconSize)
                    .frame(width: 120)
                
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            iconSize = min(128, iconSize + 8)
                        }
                    }
            }
            .padding(.horizontal, 16)
            
            Spacer()
            
            // Boutons de vue et préférences
            HStack(spacing: 12) {
                // Bouton Minimal (actuellement sélectionné)
                Button(action: {
                    // Déjà en minimal, ne rien faire
                }) {
                    Image(systemName: "rectangle")  // Changé pour correspondre
                        .font(.system(size: 16))
                        .foregroundColor(.blue)  // Orange car actif
                }
                .buttonStyle(PlainButtonStyle())
                .help("Minimal View")
                
                Button(action: {
                    onSwitchView(.single)
                }) {
                    Image(systemName: "rectangle.split.2x1")  // Changé pour correspondre
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Single View")
                
                Button(action: {
                    onSwitchView(.double)
                }) {
                    Image(systemName: "square.grid.2x2.fill")  // Changé pour correspondre
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Double View")
                
                Button(action: {
                    notesEnabled.toggle()
                    // Ne PAS changer de vue
                }) {
                    Image(systemName: notesEnabled ? "note.text.badge.plus" : "note.text")
                        .font(.system(size: 16))
                        .foregroundColor(notesEnabled ? .orange : .white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Notes")
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 4)
                
                // Bouton préférences
                Button(action: {
                    // Méthode qui fonctionne à 100%
                    NSApplication.shared.sendAction(
                        #selector(DrawerAppDelegate.showPreferences),
                        to: nil,
                        from: nil
                    )
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
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
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    backgroundColor.opacity(0.85),
                    backgroundColor.opacity(0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct WorkspaceTab: View {
    let workspace: WorkspaceFolder
    let isActive: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    @State private var showCloseButton = false
    @State private var isShiftPressed = false
    
    var body: some View {
        HStack(spacing: 6) {
            // 🎯 CROIX AU DÉBUT (seulement si Shift+Hover)
            if isShiftPressed && isHovered {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
            
            Image(systemName: workspace.icon)
                .font(.system(size: 11))
                .foregroundColor(isShiftPressed && isHovered ? .red : iconColor)
            
            Text(workspace.name)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundColor(isShiftPressed && isHovered ? .red : textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isShiftPressed && isHovered ? Color.red.opacity(0.1) : backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isShiftPressed && isHovered ? Color.red.opacity(0.3) : borderColor, lineWidth: 1)
        )
        .onTapGesture {
            // 🎯 CLIC SUR TOUT LE TAB
            if isShiftPressed && isHovered {
                onClose()  // Ferme si Shift est pressé
            } else {
                onTap()    // Sinon, active le workspace
            }
        }
        .onHover { hovering in
            showCloseButton = hovering
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isShiftPressed = event.modifierFlags.contains(.shift)
                return event
            }
        }
    }
    
    private var iconColor: Color {
        if isActive { return .white }
        if isHovered { return .white.opacity(0.8) }
        return .white.opacity(0.5)
    }
    
    private var textColor: Color {
        if isActive { return .white }
        if isHovered { return .white.opacity(0.9) }
        return .white.opacity(0.6)
    }
    
    private var backgroundColor: Color {
        if isActive { return Color.white.opacity(0.15) }
        if isHovered { return Color.white.opacity(0.08) }
        return Color.white.opacity(0.03)
    }
    
    private var borderColor: Color {
        if isActive { return Color.white.opacity(0.3) }
        if isHovered { return Color.white.opacity(0.2) }
        return Color.clear
    }
}
// MARK: - Workspace Manager
class MinimalWorkspaceManager: ObservableObject {
    static let shared = MinimalWorkspaceManager()
    
    @Published var workspaces: [WorkspaceFolder] = [] {
        didSet {
            saveWorkspaces()
        }
    }
    @Published var activeWorkspace: WorkspaceFolder?
    
    init() {
        loadWorkspaces()
    }
    
    private func saveWorkspaces() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(workspaces) {
            UserDefaults.standard.set(encoded, forKey: "MinimalViewWorkspaces")
        }
    }
    
    private func loadWorkspaces() {
        if let data = UserDefaults.standard.data(forKey: "MinimalViewWorkspaces"),
           let decoded = try? JSONDecoder().decode([WorkspaceFolder].self, from: data) {
            
            self.workspaces = decoded.filter { workspace in
                FileManager.default.fileExists(atPath: workspace.path)
            }
            
            if let first = workspaces.first {
                activeWorkspace = first
            }
        }
    }
    
    func addWorkspace(from url: URL) {
        let workspace = WorkspaceFolder(
            name: url.lastPathComponent,
            path: url.path,
            icon: "folder"
        )
        addWorkspace(workspace)
    }
    
    func addWorkspace(_ workspace: WorkspaceFolder) {
        guard !workspaces.contains(where: { $0.path == workspace.path }) else {
            return
        }
        
        workspaces.append(workspace)
        setActive(workspace)
    }
    
    func removeWorkspace(_ workspace: WorkspaceFolder) {
        workspaces.removeAll { $0.id == workspace.id }
        if activeWorkspace?.id == workspace.id {
            activeWorkspace = workspaces.first
        }
    }
    
    func setActive(_ workspace: WorkspaceFolder) {
        activeWorkspace = workspace
        NotificationCenter.default.post(
            name: NSNotification.Name("LoadWorkspaceFolder"),
            object: nil,
            userInfo: ["path": workspace.path]
        )
    }
}

// MARK: - Models
struct WorkspaceFolder: Identifiable, Codable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, path, icon
    }
    
    init(name: String, path: String, icon: String) {
        self.name = name
        self.path = path
        self.icon = icon
    }
}

// MARK: - Button Style
struct MinimalButtonStyle: ButtonStyle {
    var isCancel: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(isCancel ? .white.opacity(0.6) : .black)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCancel ? Color.white.opacity(0.1) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(isCancel ? 0.2 : 0), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
