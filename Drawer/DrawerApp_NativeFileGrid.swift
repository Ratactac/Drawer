// DrawerApp_NativeFileGrid.swift
// Solution hybride NSCollectionView pour éliminer les conflits sélection/drag
// Remplace IconGridView problématique

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

// MARK: - SwiftUI Wrapper pour NSCollectionView
struct NativeFileGridView: NSViewControllerRepresentable {
    @ObservedObject var fileManager: AsyncFileManager
    @ObservedObject var selectionManager: SelectionManager
    let iconSize: CGFloat
    let onDoubleClick: (AsyncFileItem) -> Void
    var backgroundColor: NSColor = .clear
    
    func makeNSViewController(context: Context) -> FileGridViewController {
        let controller = FileGridViewController()
        controller.fileManager = fileManager
        controller.selectionManager = selectionManager
        controller.iconSize = iconSize
        controller.onDoubleClick = onDoubleClick
        controller.coordinator = context.coordinator
        controller.backgroundColor = backgroundColor
        return controller
    }
    
    func updateNSViewController(_ controller: FileGridViewController, context: Context) {
        controller.iconSize = iconSize
        controller.reloadDataIfNeeded()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: NativeFileGridView
        
        init(_ parent: NativeFileGridView) {
            self.parent = parent
        }
    }
}

// MARK: - NSViewController pour la Grid
class FileGridViewController: NSViewController {
    var backgroundColor: NSColor = .clear
    var collectionView: NSCollectionView!
    var scrollView: NSScrollView!
    var fileManager: AsyncFileManager!
    var selectionManager: SelectionManager!
    var iconSize: CGFloat = 72 {
        didSet {
            if isViewLoaded {
                updateLayout()
            }
        }
    }
    var onDoubleClick: ((AsyncFileItem) -> Void)?
    weak var coordinator: NativeFileGridView.Coordinator?
    
    private var lastItemsCount = 0
    private var selectionAnchor: IndexPath?
    
    override func loadView() {
        setupCollectionView()
        view = scrollView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupObservers()
        reloadData()
    }
    
