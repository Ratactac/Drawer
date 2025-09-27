// DrawerApp_Core_Refactored.swift
// FUSION: Core + Models + Managers de base

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import QuickLookThumbnailing

// MARK: - AsyncFileManager (on garde votre version EXACTE)
class AsyncFileManager: ObservableObject {
    @Published var rootItems: [AsyncFileItem] = []
    @Published var isLoading = false
    @Published var currentPath: String = ""
    @Published var selectedItems: Set<AsyncFileItem> = []
    
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    private let fileManager = FileManager.default
    
    // Cache partagé statique pour toutes les instances
    static let sharedIconCache = NSCache<NSString, NSImage>()
    static let sharedItemsCache = NSCache<NSString, NSArray>()
    
    static let _cacheSetup: Void = {
        sharedIconCache.countLimit = 1000
        sharedItemsCache.countLimit = 50
    }()
    
    init() {
        _ = AsyncFileManager._cacheSetup
    }
    
    func loadDirectory(at path: String) {
        loadingTasks[currentPath]?.cancel()
        self.currentPath = path
        
        if let cachedItems = AsyncFileManager.sharedItemsCache.object(forKey: path as NSString) as? [AsyncFileItem] {
            self.rootItems = cachedItems
            self.isLoading = false
            return
        }
        
        let url = URL(fileURLWithPath: path)
        let slowPaths = ["/Applications", "/System", "/Library"]
        let needsAsync = slowPaths.contains(path) || path.contains("/Applications")
        
        if needsAsync {
            self.isLoading = true
            
            let task = Task { [weak self] in
                guard let self = self else { return }
                let items = await self.loadItemsQuickly(at: path)
                
                if !Task.isCancelled {
                    await MainActor.run {
                        self.rootItems = items
                        self.isLoading = false
                        AsyncFileManager.sharedItemsCache.setObject(items as NSArray, forKey: path as NSString)
                    }
                }
            }
            
            loadingTasks[path] = task
        } else {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                let items = contents.compactMap { itemURL -> AsyncFileItem? in
                    let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    return AsyncFileItem(
                        url: itemURL,
                        name: itemURL.lastPathComponent,
                        path: itemURL.path,
                        isDirectory: resourceValues?.isDirectory ?? false,
                        size: Int64(resourceValues?.fileSize ?? 0),
                        modificationDate: resourceValues?.contentModificationDate ?? Date()
                    )
                }

                self.rootItems = items.sorted { a, b in
                    if a.isDirectory != b.isDirectory {
                        return a.isDirectory
                    }
                    return a.modificationDate > b.modificationDate
                }
                
                AsyncFileManager.sharedItemsCache.setObject(self.rootItems as NSArray, forKey: path as NSString)
                self.isLoading = false
            } catch {
                self.rootItems = []
                self.isLoading = false
            }
        }
    }
    
    func loadChildren(for item: AsyncFileItem) {
        guard item.isDirectory else { return }
        if item.isLoadingChildren { return }
        
        item.isLoadingChildren = true
        
        Task {
            let children = await loadItemsQuickly(at: item.path)
            await MainActor.run {
                item.children = children.map { child in
                    AsyncFileItem(
                        url: child.url,
                        name: child.name,
                        path: child.path,
                        isDirectory: child.isDirectory,
                        size: child.size,
                        modificationDate: child.modificationDate
                    )
                }
                item.isExpanded = true
                item.isLoadingChildren = false
            }
        }
    }

    func openItem(_ item: AsyncFileItem) {
        if item.isDirectory {
            loadDirectory(at: item.path)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
    
    private func loadItemsQuickly(at path: String) async -> [AsyncFileItem] {
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [] }
            
            do {
                let url = URL(fileURLWithPath: path)
                let contents = try self.fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                let items = contents.compactMap { itemURL -> AsyncFileItem? in
                    guard !Task.isCancelled else { return nil }
                    
                    do {
                        let resourceValues = try itemURL.resourceValues(
                            forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                        )
                        
                        return AsyncFileItem(
                            url: itemURL,
                            name: itemURL.lastPathComponent,
                            path: itemURL.path,
                            isDirectory: resourceValues.isDirectory ?? false,
                            size: Int64(resourceValues.fileSize ?? 0),
                            modificationDate: resourceValues.contentModificationDate ?? Date()
                        )
                    } catch {
                        return nil
                    }
                }

                return items.sorted { a, b in
                    if a.isDirectory != b.isDirectory {
                        return a.isDirectory
                    }
                    return a.modificationDate > b.modificationDate
                }
            } catch {
                return []
            }
        }.value
    }
    
    func getIcon(for item: AsyncFileItem) -> NSImage {
        let key = item.path as NSString
        
        if let cachedIcon = AsyncFileManager.sharedIconCache.object(forKey: key) {
            return cachedIcon
        }
        
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        AsyncFileManager.sharedIconCache.setObject(icon, forKey: key)
        return icon
    }
    
    static func clearCache() {
        sharedItemsCache.removeAllObjects()
        sharedIconCache.removeAllObjects()
    }
}

