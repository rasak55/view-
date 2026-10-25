import Foundation
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Core Image & File Batch Engine

enum ImageTransformService {
    
    static func previewNewFilename(
        for item: ImageItem,
        index: Int,
        mode: BatchRenameMode,
        template: String,
        startNumber: Int,
        digitCount: Int,
        prefix: String,
        suffix: String,
        findText: String,
        replaceText: String
    ) -> String {
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let ext = item.url.pathExtension
        let seqNum = startNumber + index
        let formatStr = "%0\(max(1, digitCount))d"
        let paddedNum = String(format: formatStr, seqNum)
        
        var newBase: String
        switch mode {
        case .template:
            let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeTemplate = trimmed.isEmpty ? "Image_#" : trimmed
            if safeTemplate.contains("#") {
                // Replace consecutive ### with padded number
                if let range = safeTemplate.range(of: "#+", options: .regularExpression) {
                    let hashCount = safeTemplate.distance(from: range.lowerBound, to: range.upperBound)
                    let effectiveDigits = max(hashCount, digitCount)
                    let numStr = String(format: "%0\(effectiveDigits)d", seqNum)
                    newBase = safeTemplate.replacingCharacters(in: range, with: numStr)
                } else {
                    newBase = "\(safeTemplate)_\(paddedNum)"
                }
            } else {
                newBase = "\(safeTemplate)_\(paddedNum)"
            }
        case .prefixSuffix:
            newBase = "\(prefix)\(baseName)\(suffix)"
        case .findReplace:
            if findText.isEmpty {
                newBase = baseName
            } else {
                newBase = baseName.replacingOccurrences(of: findText, with: replaceText)
            }
        }
        
        if newBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBase = baseName
        }
        return ext.isEmpty ? newBase : "\(newBase).\(ext)"
    }
    
    static func loadOrientedCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        var maxDim = 16384
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if max(w, h) > 0 {
                maxDim = max(w, h)
            }
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        if let cgImg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
            return cgImg
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    
    static func transformCGImage(
        _ cgImage: CGImage,
        targetSize: CGSize? = nil,
        clockwiseDegrees: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) -> CGImage? {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        
        let baseW = targetSize?.width ?? srcW
        let baseH = targetSize?.height ?? srcH
        
        let normDeg = ((clockwiseDegrees % 360) + 360) % 360
        let isSwap = (normDeg == 90 || normDeg == 270)
        let outW = Int(max(1, round(isSwap ? baseH : baseW)))
        let outH = Int(max(1, round(isSwap ? baseW : baseH)))
        
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(outW) / 2.0, y: CGFloat(outH) / 2.0)
        
        if normDeg != 0 {
            // CoreGraphics positive angle is counter-clockwise, so clockwise is negative
            let radians = -CGFloat(normDeg) * .pi / 180.0
            ctx.rotate(by: radians)
        }
        
        ctx.scaleBy(
            x: flipHorizontal ? -1.0 : 1.0,
            y: flipVertical ? -1.0 : 1.0
        )
        
        let drawRect = CGRect(x: -baseW / 2.0, y: -baseH / 2.0, width: baseW, height: baseH)
        ctx.draw(cgImage, in: drawRect)
        return ctx.makeImage()
    }
    
    static func writeCGImage(
        _ cgImage: CGImage,
        to destinationURL: URL,
        utTypeString: String,
        jpegQuality: Double = 0.90
    ) -> Bool {
        if let dest = CGImageDestinationCreateWithURL(destinationURL as CFURL, utTypeString as CFString, 1, nil) {
            var props: [CFString: Any] = [
                kCGImagePropertyOrientation: 1
            ]
            if utTypeString == UTType.jpeg.identifier || utTypeString == UTType.heic.identifier {
                props[kCGImageDestinationLossyCompressionQuality] = jpegQuality
            }
            CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
            if CGImageDestinationFinalize(dest) {
                return true
            }
        }
        
        // Fallback via NSBitmapImageRep
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let fileType: NSBitmapImageRep.FileType
        switch utTypeString {
        case UTType.png.identifier: fileType = .png
        case UTType.tiff.identifier: fileType = .tiff
        case UTType.bmp.identifier: fileType = .bmp
        default: fileType = .jpeg
        }
        if let data = rep.representation(using: fileType, properties: [.compressionFactor: jpegQuality]) {
            do {
                try data.write(to: destinationURL, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    static func utTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return UTType.png.identifier
        case "heic", "heif": return UTType.heic.identifier
        case "tif", "tiff": return UTType.tiff.identifier
        case "bmp": return UTType.bmp.identifier
        default: return UTType.jpeg.identifier
        }
    }
}

// MARK: - ViewModel for Batch Dialog

@MainActor
final class BatchToolsViewModel: ObservableObject {
    @Published var scope: BatchScope = .allInFolder
    
    // Tab 1: Rename Settings
    @Published var renameMode: BatchRenameMode = .template
    @Published var renameTemplate: String = "Photo_###"
    @Published var startNumber: Int = 1
    @Published var digitCount: Int = 3
    @Published var prefixText: String = "IMG_"
    @Published var suffixText: String = ""
    @Published var findText: String = ""
    @Published var replaceText: String = ""
    
    // Tab 2: Convert & Resize Settings
    @Published var outputFormat: BatchOutputFormat = .jpeg
    @Published var jpegQuality: Double = 0.90
    @Published var resizeMode: BatchResizeMode = .original
    @Published var maxDimensionPx: String = "1920"
    @Published var scalePercentage: Double = 50.0
    @Published var saveConvertInSubfolder: Bool = true
    @Published var convertSubfolderName: String = "Converted"
    @Published var customOutputFolderURL: URL? = nil
    
    // Tab 3: Rotate & Flip Settings
    @Published var rotationAngle: BatchRotationAngle = .rotate90CW
    @Published var flipHorizontal: Bool = false
    @Published var flipVertical: Bool = false
    @Published var overwriteOriginalOnRotate: Bool = true
    
    // Progress & Status
    @Published var isProcessing: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var statusIsSuccess: Bool = true
    
    func targetItems(from store: ImageStore) -> [ImageItem] {
        switch scope {
        case .selectedOnly:
            return store.selectedItemsInOrder
        case .allInFolder:
            return store.filteredImages
        }
    }
    
    func chooseCustomOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "เลือกโฟลเดอร์ปลายทาง (Select Output Folder)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            customOutputFolderURL = panel.url
            saveConvertInSubfolder = false
        }
    }
    
    // MARK: - Execute Batch Rename
    
    func runBatchRename(store: ImageStore) {
        let items = targetItems(from: store)
        guard !items.isEmpty else {
            statusIsSuccess = false
            statusMessage = "ไม่มีไฟล์ที่เลือกสำหรับการเปลี่ยนชื่อ"
            return
        }
        
        isProcessing = true
        progressValue = 0
        statusMessage = "กำลังเปลี่ยนชื่อไฟล์..."
        
        let fm = FileManager.default
        var tempPairs: [(tempURL: URL, finalURL: URL)] = []
        var successCount = 0
        
        // Step 1: Move to temporary names to avoid any filename collisions
        for (idx, item) in items.enumerated() {
            let newName = ImageTransformService.previewNewFilename(
                for: item,
                index: idx,
                mode: renameMode,
                template: renameTemplate,
                startNumber: startNumber,
                digitCount: digitCount,
                prefix: prefixText,
                suffix: suffixText,
                findText: findText,
                replaceText: replaceText
            )
            let dir = item.url.deletingLastPathComponent()
            let finalURL = dir.appendingPathComponent(newName)
            
            if finalURL.standardizedFileURL == item.url.standardizedFileURL {
                continue
            }
            
            let tempURL = dir.appendingPathComponent(".tmp_rename_\(UUID().uuidString)_\(newName)")
            do {
                try fm.moveItem(at: item.url, to: tempURL)
                tempPairs.append((tempURL: tempURL, finalURL: finalURL))
            } catch {
                continue
            }
        }
        
        // Step 2: Move from temporary names to final target names
        let total = max(1, tempPairs.count)
        for (i, pair) in tempPairs.enumerated() {
            var targetURL = pair.finalURL
            if fm.fileExists(atPath: targetURL.path) {
                let base = targetURL.deletingPathExtension().lastPathComponent
                let ext = targetURL.pathExtension
                let dir = targetURL.deletingLastPathComponent()
                targetURL = dir.appendingPathComponent("\(base)_\(i + 1).\(ext)")
            }
            do {
                try fm.moveItem(at: pair.tempURL, to: targetURL)
                successCount += 1
            } catch {
                // Attempt rollback
                _ = try? fm.moveItem(at: pair.tempURL, to: pair.finalURL)
            }
            progressValue = Double(i + 1) / Double(total)
        }
        
        isProcessing = false
        statusIsSuccess = true
        statusMessage = "✅ เปลี่ยนชื่อไฟล์สำเร็จ \(successCount) ไฟล์!"
        store.reloadCurrentFolder()
    }
    
    // MARK: - Execute Batch Convert & Resize
    
    func runBatchConvert(store: ImageStore) {
        let items = targetItems(from: store).filter { !$0.isVideo }
        guard !items.isEmpty, let baseFolder = store.currentFolderURL else {
            statusIsSuccess = false
            statusMessage = "ไม่มีไฟล์รูปภาพนิ่งสำหรับแปลงไฟล์"
            return
        }
        
        isProcessing = true
        progressValue = 0
        statusMessage = "กำลังแปลงไฟล์และปรับขนาด..."
        
        let fm = FileManager.default
        let destFolder: URL
        if saveConvertInSubfolder {
            let subName = convertSubfolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            destFolder = baseFolder.appendingPathComponent(subName.isEmpty ? "Converted" : subName)
        } else if let custom = customOutputFolderURL {
            destFolder = custom
        } else {
            destFolder = baseFolder.appendingPathComponent("Converted")
        }
        
        try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
        
        var successCount = 0
        let total = max(1, items.count)
        let targetExt = outputFormat.fileExtension
        let targetUTType = outputFormat.utTypeString
        let maxDimVal = Double(maxDimensionPx) ?? 1920.0
        
        for (idx, item) in items.enumerated() {
            if let cgImg = ImageTransformService.loadOrientedCGImage(from: item.url) {
                let origW = Double(cgImg.width)
                let origH = Double(cgImg.height)
                var newSize: CGSize? = nil
                
                switch resizeMode {
                case .original:
                    newSize = nil
                case .maxDimension:
                    let longest = max(origW, origH)
                    if longest > maxDimVal && maxDimVal > 10 {
                        let ratio = maxDimVal / longest
                        newSize = CGSize(width: round(origW * ratio), height: round(origH * ratio))
                    }
                case .percentage:
                    let ratio = max(1.0, min(scalePercentage, 200.0)) / 100.0
                    newSize = CGSize(width: max(1, round(origW * ratio)), height: max(1, round(origH * ratio)))
                }
                
                if let finalCG = ImageTransformService.transformCGImage(cgImg, targetSize: newSize) {
                    let baseName = item.url.deletingPathExtension().lastPathComponent
                    let outURL = destFolder.appendingPathComponent("\(baseName).\(targetExt)")
                    if ImageTransformService.writeCGImage(finalCG, to: outURL, utTypeString: targetUTType, jpegQuality: jpegQuality) {
                        successCount += 1
                    }
                }
            }
            progressValue = Double(idx + 1) / Double(total)
        }
        
        isProcessing = false
        statusIsSuccess = true
        statusMessage = "✅ แปลงไฟล์สำเร็จ \(successCount) รูป ไปยังโฟลเดอร์ '\(destFolder.lastPathComponent)'"
        store.reloadCurrentFolder()
    }
    
    // MARK: - Execute Batch Rotate & Flip
    
    func runBatchRotate(store: ImageStore) {
        let items = targetItems(from: store).filter { !$0.isVideo }
        guard !items.isEmpty, let baseFolder = store.currentFolderURL else {
            statusIsSuccess = false
            statusMessage = "ไม่มีไฟล์รูปภาพนิ่งสำหรับหมุนภาพ"
            return
        }
        
        let deg = rotationAngle.degreesCW
        if deg == 0 && !flipHorizontal && !flipVertical {
            statusIsSuccess = false
            statusMessage = "กรุณาเลือกมุมการหมุนหรือการพลิกภาพอย่างน้อย 1 อย่าง"
            return
        }
        
        isProcessing = true
        progressValue = 0
        statusMessage = "กำลังหมุนภาพและบันทึกลงไฟล์..."
        
        let fm = FileManager.default
        let rotatedFolder = baseFolder.appendingPathComponent("Rotated")
        if !overwriteOriginalOnRotate {
            try? fm.createDirectory(at: rotatedFolder, withIntermediateDirectories: true)
        }
        
        var successCount = 0
        let total = max(1, items.count)
        
        for (idx, item) in items.enumerated() {
            if let cgImg = ImageTransformService.loadOrientedCGImage(from: item.url),
               let rotatedCG = ImageTransformService.transformCGImage(
                   cgImg,
                   targetSize: nil,
                   clockwiseDegrees: deg,
                   flipHorizontal: flipHorizontal,
                   flipVertical: flipVertical
               ) {
                let outURL = overwriteOriginalOnRotate
                    ? item.url
                    : rotatedFolder.appendingPathComponent(item.name)
                let utType = ImageTransformService.utTypeForExtension(item.fileExtension)
                if ImageTransformService.writeCGImage(rotatedCG, to: outURL, utTypeString: utType, jpegQuality: 0.94) {
                    ThumbnailCache.shared.removeThumbnail(for: outURL)
                    successCount += 1
                }
            }
            progressValue = Double(idx + 1) / Double(total)
        }
        
        isProcessing = false
        statusIsSuccess = true
        if overwriteOriginalOnRotate {
            statusMessage = "✅ หมุนและบันทึกทับไฟล์เดิมสำเร็จ \(successCount) รูป!"
        } else {
            statusMessage = "✅ หมุนและบันทึกไปยังโฟลเดอร์ 'Rotated' สำเร็จ \(successCount) รูป!"
        }
        store.reloadCurrentFolder()
    }
}

