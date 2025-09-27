// DrawerApp_FileViews.swift
// Vues pour l'affichage des fichiers (Grid, List, Columns)

import SwiftUI
import AppKit

// MARK: - Icon Grid View
struct IconGridView: View {
    let items: [AsyncFileItem]
    let iconSize: CGFloat
    @ObservedObject var selectionManager: SelectionManager
    let onDoubleClick: (AsyncFileItem) -> Void
    
    @State private var gridWidth: CGFloat = 0
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var isSelecting = false
    @State private var selectionStart: CGPoint = .zero
    @State private var selectionCurrent: CGPoint = .zero
    
    var columns: [GridItem] {
        let spacing: CGFloat = 10
        let itemWidth = iconSize + 30
        let padding: CGFloat = 32
        let availableWidth = max(100, gridWidth - padding) // Minimum 100px
        let count = max(1, Int(availableWidth / (itemWidth + spacing)))
        
        // Si on a peu de place, forcer une disposition adaptative
        if availableWidth < 300 {
            return [GridItem(.adaptive(minimum: itemWidth, maximum: itemWidth), spacing: spacing)]
        }
        
        return Array(repeating: GridItem(.flexible(minimum: itemWidth, maximum: itemWidth), spacing: spacing), count: count)
    }
    
    var selectionRect: CGRect {
        let minX = min(selectionStart.x, selectionCurrent.x)
        let minY = min(selectionStart.y, selectionCurrent.y)
        let width = abs(selectionCurrent.x - selectionStart.x)
        let height = abs(selectionCurrent.y - selectionStart.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView([.vertical, .horizontal], showsIndicators: true) {  // ← Permettre scroll horizontal aussi
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            EnhancedIconCellView(
                                item: item,
                                iconSize: iconSize,
                                isSelected: selectionManager.selectedItems.contains(item),
                                selectedItems: selectionManager.selectedItems,
                                onTap: {
                                    selectionManager.handleSimpleClick(item: item, at: index)
                                },
                                onDoubleTap: {
                                    onDoubleClick(item)
                                },
                                onCommandTap: {
                                    selectionManager.handleCommandClick(item: item, at: index)
                                },
                                onShiftTap: {
                                    selectionManager.handleShiftClick(item: item, at: index, in: items)
                                }
                            )
                            .frame(width: min(iconSize + 30, (gridWidth - 32) / CGFloat(max(1, columns.count)) - 15))
                            .frame(height: iconSize + 50)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            itemFrames[item.id] = geo.frame(in: .named("grid"))
                                        }
                                        .onChange(of: geo.frame(in: .named("grid"))) { _, newFrame in
                                            itemFrames[item.id] = newFrame
                                        }
                                }
                            )
                        }
                    }
                    .padding(16)
                    .frame(minWidth: gridWidth > 0 ? gridWidth - 20 : nil)  // ← Contrainte minimale
                    .background(
                        Color.white.opacity(0.001)
                            .onTapGesture {
                                selectionManager.clearSelection()
                            }
                    )
                    .coordinateSpace(name: "grid")
                }
                .scrollIndicators(.visible, axes: [.vertical, .horizontal])  // ← Forcer l'affichage des scrollbars
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .named("grid"))
                        .onChanged { value in
                            let startItem = selectionManager.itemAt(
                                point: value.startLocation,
                                in: itemFrames,
                                items: items
                            )
                            
                            if !isSelecting && startItem == nil {
                                isSelecting = true
                                selectionStart = value.startLocation
                                selectionManager.clearSelection()
                            }
                            
                            if isSelecting {
                                selectionCurrent = value.location
                                selectionManager.updateRectangleSelection(
                                    rect: selectionRect,
                                    items: items,
                                    itemFrames: itemFrames,
                                    additive: false
                                )
                            }
                        }
                        .onEnded { value in
                            if value.translation.width.magnitude < 2 &&
                               value.translation.height.magnitude < 2 {
                                let clickedItem = selectionManager.itemAt(
                                    point: value.startLocation,
                                    in: itemFrames,
                                    items: items
                                )
                                if clickedItem == nil {
                                    selectionManager.clearSelection()
                                }
                            }
                            
                            isSelecting = false
                            selectionStart = .zero
                            selectionCurrent = .zero
                        }
                )
                
                // Rectangle de sélection
                if isSelecting {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .background(Color.accentColor.opacity(0.1))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                gridWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                gridWidth = newWidth
            }
        }
    }
}
struct EnhancedIconCellView: View {
    @ObservedObject var item: AsyncFileItem
    let iconSize: CGFloat
    let isSelected: Bool
    let selectedItems: Set<AsyncFileItem>
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onCommandTap: (() -> Void)?
    let onShiftTap: (() -> Void)?
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .center) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: iconSize + 10, height: iconSize + 10)
                        .allowsHitTesting(false)
                }
                
                IconContent(item: item, iconSize: iconSize)
                    .frame(width: iconSize, height: iconSize)
                
                if item.isDirectory && item.isLoadingChildren {
                    ProgressView()
                        .controlSize(.small)
                        .position(x: iconSize - 10, y: iconSize - 10)
                }
            }
            .frame(width: iconSize + 10, height: iconSize + 10)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onTapGesture(count: 1) {
                isPressed = true
                onTap()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.isPressed = false
                }
            }
            .highPriorityGesture(TapGesture().modifiers(.command).onEnded { _ in
                onCommandTap?()
            })
            .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { _ in
                onShiftTap?()
            })
            
            FileNameLabel(item: item, iconSize: iconSize)
                .allowsHitTesting(false)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .onDrag {
            if isSelected {
                return createDragItem()
            } else {
                let provider = NSItemProvider(object: item.url as NSURL)
                return provider
            }
        } preview: {
            DragPreview(
                item: item,
                selectedItems: isSelected ? selectedItems : [item],
                isSelected: isSelected
            )
        }
        .contextMenu {
            FileContextMenu(
                item: item,
                isSelected: isSelected,
                selectedItems: selectedItems,
                onDoubleTap: onDoubleTap
            )
        }
        .onAppear {
            if item.shouldShowThumbnail && !item.isDirectory {
                Task {
                    await item.loadThumbnailIfNeeded()
                }
            }
        }
    }
    
    private func createDragItem() -> NSItemProvider {
        if !isSelected {
            onTap()
        }
        
        let itemsToDrag = (isSelected && selectedItems.count > 1) ?
            Array(selectedItems) : [item]
        
        if itemsToDrag.count > 1 {
            let pasteboard = NSPasteboard(name: .drag)
            pasteboard.clearContents()
            pasteboard.writeObjects(itemsToDrag.map { $0.url as NSURL })
        }
        
        let provider = NSItemProvider(object: itemsToDrag[0].url as NSURL)
        return provider
    }
}

