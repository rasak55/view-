# IMAGEV+ — Fast ACDSee-Style Image & Video Viewer for macOS

**IMAGEV+** คือซอฟต์แวร์ดูและจัดการรูปภาพ/วิดีโอสำหรับ macOS พัฒนาด้วยภาษา **Swift (AppKit + SwiftUI + AVKit + ImageIO)** ออกแบบให้ทำงานรวดเร็วและคล่องตัวสไตล์ **ACDSee** โดยไม่มีข้อจำกัดด้านสิทธิ์ Sandbox (เปิดรูปเพียงไฟล์เดียวแล้วเลื่อนดูรูปอื่นในโฟลเดอร์เดียวกันได้ทันที)

---

## เอกสารประกอบโปรเจกต์ (Documentation)
1. [README.md](README.md) — ภาพรวมฟีเจอร์และการติดตั้งใช้งาน
2. [USER_GUIDE.md](USER_GUIDE.md) — คู่มือการใช้งานโหมดต่างๆ, Folder TreeView, การดูวิดีโอ และการแก้ไขภาพ
3. [SHORTCUTS.md](SHORTCUTS.md) — ตารางคีย์ลัดและท่าทาง Trackpad (2-Finger Scroll & Pinch-to-Zoom)
4. [BATCH_TOOLS.md](BATCH_TOOLS.md) — คู่มือระบบจัดการไฟล์เป็นชุด (Batch Rename, Convert & Resize, Rotate)
5. [ARCHITECTURE.md](ARCHITECTURE.md) — โครงสร้างซอร์สโค้ด สถาปัตยกรรมระบบ และขั้นตอนการ Build
6. [CHANGELOG.md](CHANGELOG.md) — ประวัติการพัฒนาและรายการอัปเดตฟีเจอร์

---

## จุดเด่นสำคัญ (Key Features)
- **ไม่ติดสิทธิ์ใดๆ (Zero-Sandbox Restriction)**: เปิดไฟล์จากที่ไหนก็ได้ โปรแกรมจะโหลดรูปภาพและวิดีโอทั้งหมดในโฟลเดอร์นั้นให้อัตโนมัติ พร้อมทำ Ad-hoc Code Signing และล้าง Quarantine เรียบร้อย
- **Folder TreeView สไตล์ Finder / ACDSee**: กาง/ย่อโครงสร้างโฟลเดอร์ได้หลายระดับชั้น คลิกเลือกโฟลเดอร์ไหนแสดงเนื้อหาในโฟลเดอร์นั้นทันทีโดยไม่ต้องกดย้อนกลับไปมา
- **3 โหมดการแสดงผล**:
  - **ตาราง (Browse Mode)**
  - **ดูภาพขนาดใหญ่ (View Mode)**
  - **คู่ขนาน (Split Mode — Preview Area ด้านบน + Thumbnail ด้านล่าง)**
- **การควบคุมด้วย Trackpad & เมาส์ที่ลื่นไหล**:
  - **ใช้ 2 นิ้วเลื่อนขึ้น-ลง บน Trackpad** เพื่อเปลี่ยนไปดูรูป/วิดีโอก่อนหน้าหรือถัดไป
  - **ถ่าง 2 นิ้ว (Pinch-to-Zoom)** หรือกด `Cmd / Option + เลื่อน 2 นิ้ว` เพื่อซูมเข้า-ออก (`5%` ถึง `1000%`)
  - **จัดภาพอยู่กึ่งกลาง Preview Area อัตโนมัติ** และ **ดับเบิ้ลคลิกที่ภาพเพื่อแสดงเต็มหน้าจอ (Full Screen)**
- **รองรับไฟล์วิดีโอครบวงจร**: เล่นไฟล์ `MP4`, `MOV`, `M4V`, `MKV`, `AVI`, `WEBM` พร้อมสร้างภาพปก Thumbnail อัตโนมัติ
- **เชื่อมต่อการแก้ไขภาพด้วย macOS Preview (`E` / `Cmd + E`)**: ส่งภาพไปวาดเขียน ครอป ปรับสี หรือไดคัทพื้นหลังใน `Preview.app` และรีเฟรชภาพกลับมาอัตโนมัติเมื่อบันทึก
- **ระบบจัดการไฟล์เป็นชุด (Batch Processor)**:
  - **Batch Rename (`Cmd + B`)**
  - **Batch Convert & Resize (`Cmd + K`)**
  - **Batch Rotate & Flip (`Cmd + Shift + T`)**

---

## การคอมไพล์และติดตั้ง (Build & Installation)
สามารถนำไฟล์ `IMAGEV+.app` ไปวางใน `/Applications` เพื่อใช้งานได้ทันที หรือคอมไพล์ใหม่จากซอร์สโค้ดด้วยคำสั่ง:

```zsh
chmod +x build.sh
./build.sh
open IMAGEV+.app
```
