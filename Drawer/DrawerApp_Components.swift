// DrawerApp_Components.swift
// Composants UI consolidés

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Unified Sidebar (FUSION des 3 versions)
struct UnifiedSidebar: View {
    @Binding var selectedPath: String
    let onSelect: (String) -> Void
    let isDoubleViewMode: Bool
    let isLeftPanel: Bool?
    var iconSize: Binding<CGFloat>? = nil
    
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var volumesManager = VolumesManager()
    @State private var dragOverFavorites = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header pour double view uniquement
            if isDoubleViewMode, let isLeft = isLeftPanel {
                HStack {
                    Text(isLeft ? "LEFT" : "RIGHT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Favoris
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("FAVORITES")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .contextMenu {  // 👈 AJOUTEZ LE contextMenu ICI
                            Button("Reset to default favorites") {
                                favoritesManager.resetToDefaults()
                            }
                            Button("Clear all favorites") {
                                favoritesManager.favorites.removeAll()
                                favoritesManager.saveFavorites()
                            }
                        }
                        
                        ForEach(favoritesManager.favorites) { favorite in
                            SidebarItem(
                                title: favorite.name,
                                icon: favorite.icon,
                                isSelected: selectedPath == favorite.path,
                                onTap: { onSelect(favorite.path) },
                                onRemove: {
                                    favoritesManager.removeFavorite(favorite)
                                }
                            )
                        }
                        
                        // Zone de drop
                        if dragOverFavorites {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 2)
                                .padding(.horizontal, 10)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $dragOverFavorites) { providers in
                        handleFavoritesDrop(providers: providers)
                        return true
                    }
                    
                    Divider().padding(.horizontal, 12)
                    
                    // Volumes
                    if !volumesManager.volumes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("DEVICES")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .contextMenu {
                                if !volumesManager.getHiddenVolumes().isEmpty {
                                    Label("Hidden Volumes:", systemImage: "eye.slash")
                                    ForEach(volumesManager.getHiddenVolumes(), id: \.self) { name in
                                        Button("Show \(name)") {
                                            volumesManager.showVolume(name)
                                        }
                                    }
                                    Divider()
                                    Button("Show All Hidden Volumes") {
                                        volumesManager.resetHiddenVolumes()
                                    }
                                } else {
                                    Text("No hidden volumes")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            ForEach(volumesManager.volumes) { volume in
                                VolumeItemWithContextMenu(
                                    volume: volume,
                                    isSelected: selectedPath == volume.path,
                                    onTap: { onSelect(volume.path) },
                                    volumesManager: volumesManager
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            
            Spacer()
            
            // Slider pour double view
            if isDoubleViewMode, let size = iconSize {
                VStack(spacing: 4) {
                    Divider()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    size.wrappedValue = max(48, size.wrappedValue - 8)
                                }
                            }
                        
                        CustomIconSlider(value: size)
                            .frame(maxWidth: .infinity)
                        
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    size.wrappedValue = min(128, size.wrappedValue + 8)
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.05))
                }
            }
        }
        .frame(width: isDoubleViewMode ? 180 : 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func handleFavoritesDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    DispatchQueue.main.async {
                        favoritesManager.addFavorite(url: url)
                    }
                }
            }
        }
    }
}

// MARK: - Navigation Toolbars
struct NavigationToolbar: View {
    @Binding var viewMode: SingleViewContent.ViewMode
    @Binding var iconSize: CGFloat
    @ObservedObject var navigationHistory: NavigationHistory
    @State private var isShiftPressed = false
    @AppStorage("customHome") private var customHome: String = ""
    
    let currentPath: String
    let onNavigate: (String) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Navigation buttons
            HStack(spacing: 4) {
                Button(action: {
                    if let path = navigationHistory.goBack() {
                        onNavigate(path)
                    }
                }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!navigationHistory.canGoBack)
                .help("Back")
                
                Button(action: {
                    if let path = navigationHistory.goForward() {
                        onNavigate(path)
                    }
                }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!navigationHistory.canGoForward)
                .help("Forward")
                
                Button(action: {
                    if isShiftPressed {
                        customHome = currentPath
                    } else {
                        let home = customHome.isEmpty ?
                            FileManager.default.homeDirectoryForCurrentUser.path :
                            customHome
                        onNavigate(home)
                    }
                }) {
                    Image(systemName: "house")
                        .foregroundColor(isShiftPressed ? .red : .blue)
                }
                .help(isShiftPressed ? "Set as home" : "Home")
                .contextMenu {
                    if !customHome.isEmpty {
                        Button("Reset to default home") {
                            customHome = ""
                        }
                    }
                }
            }
            
