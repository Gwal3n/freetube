import Foundation

extension String {
    /// Collapses runs of spaces, tabs, and line breaks into single spaces for one-line display
    /// ("Alive 2007  [Full Concert]"). Returns `self` untouched in the common clean case, since
    /// it runs during SwiftUI body evaluation.
    var collapsingDisplayWhitespace: String {
        var previousWasSpace = false
        var needsWork = false
        for character in unicodeScalars {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(character)
            if isSpace && (previousWasSpace || character != " ") {
                needsWork = true
                break
            }
            previousWasSpace = isSpace
        }
        guard needsWork else { return self }
        return split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