// MARK: - Icon Cell Components
struct IconContent: View {
    @ObservedObject var item: AsyncFileItem
    let iconSize: CGFloat
    
    var body: some View {
        if item.shouldShowThumbnail && !item.isDirectory {
            ThumbnailView(item: item, iconSize: iconSize)
        } else {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            } else {
                ProgressView()
                    .frame(width: iconSize, height: iconSize)
            }
        }
    }
}

struct ThumbnailView: View {
    @ObservedObject var item: AsyncFileItem
    let iconSize: CGFloat
    
    var body: some View {
        ZStack {
            if let thumbnail = item.thumbnail {
                // 🖼️ EXACTEMENT COMME LE FINDER
                VStack(spacing: 0) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(Color.white) // Fond blanc SOUS l'image
                        .overlay(
                            // Bordure grise très fine
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color(white: 0.8, opacity: 1), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(maxWidth: iconSize - 6, maxHeight: iconSize - 6)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                
            } else if item.isLoadingThumbnail {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                    .overlay(ProgressView().scaleEffect(0.5))
                
            } else if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize * 0.8, height: iconSize * 0.8)
            }
            
            MediaBadges(item: item, iconSize: iconSize)
        }
        .frame(width: iconSize, height: iconSize)
        .task {
            if item.thumbnail == nil && !item.isLoadingThumbnail {
                await item.loadThumbnailIfNeeded()
            }
        }
    }
}

struct MediaBadges: View {
    let item: AsyncFileItem
    let iconSize: CGFloat
    
