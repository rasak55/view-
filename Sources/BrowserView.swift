import SwiftUI
import AppKit

@MainActor
final class ThumbnailViewModel: ObservableObject {
    @Published var thumbnail: NSImage?
    
    func load(url: URL) {
        if let cached = ThumbnailCache.shared.cachedThumbnail(for: url) {
            thumbnail = cached
            return
        }
        ThumbnailCache.shared.loadThumbnail(for: url, maxPixelSize: 380) { [weak self] loaded in
            Task { @MainActor in
                self?.thumbnail = loaded
            }
        }
    }
}

struct ThumbnailImageView: View {
    let url: URL
    let size: CGFloat
    var refreshToken: UUID = UUID()
    @StateObject private var viewModel = ThumbnailViewModel()
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.25))
            
            if let img = viewModel.thumbnail {
                Image(nsImage: img)
                    .interpolation(.medium)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
            
            if ImageItem.isVideo(url: url) {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("VIDEO")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: size, height: size * 0.78)
        .onAppear {
            viewModel.load(url: url)
        }
        .onChange(of: url) { _, newURL in
            viewModel.thumbnail = nil
            viewModel.load(url: newURL)
        }
        .onChange(of: refreshToken) { _, _ in
            viewModel.thumbnail = nil
            viewModel.load(url: url)
        }
    }
}

struct FolderTreeBranchView: View {
    @ObservedObject var store: ImageStore
    let node: FolderNode
    let depth: Int
    
    var body: some View {
        let stdURL = node.url.standardizedFileURL
        let isSelected = (store.currentFolderURL == stdURL)
        let isExpanded = store.isFolderExpanded(stdURL)
        let children = store.childFolders(for: stdURL)
        let hasChildren = !children.isEmpty
        
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 14)
                }
                
                // Expand / Collapse Disclosure Triangle
                if hasChildren {
                    Button(action: {
                        store.toggleFolderExpansion(stdURL)
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 16, height: 20)
                }
                
                // Folder Icon & Name (Single-click loads folder contents immediately!)
                Button(action: {
                    store.loadFolder(url: stdURL, recordHistory: true)
                    if hasChildren {
                        store.expandedFolderURLs.insert(stdURL)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: depth == 0 ? node.iconName : (isExpanded ? "folder.fill" : "folder.fill"))
                            .foregroundColor(depth == 0 ? .accentColor : (isSelected ? .white : .yellow))
                            .font(.system(size: 12.5))
                            .frame(width: 16)
                        
                        Text(node.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : .primary)
                        
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            
            // Recursive Children when Expanded
            if isExpanded && hasChildren {
                ForEach(children) { child in
                    FolderTreeBranchView(
                        store: store,
                        node: child,
                        depth: depth + 1
                    )
                }
            }
        }
    }
}

