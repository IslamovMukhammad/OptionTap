import AppKit
import Testing
@testable import OptionTap

struct ImageGuardTests {
    /// A real PNG of the given size (small enough to make in memory).
    private func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// A 1-bit black-and-white PNG: a big pixel size compresses to a few kilobytes, like a
    /// "decompression bomb" (decoded to RGBA, 12 000 × 12 000 is over half a gigabyte).
    private func bilevelPNG(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 1,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .calibratedWhite,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func normalImagePasses() {
        #expect(ClipboardStore.safeImageSize(png(width: 120, height: 80)) == CGSize(width: 120, height: 80))
    }

    @Test func limitIsInclusive() {
        let data = png(width: 100, height: 100)
        #expect(ClipboardStore.safeImageSize(data, maxPixels: 10_000) != nil)
        #expect(ClipboardStore.safeImageSize(data, maxPixels: 9_999) == nil)
    }

    @Test func hugeHeaderIsRejectedWithoutDecoding() {
        let bomb = bilevelPNG(width: 12_000, height: 12_000)   // 144 megapixels
        #expect(bomb.count < 1_000_000)                        // far under the 25 MB byte limit
        #expect(ClipboardStore.safeImageSize(bomb) == nil)
        // The same kind of image under the limit is read fine, so the rejection is about the size.
        let ok = bilevelPNG(width: 9_000, height: 9_000)       // 81 megapixels
        #expect(ClipboardStore.safeImageSize(ok) == CGSize(width: 9_000, height: 9_000))
    }

    @Test func unknownSizeIsSkipped() {
        #expect(ClipboardStore.safeImageSize(Data("not an image".utf8)) == nil)
        #expect(ClipboardStore.safeImageSize(Data()) == nil)
    }

    @Test func tiffIsReencodedAsPNG() {
        let tiff = NSImage(data: png(width: 10, height: 6))!.tiffRepresentation!
        let out = ClipboardStore.pngData(tiff)
        #expect(out?.starts(with: [0x89, 0x50, 0x4e, 0x47]) == true)
        #expect(out.flatMap { ClipboardStore.safeImageSize($0) } == CGSize(width: 10, height: 6))
    }
}