            Divider().frame(height: 20)
            
            // Path Bar
            PathBar(path: currentPath)
            
            Spacer()
            
            // View controls
            if viewMode == .icons {
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                iconSize = max(48, iconSize - 8)
                            }
                        }
                    
                    // 🎨 SLIDER STYLE MACOS
                    CustomIconSlider(value: $iconSize)
                        .frame(width: 100)
                    
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                iconSize = min(128, iconSize + 8)
                            }
                        }
                }
            }
            
            Divider().frame(height: 20)
            
            // View mode
            Picker("", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(SingleViewContent.ViewMode.icons)
                Image(systemName: "list.bullet").tag(SingleViewContent.ViewMode.list)
                Image(systemName: "rectangle.split.3x1").tag(SingleViewContent.ViewMode.columns)
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 100)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                self.isShiftPressed = event.modifierFlags.contains(.shift)
                return event
            }
        }
    }
}

struct DoubleViewToolbar: View {
    @ObservedObject var manager: DoubleViewManager
    @State private var isShiftPressed = false
    
    var body: some View {
        HStack {
            // GAUCHE : Boutons back/home AVANT le path
            HStack(spacing: 6) {
                Button(action: manager.navigateToParentLeft) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
                .disabled(manager.leftFileManager.currentPath == "/")
                .help("Parent folder (left)")
                
                Button(action: {
                    if isShiftPressed {
                        manager.setCustomHome(for: .left)
                    } else {
                        manager.navigateToHomeLeft()
                    }
                }) {
                    Image(systemName: "house")
                        .foregroundColor(isShiftPressed ? .red : .blue)
                }
                .help(isShiftPressed ? "Set as home (left)" : "Home (left)")
            }
            
            // Path gauche
            HStack(spacing: 0) {
                let leftPath = manager.leftFileManager.currentPath
                let leftParent = URL(fileURLWithPath: leftPath).deletingLastPathComponent().path
                let leftName = URL(fileURLWithPath: leftPath).lastPathComponent
                
                Text(leftParent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !leftParent.hasSuffix("/") {
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(leftName)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(manager.activePanel == .left ?
                Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(4)
            .lineLimit(1)
            
            // CENTRE : Sélecteur de vue
            Picker("", selection: $manager.viewMode) {
                Image(systemName: "square.grid.2x2").tag(SingleViewContent.ViewMode.icons)
                Image(systemName: "list.bullet").tag(SingleViewContent.ViewMode.list)
                Image(systemName: "rectangle.split.3x1").tag(SingleViewContent.ViewMode.columns)
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 100)
            
            // DROITE : Boutons back/home APRÈS le path
            HStack(spacing: 6) {
                Button(action: manager.navigateToParentRight) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.orange)
                }
                .disabled(manager.rightFileManager.currentPath == "/")
                .help("Parent folder (right)")
                
                Button(action: {
                    if isShiftPressed {
                        manager.setCustomHome(for: .right)
                    } else {
                        manager.navigateToHomeRight()
                    }
                }) {
                    Image(systemName: "house")
                        .foregroundColor(isShiftPressed ? .red : .orange)
                }
                .help(isShiftPressed ? "Set as home (right)" : "Home (right)")
            }
            
            // Path droit
            HStack(spacing: 0) {
                let rightPath = manager.rightFileManager.currentPath
                let rightParent = URL(fileURLWithPath: rightPath).deletingLastPathComponent().path
                let rightName = URL(fileURLWithPath: rightPath).lastPathComponent
                
                Text(rightParent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !rightParent.hasSuffix("/") {
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(rightName)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(manager.activePanel == .right ?
                Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(4)
            .lineLimit(1)
            
        }
        .padding(.horizontal)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                self.isShiftPressed = event.modifierFlags.contains(.shift)
                return event
            }
        }
    }
}

// MARK: - Sidebar Items
struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: (() -> Void)?
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(isSelected ? .white : .primary)
            
            Text(title)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
            
            if isHovered, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                // 🎨 CHANGEMENT ICI : Gris clair au lieu de bleu
                .fill(isSelected ? Color(white: 0.3) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}


struct VolumeItem: View {
    let volume: Volume
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.icon)
                .frame(width: 20)
                .foregroundColor(volume.isRemovable ? .orange : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                if volume.isRemovable {
                    ProgressView(value: volume.usedSpace, total: volume.totalSpace)
                        .progressViewStyle(LinearProgressViewStyle())
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)
                }
            }
            
            Spacer()
            
            if isHovered && volume.isEjectable {
                Button(action: { volume.eject() }) {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                // 🎨 CHANGEMENT ICI : Gris clair au lieu de bleu
                .fill(isSelected ? Color(white: 0.3) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}


struct VolumeItemWithContextMenu: View {
    let volume: Volume
    let isSelected: Bool
    let onTap: () -> Void
    let volumesManager: VolumesManager
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.icon)
                .frame(width: 20)
                .foregroundColor(volume.iconColor)
            
            Text(volume.name)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)
                .font(.system(size: 12))
            
            Spacer()
            
            if isHovered && volume.isEjectable {
                Button(action: { volume.eject() }) {
                    Image(systemName: "eject")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                .fill(isSelected ? Color(white: 0.3) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button(action: {
                volumesManager.hideVolume(volume.name)
            }) {
                Label("Hide This Volume", systemImage: "eye.slash")
            }
            
            if volume.isEjectable {
                Divider()
                Button(action: { volume.eject() }) {
                    Label("Eject", systemImage: "eject")
                }
            }
        }
    }
}

struct PathBar: View {
    let path: String
    
    var components: [String] {
        URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(components.suffix(3), id: \.self) { component in
                if component != components.suffix(3).first {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Text(component)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - FavoritesManager CORRIGÉ
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    
    @Published var favorites: [Favorite] = [] {
        didSet {
            // ✅ SAUVEGARDE AUTOMATIQUE quand les favoris changent
            saveFavorites()
        }
    }
    
    private init() {
        loadFavorites()
    }
    
    private func loadFavorites() {
        print("📂 Chargement des favoris...")
        
        // Charger depuis UserDefaults
        if let data = UserDefaults.standard.data(forKey: "DrawerAppFavorites"),
           let decoded = try? JSONDecoder().decode([SavedFavorite].self, from: data) {
            
            // Recréer les favoris depuis les données sauvegardées
            self.favorites = decoded.map { saved in
                Favorite(name: saved.name, path: saved.path, icon: saved.icon)
            }
            print("✅ \(favorites.count) favoris chargés depuis UserDefaults")
            
            // Vérifier que les chemins existent toujours
            validateFavorites()
        } else {
            print("🆕 Pas de favoris sauvegardés, création des défauts")
            loadDefaultFavorites()
        }
    }
    
    private func validateFavorites() {
        // Vérifier que les dossiers existent toujours
        let fileManager = FileManager.default
        favorites = favorites.filter { favorite in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: favorite.path, isDirectory: &isDirectory)
            if !exists {
                print("⚠️ Favori supprimé car introuvable: \(favorite.path)")
            }
            return exists && isDirectory.boolValue
        }
        // PAS de saveFavorites() ici car didSet le fait automatiquement
    }
    
    private func loadDefaultFavorites() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        // Créer les favoris par défaut
        var defaultFavorites: [Favorite] = []
        
        // Desktop
        let desktopPath = home.appendingPathComponent("Desktop").path
        if fm.fileExists(atPath: desktopPath) {
            defaultFavorites.append(Favorite(name: "Desktop", path: desktopPath, icon: "desktopcomputer"))
        }
        
        // Documents
        let documentsPath = home.appendingPathComponent("Documents").path
        if fm.fileExists(atPath: documentsPath) {
            defaultFavorites.append(Favorite(name: "Documents", path: documentsPath, icon: "doc"))
        }
        
        // Downloads
        let downloadsPath = home.appendingPathComponent("Downloads").path
        if fm.fileExists(atPath: downloadsPath) {
            defaultFavorites.append(Favorite(name: "Downloads", path: downloadsPath, icon: "arrow.down.circle"))
        }
        
        // Applications
        if fm.fileExists(atPath: "/Applications") {
            defaultFavorites.append(Favorite(name: "Applications", path: "/Applications", icon: "app.badge"))
        }
        
        self.favorites = defaultFavorites
        // didSet va automatiquement sauvegarder
    }
    
    func addFavorite(url: URL) {
        // Vérifier que ce n'est pas déjà dans les favoris
        guard !favorites.contains(where: { $0.path == url.path }) else {
            print("⚠️ Favori déjà existant: \(url.path)")
            return
        }
        
        // Vérifier que c'est bien un dossier
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("⚠️ Pas un dossier: \(url.path)")
            return
        }
        
        let favorite = Favorite(
            name: url.lastPathComponent,
            path: url.path,
            icon: "folder"
        )
        
        favorites.append(favorite)
        print("✅ Favori ajouté: \(favorite.name) - \(favorite.path)")
        // didSet va automatiquement sauvegarder
    }
    
    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        print("🗑️ Favori supprimé: \(favorite.name)")
        // didSet va automatiquement sauvegarder
    }
    
    func saveFavorites() {
        print("💾 Sauvegarde de \(favorites.count) favoris...")
        
        // Convertir en structure codable
        let savedFavorites = favorites.map { SavedFavorite(from: $0) }
        
        // Encoder et sauvegarder
        if let encoded = try? JSONEncoder().encode(savedFavorites) {
            UserDefaults.standard.set(encoded, forKey: "DrawerAppFavorites")
            UserDefaults.standard.synchronize() // ✅ FORCER LA SYNCHRONISATION
            print("✅ Favoris sauvegardés")
        } else {
            print("❌ Erreur lors de l'encodage des favoris")
        }
    }
    
    func resetToDefaults() {
        print("🔄 Reset aux favoris par défaut")
        loadDefaultFavorites()
    }
    
    // Fonction pour déplacer un favori (drag & drop réorganisation)
    func moveFavorite(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        // didSet va automatiquement sauvegarder
    }
    
    // Fonction pour renommer un favori
    func renameFavorite(_ favorite: Favorite, newName: String) {
        if let index = favorites.firstIndex(where: { $0.id == favorite.id }) {
            favorites[index] = Favorite(
                name: newName,
                path: favorite.path,
                icon: favorite.icon
            )
            // didSet va automatiquement sauvegarder
        }
    }
}
// Structure pour sauvegarder (Codable)
struct SavedFavorite: Codable {
    let name: String
    let path: String
    let icon: String
    
    init(from favorite: Favorite) {
        self.name = favorite.name
        self.path = favorite.path
        self.icon = favorite.icon
    }
}

// Modèle Favorite (pas Codable directement à cause de UUID)
struct Favorite: Identifiable, Equatable {
    let id = UUID()
    var name: String
    let path: String
    let icon: String
    
    static func == (lhs: Favorite, rhs: Favorite) -> Bool {
        lhs.id == rhs.id
    }
}

class VolumesManager: ObservableObject {
    @Published var volumes: [Volume] = []
    
    // Volumes système TOUJOURS masqués (communs à tous les Mac)
    private let systemExcludedVolumes = [
        "Preboot", "VM", "Update", "Recovery", "Data", "System",
        "TimeMachine", "home", ".timemachine", "com.apple.TimeMachine"
    ]
    
    // Volumes masqués par l'utilisateur (persistant via UserDefaults)
    @AppStorage("userHiddenVolumes") private var userHiddenVolumesData: Data = Data()
    
    private var userHiddenVolumes: Set<String> {
        get {
            if let volumes = try? JSONDecoder().decode(Set<String>.self, from: userHiddenVolumesData) {
                return volumes
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userHiddenVolumesData = data
            }
        }
    }
    
    init() {
        loadVolumes()
        setupNotifications()
    }
    
    private func loadVolumes() {
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: []) else { return }
        
        volumes = urls.compactMap { url in
            let resourceValues = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsInternalKey,
                .volumeIsRootFileSystemKey
            ])
            
            guard let name = resourceValues?.volumeName else { return nil }
            
            // 1. Toujours masquer les volumes système
            if systemExcludedVolumes.contains(name) || name.hasPrefix(".") {
                return nil
            }
            
            // 2. Masquer les volumes que l'utilisateur a choisi de masquer
            if userHiddenVolumes.contains(name) {
                return nil
            }
            
            let isInternal = !(resourceValues?.volumeIsRemovable ?? false)
            let isRoot = resourceValues?.volumeIsRootFileSystem ?? false
            
            return Volume(
                name: name,
                path: url.path,
                isRemovable: resourceValues?.volumeIsRemovable ?? false,
                isEjectable: resourceValues?.volumeIsEjectable ?? false,
                totalSpace: Double(resourceValues?.volumeTotalCapacity ?? 0),
                usedSpace: Double((resourceValues?.volumeTotalCapacity ?? 0) - (resourceValues?.volumeAvailableCapacity ?? 0)),
                isInternal: isInternal,
                isRoot: isRoot
            )
        }
    }
    