struct SidebarFolderView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation Header
            HStack(spacing: 6) {
                Button(action: { store.goBackFolder() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.historyIndex <= 0)
                .help("ย้อนกลับโฟลเดอร์ก่อนหน้า (Back)")
                
                Button(action: { store.goForwardFolder() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.historyIndex + 1 >= store.folderHistory.count)
                .help("ไปโฟลเดอร์ถัดไป (Forward)")
                
                Button(action: { store.goUpOneFolder() }) {
                    Image(systemName: "arrow.up")
                }
                .help("ขึ้นไปโฟลเดอร์แม่ (Up One Level)")
                
                Spacer()
                
                Button(action: { store.promptOpenFolderOrFile() }) {
                    Label("เปิด...", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Quick Access Favorites Section
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ทางลัดด่วน (Favorites)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)
                        
                        ForEach(store.quickAccessFolders) { node in
                            let isSelected = (store.currentFolderURL == node.url.standardizedFileURL)
                            Button(action: {
                                store.loadFolder(url: node.url, recordHistory: true)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: node.iconName)
                                        .foregroundColor(isSelected ? .white : .accentColor)
                                        .frame(width: 18)
                                    Text(node.name)
                                        .lineLimit(1)
                                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? .white : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, 8)
                    
                    // Full Expandable Folder TreeView (Finder / ACDSee Style)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("โครงสร้างโฟลเดอร์ (Folder Tree)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { store.reloadCurrentFolder() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("รีเฟรชรายการโฟลเดอร์ (Refresh Tree)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)
                        
                        ForEach(store.treeRootFolders) { rootNode in
                            FolderTreeBranchView(
                                store: store,
                                node: rootNode,
                                depth: 0
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(minWidth: 220, idealWidth: 255, maxWidth: 340)
    }
}

struct ThumbnailGridView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Path Breadcrumb Bar
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.yellow)
                Text(store.currentFolderURL?.path ?? "-")
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if store.selectedIDs.count > 1 {
                    Text("เลือก \(store.selectedIDs.count) รูป")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
                
                Button("เลือกทั้งหมด (Cmd+A)") {
                    store.selectAllImages()
                }
                .controlSize(.small)
                .disabled(store.filteredImages.isEmpty)
                
                Text("\(store.filteredImages.count) รูปภาพ")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if store.filteredImages.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 52, weight: .thin))
                        .foregroundColor(.secondary)
                    Text("ไม่พบรูปภาพหรือวิดีโอในโฟลเดอร์นี้")
                        .font(.headline)
                    Text("คลิกเลือกโฟลเดอร์อื่นจาก TreeView ด้านซ้าย หรือลากไฟล์มาวางที่นี่")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("เลือกโฟลเดอร์หรือรูปภาพ (Open...)") {
                        store.promptOpenFolderOrFile()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        let cellW = CGFloat(store.thumbnailSize)
                        let columns = [GridItem(.adaptive(minimum: cellW, maximum: cellW + 40), spacing: 14)]
                        
                        LazyVGrid(columns: columns, spacing: 14) {
                            // Image & Video Thumbnails
                            ForEach(store.filteredImages) { item in
                                let isSelected = store.selectedIDs.contains(item.id) || (store.selectedImage == item)
                                VStack(spacing: 5) {
                                    ThumbnailImageView(url: item.url, size: cellW, refreshToken: store.thumbnailRefreshToken)
                                    
                                    Text(item.name)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(width: cellW)
                                    
                                    HStack(spacing: 4) {
                                        Text(item.fileExtension.uppercased())
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2)))
                                        Text(item.formattedSize)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color.accentColor.opacity(0.28) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .gesture(
                                    TapGesture(count: 2).onEnded {
                                        store.selectedImage = item
                                        store.enterFullScreenPresentation()
                                    }
                                    .exclusively(before: TapGesture(count: 1).onEnded {
                                        store.handleGridClick(on: item)
                                    })
                                )
                                .contextMenu {
                                    Button("แสดงเต็มหน้าจอ (Full Screen)") {
                                        store.selectedImage = item
                                        store.enterFullScreenPresentation()
                                    }
                                    Button("โหมดดูภาพ (View Mode)") {
                                        store.selectedImage = item
                                        store.viewMode = .view
                                    }
                                    Divider()
                                    Button("แก้ไขด้วย macOS Preview (Edit — Cmd+E)") {
                                        if !store.selectedIDs.contains(item.id) {
                                            store.selectedIDs = [item.id]
                                            store.selectedImage = item
                                        }
                                        store.editInMacOSPreview()
                                    }
                                    Button("แก้ไขด้วยโปรแกรมอื่น... (Edit With...)") {
                                        if !store.selectedIDs.contains(item.id) {
                                            store.selectedIDs = [item.id]
                                            store.selectedImage = item
                                        }
                                        store.editWithChosenApplication()
                                    }
                                    Divider()
                                    Button("เปลี่ยนชื่อเป็นชุด... (Batch Rename)") {
                                        if !store.selectedIDs.contains(item.id) {
                                            store.selectedIDs = [item.id]
                                            store.selectedImage = item
                                        }
                                        store.openBatchTools(.rename)
                                    }
                                    Button("แปลงไฟล์/ย่อขนาดเป็นชุด... (Batch Convert)") {
                                        if !store.selectedIDs.contains(item.id) {
                                            store.selectedIDs = [item.id]
                                            store.selectedImage = item
                                        }
                                        store.openBatchTools(.convert)
                                    }
                                    Button("หมุนภาพและบันทึกเป็นชุด... (Batch Rotate)") {
                                        if !store.selectedIDs.contains(item.id) {
                                            store.selectedIDs = [item.id]
                                            store.selectedImage = item
                                        }
                                        store.openBatchTools(.rotate)
                                    }
                                    Divider()
                                    Button("แสดงใน Finder (Reveal in Finder)") {
                                        store.selectedImage = item
                                        store.revealInFinder()
                                    }
                                    Button("คัดลอกรูปภาพ (Copy Image)") {
                                        store.selectedImage = item
                                        store.copySelectedImageToClipboard()
                                    }
                                    Divider()
                                    Button("ย้ายไปถังขยะ (Move to Trash)", role: .destructive) {
                                        store.selectedImage = item
                                        store.moveSelectedImageToTrash()
                                    }
                                }
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: store.selectedImage) { _, newItem in
                        if let id = newItem?.id {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct InspectorPanelView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.accentColor)
                Text("ข้อมูลรูปภาพ (Properties / EXIF)")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if let item = store.selectedImage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Mini Preview in Browse Mode
                        if store.viewMode == .browse {
                            if item.isVideo {
                                NativeVideoPlayerView(player: store.currentAVPlayer)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 170)
                                    .cornerRadius(8)
                            } else if let nsImg = store.currentNSImage {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.black.opacity(0.85))
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(6)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 170)
                                .onTapGesture(count: 2) {
                                    store.toggleFullScreenPresentation()
                                }
                                .help("ดับเบิ้ลคลิกเพื่อแสดงเต็มหน้าจอ (Double-click for Full Screen)")
                            }
                        }
                        
                        GroupBox(label: Label("ไฟล์ (File Info)", systemImage: "doc.text")) {
                            VStack(alignment: .leading, spacing: 6) {
                                infoRow("ชื่อไฟล์", item.name)
                                infoRow("ชนิด", "\(item.fileExtension.uppercased())\(item.isVideo ? " (Video)" : "")")
                                infoRow("ขนาดไฟล์", item.formattedSize)
                                infoRow("ขนาดภาพ", store.currentMetadata.resolutionText)
                                if let dur = store.currentMetadata.videoDuration {
                                    infoRow("ความยาว", dur)
                                }
                                if let fps = store.currentMetadata.videoFrameRate {
                                    infoRow("เฟรมเรต", fps)
                                }
                                infoRow("แก้ไขล่าสุด", item.formattedDate)
                            }
                            .padding(.top, 4)
                        }
                        
                        let meta = store.currentMetadata
                        if meta.cameraModel != nil || meta.iso != nil || meta.fNumber != nil || meta.exposureTime != nil {
                            GroupBox(label: Label("ข้อมูลกล้อง (EXIF)", systemImage: "camera.aperture")) {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let make = meta.cameraMake { infoRow("ยี่ห้อกล้อง", make) }
                                    if let model = meta.cameraModel { infoRow("รุ่นกล้อง", model) }
                                    if let lens = meta.lensModel { infoRow("เลนส์", lens) }
                                    if let focal = meta.focalLength { infoRow("ระยะเลนส์", focal) }
                                    if let fNum = meta.fNumber { infoRow("รูรับแสง", fNum) }
                                    if let exp = meta.exposureTime { infoRow("สปีดชัตเตอร์", exp) }
                                    if let iso = meta.iso { infoRow("ค่าแสง", iso) }
                                    if let dateOrig = meta.dateTimeOriginal { infoRow("วันที่ถ่าย", dateOrig) }
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        GroupBox(label: Label("สีและรายละเอียด", systemImage: "paintpalette")) {
                            VStack(alignment: .leading, spacing: 6) {
                                infoRow("Color Space", meta.colorModel ?? "-")
                                infoRow("Bit Depth", meta.depth != nil ? "\(meta.depth!) bit" : "-")
                                infoRow("DPI", meta.dpiWidth != nil ? "\(meta.dpiWidth!) DPI" : "-")
                            }
                            .padding(.top, 4)
                        }
                        
                        VStack(spacing: 8) {
                            Button(action: { store.editInMacOSPreview() }) {
                                Label("แก้ไขภาพด้วย macOS Preview (Edit)", systemImage: "pencil.tip.crop.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button(action: { store.revealInFinder() }) {
                                Label("เปิดตำแหน่งไฟล์ใน Finder", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.small)
                            
                            Button(action: { store.copySelectedImageToClipboard() }) {
                                Label("คัดลอกรูปภาพ (Copy)", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                }
            } else {
                VStack {
                    Spacer()
                    Text("เลือกรูปภาพเพื่อดูรายละเอียด")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 230, idealWidth: 255, maxWidth: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
