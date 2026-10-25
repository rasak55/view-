import SwiftUI

struct ViewerView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Main Zoomable & Pannable Image Canvas
                ZoomableImageView(store: store)
                
                // Left / Right On-Screen Navigation Buttons (ACDSee style)
                if store.filteredImages.count > 1 {
                    HStack {
                        Button(action: { store.selectPreviousImage() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 72)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.black.opacity(0.45))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 14)
                        .help("รูปก่อนหน้า (ลูกศรซ้าย ←)")
                        
                        Spacer()
                        
                        Button(action: { store.selectNextImage() }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 72)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.black.opacity(0.45))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .help("รูปถัดไป (ลูกศรขวา →)")
                    }
                }
                
                // Floating HUD Control Bar at Bottom of Canvas
                VStack {
                    // Top Quick Info Pill
                    if let item = store.selectedImage {
                        HStack(spacing: 12) {
                            if store.isFullScreenPresentation {
                                Button(action: { store.exitFullScreenPresentation() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        Text("ออกจากเต็มจอ (Esc / ดับเบิ้ลคลิก)")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.accentColor))
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .help("ออกจากโหมดเต็มหน้าจอ (กด Esc หรือดับเบิ้ลคลิก)")
                            } else {
                                Button(action: { store.viewMode = .browse }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.grid.2x2.fill")
                                        Text("โหมดตาราง (Browse)")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.accentColor))
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .help("กลับไปหน้าตารางรวมรูป (Esc หรือ Enter)")
                            }
                            
                            if item.isVideo {
                                HStack(spacing: 4) {
                                    Image(systemName: "film.fill")
                                    Text("VIDEO")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.85)))
                                .foregroundColor(.white)
                            }
                            
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text("•")
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text(store.currentMetadata.resolutionText)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                            
                            Text("•")
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text(store.positionText)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                                .foregroundColor(.white)
                            
                            if item.isVideo {
                                Button(action: { store.toggleFullScreenPresentation() }) {
                                    Image(systemName: store.isFullScreenPresentation ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(5)
                                        .background(Circle().fill(Color.white.opacity(0.2)))
                                }
                                .buttonStyle(.plain)
                                .help("ขยายเต็มหน้าจอ / ออกจากเต็มหน้าจอ (F)")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.62))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        )
                        .padding(.top, 10)
                    }
                    
                    Spacer()
                    
                    // Bottom Floating Zoom & Action Bar (shown for still images; videos use native AVPlayerView controls)
                    if store.selectedImage?.isVideo != true {
                    HStack(spacing: 10) {
                        // Previous / Next
                        HStack(spacing: 4) {
                            hudButton(icon: "backward.end.fill", tooltip: "รูปแรก (Home)") {
                                store.selectFirstImage()
                            }
                            hudButton(icon: "arrow.left", tooltip: "รูปก่อนหน้า (←)") {
                                store.selectPreviousImage()
                            }
                            hudButton(icon: "arrow.right", tooltip: "รูปถัดไป (→)") {
                                store.selectNextImage()
                            }
                            hudButton(icon: "forward.end.fill", tooltip: "รูปสุดท้าย (End)") {
                                store.selectLastImage()
                            }
                        }
                        
                        Divider().frame(height: 18).background(Color.white.opacity(0.25))
                        
                        // Zoom Controls
                        HStack(spacing: 6) {
                            hudButton(icon: "minus.magnifyingglass", tooltip: "ซูมออก (-)") {
                                store.zoomOut()
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { Double(store.zoomScale) },
                                    set: { newVal in
                                        store.isFitToWindow = false
                                        store.zoomScale = CGFloat(newVal)
                                    }
                                ),
                                in: 0.1...5.0
                            )
                            .frame(width: 110)
                            .tint(.accentColor)
                            
                            hudButton(icon: "plus.magnifyingglass", tooltip: "ซูมเข้า (+)") {
                                store.zoomIn()
                            }
                            
                            Text("\(Int(round(store.zoomScale * 100)))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 48, alignment: .trailing)
                            
                            Button(action: { store.zoomFitWindow() }) {
                                Text("Fit")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(store.isFitToWindow ? Color.accentColor : Color.white.opacity(0.16))
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .help("พอดีหน้าจอ (กด 0 หรือดับเบิ้ลคลิก)")
                            
                            Button(action: { store.zoomActualSize() }) {
                                Text("1:1 (100%)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(!store.isFitToWindow && abs(store.zoomScale - 1.0) < 0.01 ? Color.accentColor : Color.white.opacity(0.16))
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .help("ขนาดจริง 100% (กด 1 หรือดับเบิ้ลคลิก)")
                        }
                        
                        Divider().frame(height: 18).background(Color.white.opacity(0.25))
                        
                        // Rotate & Flip
                        HStack(spacing: 4) {
                            hudButton(icon: "rotate.left", tooltip: "หมุนซ้าย (L)") {
                                store.rotateLeft()
                            }
                            hudButton(icon: "rotate.right", tooltip: "หมุนขวา (R)") {
                                store.rotateRight()
                            }
                            hudButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", tooltip: "พลิกแนวนอน (H)") {
                                store.toggleFlipHorizontal()
                            }
                            hudButton(icon: "pencil.tip.crop.circle", tooltip: "แก้ไขภาพด้วย macOS Preview (E หรือ Cmd+E)") {
                                store.editInMacOSPreview()
                            }
                        }
                        
                        Divider().frame(height: 18).background(Color.white.opacity(0.25))
                        
                        // Slideshow, Filmstrip & Fullscreen Toggle
                        HStack(spacing: 4) {
                            hudButton(
                                icon: store.isSlideshowRunning ? "pause.fill" : "play.fill",
                                tooltip: "สไลด์โชว์ (S)",
                                isActive: store.isSlideshowRunning
                            ) {
                                store.toggleSlideshow()
                            }
                            
                            if store.viewMode == .view && !store.isFullScreenPresentation {
                                hudButton(
                                    icon: "film",
                                    tooltip: "แสดง/ซ่อนแถบรูปด้านล่าง (Filmstrip)",
                                    isActive: store.showFilmstrip
                                ) {
                                    store.showFilmstrip.toggle()
                                }
                            }
                            
                            hudButton(
                                icon: store.isFullScreenPresentation ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                tooltip: "แสดงเต็มหน้าจอ / ออกจากเต็มจอ (ดับเบิ้ลคลิก หรือ F)",
                                isActive: store.isFullScreenPresentation
                            ) {
                                store.toggleFullScreenPresentation()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.70))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .padding(.bottom, 12)
                    }
                }
            }
            
            // Optional ACDSee Filmstrip at Bottom (only in View mode, not Split mode)
            if store.viewMode == .view && !store.isFullScreenPresentation && store.showFilmstrip && !store.filteredImages.isEmpty {
                Divider()
                FilmstripBarView(store: store)
            }
        }
    }
    
    @ViewBuilder
    private func hudButton(icon: String, tooltip: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

struct FilmstripBarView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 8) {
                    ForEach(store.filteredImages) { item in
                        let isSelected = (store.selectedImage == item)
                        VStack(spacing: 2) {
                            ThumbnailImageView(url: item.url, size: 76)
                            Text(item.name)
                                .font(.system(size: 9.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 76)
                                .foregroundColor(isSelected ? .white : .secondary)
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        .id(item.id)
                        .onTapGesture {
                            store.selectedImage = item
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: 96)
            .background(Color(white: 0.11))
            .onAppear {
                if let id = store.selectedImage?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: store.selectedImage) { _, newItem in
                if let id = newItem?.id {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}
