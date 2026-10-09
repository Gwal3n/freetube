//
//  Method.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 31.08.23.
//

import Foundation

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
extension YouTube {

    public enum ExtractionMethod: Hashable, Sendable {
        case local
    }

}

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
extension [YouTube.ExtractionMethod] {

    /// FreeTube resolves streams locally; the hosted extractor is intentionally unavailable.
    public static var `default`: Self {
        [.local]
    }

}
