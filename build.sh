#!/bin/zsh
set -e

APP_NAME="IMAGEV+"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Creating app bundle structure..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "🎨 Generating Pro AppIcon.icns..."
ICONSET_DIR="/tmp/ImageVPlus.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

cat << 'EOF' > /tmp/generate_icon.swift
import AppKit
import CoreGraphics

func drawProIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let cgSize = CGSize(width: s, height: s)
    let image = NSImage(size: cgSize)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    let space = CGColorSpaceCreateDeviceRGB()
    
    // 1. macOS Squircle Base with Drop Shadow
    let inset = s * 0.055
    let squircleRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = squircleRect.width * 0.225
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.04, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip inside Squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // Background Rich Studio Gradient
    let bgColors = [
        CGColor(red: 0.14, green: 0.17, blue: 0.29, alpha: 1.0),
        CGColor(red: 0.06, green: 0.08, blue: 0.15, alpha: 1.0),
        CGColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 1.0)
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: space, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: s * 0.2, y: s * 0.95), end: CGPoint(x: s * 0.8, y: s * 0.05), options: [])
    }
    
    // Subtle ambient glow in top-left & bottom-right
    if let glowGrad = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.0, green: 0.72, blue: 1.0, alpha: 0.28),
        CGColor(red: 0.0, green: 0.72, blue: 1.0, alpha: 0.0)
    ] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGrad, startCenter: CGPoint(x: s * 0.22, y: s * 0.78), startRadius: 0, endCenter: CGPoint(x: s * 0.22, y: s * 0.78), endRadius: s * 0.55, options: [])
    }
    if let warmGlow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1.0, green: 0.42, blue: 0.15, alpha: 0.26),
        CGColor(red: 1.0, green: 0.42, blue: 0.15, alpha: 0.0)
    ] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(warmGlow, startCenter: CGPoint(x: s * 0.78, y: s * 0.22), startRadius: 0, endCenter: CGPoint(x: s * 0.78, y: s * 0.22), endRadius: s * 0.55, options: [])
    }
    
    let center = CGPoint(x: s * 0.5, y: s * 0.51)
    
    // 2. Tilted Polaroid / Photo Frame cards behind the lens
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -0.16)
    let cardRect = CGRect(x: -s * 0.29, y: -s * 0.24, width: s * 0.58, height: s * 0.48)
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.addPath(cardPath)
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(s * 0.008)
    ctx.addPath(cardPath)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 3. Outer Metallic Camera Lens Barrel
    let outerRadius = s * 0.34
    let outerRingRect = CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.035, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    ctx.fillEllipse(in: outerRingRect)
    ctx.restoreGState()
    
    ctx.saveGState()
    ctx.addEllipse(in: outerRingRect)
    ctx.clip()
    if let barrelGrad = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.32, green: 0.37, blue: 0.48, alpha: 1.0),
        CGColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1.0)
    ] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(barrelGrad, start: CGPoint(x: center.x - outerRadius, y: center.y + outerRadius), end: CGPoint(x: center.x + outerRadius, y: center.y - outerRadius), options: [])
    }
    ctx.restoreGState()
    
    // 4. Colorful Aperture Iris Ring (ACDSee / Pro Photography Vibe)
    let irisRadius = s * 0.295
    let bladeColors: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.38, 0.18), // Sunset Orange
        (1.00, 0.72, 0.12), // Golden Yellow
        (0.18, 0.82, 0.52), // Emerald Green
        (0.08, 0.72, 0.96), // Cyan Blue
        (0.38, 0.36, 0.96), // Indigo Violet
        (0.92, 0.24, 0.62)  // Magenta Pink
    ]
    
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - irisRadius, y: center.y - irisRadius, width: irisRadius * 2, height: irisRadius * 2))
    ctx.clip()
    
    for i in 0..<6 {
        let startAngle = CGFloat(i) * (.pi / 3.0)
        let endAngle = startAngle + (.pi / 3.0) + 0.06
        let c = bladeColors[i]
        let path = CGMutablePath()
        path.move(to: center)
        path.addArc(center: center, radius: irisRadius * 1.05, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.92))
        ctx.fillPath()
        
        // Blade separator line
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.65))
        ctx.setLineWidth(s * 0.01)
        ctx.addPath(path)
        ctx.strokePath()
    }
    ctx.restoreGState()
    
    // 5. Inner Core Glass Lens with Scenic Mountain & Sun
    let glassRadius = s * 0.215
    let glassRect = CGRect(x: center.x - glassRadius, y: center.y - glassRadius, width: glassRadius * 2, height: glassRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: glassRect)
    ctx.clip()
    
    // Sky inside lens
    if let skyGrad = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.06, green: 0.14, blue: 0.34, alpha: 1.0),
        CGColor(red: 0.14, green: 0.45, blue: 0.78, alpha: 1.0),
        CGColor(red: 0.96, green: 0.56, blue: 0.32, alpha: 1.0)
    ] as CFArray, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(skyGrad, start: CGPoint(x: center.x, y: center.y + glassRadius), end: CGPoint(x: center.x, y: center.y - glassRadius), options: [])
    }
    
    // Golden Sun inside lens
    let sunRadius = s * 0.052
    let sunCenter = CGPoint(x: center.x - s * 0.055, y: center.y + s * 0.055)
    ctx.setFillColor(CGColor(red: 1.0, green: 0.88, blue: 0.35, alpha: 0.96))
    ctx.fillEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))
    
    // Mountain silhouettes inside lens
    let mtn1 = CGMutablePath()
    mtn1.move(to: CGPoint(x: center.x - glassRadius, y: center.y - glassRadius))
    mtn1.addLine(to: CGPoint(x: center.x - s * 0.06, y: center.y - s * 0.01))
    mtn1.addLine(to: CGPoint(x: center.x + s * 0.08, y: center.y - glassRadius))
    mtn1.closeSubpath()
    ctx.setFillColor(CGColor(red: 0.08, green: 0.16, blue: 0.32, alpha: 0.95))
    ctx.addPath(mtn1)
    ctx.fillPath()
    
    let mtn2 = CGMutablePath()
    mtn2.move(to: CGPoint(x: center.x - s * 0.08, y: center.y - glassRadius))
    mtn2.addLine(to: CGPoint(x: center.x + s * 0.065, y: center.y + s * 0.03))
    mtn2.addLine(to: CGPoint(x: center.x + glassRadius * 1.1, y: center.y - glassRadius))
    mtn2.closeSubpath()
    ctx.setFillColor(CGColor(red: 0.04, green: 0.09, blue: 0.22, alpha: 0.98))
    ctx.addPath(mtn2)
    ctx.fillPath()
    
    // Glossy Specular Highlight on Lens
    let glossPath = CGMutablePath()
    glossPath.addEllipse(in: CGRect(x: center.x - glassRadius * 0.85, y: center.y + glassRadius * 0.05, width: glassRadius * 1.7, height: glassRadius * 1.1))
    ctx.addPath(glossPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.fillPath()
    
    ctx.restoreGState()
    
    // Inner Lens Rim Highlight
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.65))
    ctx.setLineWidth(s * 0.012)
    ctx.strokeEllipse(in: glassRect)
    
    // 6. "V+" Pro Badge in Bottom-Right
    let badgeW = s * 0.28
    let badgeH = s * 0.16
    let badgeRect = CGRect(x: s * 0.61, y: s * 0.11, width: badgeW, height: badgeH)
    let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: badgeH * 0.42, cornerHeight: badgeH * 0.42, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    ctx.addPath(badgePath)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.52, blue: 0.98, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()
    
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.setLineWidth(s * 0.008)
    ctx.addPath(badgePath)
    ctx.strokePath()
    
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let font = NSFont.systemFont(ofSize: s * 0.095, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: para
    ]
    let badgeStr = "V+" as NSString
    let textSize = badgeStr.size(withAttributes: attrs)
    let textRect = CGRect(
        x: badgeRect.origin.x,
        y: badgeRect.origin.y + (badgeRect.height - textSize.height) / 2.0,
        width: badgeRect.width,
        height: textSize.height
    )
    badgeStr.draw(in: textRect, withAttributes: attrs)
    
    // Outer Squircle Glass Rim Border
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.setLineWidth(s * 0.012)
    ctx.addPath(squirclePath)
    ctx.strokePath()
    
    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func saveIcon(size: Int, outputPath: String) {
    let img = drawProIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: outputPath))
    }
}