    private func setupCollectionView() {
        collectionView = NSCollectionView()
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.backgroundColors = [backgroundColor] 
        
        let flowLayout = NSCollectionViewFlowLayout()
        // Réduire l'espace autour des items pour éviter les clics loin de l'icône
        flowLayout.itemSize = NSSize(width: iconSize + 20, height: iconSize + 40)
        flowLayout.minimumInteritemSpacing = 15
        flowLayout.minimumLineSpacing = 15
        flowLayout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        collectionView.collectionViewLayout = flowLayout
        
        collectionView.registerForDraggedTypes([.fileURL, .string])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy], forLocal: false)
        
        collectionView.delegate = self
        collectionView.dataSource = self
        
        collectionView.register(
            FileGridItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("FileGridItem")
        )
        
        scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fileManagerDidUpdate),
            name: NSNotification.Name("FileManagerDidUpdate"),
            object: nil
        )
    }
    
    @objc private func fileManagerDidUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadDataIfNeeded()
        }
    }
    
    func reloadDataIfNeeded() {
        let currentCount = fileManager.rootItems.count
        if currentCount != lastItemsCount {
            lastItemsCount = currentCount
            reloadData()
        }
    }
    
    func reloadData() {
        collectionView.reloadData()
        
        var indexPaths = Set<IndexPath>()
        for (index, item) in fileManager.rootItems.enumerated() {
            if selectionManager.selectedItems.contains(item) {
                indexPaths.insert(IndexPath(item: index, section: 0))
            }
        }
        collectionView.selectionIndexPaths = indexPaths
    }
    
    private func updateLayout() {
        guard let flowLayout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        
        // 1️⃣ Changer la taille du layout
        flowLayout.itemSize = NSSize(width: iconSize + 20, height: iconSize + 40)
        flowLayout.invalidateLayout()
        
        // 2️⃣ 🆕 FORCER la mise à jour des items visibles
        collectionView.visibleItems().forEach { item in
            if let fileItem = item as? FileGridItem {
                fileItem.updateIconSize(iconSize)  // ⚠️ Méthode à ajouter
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(collectionView)
    }

    override func mouseDown(with event: NSEvent) {
        view.window?.makeFirstResponder(collectionView)
        super.mouseDown(with: event)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0 && event.modifierFlags.contains(.command) {
            selectAll()
        } else {
            super.keyDown(with: event)
        }
    }
    
    private func selectAll() {
        let allItems = Set(fileManager.rootItems)
        selectionManager.selectedItems = allItems
        
        var indexPaths = Set<IndexPath>()
        for (index, _) in fileManager.rootItems.enumerated() {
            indexPaths.insert(IndexPath(item: index, section: 0))
        }
        collectionView.selectionIndexPaths = indexPaths
    }
    
    private func openSelected() {
        for item in selectionManager.selectedItems {
            if item.isDirectory {
                onDoubleClick?(item)
                break
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }
    
    private func moveSelectedToTrash() {
        guard !selectionManager.selectedItems.isEmpty else { return }
        
        let alert = NSAlert()
        alert.messageText = "Placer \(selectionManager.selectedItems.count) éléments dans la corbeille ?"
        alert.addButton(withTitle: "Placer dans la corbeille")
        alert.addButton(withTitle: "Annuler")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            for item in selectionManager.selectedItems {
                try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            }
            fileManager.loadDirectory(at: fileManager.currentPath)
        }
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        return view.window?.makeFirstResponder(collectionView) ?? false
    }
}

// MARK: - NSCollectionViewDataSource
extension FileGridViewController: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return fileManager.rootItems.count
    }
    
    func collectionView(_ collectionView: NSCollectionView,
                       itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("FileGridItem"),
            for: indexPath
        ) as! FileGridItem
        
        if let fileItem = fileManager.rootItems[safe: indexPath.item] {
            item.configure(with: fileItem, iconSize: iconSize)
        }
        
        return item
    }
}

// MARK: - NSCollectionViewDelegate
extension FileGridViewController: NSCollectionViewDelegate {
    
    func collectionView(_ collectionView: NSCollectionView,
                       canDragItemsAt indexPaths: Set<IndexPath>,
                       with event: NSEvent) -> Bool {
        return !indexPaths.isEmpty
    }
    
    func collectionView(_ collectionView: NSCollectionView,
                       pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let item = fileManager.rootItems[safe: indexPath.item] else { return nil }
        return item.url as NSURL
    }
    
    func collectionView(_ collectionView: NSCollectionView,
                       draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint,
                       forItemsAt indexPaths: Set<IndexPath>) {
        
        if selectionManager.selectedItems.count > 1 {
            let selectedURLs = Array(selectionManager.selectedItems).map { $0.url }
            
            print("🎯 Multi-drag initié avec \(selectedURLs.count) fichiers:")
            for url in selectedURLs {
                print("  - \(url.lastPathComponent)")
            }
            
            let pasteboard = session.draggingPasteboard
            pasteboard.clearContents()
            pasteboard.writeObjects(selectedURLs as [NSURL])
        }
    }
    
