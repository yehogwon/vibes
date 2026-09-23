import Foundation

/// Word and character counts shown under the editor.
public struct TextStats: Equatable, Sendable {
    public var words: Int
    public var characters: Int

    public init(words: Int = 0, characters: Int = 0) {
        self.words = words
        self.characters = characters
    }

    public init(counting text: String) {
        var words = 0
        var characters = 0
        var inWord = false
        for character in text {
            characters += 1
            if character.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        self.init(words: words, characters: characters)
    }
}
