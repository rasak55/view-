import SwiftUI
import AppKit

@main
struct ImageVPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ImageStore()
    
    var body: some Scene {
        WindowGroup("IMAGEV+ (ACDSee Style Image Viewer)") {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.store = store
                    if let pendingURL = appDelegate.pendingOpenURL {
                        store.openURL(pendingURL)
                        appDelegate.pendingOpenURL = nil
                    }
                }
                .onOpenURL { url in
                    store.openURL(url)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("เปิดรูปภาพหรือโฟลเดอร์... (Open Image or Folder)") {
                    store.promptOpenFolderOrFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Divider()
                
                Button("แสดงใน Finder (Reveal in Finder)") {
                    store.revealInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Divider()
                
                Button("แก้ไขภาพด้วย macOS Preview (Edit in Preview)") {
                    store.editInMacOSPreview()
                }
                .keyboardShortcut("e", modifiers: [.command])
                
                Button("แก้ไขด้วยโปรแกรมอื่น... (Edit With...)") {
                    store.editWithChosenApplication()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            
            CommandMenu("การนำทาง (Navigate)") {
                Button("รูปก่อนหน้า (Previous Image)") {
                    store.selectPreviousImage()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("รูปถัดไป (Next Image)") {
                    store.selectNextImage()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                Divider()
                
                Button("รูปแรกสุด (First Image)") {
                    store.selectFirstImage()
                }
                .keyboardShortcut(.home, modifiers: [])
                
                Button("รูปสุดท้าย (Last Image)") {
                    store.selectLastImage()
                }
                .keyboardShortcut(.end, modifiers: [])
                
                Divider()
                
                Button("ขึ้นไปโฟลเดอร์แม่ (Up One Folder)") {
                    store.goUpOneFolder()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
            }
            
            CommandMenu("มุมมองและซูม (View & Zoom)") {
                Button("โหมดตาราง (Browse Mode)") {
                    store.viewMode = .browse
                }
                .keyboardShortcut("1", modifiers: [.command])
                
                Button("โหมดดูภาพ (View Mode)") {
                    store.viewMode = .view
                }
                .keyboardShortcut("2", modifiers: [.command])
                
                Button("โหมดคู่ขนาน (Split Mode)") {
                    store.viewMode = .split
                }
                .keyboardShortcut("3", modifiers: [.command])
                
                Divider()
                
                Button("ซูมเข้า (Zoom In)") {
                    store.zoomIn()
                }
                .keyboardShortcut("+", modifiers: [.command])
                
                Button("ซูมออก (Zoom Out)") {
                    store.zoomOut()
                }
                .keyboardShortcut("-", modifiers: [.command])
                
                Button("ขนาดพอดีหน้าจอ (Fit to Window)") {
                    store.zoomFitWindow()
                }
                .keyboardShortcut("9", modifiers: [.command])
                
                Button("ขนาดจริง 100% (Actual Size 1:1)") {
                    store.zoomActualSize()
                }
                .keyboardShortcut("0", modifiers: [.command])
                
                Divider()
                
                Button("หมุนซ้าย 90° (Rotate Left)") {
                    store.rotateLeft()
                }
                .keyboardShortcut("[", modifiers: [.command])
                
                Button("หมุนขวา 90° (Rotate Right)") {
                    store.rotateRight()
                }
                .keyboardShortcut("]", modifiers: [.command])
                
                Button("เล่น/หยุด สไลด์โชว์ (Slideshow)") {
                    store.toggleSlideshow()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            
            CommandMenu("จัดการเป็นชุด (Batch Tools)") {
                Button("เลือกทั้งหมดในโฟลเดอร์ (Select All Images)") {
                    store.selectAllImages()
                }
                .keyboardShortcut("a", modifiers: [.command])
                
                Divider()
                
                Button("เปลี่ยนชื่อไฟล์เป็นชุด... (Batch Rename)") {
                    store.openBatchTools(.rename)
                }
                .keyboardShortcut("b", modifiers: [.command])
                
                Button("แปลงไฟล์และย่อขนาดเป็นชุด... (Batch Convert & Resize)") {
                    store.openBatchTools(.convert)
                }
                .keyboardShortcut("k", modifiers: [.command])
                
                Button("หมุนและบันทึกภาพเป็นชุด... (Batch Rotate & Save)") {
                    store.openBatchTools(.rotate)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: ImageStore?
    var pendingOpenURL: URL?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        if let store = store {
            store.openURL(first)
        } else {
            pendingOpenURL = first
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