    var body: some View {
        Group {
            if item.isVideoFile {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: iconSize * 0.2))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: iconSize * 0.25, height: iconSize * 0.25)
                            )
                            .padding(4)
                    }
                }
                .frame(width: iconSize, height: iconSize)
            }
            
            if item.fileExtension == "psd" || item.fileExtension == "psb" {
                VStack {
                    HStack {
                        Spacer()
                        Text("PSD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.purple)
                            )
                            .padding(4)
                    }
                    Spacer()
                }
                .frame(width: iconSize, height: iconSize)
            }
        }
    }
}

struct FileNameLabel: View {
    let item: AsyncFileItem
    let iconSize: CGFloat
    
    var body: some View {
        HStack(spacing: 2) {
            Text(item.url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)
            
            if item.shouldShowThumbnail && !item.isDirectory {
                Text(".\(item.fileExtension)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(getExtensionColor(item.fileExtension))
            }
        }
        .frame(width: iconSize + 20)
    }
    
    private func getExtensionColor(_ ext: String) -> Color {
        switch ext {
        case let e where AsyncFileItem.imageExtensions.contains(e):
            return .blue
        case let e where AsyncFileItem.psdExtensions.contains(e):
            return .purple
        case let e where AsyncFileItem.videoExtensions.contains(e):
            return .orange
        case let e where AsyncFileItem.rawExtensions.contains(e):
            return .cyan
        default:
            return .gray
        }
    }
}

struct DragPreview: View {
    let item: AsyncFileItem
    let selectedItems: Set<AsyncFileItem>
    let isSelected: Bool
    
    var body: some View {
        Group {
            if isSelected && selectedItems.count > 1 {
                ZStack {
                    ForEach(0..<min(3, selectedItems.count), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(radius: 2)
                            .frame(width: 50, height: 50)
                            .offset(x: CGFloat(index * 4), y: CGFloat(index * 4))
                    }
                    
                    VStack(spacing: 2) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        Text("\(selectedItems.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 50, height: 50)
                }
            } else {
                VStack {
                    if let thumbnail = item.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .frame(width: 40, height: 40)
                    } else if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                    }
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FileContextMenu: View {
    let item: AsyncFileItem
    let isSelected: Bool
    let selectedItems: Set<AsyncFileItem>
    let onDoubleTap: () -> Void
    
    var body: some View {
        Group {
            if isSelected && selectedItems.count > 1 {
                Button("Open \(selectedItems.count) items") {
                    for selectedItem in selectedItems {
                        NSWorkspace.shared.open(selectedItem.url)
                    }
                }
            } else {
                Button("Open") { onDoubleTap() }
            }
            
            if !item.isDirectory {
                Button("Open With...") {
                    NSWorkspace.shared.open(item.url)
                }
            }
            
            Divider()
            
            if isSelected && selectedItems.count > 1 {
                Button("Copy \(selectedItems.count) items") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects(Array(selectedItems).map { $0.url as NSURL })
                }
            } else {
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([item.url as NSURL])
                }
            }
            
            Button("Show in Finder") {
                if isSelected && selectedItems.count > 1 {
                    for selectedItem in selectedItems {
                        NSWorkspace.shared.selectFile(selectedItem.path, inFileViewerRootedAtPath: "")
                    }
                } else {
                    NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }
}

// MARK: - List View
struct AsyncListView: View {
    let items: [AsyncFileItem]
    @Binding var selectedItems: Set<AsyncFileItem>
    let onDoubleClick: (AsyncFileItem) -> Void
    @State private var lastSelectedIndex: Int? = nil
    
    var body: some View {
        List(selection: $selectedItems) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                AsyncListRow(
                    item: item,
                    isSelected: selectedItems.contains(item),
                    selectedItems: selectedItems,
                    onDoubleClick: {
                        onDoubleClick(item)
                    }
                )
                .tag(item)
                .onTapGesture {
                    handleSelection(item, at: index)
                }
            }
        }
        .listStyle(PlainListStyle())
        .scrollIndicators(.hidden)
    }
    
    private func handleSelection(_ item: AsyncFileItem, at index: Int) {
        let modifiers = NSEvent.modifierFlags
        
        if modifiers.contains(.shift), let lastIndex = lastSelectedIndex {
            let start = min(lastIndex, index)
            let end = max(lastIndex, index)
            
            for i in start...end {
                if i < items.count {
                    selectedItems.insert(items[i])
                }
            }
        } else if modifiers.contains(.command) {
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
            lastSelectedIndex = index
        } else {
            selectedItems = [item]
            lastSelectedIndex = index
        }
    }
}

struct AsyncListRow: View {
    @ObservedObject var item: AsyncFileItem
    let isSelected: Bool
    let selectedItems: Set<AsyncFileItem>
    let onDoubleClick: () -> Void
    @State private var isDragging = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon ?? NSImage())
                .resizable()
                .frame(width: 16, height: 16)
            
            Text(item.name)
                .lineLimit(1)
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text(item.formattedDate)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .trailing)
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onDrag {
            isDragging = true
            
            let urls: [URL]
            if isSelected && selectedItems.count > 1 {
                urls = Array(selectedItems).map { $0.url }
            } else {
                urls = [item.url]
            }
            
            if urls.count > 1 {
                let pasteboard = NSPasteboard(name: .drag)
                pasteboard.clearContents()
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            }
            
            return NSItemProvider(object: urls.first! as NSURL)
        } preview: {
            Group {
                if isSelected && selectedItems.count > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14))
                        Text("\(selectedItems.count)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(nsImage: item.icon ?? NSImage())
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            .onAppear { isDragging = true }
            .onDisappear { isDragging = false }
        }
    }
}

// MARK: - Column View
struct AsyncColumnView: View {
    let rootPath: String
    @ObservedObject var fileManager: AsyncFileManager
    @Binding var selectedItems: Set<AsyncFileItem>
    let onDoubleClick: (AsyncFileItem) -> Void
    