    //dsazdzadza
    
    
    // MARK: - Sélection en temps réel avec rectangle
    func collectionView(_ collectionView: NSCollectionView,
                       didChangeItemsAt indexPaths: Set<IndexPath>,
                       to highlightState: NSCollectionViewItem.HighlightState) {
        // Mise à jour visuelle pendant le drag de sélection
        for indexPath in indexPaths {
            if let item = collectionView.item(at: indexPath) as? FileGridItem {
                switch highlightState {
                case .forSelection:
                    // Pendant que le rectangle passe sur l'item
                    item.setTemporaryHighlight(true)
                case .forDeselection:
                    // Quand le rectangle quitte l'item
                    item.setTemporaryHighlight(false)
                case .none:
                    item.setTemporaryHighlight(false)
                case .asDropTarget:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                       didSelectItemsAt indexPaths: Set<IndexPath>) {
        // Synchroniser avec le SelectionManager
        for indexPath in indexPaths {
            if let item = fileManager.rootItems[safe: indexPath.item] {
                selectionManager.selectedItems.insert(item)
            }
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                       didDeselectItemsAt indexPaths: Set<IndexPath>) {
        // Synchroniser avec le SelectionManager
        for indexPath in indexPaths {
            if let item = fileManager.rootItems[safe: indexPath.item] {
                selectionManager.selectedItems.remove(item)
            }
        }
    }
    
    //dazdzadazdaz
    func collectionView(_ collectionView: NSCollectionView,
                       validateDrop draggingInfo: NSDraggingInfo,
                       proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                       dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        
        if draggingInfo.draggingSource as? NSCollectionView === collectionView {
            return []
        }
        
        guard let item = fileManager.rootItems[safe: proposedDropIndexPath.pointee.item],
              item.isDirectory else {
            return []
        }
        
        return .copy
    }
    
    func collectionView(_ collectionView: NSCollectionView,
                       acceptDrop draggingInfo: NSDraggingInfo,
                       indexPath: IndexPath,
                       dropOperation: NSCollectionView.DropOperation) -> Bool {
        
        guard let item = fileManager.rootItems[safe: indexPath.item],
              item.isDirectory else {
            return false
        }
        
        let pasteboard = draggingInfo.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        for url in urls {
            print("Drop \(url.lastPathComponent) into \(item.name)")
        }
        
        return true
    }
}

// MARK: - NSPasteboardItemDataProvider
extension FileGridViewController: NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
    }
}

// MARK: - NSCollectionViewItem personnalisé
class FileGridItem: NSCollectionViewItem {
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var fileItem: AsyncFileItem?
    private var thumbnailTask: Task<Void, Never>?
    private var selectionBackgroundView: NSView!
    private var textSelectionBackgroundView: NSView!
    private var isTemporarilyHighlighted = false
    
    // Contraintes
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var selectionWidthConstraint: NSLayoutConstraint?
    private var selectionHeightConstraint: NSLayoutConstraint?
    
    override func loadView() {
        view = NSView()
        setupViews()
    }
    
    private func setupViews() {
        view = NSView()
        view.wantsLayer = true
        
        // Fond de sélection pour l'ICÔNE (gris)
        selectionBackgroundView = NSView()
        selectionBackgroundView.wantsLayer = true
        selectionBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        selectionBackgroundView.layer?.cornerRadius = 4
        selectionBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectionBackgroundView)
        
        // Image/Icon
        iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.wantsLayer = true
        view.addSubview(iconImageView)
        
        // Fond de sélection pour le TEXTE (bleu)
        textSelectionBackgroundView = NSView()
        textSelectionBackgroundView.wantsLayer = true
        textSelectionBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        textSelectionBackgroundView.layer?.cornerRadius = 3
        textSelectionBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textSelectionBackgroundView)
        
        // Label
        titleLabel = NSTextField()
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        setupInitialConstraints()
    }
    
