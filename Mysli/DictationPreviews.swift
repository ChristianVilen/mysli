#if DEBUG
import AppKit
import SwiftUI

#Preview("Dictation · Listening", traits: .fixedLayout(width: 154, height: 42)) {
    DictationPanel.preview(.listening(level: 0.6, warning: false))
}

#Preview("Dictation · Near time limit", traits: .fixedLayout(width: 154, height: 42)) {
    DictationPanel.preview(.listening(level: 0.82, warning: true))
}

#Preview("Dictation · Transcribing", traits: .fixedLayout(width: 96, height: 42)) {
    DictationPanel.preview(.transcribing)
}

#Preview("Dictation · Unavailable", traits: .fixedLayout(width: 64, height: 42)) {
    DictationPanel.preview(.error)
}
#endif