// MARK: - Batch Tools Sheet UI

struct BatchToolsSheetView: View {
    @ObservedObject var store: ImageStore
    @StateObject private var vm = BatchToolsViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("จัดการรูปภาพเป็นชุด (ACDSee Batch Processor)")
                        .font(.system(size: 16, weight: .bold))
                    Text("เปลี่ยนชื่อไฟล์ แปลงนามสกุล/ย่อขนาด และหมุนภาพพร้อมกันหลายไฟล์")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("ปิดหน้าต่าง (Close)") {
                    store.showBatchSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Scope Selector & Tab Bar
            VStack(spacing: 12) {
                HStack {
                    Text("ขอบเขตไฟล์ (Target):")
                        .font(.system(size: 12.5, weight: .semibold))
                    Picker("", selection: $vm.scope) {
                        Text("ทุกรูปในโฟลเดอร์ปัจจุบัน (\(store.filteredImages.count) รูป)")
                            .tag(BatchScope.allInFolder)
                        Text("เฉพาะรูปที่เลือกไว้ (\(store.selectedItemsInOrder.count) รูป)")
                            .tag(BatchScope.selectedOnly)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 440)
                    Spacer()
                }
                
                Picker("", selection: $store.activeBatchTab) {
                    ForEach(BatchTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main Tab Content
            Group {
                switch store.activeBatchTab {
                case .rename:
                    batchRenameTabContent
                case .convert:
                    batchConvertTabContent
                case .rotate:
                    batchRotateTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer with Progress & Execute Button
            HStack(spacing: 14) {
                if vm.isProcessing {
                    ProgressView(value: vm.progressValue)
                        .frame(width: 180)
                }
                
                if !vm.statusMessage.isEmpty {
                    Text(vm.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(vm.statusIsSuccess ? .green : .orange)
                        .lineLimit(1)
                } else {
                    Text("จำนวนที่จะประมวลผล: \(vm.targetItems(from: store).count) ไฟล์")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    switch store.activeBatchTab {
                    case .rename:
                        vm.runBatchRename(store: store)
                    case .convert:
                        vm.runBatchConvert(store: store)
                    case .rotate:
                        vm.runBatchRotate(store: store)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(actionButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isProcessing || vm.targetItems(from: store).isEmpty)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 720, height: 540)
        .onAppear {
            if store.selectedIDs.count > 1 {
                vm.scope = .selectedOnly
            } else {
                vm.scope = .allInFolder
            }
        }
    }
    
    private var actionButtonTitle: String {
        switch store.activeBatchTab {
        case .rename: return "เริ่มเปลี่ยนชื่อไฟล์ (Rename Files)"
        case .convert: return "เริ่มแปลงไฟล์ (Convert Images)"
        case .rotate: return "เริ่มหมุนและบันทึกภาพ (Rotate & Save)"
        }
    }
    
    // MARK: - Tab 1: Rename UI
    
    private var batchRenameTabContent: some View {
        HStack(spacing: 0) {
            // Left Settings
            VStack(alignment: .leading, spacing: 14) {
                Text("รูปแบบการเปลี่ยนชื่อ (Rename Mode)")
                    .font(.system(size: 12.5, weight: .semibold))
                
                Picker("", selection: $vm.renameMode) {
                    ForEach(BatchRenameMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                
                Divider()
                
                switch vm.renameMode {
                case .template:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("เทมเพลตชื่อไฟล์ (ใช้ # แทนตำแหน่งตัวเลข):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("เช่น Photo_### หรือ Trip2026_###", text: $vm.renameTemplate)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Text("เลขเริ่มต้น:")
                                .font(.caption)
                            Stepper(value: $vm.startNumber, in: 0...99999) {
                                Text("\(vm.startNumber)")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                        
                        HStack {
                            Text("จำนวนหลักตัวเลข:")
                                .font(.caption)
                            Stepper(value: $vm.digitCount, in: 1...6) {
                                Text("\(vm.digitCount) หลัก")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                case .prefixSuffix:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("คำนำหน้า (Prefix):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("เช่น IMG_", text: $vm.prefixText)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("คำต่อท้าย (Suffix ก่อนนามสกุลไฟล์):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("เช่น _edited", text: $vm.suffixText)
                            .textFieldStyle(.roundedBorder)
                    }
                case .findReplace:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ค้นหาคำว่า (Find):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("คำที่ต้องการค้นหา", text: $vm.findText)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("แทนที่ด้วย (Replace with):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("คำใหม่ที่ต้องการแทนที่", text: $vm.replaceText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Spacer()
            }
            .padding(16)
            .frame(width: 290)
            
            Divider()
            
            // Right Live Preview List
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("ตัวอย่างชื่อไฟล์ใหม่ (Live Preview)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                let items = vm.targetItems(from: store)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            let previewName = ImageTransformService.previewNewFilename(
                                for: item,
                                index: idx,
                                mode: vm.renameMode,
                                template: vm.renameTemplate,
                                startNumber: vm.startNumber,
                                digitCount: vm.digitCount,
                                prefix: vm.prefixText,
                                suffix: vm.suffixText,
                                findText: vm.findText,
                                replaceText: vm.replaceText
                            )
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                                
                                Text(previewName)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 2: Convert & Resize UI
    
    private var batchConvertTabContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("1. ฟอร์แมตไฟล์ปลายทาง (Output Format)", systemImage: "doc.badge.gearshape")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        Picker("ชนิดไฟล์:", selection: $vm.outputFormat) {
                            ForEach(BatchOutputFormat.allCases) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .frame(width: 240)
                        
                        if vm.outputFormat == .jpeg || vm.outputFormat == .heic {
                            HStack(spacing: 8) {
                                Text("คุณภาพ (Quality):")
                                    .font(.caption)
                                Slider(value: $vm.jpegQuality, in: 0.1...1.0)
                                    .frame(width: 130)
                                Text("\(Int(round(vm.jpegQuality * 100)))%")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .frame(width: 42)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(8)
            }
            
            GroupBox(label: Label("2. ปรับขนาดรูปภาพ (Resize Options)", systemImage: "arrow.up.left.and.down.right.magnifyingglass")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("โหมดขนาดภาพ:", selection: $vm.resizeMode) {
                        ForEach(BatchResizeMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(width: 390)
                    
                    if vm.resizeMode == .maxDimension {
                        HStack(spacing: 10) {
                            Text("ด้านยาวสุดไม่เกิน (พิกเซล):")
                                .font(.caption)
                            TextField("1920", text: $vm.maxDimensionPx)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("px (รักษาสัดส่วนภาพอัตโนมัติ)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(["1080", "1920", "2560", "3840"], id: \.self) { preset in
                                Button("\(preset)px") {
                                    vm.maxDimensionPx = preset
                                }
                                .controlSize(.small)
                            }
                        }
                    } else if vm.resizeMode == .percentage {
                        HStack(spacing: 10) {
                            Text("ย่อเหลือ:")
                                .font(.caption)
                            Slider(value: $vm.scalePercentage, in: 10...100, step: 5)
                                .frame(width: 180)
                            Text("\(Int(vm.scalePercentage))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                }
                .padding(8)
            }
            
            GroupBox(label: Label("3. โฟลเดอร์จัดเก็บไฟล์ (Output Destination)", systemImage: "folder.badge.gearshape")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("สร้างโฟลเดอร์ย่อยในโฟลเดอร์ปัจจุบัน (แนะนำ เพื่อไม่ให้ปนกับไฟล์เดิม)", isOn: $vm.saveConvertInSubfolder)
                    
                    if vm.saveConvertInSubfolder {
                        HStack {
                            Text("ชื่อโฟลเดอร์ย่อย:")
                                .font(.caption)
                            TextField("Converted", text: $vm.convertSubfolderName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                    } else {
                        HStack {
                            Text("โฟลเดอร์ปลายทาง: \(vm.customOutputFolderURL?.path ?? store.currentFolderURL?.path ?? "-")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("เลือกโฟลเดอร์...") {
                                vm.chooseCustomOutputFolder()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(8)
            }
            
            Spacer()
        }
        .padding(18)
    }
    
    // MARK: - Tab 3: Rotate & Flip UI
    
    private var batchRotateTabContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("1. ทิศทางการหมุนภาพ (Rotation Angle)", systemImage: "rotate.right.fill")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("มุมการหมุน:", selection: $vm.rotationAngle) {
                        ForEach(BatchRotationAngle.allCases) { angle in
                            Text(angle.rawValue).tag(angle)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("2. การพลิกกลับด้าน (Flip / Mirror)", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")) {
                HStack(spacing: 24) {
                    Toggle("พลิกแนวนอน (Flip Horizontal - ซ้ายสลับขวา)", isOn: $vm.flipHorizontal)
                    Toggle("พลิกแนวตั้ง (Flip Vertical - บนสลับล่าง)", isOn: $vm.flipVertical)
                    Spacer()
                }
                .padding(8)
            }
            
            GroupBox(label: Label("3. การบันทึกไฟล์ (Save Mode)", systemImage: "externaldrive.fill.badge.checkmark")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("บันทึกทับไฟล์ต้นฉบับโดยตรง (Overwrite Original Files)", isOn: $vm.overwriteOriginalOnRotate)
                    Text(vm.overwriteOriginalOnRotate
                         ? "ไฟล์ภาพที่เลือกจะถูกหมุนและบันทึกทับไฟล์เดิมทันที"
                         : "ไฟล์ที่หมุนแล้วจะถูกแยกเก็บไว้ในโฟลเดอร์ย่อยชื่อ 'Rotated'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
        }
        .padding(18)
    }
}