    @State private var columnPaths: [String] = []
    @State private var columnItems: [[AsyncFileItem]] = []
    @State private var lastSelectedIndex: [Int: Int] = [:]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<columnPaths.count, id: \.self) { columnIndex in
                    VStack(spacing: 0) {
                        Text(URL(fileURLWithPath: columnPaths[columnIndex]).lastPathComponent)
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                        
                        List(Array((columnItems[safe: columnIndex] ?? []).enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Image(nsImage: item.icon ?? NSImage())
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                
                                Text(item.name)
                                    .lineLimit(1)
                                
                                if item.isDirectory {
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .background(selectedItems.contains(item) ? Color.accentColor.opacity(0.2) : Color.clear)
                            .onTapGesture {
                                handleColumnSelection(item, at: index, in: columnIndex)
                            }
                            .tag(item)
                        }
                        .listStyle(PlainListStyle())
                        .scrollIndicators(.hidden)
                    }
                    .frame(width: 200)
                    
                    Divider()
                }
            }
        }
        .onAppear {
            loadInitialColumn()
        }
    }
    
    private func loadInitialColumn() {
        columnPaths = [rootPath]
        columnItems = [fileManager.rootItems]
    }
    
    private func handleColumnSelection(_ item: AsyncFileItem, at index: Int, in columnIndex: Int) {
        let modifiers = NSEvent.modifierFlags
        let itemsInColumn = columnItems[safe: columnIndex] ?? []
        
        if modifiers.contains(.shift), let lastIndex = lastSelectedIndex[columnIndex] {
            let start = min(lastIndex, index)
            let end = max(lastIndex, index)
            
            for i in start...end {
                if i < itemsInColumn.count {
                    selectedItems.insert(itemsInColumn[i])
                }
            }
        } else if modifiers.contains(.command) {
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
            lastSelectedIndex[columnIndex] = index
        } else {
            selectedItems = [item]
            lastSelectedIndex[columnIndex] = index
            
            if item.isDirectory {
                fileManager.loadChildren(for: item)
                
                columnPaths = Array(columnPaths.prefix(columnIndex + 1))
                columnItems = Array(columnItems.prefix(columnIndex + 1))
                
                columnPaths.append(item.path)
                columnItems.append(item.children)
            } else {
                onDoubleClick(item)
            }
        }
    }
}
