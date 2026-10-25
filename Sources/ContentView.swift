import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        VStack(spacing: 0) {
            if !store.isFullScreenPresentation {
                // Top ACDSee Toolbar
                TopToolbarView(store: store)
                Divider()
            }
            
            // Main Workspace Area
            HStack(spacing: 0) {
                if store.showSidebar && !store.isFullScreenPresentation {
                    SidebarFolderView(store: store)
                    Divider()
                }
                
                // Center Content according to ViewMode
                Group {
                    switch store.viewMode {
                    case .browse:
                        ThumbnailGridView(store: store)
                    case .view:
                        ViewerView(store: store)
                    case .split:
                        VSplitView {
                            ViewerView(store: store)
                                .frame(minHeight: 280)
                            ThumbnailGridView(store: store)
                                .frame(minHeight: 180)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if store.showInspector && !store.isFullScreenPresentation {
                    Divider()
                    InspectorPanelView(store: store)
                }
            }
            
            if !store.isFullScreenPresentation {
                Divider()
                // Bottom ACDSee Status Bar
                BottomStatusBarView(store: store)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if store.isFullScreenPresentation {
                store.exitFullScreenPresentation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshSelectedFileAfterExternalEdit()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(store.isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(2)
        )
        .onDrop(of: [.fileURL], isTargeted: $store.isDropTargeted) { providers in
            guard let first = providers.first else { return false }
            _ = first.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        store.openURL(url)
                    }
                }
            }
            return true
        }
        .background(KeyboardShortcutMonitor(store: store))
        .sheet(isPresented: $store.showBatchSheet) {
            BatchToolsSheetView(store: store)
        }
    }
}

struct TopToolbarView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        HStack(spacing: 10) {
            // Left: Sidebar toggle & Open button
            HStack(spacing: 6) {
                Button(action: { store.showSidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .help("แสดง/ซ่อนแถบโฟลเดอร์ซ้าย (Sidebar)")
                
                Button(action: { store.promptOpenFolderOrFile() }) {
                    Label("เปิดไฟล์/โฟลเดอร์", systemImage: "folder")
                }
                .help("เลือกรูปภาพหรือโฟลเดอร์ (Cmd+O)")
            }
            
            Divider().frame(height: 20)
            
            // Mode Switcher (Browse / View / Split - ACDSee style)
            Picker("", selection: $store.viewMode) {
                Label("ตาราง (Browse)", systemImage: "square.grid.2x2").tag(AppViewMode.browse)
                Label("ดูภาพ (View)", systemImage: "photo").tag(AppViewMode.view)
                Label("คู่ขนาน (Split)", systemImage: "rectangle.split.1x2").tag(AppViewMode.split)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            
            Divider().frame(height: 20)
            
            // Quick Prev / Next & Zoom Controls
            HStack(spacing: 4) {
                Button(action: { store.selectPreviousImage() }) {
                    Image(systemName: "arrow.left")
                }
                .disabled(store.filteredImages.isEmpty)
                .help("รูปก่อนหน้า (ลูกศรซ้าย ←)")
                
                Button(action: { store.selectNextImage() }) {
                    Image(systemName: "arrow.right")
                }
                .disabled(store.filteredImages.isEmpty)
                .help("รูปถัดไป (ลูกศรขวา →)")
                
                Divider().frame(height: 16)
                
                Button(action: { store.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(store.selectedImage == nil)
                .help("ซูมออก (-)")
                
                Button(action: { store.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(store.selectedImage == nil)
                .help("ซูมเข้า (+)")
                
                Button(action: { store.zoomFitWindow() }) {
                    Text("Fit")
                        .font(.system(size: 11, weight: .semibold))
                }
                .disabled(store.selectedImage == nil)
                .help("ซูมพอดีหน้าจอ (กด 0)")
                
                Button(action: { store.zoomActualSize() }) {
                    Text("100%")
                        .font(.system(size: 11, weight: .semibold))
                }
                .disabled(store.selectedImage == nil)
                .help("ขนาดจริง 1:1 (กด 1)")
                
                Divider().frame(height: 16)
                
                Button(action: { store.rotateLeft() }) {
                    Image(systemName: "rotate.left")
                }
                .disabled(store.selectedImage == nil)
                .help("หมุนซ้าย 90° (L)")
                
                Button(action: { store.rotateRight() }) {
                    Image(systemName: "rotate.right")
                }
                .disabled(store.selectedImage == nil)
                .help("หมุนขวา 90° (R)")
                
                Divider().frame(height: 16)
                
                Button(action: { store.editInMacOSPreview() }) {
                    Label("แก้ไขภาพ (Edit)", systemImage: "pencil.tip.crop.circle")
                }
                .disabled(store.selectedImage == nil)
                .help("แก้ไขรูปภาพด้วยโปรแกรม Preview ของ macOS (กด E หรือ Cmd+E)")
                
                Menu {
                    Button(action: { store.openBatchTools(.rename) }) {
                        Label("เปลี่ยนชื่อไฟล์เป็นชุด (Batch Rename)", systemImage: "pencil.and.list.clipboard")
                    }
                    Button(action: { store.openBatchTools(.convert) }) {
                        Label("แปลงไฟล์และย่อขนาด (Batch Convert & Resize)", systemImage: "photo.stack")
                    }
                    Button(action: { store.openBatchTools(.rotate) }) {
                        Label("หมุนและบันทึกภาพเป็นชุด (Batch Rotate & Save)", systemImage: "rotate.right.fill")
                    }
                    Divider()
                    Button(action: { store.editInMacOSPreview() }) {
                        Label("แก้ไขด้วย macOS Preview (Edit in Preview)", systemImage: "pencil.tip.crop.circle")
                    }
                    Button(action: { store.editWithChosenApplication() }) {
                        Label("แก้ไขด้วยโปรแกรมอื่น... (Edit With...)", systemImage: "app.badge")
                    }
                } label: {
                    Label("จัดการชุด (Batch)", systemImage: "gearshape.2.fill")
                }
                .disabled(store.filteredImages.isEmpty)
                .help("เครื่องมือจัดการไฟล์เป็นชุด: เปลี่ยนชื่อ แปลงไฟล์ และหมุนภาพ (Cmd+B)")
            }
            
            Spacer()
            
            // Sort & Thumbnail Size when Browse/Split
            if store.viewMode != .view {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $store.thumbnailSize, in: 90...280)
                        .frame(width: 85)
                        .help("ปรับขนาด Thumbnail")
                    Image(systemName: "photo")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Menu {
                    Picker("เรียงตาม", selection: $store.sortField) {
                        ForEach(SortField.allCases) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    Divider()
                    Button(action: { store.sortAscending = true }) {
                        HStack {
                            Text("น้อยไปมาก (A → Z)")
                            if store.sortAscending { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { store.sortAscending = false }) {
                        HStack {
                            Text("มากไปน้อย (Z → A)")
                            if !store.sortAscending { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    Label("เรียงลำดับ", systemImage: "arrow.up.arrow.down")
                }
                .frame(width: 105)
            }
            
            // Search Box
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("ค้นหาชื่อไฟล์...", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 125)
                if !store.searchText.isEmpty {
                    Button(action: { store.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            
            // Right Inspector Toggle
            Button(action: { store.showInspector.toggle() }) {
                Image(systemName: "sidebar.right")
            }
            .help("แสดง/ซ่อนข้อมูลรูปภาพ EXIF (Inspector)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct BottomStatusBarView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        HStack(spacing: 14) {
            Text("ลำดับภาพ: \(store.positionText)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            
            if let item = store.selectedImage {
                Divider().frame(height: 12)
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Divider().frame(height: 12)
                Text(store.currentMetadata.resolutionText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Divider().frame(height: 12)
                Text(item.formattedSize)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Divider().frame(height: 12)
                Text("ซูม: \(Int(round(store.zoomScale * 100)))%\(store.isFitToWindow ? " (Fit)" : "")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("คีย์ลัด: [2 นิ้วเลื่อนขึ้น-ลง / ←/→] เปลี่ยนภาพ  [ถ่าง 2 นิ้ว / Cmd+เลื่อน / +/-] ซูม  [0] พอดีจอ  [1] 100%  [Enter] สลับโหมด")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct KeyboardShortcutMonitor: NSViewRepresentable {
    @ObservedObject var store: ImageStore
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyMonitorNSView()
        view.store = store
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? KeyMonitorNSView {
            v.store = store
        }
    }
    
    final class KeyMonitorNSView: NSView {
        var store: ImageStore?
        private var monitor: Any?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self, let store = self.store else { return event }
                    
                    if store.showBatchSheet {
                        return event
                    }
                    
                    // Ignore when typing inside a TextField
                    if let responder = event.window?.firstResponder as? NSTextView,
                       responder.isFieldEditor {
                        return event
                    }
                    
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCmd = flags.contains(.command)
                    
                    switch event.keyCode {
                    case 123: // Left Arrow ←
                        store.selectPreviousImage()
                        return nil
                    case 124: // Right Arrow →
                        store.selectNextImage()
                        return nil
                    case 126: // Up Arrow ↑
                        if store.viewMode == .view {
                            store.selectPreviousImage()
                            return nil
                        }
                    case 125: // Down Arrow ↓
                        if store.viewMode == .view {
                            store.selectNextImage()
                            return nil
                        }
                    case 49: // Spacebar
                        if store.selectedImage?.isVideo == true {
                            store.toggleVideoPlayPause()
                        } else {
                            store.selectNextImage()
                        }
                        return nil
                    case 51: // Delete / Backspace
                        if isCmd {
                            store.moveSelectedImageToTrash()
                        } else {
                            store.selectPreviousImage()
                        }
                        return nil
                    case 36, 76: // Return / Enter
                        store.viewMode = (store.viewMode == .browse) ? .view : .browse
                        return nil
                    case 53: // Escape
                        if store.isSlideshowRunning {
                            store.stopSlideshow()
                            return nil
                        } else if store.isFullScreenPresentation {
                            store.exitFullScreenPresentation()
                            return nil
                        } else if store.viewMode == .view {
                            store.viewMode = .browse
                            return nil
                        }
                    case 115: // Home
                        store.selectFirstImage()
                        return nil
                    case 119: // End
                        store.selectLastImage()
                        return nil
                    case 24, 69: // + or =
                        store.zoomIn()
                        return nil
                    case 27, 78: // -
                        store.zoomOut()
                        return nil
                    case 29, 82: // 0
                        store.zoomFitWindow()
                        return nil
                    case 18, 83: // 1
                        store.zoomActualSize()
                        return nil
                    default:
                        if !isCmd, let chars = event.charactersIgnoringModifiers?.lowercased() {
                            switch chars {
                            case "r", "]":
                                store.rotateRight()
                                return nil
                            case "l", "[":
                                store.rotateLeft()
                                return nil
                            case "h":
                                store.toggleFlipHorizontal()
                                return nil
                            case "v":
                                store.toggleFlipVertical()
                                return nil
                            case "s":
                                store.toggleSlideshow()
                                return nil
                            case "f":
                                store.toggleFullScreenPresentation()
                                return nil
                            case "e":
                                store.editInMacOSPreview()
                                return nil
                            default:
                                break
                            }
                        }
                    }
                    return event
                }
            } else if window == nil, let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
        
        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
