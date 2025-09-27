// DrawerApp_MainViews.swift
// Vues principales: Single et Double View

import SwiftUI
import AppKit

// MARK: - Single View Content (ex-RefactoredDrawerContent)
struct SingleViewContent: View {
    @StateObject private var fileManager = AsyncFileManager()
    @StateObject private var navigationHistory = NavigationHistory()
    @State private var viewMode: ViewMode = .icons
    @State private var iconSize: CGFloat = 72
    @State private var selectedItems: Set<AsyncFileItem> = []
    @EnvironmentObject var drawerManager: DrawerManager
    
    enum ViewMode {
        case icons, list, columns
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            UnifiedSidebar(
                selectedPath: $fileManager.currentPath,
                onSelect: { path in
                    fileManager.loadDirectory(at: path)
                    navigationHistory.add(path)
                },
                isDoubleViewMode: false,
                isLeftPanel: nil
            )
            
            Divider()
            
            // Contenu principal
            VStack(spacing: 0) {
                // Navigation Bar
                NavigationToolbar(
                    viewMode: $viewMode,
                    iconSize: $iconSize,
                    navigationHistory: navigationHistory,
                    currentPath: fileManager.currentPath,
                    onNavigate: { path in
                        fileManager.loadDirectory(at: path)
                    }
                )
                
                Divider()
                
                // Zone de contenu
                ZStack {
                    Color.white.opacity(0.02)
                    
                    switch viewMode {
                    case .icons:
                        NativeFileGridView(
                            fileManager: fileManager,
                            selectionManager: SelectionManager(),
                            iconSize: iconSize,
                            onDoubleClick: handleItemOpen
                        )
                    case .list:
                        AsyncListView(
                            items: fileManager.rootItems,
                            selectedItems: $selectedItems,
                            onDoubleClick: handleItemOpen
                        )
                    case .columns:
                        AsyncColumnView(
                            rootPath: fileManager.currentPath,
                            fileManager: fileManager,
                            selectedItems: $selectedItems,
                            onDoubleClick: handleItemOpen
                        )
                    }
                    
                    if fileManager.isLoading {
                        ProgressView("Loading...")
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .onAppear {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            fileManager.loadDirectory(at: home)
            navigationHistory.add(home)  // ✅ Premier dossier dans l'historique
        }
    }
    
    private func handleItemOpen(_ item: AsyncFileItem) {
        if item.isDirectory {
            fileManager.loadDirectory(at: item.path)
            navigationHistory.add(item.path)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}

// MARK: - Double View Content
struct DoubleViewContent: View {
    @StateObject private var manager = DoubleViewManager()
    @State private var refreshID = UUID()
    
    var body: some View {
        HStack(spacing: 0) {
            // SIDEBAR GAUCHE
            UnifiedSidebar(
                selectedPath: $manager.leftFileManager.currentPath,
                onSelect: { path in
                    manager.navigateLeft(to: path)
                    // PAS BESOIN d'ajouter à l'historique ici, navigateLeft le fait
                },
                isDoubleViewMode: true,
                isLeftPanel: true,
                iconSize: $manager.leftIconSize
            )
            .frame(minWidth: 150, maxWidth: 180)
            .environmentObject(manager)
            .id(refreshID)
            
            Divider()
            
            // ZONE CENTRALE
            VStack(spacing: 0) {
                DoubleViewToolbar(manager: manager)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                
                Divider()
                
                HStack(spacing: 0) {
                    // Fichiers gauche
                    FilePanel(
                        fileManager: manager.leftFileManager,
                        selectionManager: manager.leftSelectionManager,
                        viewMode: $manager.viewMode,
                        iconSize: $manager.leftIconSize,
                        isActive: manager.activePanel == .left,
                        onActivate: { manager.setActivePanel(.left) },
                        onNavigate: { path in
                            manager.navigateLeft(to: path)
                            // L'historique est géré dans navigateLeft
                        }
                    )
                    .frame(minWidth: 200)
                    
                    CenterDivider()
                    
                    // Fichiers droit - UN SEUL FilePanel !
                    FilePanel(
                        fileManager: manager.rightFileManager,
                        selectionManager: manager.rightSelectionManager,
                        viewMode: $manager.viewMode,
                        iconSize: $manager.rightIconSize,
                        isActive: manager.activePanel == .right,
                        onActivate: { manager.setActivePanel(.right) },
                        onNavigate: { path in
                            manager.navigateRight(to: path)
                            // L'historique est géré dans navigateRight
                        }
                    )
                    .frame(minWidth: 200)
                }
            }
            .frame(minWidth: 400)
            
            Divider()
            
            // SIDEBAR DROITE
            UnifiedSidebar(
                selectedPath: $manager.rightFileManager.currentPath,
                onSelect: { path in
                    manager.navigateRight(to: path)
                    // PAS BESOIN d'ajouter à l'historique ici
                },
                isDoubleViewMode: true,
                isLeftPanel: false,
                iconSize: $manager.rightIconSize
            )
            .frame(minWidth: 150, maxWidth: 180)
            .environmentObject(manager)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshID = UUID()
        }
    }
}

// MARK: - DoubleViewManager
@MainActor
class DoubleViewManager: ObservableObject {
    @Published var leftFileManager = AsyncFileManager()
    @Published var rightFileManager = AsyncFileManager()
    @Published var activePanel: ActivePanel = .left
    @Published var viewMode: SingleViewContent.ViewMode = .icons
    @Published var leftIconSize: CGFloat = 64
    @Published var rightIconSize: CGFloat = 64
    @Published var leftSelectionManager = SelectionManager()
    @Published var rightSelectionManager = SelectionManager()
    
    // 🆕 AJOUTER LES HISTORIQUES
    @Published var leftHistory = NavigationHistory()
    @Published var rightHistory = NavigationHistory()
    
    @AppStorage("leftCustomHome") var leftCustomHome: String = ""
    @AppStorage("rightCustomHome") var rightCustomHome: String = ""
    
    enum ActivePanel {
        case left, right
    }
    
    init() {
        let defaultHome = FileManager.default.homeDirectoryForCurrentUser.path
        let leftHome = leftCustomHome.isEmpty ? defaultHome : leftCustomHome
        let rightHome = rightCustomHome.isEmpty ? defaultHome : rightCustomHome
        
        leftFileManager.loadDirectory(at: leftHome)
        rightFileManager.loadDirectory(at: rightHome)
        
        // ✅ Maintenant ça fonctionne
        leftHistory.add(leftHome)
        rightHistory.add(rightHome)
    }
    
    func setActivePanel(_ panel: ActivePanel) {
        activePanel = panel
        
        if panel == .left {
            rightSelectionManager.clearSelection()
            objectWillChange.send()
        } else {
            leftSelectionManager.clearSelection()
            objectWillChange.send()
        }
    }
    
    // 🔄 MODIFIER pour gérer l'historique
    func navigateLeft(to path: String, isManual: Bool = true) {
        objectWillChange.send()
        leftFileManager.loadDirectory(at: path)
        if isManual {
            leftHistory.add(path)
        }

    }
    
    func navigateRight(to path: String, isManual: Bool = true) {
        rightFileManager.loadDirectory(at: path)
        if isManual {
            rightHistory.add(path)
        }
        objectWillChange.send()
    }
    
    // 🆕 AJOUTER les méthodes Back/Forward
    func goBackLeft() {
        if let path = leftHistory.goBack() {
            navigateLeft(to: path, isManual: false)
        }
    }
    
    func goForwardLeft() {
        if let path = leftHistory.goForward() {
            navigateLeft(to: path, isManual: false)
        }
    }
    
    func goBackRight() {
        if let path = rightHistory.goBack() {
            navigateRight(to: path, isManual: false)
        }
    }
    
    func goForwardRight() {
        if let path = rightHistory.goForward() {
            navigateRight(to: path, isManual: false)
        }
    }
    
    func navigateToParentLeft() {
        let parent = URL(fileURLWithPath: leftFileManager.currentPath)
            .deletingLastPathComponent().path
        navigateLeft(to: parent)  // isManual = true par défaut, donc ajouté à l'historique
    }
    
    func navigateToParentRight() {
        let parent = URL(fileURLWithPath: rightFileManager.currentPath)
            .deletingLastPathComponent().path
        navigateRight(to: parent)  // isManual = true par défaut, donc ajouté à l'historique
    }
    
    func navigateToHomeLeft() {
        navigateLeft(to: getHome(for: .left))
    }
    
    func navigateToHomeRight() {
        navigateRight(to: getHome(for: .right))
    }
    
    func setCustomHome(for panel: ActivePanel) {
        if panel == .left {
            leftCustomHome = leftFileManager.currentPath
        } else {
            rightCustomHome = rightFileManager.currentPath
        }
    }
    
    func getHome(for panel: ActivePanel) -> String {
        let defaultHome = FileManager.default.homeDirectoryForCurrentUser.path
        if panel == .left {
            return leftCustomHome.isEmpty ? defaultHome : leftCustomHome
        } else {
            return rightCustomHome.isEmpty ? defaultHome : rightCustomHome
        }
    }
    
    func resetHome(for panel: ActivePanel) {
        if panel == .left {
            leftCustomHome = ""
        } else {
            rightCustomHome = ""
        }
    }
}

// MARK: - FilePanel (pour double view)
struct FilePanel: View {
    @ObservedObject var fileManager: AsyncFileManager
    @ObservedObject var selectionManager: SelectionManager
    @Binding var viewMode: SingleViewContent.ViewMode
    @Binding var iconSize: CGFloat
    let isActive: Bool
    let onActivate: () -> Void
    let onNavigate: (String) -> Void
    
    @State private var localRefreshID = UUID()
    @State private var panelWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(isActive ? Color.accentColor.opacity(0.05) : Color.clear)
                    .onTapGesture {
                        onActivate()
                        localRefreshID = UUID()
                    }
                
                Group {
                    switch viewMode {
                    case .icons:
                        let adaptiveIconSize = panelWidth < 300 ? min(48, iconSize) : iconSize
                        
                        NativeFileGridView(
                            fileManager: fileManager,
                            selectionManager: selectionManager,
                            iconSize: adaptiveIconSize,
                            onDoubleClick: { item in
                                if item.isDirectory {
                                    onNavigate(item.path)
                                    // Forcer le rafraîchissement
                                    localRefreshID = UUID()
                                } else {
                                    NSWorkspace.shared.open(item.url)
                                }
                            }
                        )
                        .id(localRefreshID)
                        
                    case .list:
                        AsyncListView(
                            items: fileManager.rootItems,
                            selectedItems: .constant(selectionManager.selectedItems),
                            onDoubleClick: { item in
                                if item.isDirectory {
                                    onNavigate(item.path)
                                } else {
                                    NSWorkspace.shared.open(item.url)
                                }
                            }
                        )
                        .id(localRefreshID)
                        
                    case .columns:
                        AsyncColumnView(
                            rootPath: fileManager.currentPath,
                            fileManager: fileManager,
                            selectedItems: .constant(selectionManager.selectedItems),
                            onDoubleClick: { item in
                                if item.isDirectory {
                                    onNavigate(item.path)
                                } else {
                                    NSWorkspace.shared.open(item.url)
                                }
                            }
                        )
                        .id(localRefreshID)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if fileManager.isLoading {
                    ProgressView("Loading...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
            }
            .onAppear {
                panelWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                panelWidth = newWidth
            }
        }
    }
}

// MARK: - Navigation History CORRIGÉE
class NavigationHistory: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    
    private var history: [String] = []
    private var currentIndex = -1
    private var isNavigatingViaHistory = false
    
    func add(_ path: String) {
        // Ignorer si on est en navigation back/forward
        if isNavigatingViaHistory {
            return
        }
        
        // Si on navigue après un back, supprimer l'historique futur
        if currentIndex < history.count - 1 {
            history = Array(history.prefix(currentIndex + 1))
        }
        
        // Éviter les doublons consécutifs
        if history.last != path {
            history.append(path)
            currentIndex = history.count - 1
        }
        
        updateState()
    }
    
    func goBack() -> String? {
        guard canGoBack else { return nil }
        
        isNavigatingViaHistory = true
        currentIndex -= 1
        let path = history[currentIndex]
        
        // Reset le flag après un court délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isNavigatingViaHistory = false
        }
        
        updateState()
        return path
    }
    
    func goForward() -> String? {
        guard canGoForward else { return nil }
        
        isNavigatingViaHistory = true
        currentIndex += 1
        let path = history[currentIndex]
        
        // Reset le flag après un court délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isNavigatingViaHistory = false
        }
        
        updateState()
        return path
    }
    
    private func updateState() {
        canGoBack = currentIndex > 0
        canGoForward = currentIndex < history.count - 1
    }
}

// MARK: - Center Divider
struct CenterDivider: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 2)
            
            VStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .frame(width: 20)
    }
}

// Extension utile
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