    // Masquer un volume (l'ajouter à la liste des masqués)
    func hideVolume(_ volumeName: String) {
        var hidden = userHiddenVolumes
        hidden.insert(volumeName)
        userHiddenVolumes = hidden
        loadVolumes()
        print("🔴 Volume masqué : \(volumeName)")
    }
    
    // Afficher un volume (le retirer de la liste des masqués)
    func showVolume(_ volumeName: String) {
        var hidden = userHiddenVolumes
        hidden.remove(volumeName)
        userHiddenVolumes = hidden
        loadVolumes()
        print("🔵 Volume affiché : \(volumeName)")
    }
    
    // Obtenir tous les volumes masqués
    func getHiddenVolumes() -> [String] {
        Array(userHiddenVolumes).sorted()
    }
    
    // Réinitialiser (afficher tous les volumes)
    func resetHiddenVolumes() {
        userHiddenVolumes = []
        loadVolumes()
        print("♻️ Tous les volumes sont maintenant visibles")
    }
    
    private func setupNotifications() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
    }
    
    @objc private func volumesChanged() {
        loadVolumes()
    }
}

// Mise à jour du modèle Volume
struct Volume: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isRemovable: Bool
    let isEjectable: Bool
    let totalSpace: Double
    let usedSpace: Double
    let isInternal: Bool
    let isRoot: Bool
    
    var icon: String {
        if isRemovable {
            return "externaldrive"
        } else if isRoot {
            return "internaldrive"
        } else {
            return "folder"
        }
    }
    
    var iconColor: Color {
        if isRemovable {
            return .orange
        } else if isRoot {
            return .blue
        } else {
            return .secondary
        }
    }
    
    func eject() {
        if isEjectable {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Cercle percé style macOS
class SmallCircleSliderCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {
        // Taille du cercle
        let knobSize: CGFloat = 17   // ← Changez ici (13, 15 ou 17)
        let holeSize: CGFloat = 15    // ← Changez ici (3, 4 ou 5)
        
        let verticalOffset: CGFloat = -2
        let center = NSPoint(x: knobRect.midX, y: knobRect.midY + verticalOffset)
        
        // 1. Dessiner l'ombre
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        
        // 2. Cercle extérieur blanc
        let outerRect = NSRect(
            x: center.x - knobSize/2,
            y: center.y - knobSize/2,
            width: knobSize,
            height: knobSize
        )
        let outerCircle = NSBezierPath(ovalIn: outerRect)
        
        // Remplir en blanc
        NSColor.lightGray.setFill()
        outerCircle.fill()
        
        // Bordure grise
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        outerCircle.lineWidth = 0.5
        outerCircle.stroke()
        
        // 3. 🎯 TROU CENTRAL GRIS FONCÉ

        let innerRect = NSRect(
            x: center.x - holeSize/2,  // ← Utilise le holeSize du haut
            y: center.y - holeSize/2,
            width: holeSize,
            height: holeSize
        )
        let innerCircle = NSBezierPath(ovalIn: innerRect)
        
        // Remplir avec gris foncé
        NSColor.darkGray.setFill()
        innerCircle.fill()
    }
}

// MARK: - Custom macOS Style Slider
struct CustomIconSlider: NSViewRepresentable {
    @Binding var value: CGFloat
    
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        
        // 🎯 Utiliser le slider personnalisé
        let customCell = SmallCircleSliderCell()
        slider.cell = customCell
        
        slider.sliderType = .linear
        slider.minValue = 48
        slider.maxValue = 128
        slider.doubleValue = Double(value)
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.sliderChanged(_:))
        
        // Style personnalisé
        slider.trackFillColor = NSColor.systemGray.withAlphaComponent(0.3)
        slider.isContinuous = true
        
        return slider
    }
    
    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.doubleValue = Double(value)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CustomIconSlider
        
        init(_ parent: CustomIconSlider) {
            self.parent = parent
        }
        
        @objc func sliderChanged(_ sender: NSSlider) {
            // Snap to steps of 8
            let rawValue = CGFloat(sender.doubleValue)
            let steppedValue = round(rawValue / 8) * 8
            parent.value = steppedValue
        }
    }
}