// MARK: - AsyncFileItem (votre version EXACTE)
class AsyncFileItem: ObservableObject, Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date
    
    @Published var children: [AsyncFileItem] = []
    @Published var isExpanded = false
    @Published var isLoadingChildren = false
    @Published var icon: NSImage?
    @Published var thumbnail: NSImage?
    @Published var isLoadingThumbnail = false
    
    static let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp", "ico", "svg"]
    static let psdExtensions = ["psd", "psb", "ai", "eps"]
    static let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "webm", "mpg", "mpeg"]
    static let rawExtensions = ["raw", "cr2", "nef", "arw", "dng", "orf"]
    
    var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    var isImageFile: Bool {
        Self.imageExtensions.contains(fileExtension) ||
        Self.psdExtensions.contains(fileExtension) ||
        Self.rawExtensions.contains(fileExtension)
    }
    
    var isVideoFile: Bool {
        Self.videoExtensions.contains(fileExtension)
    }
    
    var shouldShowThumbnail: Bool {
        isImageFile || isVideoFile
    }
    
    init(url: URL, name: String, path: String, isDirectory: Bool, size: Int64, modificationDate: Date) {
        self.url = url
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.icon = NSWorkspace.shared.icon(forFile: path)
    }

    @MainActor
    func loadThumbnailIfNeeded() async {
        guard thumbnail == nil,
              !isLoadingThumbnail,
              shouldShowThumbnail,
              !isDirectory else { return }
        
        isLoadingThumbnail = true
        
        let thumbnailImage = await generateQuickLookThumbnail()
        
        if let thumbnailImage = thumbnailImage {
            self.thumbnail = thumbnailImage
        }
        
        isLoadingThumbnail = false
    }

    @MainActor
    private func generateQuickLookThumbnail() async -> NSImage? {
        return await withCheckedContinuation { continuation in
            // 🔧 MODIFICATION : Taille maximale au lieu de taille fixe
            let maxSize = CGSize(width: 256, height: 256)  // Plus grand pour meilleure qualité
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: maxSize,
                scale: scale,
                representationTypes: .thumbnail
            )
            
            // 🔧 IMPORTANT : Ne pas forcer en mode icône
            request.iconMode = false
            
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { (thumbnail, error) in
                if let thumbnail = thumbnail {
                    // 🔧 Créer l'image avec le ratio original
                    let nsImage = NSImage(cgImage: thumbnail.cgImage, size: NSSize(
                        width: thumbnail.cgImage.width / Int(scale),
                        height: thumbnail.cgImage.height / Int(scale)
                    ))
                    continuation.resume(returning: nsImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
    
    static func == (lhs: AsyncFileItem, rhs: AsyncFileItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SelectionManager (votre version EXACTE)
@MainActor
class SelectionManager: ObservableObject {
    @Published var selectedItems: Set<AsyncFileItem> = []
    var lastSelectedIndex: Int? = nil
    var lastSelectedItem: AsyncFileItem? = nil
    
    func handleClick(item: AsyncFileItem, at index: Int, in items: [AsyncFileItem]) {
        let modifiers = NSEvent.modifierFlags
        
        if modifiers.contains(.command) {
            handleCommandClick(item: item, at: index)
        } else if modifiers.contains(.shift) {
            handleShiftClick(item: item, at: index, in: items)
        } else {
            handleSimpleClick(item: item, at: index)
        }
    }
    
    func handleSimpleClick(item: AsyncFileItem, at index: Int) {
        selectedItems = [item]
        lastSelectedIndex = index
        lastSelectedItem = item
    }
    
    func handleCommandClick(item: AsyncFileItem, at index: Int) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
            if item == lastSelectedItem {
                lastSelectedItem = selectedItems.first
                lastSelectedIndex = nil
            }
        } else {
            selectedItems.insert(item)
            lastSelectedIndex = index
            lastSelectedItem = item
        }
    }
    
    func handleShiftClick(item: AsyncFileItem, at index: Int, in items: [AsyncFileItem]) {
        guard let anchorIndex = lastSelectedIndex else {
            handleSimpleClick(item: item, at: index)
            return
        }
        
        let start = min(anchorIndex, index)
        let end = max(anchorIndex, index)
        
        selectedItems.removeAll()
        for i in start...end {
            if i < items.count {
                selectedItems.insert(items[i])
            }
        }
    }
    
    func prepareForDrag(item: AsyncFileItem) {
        if !selectedItems.contains(item) {
            selectedItems = [item]
            lastSelectedItem = item
        }
    }
    
    func clearSelection() {
        selectedItems.removeAll()
        lastSelectedIndex = nil
        lastSelectedItem = nil
    }
    
    func updateRectangleSelection(
        rect: CGRect,
        items: [AsyncFileItem],
        itemFrames: [UUID: CGRect],
        additive: Bool = false
    ) {
        if !additive {
            selectedItems.removeAll()
        }
        
        for (itemId, frame) in itemFrames {
            if rect.intersects(frame) {
                if let item = items.first(where: { $0.id == itemId }) {
                    selectedItems.insert(item)
                    if let index = items.firstIndex(where: { $0.id == itemId }) {
                        lastSelectedIndex = index
                        lastSelectedItem = item
                    }
                }
            } else if !additive {
                if let item = items.first(where: { $0.id == itemId }) {
                    selectedItems.remove(item)
                }
            }
        }
    }
    
    func itemAt(point: CGPoint, in frames: [UUID: CGRect], items: [AsyncFileItem]) -> AsyncFileItem? {
        for (itemId, frame) in frames {
            if frame.contains(point) {
                return items.first { $0.id == itemId }
            }
        }
        return nil
    }
}

// MARK: - DrawerPanel (UNIQUE - on garde cette version)
class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !self.isKeyWindow {
            self.makeKey()
        }
        super.sendEvent(event)
    }
}
// MARK: - Note Model
struct Note: Identifiable, Codable {
    var id: UUID
    var title: String
    var content: String
    var createdDate: Date
    var modifiedDate: Date
    
    init() {
        self.id = UUID()
        self.title = "Untitled Note"
        self.content = ""
        self.createdDate = Date()
        self.modifiedDate = Date()
    }
    
    var preview: String {
        let lines = content.components(separatedBy: .newlines)
        return lines.prefix(2).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modifiedDate, relativeTo: Date())
    }
}

// Extension UserDefaults pour sauvegarder les notes
extension UserDefaults {
    func saveNotes(_ notes: [Note]) {
        if let encoded = try? JSONEncoder().encode(notes) {
            set(encoded, forKey: "DrawerAppNotes")
        }
    }
    
    func loadNotes() -> [Note] {
        guard let data = data(forKey: "DrawerAppNotes"),
              let notes = try? JSONDecoder().decode([Note].self, from: data) else {
            return []
        }
        return notes
    }
}

// MARK: - Visual Effect Blur
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension Color {
    var isLight: Bool {
        let components = NSColor(self).cgColor.components ?? [0, 0, 0]
        let brightness = (components[0] * 0.299 + components[1] * 0.587 + components[2] * 0.114)
        return brightness > 0.5
    }
}

extension Text {
    func autoTextColor(for background: Color) -> Text {
        self.foregroundColor(background.isLight ? .black : .white)
    }
}
