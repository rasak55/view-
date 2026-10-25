import SwiftUI
import AppKit
import AVKit
import AVFoundation

struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = true
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct ZoomableImageView: View {
    @ObservedObject var store: ImageStore
    
    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let fitScale: CGFloat = {
                guard let nsImage = store.currentNSImage else { return 1.0 }
                return calculateFitScale(imageSize: effectiveImageSize(for: nsImage), in: viewSize)
            }()
            
            ZStack {
                Color(white: store.viewerBackgroundBrightness)
                    .ignoresSafeArea()
                
                if let item = store.selectedImage, item.isVideo {
                    NativeVideoPlayerView(player: store.currentAVPlayer)
                        .frame(width: viewSize.width, height: viewSize.height)
                        .position(x: viewSize.width / 2.0, y: viewSize.height / 2.0)
                } else if let nsImage = store.currentNSImage {
                    let imgPixelSize = effectiveImageSize(for: nsImage)
                    let activeScale = max(0.01, (store.isFitToWindow ? fitScale : store.zoomScale) * store.gestureZoom)
                    let displayWidth = max(1, imgPixelSize.width * activeScale)
                    let displayHeight = max(1, imgPixelSize.height * activeScale)
                    let isRotated90 = (store.rotationDegrees % 180) != 0
                    let visualSize = CGSize(
                        width: isRotated90 ? displayHeight : displayWidth,
                        height: isRotated90 ? displayWidth : displayHeight
                    )
                    let effectivePan = clampedPanOffset(store.panOffset, visualSize: visualSize, in: viewSize)
                    
                    Image(nsImage: nsImage)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displayWidth, height: displayHeight)
                        .scaleEffect(
                            x: store.isFlippedHorizontally ? -1 : 1,
                            y: store.isFlippedVertically ? -1 : 1
                        )
                        .rotationEffect(.degrees(Double(store.rotationDegrees)))
                        .position(
                            x: (viewSize.width / 2.0) + effectivePan.width,
                            y: (viewSize.height / 2.0) + effectivePan.height
                        )
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    guard !store.isFitToWindow else { return }
                                    let proposed = CGSize(
                                        width: store.lastPanOffset.width + value.translation.width,
                                        height: store.lastPanOffset.height + value.translation.height
                                    )
                                    store.panOffset = clampedPanOffset(proposed, visualSize: visualSize, in: viewSize)
                                }
                                .onEnded { _ in
                                    store.lastPanOffset = store.panOffset
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    if store.isFitToWindow {
                                        store.zoomScale = fitScale
                                        store.isFitToWindow = false
                                    }
                                    store.gestureZoom = value
                                }
                                .onEnded { value in
                                    let finalScale = min(max(store.zoomScale * value, 0.05), 10.0)
                                    store.zoomScale = finalScale
                                    store.gestureZoom = 1.0
                                    let finalVisual = CGSize(
                                        width: (isRotated90 ? imgPixelSize.height : imgPixelSize.width) * finalScale,
                                        height: (isRotated90 ? imgPixelSize.width : imgPixelSize.height) * finalScale
                                    )
                                    store.panOffset = clampedPanOffset(store.panOffset, visualSize: finalVisual, in: viewSize)
                                    store.lastPanOffset = store.panOffset
                                }
                        )
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 54, weight: .thin))
                            .foregroundColor(.secondary)
                        Text("ไม่มีรูปภาพที่เลือก (No Image Selected)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Button("เปิดรูปภาพหรือโฟลเดอร์ (Open Image / Folder)") {
                            store.promptOpenFolderOrFile()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .position(x: viewSize.width / 2.0, y: viewSize.height / 2.0)
                }
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        store.toggleFullScreenPresentation()
                    }
                    .exclusively(
                        before: TapGesture(count: 1)
                            .onEnded {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    store.showViewerControls.toggle()
                                }
                            }
                    )
            )
            .background(
                ScrollWheelCaptureView(
                    onNavigate: { direction in
                        if direction > 0 {
                            store.selectNextImage()
                        } else {
                            store.selectPreviousImage()
                        }
                    },
                    onZoom: { deltaY in
                        handleScrollZoom(deltaY: deltaY, fitScale: fitScale, in: viewSize)
                    }
                )
            )
            .clipped()
            .onAppear {
                store.containerSize = viewSize
                syncFitScaleIfNeeded(in: viewSize)
            }
            .onChange(of: viewSize) { _, newSize in
                store.containerSize = newSize
                syncFitScaleIfNeeded(in: newSize)
            }
            .onChange(of: store.selectedImage) { _, _ in
                store.panOffset = .zero
                store.lastPanOffset = .zero
                store.gestureZoom = 1.0
                store.isFitToWindow = true
                syncFitScaleIfNeeded(in: store.containerSize)
            }
            .onChange(of: store.isFitToWindow) { _, isFit in
                if isFit {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.panOffset = .zero
                        store.lastPanOffset = .zero
                        syncFitScaleIfNeeded(in: store.containerSize)
                    }
                }
            }
            .onChange(of: store.rotationDegrees) { _, _ in
                store.panOffset = .zero
                store.lastPanOffset = .zero
                syncFitScaleIfNeeded(in: store.containerSize)
            }
        }
    }
    
    /// Ensures the image is always centered when smaller than the preview area, and clamped to edges when zoomed in
    private func clampedPanOffset(_ offset: CGSize, visualSize: CGSize, in viewSize: CGSize) -> CGSize {
        if store.isFitToWindow {
            return .zero
        }
        let maxOffsetX = max(0, (visualSize.width - viewSize.width) / 2.0)
        let maxOffsetY = max(0, (visualSize.height - viewSize.height) / 2.0)
        
        let clampedX = min(max(offset.width, -maxOffsetX), maxOffsetX)
        let clampedY = min(max(offset.height, -maxOffsetY), maxOffsetY)
        return CGSize(width: clampedX, height: clampedY)
    }
    
    private func effectiveImageSize(for image: NSImage) -> CGSize {
        var w: CGFloat = 0
        var h: CGFloat = 0
        if store.currentMetadata.pixelWidth > 0 && store.currentMetadata.pixelHeight > 0 {
            w = CGFloat(store.currentMetadata.pixelWidth)
            h = CGFloat(store.currentMetadata.pixelHeight)
        } else if let rep = image.representations.first, rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            w = CGFloat(rep.pixelsWide)
            h = CGFloat(rep.pixelsHigh)
        } else {
            return image.size
        }
        
        // Match visual orientation of NSImage (which automatically applies EXIF orientation)
        let imgSize = image.size
        if imgSize.width > 0 && imgSize.height > 0 {
            let isVisualPortrait = imgSize.height > imgSize.width
            let isPixelPortrait = h > w
            if isVisualPortrait != isPixelPortrait && w != h {
                swap(&w, &h)
            }
        }
        return CGSize(width: w, height: h)
    }
    
    private func calculateFitScale(imageSize: CGSize, in viewSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 20, viewSize.height > 20 else {
            return 1.0
        }
        let isRotated90 = (store.rotationDegrees % 180) != 0
        let imgW = isRotated90 ? imageSize.height : imageSize.width
        let imgH = isRotated90 ? imageSize.width : imageSize.height
        
        let padding: CGFloat = store.isFullScreenPresentation ? 0 : 16
        let availW = max(20, viewSize.width - padding)
        let availH = max(20, viewSize.height - padding)
        let scale = min(availW / imgW, availH / imgH)
        return scale
    }
    
    private func syncFitScaleIfNeeded(in viewSize: CGSize) {
        guard store.isFitToWindow, let img = store.currentNSImage else { return }
        let size = effectiveImageSize(for: img)
        store.zoomScale = calculateFitScale(imageSize: size, in: viewSize)
        store.panOffset = .zero
        store.lastPanOffset = .zero
    }
    
    private func handleScrollZoom(deltaY: CGFloat, fitScale: CGFloat, in viewSize: CGSize) {
        guard abs(deltaY) > 0.01 else { return }
        if store.isFitToWindow {
            store.zoomScale = fitScale
            store.isFitToWindow = false
        }
        let sensitivity: CGFloat = 0.03
        let factor = 1.0 + (deltaY * sensitivity)
        let clampedFactor = min(max(factor, 0.80), 1.25)
        let nextScale = min(max(store.zoomScale * clampedFactor, 0.05), 10.0)
        store.zoomScale = nextScale
        
        if let img = store.currentNSImage {
            let imgSize = effectiveImageSize(for: img)
            let isRotated90 = (store.rotationDegrees % 180) != 0
            let visualSize = CGSize(
                width: (isRotated90 ? imgSize.height : imgSize.width) * nextScale,
                height: (isRotated90 ? imgSize.width : imgSize.height) * nextScale
            )
            store.panOffset = clampedPanOffset(store.panOffset, visualSize: visualSize, in: viewSize)
            store.lastPanOffset = store.panOffset
        }
    }
}