let base = "/tmp/ImageVPlus.iconset"
let sizes = [16, 32, 128, 256, 512]
for s in sizes {
    saveIcon(size: s, outputPath: "\(base)/icon_\(s)x\(s).png")
    saveIcon(size: s * 2, outputPath: "\(base)/icon_\(s)x\(s)@2x.png")
}
EOF

swift -module-cache-path /tmp/swift-module-cache /tmp/generate_icon.swift
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
rm -rf "${ICONSET_DIR}"

echo "📝 Writing Info.plist (Non-Sandboxed, Unrestricted Local Access)..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>IMAGEV+</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.imagevplus.viewer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>IMAGEV+</string>
    <key>CFBundleDisplayName</key>
    <string>IMAGEV+</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Media File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
                <string>public.movie</string>
                <string>public.video</string>
                <string>public.folder</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "🚀 Compiling Swift sources..."
swiftc -O -module-cache-path /tmp/swift-module-cache \
    Sources/Models.swift \
    Sources/ImageStore.swift \
    Sources/BatchProcessor.swift \
    Sources/ZoomableImageView.swift \
    Sources/BrowserView.swift \
    Sources/ViewerView.swift \
    Sources/ContentView.swift \
    Sources/App.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

echo "🔓 Signing app bundle ad-hoc & removing quarantine flags..."
xattr -cr "${BUNDLE_DIR}" || true
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "🖼️ Applying custom icon to bundle for instant Finder visibility..."
swift -module-cache-path /tmp/swift-module-cache -e '
import AppKit
let bundlePath = CommandLine.arguments[1]
let icnsPath = "\(bundlePath)/Contents/Resources/AppIcon.icns"
if let img = NSImage(contentsOfFile: icnsPath) {
    NSWorkspace.shared.setIcon(img, forFile: bundlePath, options: [])
}
' "$(pwd)/${BUNDLE_DIR}" || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(pwd)/${BUNDLE_DIR}" || true
touch "${BUNDLE_DIR}"
rm -f /tmp/generate_icon.swift

echo "✅ Successfully built ${BUNDLE_DIR} with custom icon!"
