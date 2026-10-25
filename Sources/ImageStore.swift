import Foundation
import AppKit
import SwiftUI
import ImageIO
import AVFoundation

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "com.imagevplus.thumbnail", qos: .userInitiated, attributes: .concurrent)
    
    private init() {
        cache.countLimit = 800
    }
    
    func cachedThumbnail(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }
    
    func removeThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
    
    func clearAll() {
        cache.removeAllObjects()
    }
    
    func loadThumbnail(for url: URL, maxPixelSize: Int = 360, completion: @escaping @Sendable (NSImage?) -> Void) {
        if let existing = cache.object(forKey: url as NSURL) {
            completion(existing)
            return
        }
        
        queue.async { [weak self] in
            var resultImage: NSImage? = nil
            
            if ImageItem.isVideo(url: url) {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    resultImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                } else if let cgImageZero = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    resultImage = NSImage(cgImage: cgImageZero, size: NSSize(width: cgImageZero.width, height: cgImageZero.height))
                } else {
                    resultImage = NSImage(systemSymbolName: "film.fill", accessibilityDescription: "Video")
                }
            } else {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ]
                
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    resultImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                } else if let fallback = NSImage(contentsOf: url) {
                    resultImage = fallback
                }
            }
            
            if let img = resultImage {
                self?.cache.setObject(img, forKey: url as NSURL)
            }
            
            DispatchQueue.main.async {
                completion(resultImage)
            }
        }
    }
}

@MainActor
final class ImageStore: ObservableObject {
    @Published var currentFolderURL: URL?
    @Published var subfolders: [FolderNode] = []
    @Published var allImages: [ImageItem] = []
    @Published var filteredImages: [ImageItem] = []
    @Published var selectedImage: ImageItem? {
        didSet {
            if selectedImage != oldValue {
                loadCurrentImageAndMetadata()
            }
            if let item = selectedImage, selectedIDs.isEmpty {
                selectedIDs = [item.id]
            }
        }
    }
    @Published var selectedIDs: Set<URL> = []
    @Published var showBatchSheet: Bool = false
    @Published var activeBatchTab: BatchTab = .rename
    @Published var thumbnailRefreshToken: UUID = UUID()
    
    @Published var currentNSImage: NSImage?
    @Published var currentAVPlayer: AVPlayer?
    @Published var currentMetadata: ImageMetadata = ImageMetadata()
    
    // View & UI States
    @Published var viewMode: AppViewMode = .split
    @Published var showSidebar: Bool = true
    @Published var showInspector: Bool = true
    @Published var showFilmstrip: Bool = true
    @Published var isFullScreenPresentation: Bool = false
    @Published var thumbnailSize: Double = 150
    
    private var savedViewModeBeforeFullScreen: AppViewMode = .split
    private var savedShowSidebar: Bool = true
    private var savedShowInspector: Bool = true
    private var savedShowFilmstrip: Bool = true
    
    // Sorting & Filtering
    @Published var sortField: SortField = .name {
        didSet { applyFilterAndSort() }
    }
    @Published var sortAscending: Bool = true {
        didSet { applyFilterAndSort() }
    }
    @Published var searchText: String = "" {
        didSet { applyFilterAndSort() }
    }
    
    // Viewer Zoom & Transform States
    @Published var zoomScale: CGFloat = 1.0
    @Published var isFitToWindow: Bool = true
    @Published var panOffset: CGSize = .zero
    @Published var lastPanOffset: CGSize = .zero
    @Published var gestureZoom: CGFloat = 1.0
    @Published var containerSize: CGSize = .zero
    @Published var isDropTargeted: Bool = false
    @Published var rotationDegrees: Int = 0
    @Published var isFlippedHorizontally: Bool = false
    @Published var isFlippedVertically: Bool = false
    @Published var viewerBackgroundBrightness: Double = 0.08
    
    // Slideshow
    @Published var isSlideshowRunning: Bool = false
    @Published var slideshowInterval: TimeInterval = 3.0
    private var slideshowTimer: Timer?
    
    // Folder History & TreeView State
    @Published var folderHistory: [URL] = []
    @Published var historyIndex: Int = -1
    @Published var expandedFolderURLs: Set<URL> = []
    private var subfoldersCache: [URL: [FolderNode]] = [:]
    
