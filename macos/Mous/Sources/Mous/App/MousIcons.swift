import AppKit

enum MousIcons {
    static let variantFileNames = [
        "logo-variant",
        "logo-variant-1",
        "logo-variant-2",
        "logo-variant-3",
        "logo-variant-4",
        "logo-variant-5",
    ]

    /// Canonical lime mark (`logo-variant-2`) used to sample the accent.
    static let accentSourceName = "logo-variant-2"

    static var directory: URL? {
        if let bundled = Bundle.main.resourceURL {
            let probe = bundled.appendingPathComponent("logo-variant-1.png")
            if FileManager.default.isReadableFile(atPath: probe.path) {
                return bundled
            }
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let icon = dir.appendingPathComponent("Icon", isDirectory: true)
            let probe = icon.appendingPathComponent("logo-variant-1.png")
            if FileManager.default.isReadableFile(atPath: probe.path) {
                return icon
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static var appIcon: NSImage? {
        image(named: "AppIcon", extensions: ["icns", "png"])
    }

    static func variantImages() -> [NSImage] {
        variantFileNames.compactMap { image(named: $0, extensions: ["png"]) }
    }

    static func themedVariants(isDark: Bool) -> [NSImage] {
        variantFileNames.compactMap { themed(named: $0, extensions: ["png"], isDark: isDark) }
    }

    static func applyDockIcon(isDark: Bool) {
        if let image = themed(named: "AppIcon", extensions: ["icns", "png"], isDark: isDark)
            ?? themed(named: accentSourceName, extensions: ["png"], isDark: isDark)
        {
            NSApp.applicationIconImage = image
        }
    }

    static func sampledMarkColor() -> NSColor? {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        if let cachedSample {
            return cachedSample
        }
        guard let source = image(named: accentSourceName, extensions: ["png"]),
              let color = averageMarkColor(in: source)
        else {
            return nil
        }
        cachedSample = color
        return color
    }

    static func themed(named name: String, extensions: [String], isDark: Bool) -> NSImage? {
        let key = "\(name)|\(isDark ? "d" : "l")"
        cacheLock.lock()
        if let cached = themedCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        guard let source = image(named: name, extensions: extensions),
              let processed = punched(source, darkenMarks: !isDark)
        else {
            return nil
        }
        cacheLock.lock()
        themedCache[key] = processed
        cacheLock.unlock()
        return processed
    }

    private static let cacheLock = NSLock()
    private static let sampleLock = NSLock()
    nonisolated(unsafe) private static var themedCache: [String: NSImage] = [:]
    nonisolated(unsafe) private static var cachedSample: NSColor?

    private static func image(named name: String, extensions: [String]) -> NSImage? {
        guard let directory else { return nil }
        for ext in extensions {
            let url = directory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.isReadableFile(atPath: url.path),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }
        return nil
    }

    /// Knock out the black field; in light theme, darken the remaining marks
    /// so they read on pale materials the way the lime reads on black.
    private static func punched(_ source: NSImage, darkenMarks: Bool) -> NSImage? {
        guard let cg = raster(source) else { return source }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let buf = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            let count = width * height
            for i in 0..<count {
                let o = i * 4
                let r = buf[o]
                let g = buf[o + 1]
                let b = buf[o + 2]
                let a = buf[o + 3]
                if a < 12 {
                    continue
                }
                let luma = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
                if luma < 0.08 && r < 28 && g < 28 && b < 28 {
                    buf[o] = 0
                    buf[o + 1] = 0
                    buf[o + 2] = 0
                    buf[o + 3] = 0
                    continue
                }
                if darkenMarks {
                    buf[o] = UInt8(Double(r) * 0.52)
                    buf[o + 1] = UInt8(Double(g) * 0.52)
                    buf[o + 2] = UInt8(Double(b) * 0.52)
                }
            }
            return true
        }
        guard ok,
              let provider = CGDataProvider(data: data as CFData),
              let out = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            return source
        }
        let image = NSImage(cgImage: out, size: source.size)
        image.isTemplate = false
        return image
    }

    private static func averageMarkColor(in source: NSImage) -> NSColor? {
        guard let cg = raster(source) else { return nil }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        var sumR = 0.0
        var sumG = 0.0
        var sumB = 0.0
        var count = 0.0
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let buf = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            let pixels = width * height
            let step = max(1, pixels / 40_000)
            var i = 0
            while i < pixels {
                let o = i * 4
                i += step
                let r = buf[o]
                let g = buf[o + 1]
                let b = buf[o + 2]
                let a = buf[o + 3]
                if a < 12 { continue }
                let luma = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
                if luma < 0.08 { continue }
                let alpha = Double(a) / 255.0
                guard alpha > 0 else { continue }
                sumR += Double(r) / alpha
                sumG += Double(g) / alpha
                sumB += Double(b) / alpha
                count += 1
            }
            return true
        }
        guard ok, count > 0 else { return nil }
        return NSColor(
            srgbRed: min(1, sumR / count / 255.0),
            green: min(1, sumG / count / 255.0),
            blue: min(1, sumB / count / 255.0),
            alpha: 1
        )
    }

    private static func raster(_ image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        return image.representations.compactMap { $0 as? NSBitmapImageRep }.compactMap(\.cgImage).first
    }
}
