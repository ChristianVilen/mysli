import Foundation

struct TranscriptSegment: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct TrackTranscript: Equatable {
    let segments: [TranscriptSegment]
    let duration: TimeInterval
}

struct TranscriptLine: Equatable {
    let speaker: Speaker
    let start: TimeInterval
    let text: String
}

struct CorrectedTranscript: Equatable, Sendable {
    /// The corrected text without the known-words note. It ends with a line break when a note
    /// follows it.
    let body: String
    let applied: [AppliedCorrection]

    var markdown: String {
        guard !applied.isEmpty else { return body }
        let pairs = applied.map { "\($0.heard) → \($0.right) (\($0.count))" }.joined(separator: ", ")
        return body + Self.noteStart + pairs + ".\n"
    }

    fileprivate static let noteStart = "\n---\n\nKnown words applied: "
}

enum Transcript {
    /// Joins a speaker's segments while the gap between them is under `joinGap`. With nil, each
    /// segment is a line of its own. With `.voices`, the microphone lines get room labels: see
    /// `microphoneLines`.
    static func merge(_ tracks: [MeetingTrack: [TranscriptSegment]], rooms: RoomLabels,
                      joinGap: TimeInterval? = 2, speakers: TeamsSpeakerEvidence = .empty) -> [TranscriptLine] {
        let them = withText(tracks[.system] ?? [])
        // sorted(by:) is stable, so Them, listed first, stays first on an equal start.
        let spoken = (systemLines(them, speakers: speakers)
            + microphoneLines(microphoneSpeech(tracks), them: them, rooms: rooms))
            .sorted { $0.segment.start < $1.segment.start }

        var lines: [TranscriptLine] = []
        var lastEnd = -TimeInterval.infinity
        for (speaker, segment) in spoken {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let joinGap, let last = lines.last, last.speaker == speaker, segment.start - lastEnd < joinGap {
                lines[lines.count - 1] = TranscriptLine(speaker: speaker, start: last.start, text: last.text + " " + text)
            } else {
                lines.append(TranscriptLine(speaker: speaker, start: segment.start, text: text))
            }
            lastEnd = segment.end
        }
        return lines
    }

    private static func systemLines(_ segments: [TranscriptSegment], speakers: TeamsSpeakerEvidence)
        -> [(speaker: Speaker, segment: TranscriptSegment)] {
        let sorted = segments.sorted { $0.start < $1.start }
        var furthestEnd = -TimeInterval.infinity
        return sorted.enumerated().map { index, segment in
            let overlapsPrevious = segment.start < furthestEnd
            let overlapsNext = index + 1 < sorted.count && sorted[index + 1].start < segment.end
            furthestEnd = max(furthestEnd, segment.end)
            let name = overlapsPrevious || overlapsNext ? nil : speakers.name(for: segment)
            return (name.map(Speaker.teams) ?? .them, segment)
        }
    }

    /// Microphone segments with text that pass the segment-echo filter, in time order.
    /// `merge` can later remove segments from echo voices.
    static func microphoneSpeech(_ tracks: [MeetingTrack: [TranscriptSegment]]) -> [TranscriptSegment] {
        let them = tracks[.system] ?? []
        return withText(tracks[.microphone] ?? [])
            .filter { mic in !them.contains { isEcho(mic, of: $0) } }
            .sorted { $0.start < $1.start }
    }