    var quickAccessFolders: [FolderNode] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL
        var nodes: [FolderNode] = [
            FolderNode(id: home, url: home, name: "Home (\(home.lastPathComponent))", iconName: "house.fill")
        ]
        
        let standardDirs: [(FileManager.SearchPathDirectory, String, String)] = [
            (.picturesDirectory, "Pictures (รูปภาพ)", "photo.on.rectangle.angled"),
            (.desktopDirectory, "Desktop (เดสก์ท็อป)", "menubar.dock.rectangle"),
            (.downloadsDirectory, "Downloads (ดาวน์โหลด)", "arrow.down.circle.fill"),
            (.documentDirectory, "Documents (เอกสาร)", "doc.fill")
        ]
        
        for (dir, title, icon) in standardDirs {
            if let url = fm.urls(for: dir, in: .userDomainMask).first?.standardizedFileURL {
                nodes.append(FolderNode(id: url, url: url, name: title, iconName: icon))
            }
        }
        return nodes
    }
    
    var treeRootFolders: [FolderNode] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL
        var roots: [FolderNode] = [
            FolderNode(id: home, url: home, name: "Home (\(home.lastPathComponent))", iconName: "house.fill")
        ]
        
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        if let volumes = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for vol in volumes {
                let stdVol = vol.standardizedFileURL
                if stdVol.path != "/" {
                    roots.append(FolderNode(id: stdVol, url: stdVol, name: stdVol.lastPathComponent, iconName: "externaldrive.fill"))
                }
            }
        }
        return roots
    }
    
    func childFolders(for folderURL: URL) -> [FolderNode] {
        let stdURL = folderURL.standardizedFileURL
        if let cached = subfoldersCache[stdURL] {
            return cached
        }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let contents = try? fm.contentsOfDirectory(at: stdURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            subfoldersCache[stdURL] = []
            return []
        }
        var children: [FolderNode] = []
        for itemURL in contents {
            let stdItem = itemURL.standardizedFileURL
            guard let res = try? stdItem.resourceValues(forKeys: Set(keys)) else { continue }
            if res.isDirectory == true && res.isPackage != true {
                children.append(
                    FolderNode(
                        id: stdItem,
                        url: stdItem,
                        name: stdItem.lastPathComponent,
                        iconName: "folder.fill"
                    )
                )
            }
        }
        children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        subfoldersCache[stdURL] = children
        return children
    }
    
    func isFolderExpanded(_ folderURL: URL) -> Bool {
        expandedFolderURLs.contains(folderURL.standardizedFileURL)
    }
    
    func toggleFolderExpansion(_ folderURL: URL) {
        let stdURL = folderURL.standardizedFileURL
        if expandedFolderURLs.contains(stdURL) {
            expandedFolderURLs.remove(stdURL)
        } else {
            expandedFolderURLs.insert(stdURL)
        }
    }
    
    func expandTreePath(to targetURL: URL) {
        var current = targetURL.standardizedFileURL
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        expandedFolderURLs.insert(current)
        
        while current.path.count > 1 && current.path != "/" {
            expandedFolderURLs.insert(current)
            if current.path == homePath {
                break
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current { break }
            current = parent
        }
    }
    
    init() {
        let fm = FileManager.default
        // Check command line arguments first
        let args = CommandLine.arguments.dropFirst()
        if let firstArg = args.first, !firstArg.starts(with: "-"), fm.fileExists(atPath: firstArg) {
            openURL(URL(fileURLWithPath: firstArg))
            return
        }
        
        // Load Pictures if it has images, otherwise check SampleImages in current directory or Desktop
        if let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first {
            loadFolder(url: pictures, recordHistory: true)
            if allImages.isEmpty {
                let sampleDir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("SampleImages")
                let bundleSiblingSample = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SampleImages")
                if fm.fileExists(atPath: bundleSiblingSample.path) {
                    loadFolder(url: bundleSiblingSample, recordHistory: true)
                } else if fm.fileExists(atPath: sampleDir.path) {
                    loadFolder(url: sampleDir, recordHistory: true)
                }
            }
        } else {
            loadFolder(url: fm.homeDirectoryForCurrentUser, recordHistory: true)
        }
    }
    
    func openURL(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                loadFolder(url: url, recordHistory: true)
            } else if ImageItem.isSupported(url: url) {
                let parent = url.deletingLastPathComponent()
                loadFolder(url: parent, selectingFileURL: url, recordHistory: true)
                viewMode = .view
            }
        }
    }
    
    func promptOpenFolderOrFile() {
        let panel = NSOpenPanel()
        panel.title = "เลือกรูปภาพหรือโฟลเดอร์ (Open Image or Folder)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        
        if panel.runModal() == .OK, let url = panel.url {
            openURL(url)
        }
    }
    
    func loadFolder(url: URL, selectingFileURL: URL? = nil, recordHistory: Bool = true) {
        stopSlideshow()
        let standardizedURL = url.standardizedFileURL
        currentFolderURL = standardizedURL
        
        if recordHistory {
            if historyIndex < folderHistory.count - 1 {
                folderHistory.removeSubrange((historyIndex + 1)..<folderHistory.count)
            }
            if folderHistory.last != standardizedURL {
                folderHistory.append(standardizedURL)
                historyIndex = folderHistory.count - 1
            }
        }
        
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isPackageKey]
        
        guard let contents = try? fm.contentsOfDirectory(
            at: standardizedURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            subfolders = []
            allImages = []
            filteredImages = []
            selectedImage = nil
            return
        }
        
        var folders: [FolderNode] = []
        var images: [ImageItem] = []
        
        for itemURL in contents {
            let stdItemURL = itemURL.standardizedFileURL
            guard let res = try? stdItemURL.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            
            if res.isDirectory == true && res.isPackage != true {
                folders.append(
                    FolderNode(
                        id: stdItemURL,
                        url: stdItemURL,
                        name: stdItemURL.lastPathComponent,
                        iconName: "folder.fill"
                    )
                )
            } else if ImageItem.isSupported(url: stdItemURL) {
                let size = Int64(res.fileSize ?? 0)
                let modDate = res.contentModificationDate ?? Date.distantPast
                images.append(
                    ImageItem(
                        id: stdItemURL,
                        url: stdItemURL,
                        name: stdItemURL.lastPathComponent,
                        fileExtension: stdItemURL.pathExtension.lowercased(),
                        fileSize: size,
                        modificationDate: modDate
                    )
                )
            }
        }
        
        subfolders = folders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        subfoldersCache[standardizedURL] = subfolders
        expandTreePath(to: standardizedURL)
        allImages = images
        applyFilterAndSort()
        
        if let targetURL = selectingFileURL?.standardizedFileURL,
           let matched = filteredImages.first(where: { $0.url.standardizedFileURL == targetURL }) {
            selectedImage = matched
            selectedIDs = [matched.id]
        } else {
            selectedImage = filteredImages.first
            selectedIDs = selectedImage != nil ? [selectedImage!.id] : []
        }
    }
    
    func reloadCurrentFolder() {
        guard let currentFolder = currentFolderURL else { return }
        let currentSelectedURL = selectedImage?.url
        subfoldersCache.removeAll()
        ThumbnailCache.shared.clearAll()
        thumbnailRefreshToken = UUID()
        loadFolder(url: currentFolder, selectingFileURL: currentSelectedURL, recordHistory: false)
        loadCurrentImageAndMetadata()
    }
    
    func handleGridClick(on item: ImageItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedIDs.contains(item.id) && selectedIDs.count > 1 {
                selectedIDs.remove(item.id)
                if selectedImage == item {
                    selectedImage = filteredImages.first(where: { selectedIDs.contains($0.id) })
                }
            } else {
                selectedIDs.insert(item.id)
                selectedImage = item
            }
        } else if flags.contains(.shift),
                  let anchor = selectedImage,
                  let anchorIdx = filteredImages.firstIndex(of: anchor),
                  let targetIdx = filteredImages.firstIndex(of: item) {
            let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
            selectedIDs = Set(filteredImages[range].map { $0.id })
            selectedImage = item
        } else {
            selectedIDs = [item.id]
            selectedImage = item
        }
    }
    
    func selectAllImages() {
        selectedIDs = Set(filteredImages.map { $0.id })
        if selectedImage == nil {
            selectedImage = filteredImages.first
        }
    }
    
    var selectedItemsInOrder: [ImageItem] {
        let matched = filteredImages.filter { selectedIDs.contains($0.id) }
        if !matched.isEmpty {
            return matched
        }
        if let single = selectedImage {
            return [single]
        }
        return []
    }
    
    func openBatchTools(_ tab: BatchTab) {
        activeBatchTab = tab
        showBatchSheet = true
    }
    
    func applyFilterAndSort() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = allImages
        
        if !query.isEmpty {
            list = list.filter { $0.name.lowercased().contains(query) }
        }
        
        list.sort { a, b in
            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = a.name.localizedStandardCompare(b.name)
            case .dateModified:
                if a.modificationDate == b.modificationDate {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.modificationDate < b.modificationDate ? .orderedAscending : .orderedDescending
                }
            case .size:
                if a.fileSize == b.fileSize {
                    comparison = a.name.localizedStandardCompare(b.name)
                } else {
                    comparison = a.fileSize < b.fileSize ? .orderedAscending : .orderedDescending
                }
            case .type:
                let extComp = a.fileExtension.localizedStandardCompare(b.fileExtension)
                comparison = extComp == .orderedSame ? a.name.localizedStandardCompare(b.name) : extComp
            }
            return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        }
        
        filteredImages = list
        if let current = selectedImage, !filteredImages.contains(current) {
            selectedImage = filteredImages.first
        }
    }
    
    // MARK: - Navigation (Left / Right / First / Last)
    
    var currentIndex: Int? {
        guard let selected = selectedImage else { return nil }
        return filteredImages.firstIndex(of: selected)
    }
    
    var positionText: String {
        guard let idx = currentIndex, !filteredImages.isEmpty else {
            return "0 / 0"
        }
        return "\(idx + 1) / \(filteredImages.count)"
    }
    
    func selectNextImage(wrap: Bool = true) {
        guard !filteredImages.isEmpty else { return }
        guard let idx = currentIndex else {
            selectedImage = filteredImages.first
            if let s = selectedImage { selectedIDs = [s.id] }
            return
        }
        if idx + 1 < filteredImages.count {
            selectedImage = filteredImages[idx + 1]
        } else if wrap {
            selectedImage = filteredImages.first
        }
        if let s = selectedImage { selectedIDs = [s.id] }
    }
    
    func selectPreviousImage(wrap: Bool = true) {
        guard !filteredImages.isEmpty else { return }
        guard let idx = currentIndex else {
            selectedImage = filteredImages.first
            if let s = selectedImage { selectedIDs = [s.id] }
            return
        }
        if idx - 1 >= 0 {
            selectedImage = filteredImages[idx - 1]
        } else if wrap {
            selectedImage = filteredImages.last
        }
        if let s = selectedImage { selectedIDs = [s.id] }
    }
    
    func selectFirstImage() {
        selectedImage = filteredImages.first
        if let s = selectedImage { selectedIDs = [s.id] }
    }
    
    func selectLastImage() {
        selectedImage = filteredImages.last
        if let s = selectedImage { selectedIDs = [s.id] }
    }
    
    func goUpOneFolder() {
        guard let current = currentFolderURL else { return }
        let parent = current.deletingLastPathComponent()
        if parent != current {
            loadFolder(url: parent, recordHistory: true)
        }
    }
    
    func goBackFolder() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        let url = folderHistory[historyIndex]
        loadFolder(url: url, recordHistory: false)
    }
    
    func goForwardFolder() {
        guard historyIndex + 1 < folderHistory.count else { return }
        historyIndex += 1
        let url = folderHistory[historyIndex]
        loadFolder(url: url, recordHistory: false)
    }
    
    // MARK: - Zoom & Rotation Controls
    
    func zoomIn() {
        isFitToWindow = false
        let next = min(zoomScale * 1.25, 10.0)
        zoomScale = next
    }
    
    func zoomOut() {
        isFitToWindow = false
        let next = max(zoomScale / 1.25, 0.05)
        zoomScale = next
    }
    
    func zoomActualSize() {
        isFitToWindow = false
        zoomScale = 1.0
        panOffset = .zero
        lastPanOffset = .zero
    }
    
    func zoomFitWindow() {
        isFitToWindow = true
        panOffset = .zero
        lastPanOffset = .zero
    }
    
    func centerImage() {
        panOffset = .zero
        lastPanOffset = .zero
    }
    
    func toggleFullScreenPresentation() {
        if isFullScreenPresentation {
            exitFullScreenPresentation()
        } else {
            enterFullScreenPresentation()
        }
    }
    
    func enterFullScreenPresentation() {
        savedViewModeBeforeFullScreen = viewMode
        savedShowSidebar = showSidebar
        savedShowInspector = showInspector
        savedShowFilmstrip = showFilmstrip
        
        isFullScreenPresentation = true
        viewMode = .view
        showSidebar = false
        showInspector = false
        showFilmstrip = false
        isFitToWindow = true
        panOffset = .zero
        lastPanOffset = .zero
        
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }
    
    func exitFullScreenPresentation() {
        guard isFullScreenPresentation else { return }
        isFullScreenPresentation = false
        viewMode = savedViewModeBeforeFullScreen
        showSidebar = savedShowSidebar
        showInspector = savedShowInspector
        showFilmstrip = savedShowFilmstrip
        isFitToWindow = true
        panOffset = .zero
        lastPanOffset = .zero
        
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }
    
    func rotateRight() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }
    
    func rotateLeft() {
        rotationDegrees = (rotationDegrees + 270) % 360
    }
    
    func toggleFlipHorizontal() {
        isFlippedHorizontally.toggle()
    }
    
    func toggleFlipVertical() {
        isFlippedVertically.toggle()
    }
    
    func resetTransform() {
        rotationDegrees = 0
        isFlippedHorizontally = false
        isFlippedVertically = false
        isFitToWindow = true
        panOffset = .zero
        lastPanOffset = .zero
        gestureZoom = 1.0
    }
    
    // MARK: - Slideshow
    
    func toggleSlideshow() {
        if isSlideshowRunning {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }
    
    func startSlideshow() {
        guard !filteredImages.isEmpty else { return }
        if viewMode == .browse {
            viewMode = .view
        }
        isSlideshowRunning = true
        slideshowTimer?.invalidate()
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.selectNextImage(wrap: true)
            }
        }
    }
    
    func stopSlideshow() {
        isSlideshowRunning = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }
    
    // MARK: - File Actions
    
    func editInMacOSPreview() {
        let targets = selectedItemsInOrder.map { $0.url }
        guard !targets.isEmpty else { return }
        
        let previewAppURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        if FileManager.default.fileExists(atPath: previewAppURL.path) {
            NSWorkspace.shared.open(targets, withApplicationAt: previewAppURL, configuration: config, completionHandler: nil)
        } else if let first = targets.first {
            NSWorkspace.shared.open(first)
        }
    }
    
    func editWithChosenApplication() {
        let targets = selectedItemsInOrder.map { $0.url }
        guard !targets.isEmpty else { return }
        
        let panel = NSOpenPanel()
        panel.title = "เลือกโปรแกรมสำหรับแก้ไขรูปภาพ (Choose Editor Application)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        
        if panel.runModal() == .OK, let appURL = panel.url {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(targets, withApplicationAt: appURL, configuration: config, completionHandler: nil)
        }
    }
    
    func refreshSelectedFileAfterExternalEdit() {
        guard let item = selectedImage else { return }
        ThumbnailCache.shared.removeThumbnail(for: item.url)
        thumbnailRefreshToken = UUID()
        loadCurrentImageAndMetadata()
    }
    
    func revealInFinder() {
        if let item = selectedImage {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else if let folder = currentFolderURL {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
        }
    }
    
    func copySelectedImageToClipboard() {
        guard let image = currentNSImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
    
    func moveSelectedImageToTrash() {
        guard let item = selectedImage else { return }
        let currentIdx = currentIndex ?? 0
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            allImages.removeAll { $0 == item }
            applyFilterAndSort()
            if !filteredImages.isEmpty {
                let nextIdx = min(currentIdx, filteredImages.count - 1)
                selectedImage = filteredImages[nextIdx]
            } else {
                selectedImage = nil
            }
        } catch {
            NSSound.beep()
        }
    }
    
    // MARK: - Image / Video & EXIF Metadata Loading
    
    func toggleVideoPlayPause() {
        guard let player = currentAVPlayer else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
    
    private func loadCurrentImageAndMetadata() {
        resetTransform()
        currentAVPlayer?.pause()
        currentAVPlayer = nil
        
        guard let item = selectedImage else {
            currentNSImage = nil
            currentMetadata = ImageMetadata()
            return
        }
        
        let url = item.url
        if item.isVideo {
            let player = AVPlayer(url: url)
            currentAVPlayer = player
            player.play()
            
            // Load poster frame for inspector preview
            ThumbnailCache.shared.loadThumbnail(for: url, maxPixelSize: 640) { [weak self] thumb in
                Task { @MainActor in
                    if self?.selectedImage?.url == url {
                        self?.currentNSImage = thumb
                    }
                }
            }
            
            currentMetadata = ImageMetadata()
            Task { @MainActor in
                let asset = AVURLAsset(url: url)
                var meta = ImageMetadata()
                if let dur = try? await asset.load(.duration) {
                    let totalSec = Int(max(0, round(CMTimeGetSeconds(dur))))
                    let mins = totalSec / 60
                    let secs = totalSec % 60
                    let hours = mins / 60
                    if hours > 0 {
                        meta.videoDuration = String(format: "%d:%02d:%02d", hours, mins % 60, secs)
                    } else {
                        meta.videoDuration = String(format: "%02d:%02d", mins, secs)
                    }
                }
                if let tracks = try? await asset.loadTracks(withMediaType: .video),
                   let track = tracks.first {
                    if let natSize = try? await track.load(.naturalSize),
                       let prefTrans = try? await track.load(.preferredTransform) {
                        let transformed = natSize.applying(prefTrans)
                        meta.pixelWidth = Int(abs(round(transformed.width)))
                        meta.pixelHeight = Int(abs(round(transformed.height)))
                    }
                    if let fps = try? await track.load(.nominalFrameRate), fps > 0 {
                        meta.videoFrameRate = String(format: "%.0f fps", round(fps))
                    }
                }
                if self.selectedImage?.url == url {
                    self.currentMetadata = meta
                }
            }
            return
        }
        
        if let image = NSImage(contentsOf: url) {
            currentNSImage = image
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            currentNSImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            currentNSImage = nil
        }
        
        currentMetadata = extractMetadata(from: url, fallbackImage: currentNSImage)
    }
    
    private func extractMetadata(from url: URL, fallbackImage: NSImage?) -> ImageMetadata {
        var meta = ImageMetadata()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            if let rep = fallbackImage?.representations.first {
                meta.pixelWidth = rep.pixelsWide
                meta.pixelHeight = rep.pixelsHigh
            }
            return meta
        }
        
        meta.pixelWidth = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        meta.pixelHeight = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        meta.dpiWidth = props[kCGImagePropertyDPIWidth] as? Int
        meta.colorModel = props[kCGImagePropertyColorModel] as? String
        meta.depth = props[kCGImagePropertyDepth] as? Int
        
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            meta.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.lensModel = exif[kCGImagePropertyExifLensModel] as? String
            meta.dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            
            if let fNum = exif[kCGImagePropertyExifFNumber] as? Double {
                meta.fNumber = String(format: "f/%.1f", fNum)
            }
            if let exp = exif[kCGImagePropertyExifExposureTime] as? Double {
                if exp > 0 && exp < 1.0 {
                    let denom = Int(round(1.0 / exp))
                    meta.exposureTime = "1/\(denom) sec"
                } else if exp >= 1.0 {
                    meta.exposureTime = String(format: "%.1f sec", exp)
                }
            }
            if let isoArr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let firstISO = isoArr.first {
                meta.iso = "ISO \(firstISO)"
            }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                meta.focalLength = String(format: "%.0f mm", focal)
            }
        }
        
        return meta
    }
}
