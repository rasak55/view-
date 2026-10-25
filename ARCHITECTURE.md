# สถาปัตยกรรมซอฟต์แวร์และโครงสร้างโค้ด (Architecture)

เอกสารนี้อธิบายโครงสร้างภายในของโปรเจกต์ **IMAGEV+** และการออกแบบให้ทำงานได้รวดเร็วบน macOS โดยไม่ติดข้อจำกัดของ App Sandbox

---

## โครงสร้างไดเรกทอรี (Project Structure)

```text
IMAGEV+/
├── Sources/
│   ├── App.swift                # จุดเริ่มต้นของแอป (@main), AppDelegate และ Menu Bar Commands
│   ├── Models.swift             # โครงสร้างข้อมูลหลัก (ImageItem, ImageMetadata, FolderNode, Batch Enums)
│   ├── ImageStore.swift         # State Management กลาง, Folder Tree Cache, ThumbnailCache, EXIF & AVPlayer
│   ├── ZoomableImageView.swift  # พื้นที่แสดงภาพ/วิดีโอ, Auto-Centering, Pinch/Scroll Gestures และ NativeVideoPlayerView
│   ├── ViewerView.swift         # หน้าจอโหมดดูภาพ, ปุ่มเลื่อนซ้าย-ขวา, แถบควบคุมลอย (HUD) และ Filmstrip
│   ├── BrowserView.swift        # Folder TreeView ด้านซ้าย, ตาราง ThumbnailGridView และแผงข้อมูล InspectorPanelView
│   ├── ContentView.swift        # หน้าต่างหลัก, TopToolbarView, BottomStatusBarView และตัวดักจับคีย์ลัดระดับหน้าต่าง
│   └── BatchProcessor.swift     # เอ็นจินแปลงไฟล์/ย่อขนาด/หมุนภาพ/เปลี่ยนชื่อชุด และหน้าต่าง BatchToolsSheetView
├── SampleImages/                # รูปภาพตัวอย่างสำหรับทดสอบโปรแกรม
├── build.sh                     # สคริปต์สร้างไอคอน, คอมไพล์ไบนารี, สร้าง Info.plist และเซ็นชื่อแอป
├── IMAGEV+.app/                 # แพ็กเกจแอปพลิเคชัน macOS พร้อมใช้งาน
└── *.md                         # เอกสารประกอบโปรเจกต์ทั้ง 6 ไฟล์
```

---

## หลักการออกแบบทางเทคนิค (Technical Design)

1. **Zero-Sandbox & Unrestricted Folder Discovery**:
   - กำหนดค่า `Info.plist` โดยไม่เปิดใช้ `com.apple.security.app-sandbox` ทำให้เมื่อผู้ใช้เปิดไฟล์ภาพหรือวิดีโอเพียง 1 ไฟล์ผ่าน Finder (`Open With`) ตัวแอปสามารถเข้าถึงโฟลเดอร์แม่ (`url.deletingLastPathComponent()`) เพื่อโหลดรายการภาพและวิดีโอทั้งหมดในโฟลเดอร์เดียวกันได้ทันทีเหมือน ACDSee บน Windows
   - สคริปต์ `build.sh` ทำการเซ็นชื่อแบบ Ad-hoc (`codesign --force --deep --sign -`) และล้าง Extended Attributes (`xattr -cr`) เพื่อให้เปิดใช้งานได้ทันทีโดยไม่ติดการบล็อกจาก Gatekeeper

2. **High-Speed Asynchronous Thumbnail Pipeline (`ThumbnailCache`)**:
   - สำหรับไฟล์ภาพนิ่ง: ใช้ `CGImageSourceCreateThumbnailAtIndex` จากเฟรมเวิร์ก `ImageIO` ที่ถอดรหัสเฉพาะระดับขนาดย่อ (Downsampled Decode) แทนการโหลดภาพความละเอียดเต็มเข้าหน่วยความจำ
   - สำหรับไฟล์วิดีโอ: ใช้ `AVAssetImageGenerator` ดึงภาพ Poster Frame พร้อมคำนวณ `appliesPreferredTrackTransform`
   - เก็บผลลัพธ์ลงใน `NSCache<NSURL, NSImage>` บนคิวแบบ Concurrent (`DispatchQueue.qos = .userInitiated`)

3. **Auto-Centered Zoom & Pan Engine (`ZoomableImageView`)**:
   - คำนวณขนาดแสดงผลจริง (`displayWidth × displayHeight`) และล็อกจุดศูนย์กลางด้วย `.position(x: viewSize.width / 2 + effectivePan.width, y: viewSize.height / 2 + effectivePan.height)`
   - มีฟังก์ชัน `clampedPanOffset` คอยดึงภาพกลับมาจุดกึ่งกลางอัตโนมัติเมื่อภาพมีขนาดเล็กกว่าพื้นที่ Preview Area
   - ใช้ `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` แยกแยะระหว่างการเลื่อน 2 นิ้วขึ้น-ลงเพื่อเปลี่ยนภาพ กับการกด `Cmd/Option + เลื่อน 2 นิ้ว` เพื่อซูมภาพ พร้อมตัดแรงเฉื่อย (`event.momentumPhase`) ไม่ให้ภาพไหลข้ามหลายรูป