    private static func withText(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Room labels come only from the voices that count. An echo voice speaks while Them speaks
    /// for at least `echoVoiceTimeShare` of its time, and at least `echoVoiceWordShare` of its words
    /// are in the Them segments near its own; its lines are dropped. A voice with fewer than
    /// `minimumRoomVoiceWords` words is too small to count; its lines take the counted voice whose
    /// turn is nearest. With fewer than two counted voices, every line is "Me". Room numbers follow
    /// each counted voice's first line.
    private static func microphoneLines(_ me: [TranscriptSegment], them: [TranscriptSegment], rooms: RoomLabels)
        -> [(speaker: Speaker, segment: TranscriptSegment)] {
        guard case .voices(let voices) = rooms else { return me.map { (.me, $0) } }
        let voiced = me.map { (segment: $0, voice: voices.voice(for: $0)) }
        let stats = voiceStats(voiced, them: them)
        let echoes = Set(stats.filter { $0.value.isEcho }.keys)
        let kept = voiced.filter { !echoes.contains($0.voice) }

        let counted = Set(stats.filter { !$0.value.isEcho && $0.value.words >= minimumRoomVoiceWords }.keys)
        guard counted.count > 1, let countedVoices = voices.keeping(counted) else { return kept.map { (.me, $0.segment) } }
        var numbers: [Int: Int] = [:]
        return kept.map { segment, voice in
            let room = counted.contains(voice) ? voice : countedVoices.voice(for: segment)
            if numbers[room] == nil { numbers[room] = numbers.count + 1 }
            return (.room(numbers[room]!), segment)
        }
    }

    private struct VoiceStats {
        var time: TimeInterval = 0
        /// The part of `time` during "Them" speech.
        var overlap: TimeInterval = 0
        var words = 0
        /// The words that are also in the "Them" segments near their own segment.
        var repeated = 0

        var isEcho: Bool {
            time > 0 && overlap >= Transcript.echoVoiceTimeShare * time
                && Double(repeated) >= Transcript.echoVoiceWordShare * Double(words)
        }
    }

    /// `voiced` must be in time order for `timeOverlapping`.
    private static func voiceStats(_ voiced: [(segment: TranscriptSegment, voice: Int)],
                                   them: [TranscriptSegment]) -> [Int: VoiceStats] {
        var stats: [Int: VoiceStats] = [:]
        for ((segment, voice), overlap) in zip(voiced, timeOverlapping(them, for: voiced.map(\.segment))) {
            let heard = Set(them.filter { nearInTime(segment, $0) }.flatMap { words($0.text) })
            let said = words(segment.text)
            var sum = stats[voice, default: VoiceStats()]
            sum.time += segment.end - segment.start
            sum.overlap += overlap
            sum.words += said.count
            sum.repeated += said.filter(heard.contains).count
            stats[voice] = sum
        }
        return stats
    }

    /// Short echoes can pass the segment filter and get a voice of their own. The voice filter
    /// uses both time overlap and repeated words as evidence of an echo.
    private static let echoVoiceTimeShare = 0.7
    private static let echoVoiceWordShare = 0.5
    private static let minimumRoomVoiceWords = 5

    /// The seconds of each of `segments` inside any segment of `other`. `segments` must be in time order.
    private static func timeOverlapping(_ other: [TranscriptSegment], for segments: [TranscriptSegment]) -> [TimeInterval] {
        var spans: [(start: TimeInterval, end: TimeInterval)] = []
        for segment in other.sorted(by: { $0.start < $1.start }) where segment.end > segment.start {
            if let last = spans.last, segment.start <= last.end {
                spans[spans.count - 1].end = max(last.end, segment.end)
            } else {
                spans.append((segment.start, segment.end))
            }
        }
        var first = 0
        return segments.map { segment in
            while first < spans.count, spans[first].end <= segment.start { first += 1 }
            var time: TimeInterval = 0
            for span in spans[first...] {
                guard span.start < segment.end else { break }
                time += min(span.end, segment.end) - max(span.start, segment.start)
            }
            return time
        }
    }

    static func isEcho(_ microphone: TranscriptSegment, of system: TranscriptSegment) -> Bool {
        guard nearInTime(microphone, system) else { return false }
        let micWords = words(microphone.text)
        guard micWords.count >= minimumMicrophoneWords else { return false }
        let systemWords = Set(words(system.text))
        let shared = micWords.filter(systemWords.contains).count
        return Double(shared) >= sharedWordFraction * Double(micWords.count)
    }

    private static func nearInTime(_ microphone: TranscriptSegment, _ system: TranscriptSegment) -> Bool {
        microphone.start <= system.end + slack && system.start <= microphone.end + slack
    }

    private static let slack: TimeInterval = 1
    /// Shorter microphone segments are never echoes: a short reply such as
    /// "okay" or "yes please" often shares its words with the other side.
    private static let minimumMicrophoneWords = 3
    private static let sharedWordFraction = 0.6

    /// Everything after the speaker legend, so the summary CLI gets no header and no failure lines.
    /// `markdown` has no known-words note: it is a `CorrectedTranscript.body`.
    static func contentForSummary(_ markdown: String) -> String {
        for legend in Legend.allCases {
            if let boundary = markdown.range(of: legend.rawValue + "\n\n") {
                return String(markdown[boundary.upperBound...])
            }
        }
        return markdown
    }

    /// Corrects only spoken text, leaving headers and labels unchanged. Without replacements,
    /// returns `heard` byte for byte; otherwise the note lists each pair in order of first use.
    /// `heard` must be the original transcript so replacements never apply twice.
    static func corrected(_ heard: String, by corrector: Corrector) -> CorrectedTranscript {
        var found: [AppliedCorrection] = []
        let lines = heard.components(separatedBy: "\n").map { line -> String in
            guard let spoken = spokenLine(line[...]) else { return line }
            let corrected = corrector.correct(String(spoken.text))
            found += corrected.applied
            return line[..<spoken.text.startIndex] + corrected.text
        }
        let applied = summed(found)
        guard !applied.isEmpty else { return CorrectedTranscript(body: heard, applied: []) }
        var text = lines.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return CorrectedTranscript(body: text, applied: applied)
    }

    static func withoutCorrectionNote(_ markdown: String) -> String {
        guard let note = markdown.range(of: CorrectedTranscript.noteStart, options: .backwards) else { return markdown }
        return String(markdown[..<note.lowerBound])
    }

    /// Matches quotes in spoken text using `Phrase.fold`; returns a place such as "Them at 00:12:31".
    static func place(of quote: String, in markdown: String) -> String? {
        let quote = Phrase.fold(quote)
        guard !quote.isEmpty else { return nil }
        for line in markdown.components(separatedBy: "\n") {
            if let spoken = spokenLine(line[...]), Phrase.fold(String(spoken.text)).contains(quote) {
                return "\(spoken.label) at \(spoken.time)"
            }
        }
        return nil
    }

    /// Each pair once, in the order of its first use, with its counts added up.
    private static func summed(_ corrections: [AppliedCorrection]) -> [AppliedCorrection] {
        var summed: [AppliedCorrection] = []
        for correction in corrections {
            if let index = summed.firstIndex(where: { $0.heard == correction.heard && $0.right == correction.right }) {
                summed[index] = AppliedCorrection(heard: correction.heard, right: correction.right,
                                                  count: summed[index].count + correction.count)
            } else {
                summed.append(correction)
            }
        }
        return summed
    }

    private static func spokenLine(_ line: Substring) -> (time: Substring, label: Substring, text: Substring)? {
        guard let prefix = line.prefixMatch(of: #/\*\*\[(\d{2,}:\d{2}:\d{2})\] ([^*\n]+):\*\* /#) else { return nil }
        return (prefix.1, prefix.2, line[prefix.range.upperBound...])
    }

    static func markdown(_ lines: [TranscriptLine], title: String, duration: TimeInterval,
                         by transcriber: String, after failures: [TranscriberFailure], rooms: RoomLabels,
                         teams: TeamsScanSummary) -> String {
        let byline = failures.isEmpty
            ? "Transcript by \(transcriber)."
            : "Transcript by \(transcriber). Tried first:\n\n" + failures.map { "- \($0)" }.joined(separator: "\n")
        var header = [byline]
        if case .failed(let failure) = rooms { header.append("There are no room labels. \(failure)") }
        if let note = teams.transcriptNote(for: lines) { header.append(note) }
        let hasRooms = lines.contains { line in
            if case .room = line.speaker { return true }
            return false
        }
        let hasNames = lines.contains { line in
            if case .teams = line.speaker { return true }
            return false
        }
        let legend: Legend = hasNames ? (hasRooms ? .teamsRooms : .teamsMicrophone) : (hasRooms ? .rooms : .microphone)
        header.append(legend.rawValue)
        var text = """
        # \(MeetingTitle.heading(title))

        Duration: \(clock(duration))

        \(header.joined(separator: "\n\n"))


        """
        for line in lines {
            text += "**[\(clock(line.start))] \(line.speaker.label):** \(line.text)\n\n"
        }
        if lines.isEmpty {
            text += "No speech was detected.\n\n"
        }
        return String(text.dropLast())
    }

    /// Every legend that any Ku-Ka version wrote. `markdown` writes `rooms` or `microphone`.
    /// `contentForSummary` must still find a legend in a transcript that waits for its summary
    /// across an app update, so add a case for a new legend, and never edit or delete one.
    private enum Legend: String, CaseIterable {
        case teamsRooms = "\"Room 1\", \"Room 2\", and so on are voices on the microphone of the Mac that recorded the meeting. The microphone hears the person who recorded the meeting and anyone in the same room. Ku-Ka told the voices apart on this Mac and numbered them in the order they first spoke. Two people with similar voices can share one label, and one person can get two labels. No label tells which voice is the person who recorded the meeting. Labels ending in \"(Teams)\" come from best-effort Teams meeting UI observations. They can be wrong and do not prove action ownership. \"Them\" is system audio without a supported name."
        case teamsMicrophone = "\"Me\" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. Labels ending in \"(Teams)\" come from best-effort Teams meeting UI observations. They can be wrong and do not prove action ownership. \"Them\" is system audio without a supported name."
        case rooms = "\"Room 1\", \"Room 2\", and so on are voices on the microphone of the Mac that recorded the meeting. The microphone hears the person who recorded the meeting and anyone in the same room. Ku-Ka told the voices apart on this Mac and numbered them in the order they first spoke. Two people with similar voices can share one label, and one person can get two labels. No label tells which voice is the person who recorded the meeting. \"Them\" is everyone else on the call."
        case microphone = "\"Me\" is the microphone of the Mac that recorded the meeting. It hears the person who recorded the meeting and anyone in the same room. \"Them\" is everyone else on the call."
        case person = "\"Me\" is the person who recorded the meeting. \"Them\" is everyone else on the call."
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