    private func setupInitialConstraints() {
        NSLayoutConstraint.activate([
            // Icône
            iconImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Fond de sélection icône
            selectionBackgroundView.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            selectionBackgroundView.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            
            // Fond de sélection texte
            textSelectionBackgroundView.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 6),
            textSelectionBackgroundView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textSelectionBackgroundView.heightAnchor.constraint(equalToConstant: 18),
            textSelectionBackgroundView.widthAnchor.constraint(equalTo: titleLabel.widthAnchor, constant: 8),
            
            // Label
            titleLabel.centerXAnchor.constraint(equalTo: textSelectionBackgroundView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: textSelectionBackgroundView.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -4)
        ])
    }
    
    func updateIconSize(_ newSize: CGFloat) {
        iconWidthConstraint?.isActive = false
        iconHeightConstraint?.isActive = false
        selectionWidthConstraint?.isActive = false
        selectionHeightConstraint?.isActive = false
        
        iconWidthConstraint = iconImageView.widthAnchor.constraint(equalToConstant: newSize)
        iconHeightConstraint = iconImageView.heightAnchor.constraint(equalToConstant: newSize)
        selectionWidthConstraint = selectionBackgroundView.widthAnchor.constraint(equalToConstant: newSize + 6)
        selectionHeightConstraint = selectionBackgroundView.heightAnchor.constraint(equalToConstant: newSize + 6)
        
        iconWidthConstraint?.isActive = true
        iconHeightConstraint?.isActive = true
        selectionWidthConstraint?.isActive = true
        selectionHeightConstraint?.isActive = true
        
        view.needsLayout = true
    }
    
    func configure(with item: AsyncFileItem, iconSize: CGFloat) {
        self.fileItem = item
        
        titleLabel.stringValue = item.name
        iconImageView.image = item.icon ?? NSWorkspace.shared.icon(forFile: item.path)
        
        // Réinitialiser le style
        iconImageView.layer?.backgroundColor = NSColor.clear.cgColor
        iconImageView.layer?.borderWidth = 0
        iconImageView.layer?.shadowOpacity = 0
        
        // Configuration selon le type
        if item.shouldShowThumbnail && !item.isDirectory {
            iconImageView.imageScaling = .scaleProportionallyDown
        } else {
            iconImageView.imageScaling = .scaleProportionallyUpOrDown
        }
        
        updateIconSize(iconSize)
        
        if item.shouldShowThumbnail {
            loadThumbnail(for: item)
        }
    }
    
    private func loadThumbnail(for item: AsyncFileItem) {
        thumbnailTask?.cancel()
        
        thumbnailTask = Task { @MainActor in
            if let thumbnail = item.thumbnail {
                self.applyImageWithFrame(thumbnail)
                return
            }
            
            await item.loadThumbnailIfNeeded()
            if let thumbnail = item.thumbnail {
                self.applyImageWithFrame(thumbnail)
            }
        }
    }
    
    // 🆕 MÉTHODE CLÉE : Appliquer l'image avec un cadre qui respecte son ratio
    private func applyImageWithFrame(_ image: NSImage) {
        // 1. Obtenir le ratio de l'image
        let imageRatio = image.size.width / image.size.height
        
        // 2. Calculer la taille finale dans le conteneur
        let maxSize = iconWidthConstraint?.constant ?? 64
        var finalWidth: CGFloat
        var finalHeight: CGFloat
        
        if imageRatio > 1 {
            // Image paysage
            finalWidth = maxSize
            finalHeight = maxSize / imageRatio
        } else {
            // Image portrait ou carrée
            finalWidth = maxSize * imageRatio
            finalHeight = maxSize
        }
        
        // 3. Créer une nouvelle image avec fond blanc et bordure
        let frameSize = NSSize(width: finalWidth + 6, height: finalHeight + 6)
        let framedImage = NSImage(size: frameSize)
        
        framedImage.lockFocus()
        
        // Dessiner le fond blanc
        NSColor.white.setFill()
        let backgroundRect = NSRect(x: 0, y: 0, width: frameSize.width, height: frameSize.height)
        NSBezierPath(roundedRect: backgroundRect, xRadius: 3, yRadius: 3).fill()
        
        // Dessiner la bordure
        NSColor.gray.withAlphaComponent(0.3).setStroke()
        let borderPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 3, yRadius: 3)
        borderPath.lineWidth = 0.5
        borderPath.stroke()
        
        // Dessiner l'image centrée
        let imageRect = NSRect(x: 3, y: 3, width: finalWidth, height: finalHeight)
        image.draw(in: imageRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        
        framedImage.unlockFocus()
        
        // 4. Appliquer l'image avec cadre
        iconImageView.image = framedImage
        iconImageView.imageScaling = .scaleProportionallyDown
        
        // 5. Ajouter l'ombre
        iconImageView.layer?.shadowColor = NSColor.black.cgColor
        iconImageView.layer?.shadowOpacity = 0.15
        iconImageView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        iconImageView.layer?.shadowRadius = 2
    }
    
    func setTemporaryHighlight(_ highlighted: Bool) {
        isTemporarilyHighlighted = highlighted
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            if highlighted {
                selectionBackgroundView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.15).cgColor
                textSelectionBackgroundView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            } else if !isSelected {
                selectionBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
                textSelectionBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let locationInView = view.convert(event.locationInWindow, from: nil)
        let iconFrame = iconImageView.frame
        
        if !iconFrame.contains(locationInView) {
            super.mouseDown(with: event)
            return
        }
        
        if event.modifierFlags.contains(.command) {
            isSelected.toggle()
        } else if event.modifierFlags.contains(.shift) {
            super.mouseDown(with: event)
        } else if event.clickCount == 2 {
            if let fileItem = self.fileItem {
                if let delegate = self.collectionView?.delegate as? FileGridViewController {
                    delegate.onDoubleClick?(fileItem)
                }
            }
            super.mouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if !isSelected {
            isSelected = true
        }
        
        let menu = NSMenu()
        let selectedCount = (collectionView?.delegate as? FileGridViewController)?.selectionManager.selectedItems.count ?? 1
        
        let openItem = NSMenuItem(
            title: selectedCount > 1 ? "Ouvrir \(selectedCount) éléments" : "Ouvrir",
            action: #selector(openFiles(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        
        let copyItem = NSMenuItem(
            title: selectedCount > 1 ? "Copier \(selectedCount) éléments" : "Copier",
            action: #selector(copyFiles(_:)),
            keyEquivalent: "c"
        )
        copyItem.target = self
        menu.addItem(copyItem)
        menu.addItem(NSMenuItem.separator())
        
        let showInFinderItem = NSMenuItem(
            title: "Afficher dans le Finder",
            action: #selector(showInFinder(_:)),
            keyEquivalent: ""
        )
        showInFinderItem.target = self
        menu.addItem(showInFinderItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self.view)
    }
    
    @objc private func openFiles(_ sender: Any) {
        if let controller = collectionView?.delegate as? FileGridViewController {
            if controller.selectionManager.selectedItems.isEmpty {
                if let fileItem = self.fileItem {
                    controller.onDoubleClick?(fileItem)
                }
            } else {
                for item in controller.selectionManager.selectedItems {
                    if item.isDirectory {
                        controller.onDoubleClick?(item)
                        break
                    } else {
                        NSWorkspace.shared.open(item.url)
                    }
                }
            }
        }
    }
    
    @objc private func copyFiles(_ sender: Any) {
        if let controller = collectionView?.delegate as? FileGridViewController {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            
            if controller.selectionManager.selectedItems.isEmpty {
                if let fileItem = self.fileItem {
                    pasteboard.writeObjects([fileItem.url as NSURL])
                }
            } else {
                let urls = Array(controller.selectionManager.selectedItems).map { $0.url as NSURL }
                pasteboard.writeObjects(urls)
            }
        }
    }
    
    @objc private func showInFinder(_ sender: Any) {
        if let fileItem = self.fileItem {
            NSWorkspace.shared.selectFile(fileItem.path, inFileViewerRootedAtPath: "")
        }
    }
    
    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }
    
    private func updateSelectionAppearance() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            if isSelected {
                selectionBackgroundView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.2).cgColor
                textSelectionBackgroundView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
            } else if !isTemporarilyHighlighted {
                selectionBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
                textSelectionBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        fileItem = nil
        iconImageView.image = nil
        titleLabel.stringValue = ""
        isTemporarilyHighlighted = false
        
        // Réinitialiser le style
        iconImageView.layer?.backgroundColor = NSColor.clear.cgColor
        iconImageView.layer?.shadowOpacity = 0
    }
}

// MARK: - Extension Helper
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
