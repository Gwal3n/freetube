import CoreGraphics
import Foundation

enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case auto
    case p144 = "144p"
    case p240 = "240p"
    case p360 = "360p"
    case p480 = "480p"
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case p2160 = "2160p"
    case audioOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .audioOnly: return "Audio"
        default: return rawValue
        }
    }

    var heightCap: Int? {
        switch self {
        case .auto: return 1080
        case .p144: return 144
        case .p240: return 240
        case .p360: return 360
        case .p480: return 480
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .p2160: return 2160
        case .audioOnly: return 0
        }
    }
}

extension VideoQuality {
    /// AVPlayer's reported picture size is a useful live indication, but it is not a
    /// guaranteed identifier for the HLS rendition currently being downloaded.
    static func reportedPictureLabel(for size: CGSize) -> String? {
        let shorterSide = min(size.width, size.height)
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1,
              size.width <= 16_384, size.height <= 16_384 else { return nil }
        return "≈\(Int(shorterSide.rounded()))p"
    }
}
