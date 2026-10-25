import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AppViewMode: String, CaseIterable {
    case browse = "Browse"
    case view = "View"
    case split = "Split"
}

enum SortField: String, CaseIterable, Identifiable {
    case name = "ชื่อไฟล์ (Name)"
    case dateModified = "วันที่แก้ไข (Date)"
    case size = "ขนาดไฟล์ (Size)"
    case type = "ชนิดไฟล์ (Type)"
    
    var id: String { rawValue }
}

enum ZoomMode: Equatable {
    case fitWindow
    case actualSize
    case custom(CGFloat)
}

struct ImageMetadata {
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var dpiWidth: Int?
    var colorModel: String?
    var depth: Int?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var fNumber: String?
    var exposureTime: String?
    var iso: String?
    var focalLength: String?
    var dateTimeOriginal: String?
    var videoDuration: String?
    var videoFrameRate: String?
    
    var resolutionText: String {
        guard pixelWidth > 0 && pixelHeight > 0 else { return "-" }
        if let dur = videoDuration {
            return "\(pixelWidth) × \(pixelHeight) px • \(dur)"
        }
        let mp = Double(pixelWidth * pixelHeight) / 1_000_000.0
        return String(format: "%d × %d px (%.1f MP)", pixelWidth, pixelHeight, mp)
    }
}

struct ImageItem: Identifiable, Equatable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let fileExtension: String
    let fileSize: Int64
    let modificationDate: Date
    
    var isVideo: Bool {
        Self.isVideo(url: url)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
    
    static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif",
        "tif", "tiff", "bmp", "ico", "icns", "jp2", "svg",
        "raw", "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "pef", "raf"
    ]
    
    static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "mpg", "mpeg", "3gp", "ts", "mts", "m2ts"
    ]
    
    static var supportedExtensions: Set<String> {
        supportedImageExtensions.union(supportedVideoExtensions)
    }
    
    static func isVideo(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedVideoExtensions.contains(ext) {
            return true
        }
        if let type = UTType(filenameExtension: ext),
           (type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)) {
            return true
        }
        return false
    }
    
    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedImageExtensions.contains(ext) || supportedVideoExtensions.contains(ext) {
            return true
        }
        if let type = UTType(filenameExtension: ext),
           (type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .video)) {
            return true
        }
        return false
    }
}

struct FolderNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let iconName: String
}

enum BatchTab: String, CaseIterable, Identifiable {
    case rename = "เปลี่ยนชื่อชุด (Batch Rename)"
    case convert = "แปลงไฟล์/ย่อขนาด (Convert & Resize)"
    case rotate = "หมุน/พลิกภาพ (Batch Rotate)"
    
    var id: String { rawValue }
}

enum BatchScope: String, CaseIterable, Identifiable {
    case selectedOnly = "เฉพาะรูปที่เลือก (Selected Images)"
    case allInFolder = "ทุกรูปในโฟลเดอร์ปัจจุบัน (All in Folder)"
    
    var id: String { rawValue }
}

enum BatchRenameMode: String, CaseIterable, Identifiable {
    case template = "ตั้งชื่อใหม่ + รันตัวเลข (Template + Number)"
    case prefixSuffix = "เติมคำนำหน้า / ต่อท้าย (Prefix & Suffix)"
    case findReplace = "ค้นหาและแทนที่คำ (Find & Replace)"
    
    var id: String { rawValue }
}

enum BatchOutputFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG (.jpg)"
    case png = "PNG (.png)"
    case heic = "HEIC (.heic)"
    case tiff = "TIFF (.tiff)"
    case bmp = "BMP (.bmp)"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .bmp: return "bmp"
        }
    }
    
    var utTypeString: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .heic: return UTType.heic.identifier
        case .tiff: return UTType.tiff.identifier
        case .bmp: return UTType.bmp.identifier
        }
    }
}

enum BatchResizeMode: String, CaseIterable, Identifiable {
    case original = "ขนาดเท่าเดิม (Keep Original Size)"
    case maxDimension = "กำหนดด้านยาวสุดไม่เกิน (Max Dimension px)"
    case percentage = "ย่อตามเปอร์เซ็นต์ (Percentage %)"
    
    var id: String { rawValue }
}

enum BatchRotationAngle: String, CaseIterable, Identifiable {
    case rotate90CW = "หมุนขวา 90° ตามเข็มนาฬิกา (90° CW)"
    case rotate90CCW = "หมุนซ้าย 90° ทวนเข็มนาฬิกา (90° CCW)"
    case rotate180 = "หมุนกลับหัว 180° (180°)"
    case none = "ไม่หมุน (ใช้เฉพาะพลิกภาพ Flip)"
    
    var id: String { rawValue }
    
    var degreesCW: Int {
        switch self {
        case .rotate90CW: return 90
        case .rotate90CCW: return 270
        case .rotate180: return 180
        case .none: return 0
        }
    }
}