struct ScrollWheelCaptureView: NSViewRepresentable {
    /// direction: +1 = Next Image, -1 = Previous Image
    var onNavigate: (Int) -> Void
    var onZoom: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onNavigate = onNavigate
        view.onZoom = onZoom
        return view
    }
    
    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onNavigate = onNavigate
        nsView.onZoom = onZoom
    }
    
    final class ScrollWheelNSView: NSView {
        var onNavigate: ((Int) -> Void)?
        var onZoom: ((CGFloat) -> Void)?
        private var monitor: Any?
        private var accumulatedDeltaY: CGFloat = 0
        private var lastSwitchTimestamp: TimeInterval = 0
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self = self,
                          let window = self.window,
                          event.window == window else {
                        return event
                    }
                    let pointInView = self.convert(event.locationInWindow, from: nil)
                    guard self.bounds.contains(pointInView) else {
                        return event
                    }
                    
                    let isMod = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
                    if isMod {
                        // Cmd / Option + 2-finger scroll => Zoom in/out
                        self.onZoom?(event.scrollingDeltaY)
                        return nil
                    }
                    
                    // Ignore inertial coasting after lifting fingers so it doesn't keep flipping images
                    if event.momentumPhase != [] {
                        return nil
                    }
                    
                    if event.phase == .began {
                        self.accumulatedDeltaY = 0
                    }
                    
                    let now = ProcessInfo.processInfo.systemUptime
                    let deltaY = event.scrollingDeltaY
                    
                    if event.hasPreciseScrollingDeltas {
                        // 2-Finger Trackpad Scroll Up/Down
                        self.accumulatedDeltaY += deltaY
                        let threshold: CGFloat = 30.0
                        let cooldown: TimeInterval = 0.20
                        
                        if abs(self.accumulatedDeltaY) >= threshold && (now - self.lastSwitchTimestamp) >= cooldown {
                            if self.accumulatedDeltaY < 0 {
                                // Scroll down / swipe up => Next image
                                self.onNavigate?(1)
                            } else {
                                // Scroll up / swipe down => Previous image
                                self.onNavigate?(-1)
                            }
                            self.accumulatedDeltaY = 0
                            self.lastSwitchTimestamp = now
                        }
                    } else {
                        // Discrete Mouse Scroll Wheel
                        let cooldown: TimeInterval = 0.14
                        if abs(deltaY) > 0.05 && (now - self.lastSwitchTimestamp) >= cooldown {
                            if deltaY < 0 {
                                self.onNavigate?(1)
                            } else {
                                self.onNavigate?(-1)
                            }
                            self.lastSwitchTimestamp = now
                        }
                    }
                    
                    if event.phase == .ended || event.phase == .cancelled {
                        self.accumulatedDeltaY = 0
                    }
                    
                    return nil
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
