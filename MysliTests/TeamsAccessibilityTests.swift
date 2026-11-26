import XCTest
import ApplicationServices
@testable import Mysli

final class TeamsAccessibilityTests: XCTestCase {
    func testAnAttributeWithoutAValueIsNoErrorButOtherStatusesAre() throws {
        XCTAssertTrue(try TeamsAXRules.hasValue(.success))
        XCTAssertFalse(try TeamsAXRules.hasValue(.attributeUnsupported))
        XCTAssertFalse(try TeamsAXRules.hasValue(.noValue))
        for status in [AXError.cannotComplete, .failure, .invalidUIElement, .apiDisabled] {
            XCTAssertThrowsError(try TeamsAXRules.hasValue(status)) { error in
                XCTAssertEqual(error as? TeamsScanReason, .axError(status.rawValue))
            }
        }
    }

    func testANegativeCountIsUnexpectedDataAndACountOverTheLimitEndsTheScan() throws {
        let maximum = TeamsScanLimit.children.maximum
        XCTAssertNoThrow(try TeamsAXRules.checkCount(0, limit: .children))
        XCTAssertNoThrow(try TeamsAXRules.checkCount(maximum, limit: .children))
        XCTAssertThrowsError(try TeamsAXRules.checkCount(maximum + 1, limit: .children)) { error in
            XCTAssertEqual(error as? TeamsScanReason, .scanLimit(.children))
        }
        XCTAssertThrowsError(try TeamsAXRules.checkCount(-1, limit: .children)) { error in
            XCTAssertEqual(error as? TeamsScanReason, .unexpectedAXValue)
        }
    }

    func testInvalidSecondMarkerStillMakesTheCandidateAmbiguous() {
        for metadata in [TeamsAXMetadata(role: "AXUnknown"), TeamsAXMetadata(identifier: "chat"),
                         TeamsAXMetadata(bounds: .zero)] {
            let tree = FakeTeamsAX.meeting()
            tree.nodes[0]!.children.append(5)
            var marker = metadata
            marker.classes.formUnion(["vdi-frame-occlusion", "frwhdur", "f578s74"])
            tree.nodes[5] = .init(metadata: marker)
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.multipleHighlightedTiles))
            XCTAssertEqual(tree.labelReads, [2, 3, 4])
        }
    }

    /// Tile 3 with the name 4 of `meeting()`, and tile 5 with the name 6 after it.
    private func twoTiles() -> FakeTeamsAX {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[0]!.children.append(5)
        tree.nodes[5] = tree.nodes[3]
        tree.nodes[5]!.children = [6]
        tree.nodes[6] = .init(metadata: TeamsAXMetadata(role: "AXStaticText"), label: "Grace Hopper")
        return tree
    }

    func testTheUsersOwnTileDropsOutBesideAnotherHighlightedTile() {
        let ways: [(String, (FakeTeamsAX, _ tile: Int, _ name: Int) -> Void)] = [
            ("self metadata", { tree, tile, _ in tree.nodes[tile]!.metadata.identifier = "self-video" }),
            ("tile label", { tree, tile, _ in tree.nodes[tile]!.label = "Myself video, muted" }),
            ("You", { tree, _, name in tree.nodes[name]!.label = "You" }),
            ("(you)", { tree, _, name in tree.nodes[name]!.label = "Ada Lovelace (you)" })
        ]
        for (way, makeOwn) in ways {
            let ownFirst = twoTiles()
            makeOwn(ownFirst, 3, 4)
            XCTAssertEqual(TeamsAccessibility(reader: ownFirst).snapshot().result.speaker?.value, "Grace Hopper", way)
            let ownLast = twoTiles()
            makeOwn(ownLast, 5, 6)
            XCTAssertEqual(TeamsAccessibility(reader: ownLast).snapshot().result.speaker?.value, "Ada Lovelace", way)
        }
    }

    func testTheTilesLeftBesideTheUsersOwnDecideTheResult() {
        let onlyOwn = twoTiles()
        onlyOwn.nodes[3]!.metadata.identifier = "self-video"
        onlyOwn.nodes[6]!.label = "You"
        XCTAssertEqual(TeamsAccessibility(reader: onlyOwn).snapshot().result, .unnamed(.selfTile))

        let unsupported = twoTiles()
        unsupported.nodes[3]!.metadata.identifier = "self-video"
        unsupported.nodes[5]!.children = [6, 7]
        unsupported.nodes[7] = unsupported.nodes[6]
        XCTAssertEqual(TeamsAccessibility(reader: unsupported).snapshot().result, .unnamed(.unsupportedTile))

        let rejected = twoTiles()
        rejected.nodes[3]!.metadata.identifier = "self-video"
        rejected.nodes[6]!.label = "Them"
        XCTAssertEqual(TeamsAccessibility(reader: rejected).snapshot().result, .unnamed(.nameRejected))

        let twoOthers = twoTiles()
        twoOthers.nodes[3]!.metadata.identifier = "self-video"
        twoOthers.nodes[0]!.children.append(7)
        twoOthers.nodes[7] = twoOthers.nodes[5]
        twoOthers.nodes[7]!.children = [8]
        twoOthers.nodes[8] = .init(metadata: TeamsAXMetadata(role: "AXStaticText"), label: "Alan Turing")
        XCTAssertEqual(TeamsAccessibility(reader: twoOthers).snapshot().result, .unnamed(.multipleHighlightedTiles))
    }

    func testToolbarInteriorGroupsDoNotNeedBoundsOrRejectSelfButTileGroupsDo() {
        for metadata in [TeamsAXMetadata(bounds: .zero), TeamsAXMetadata(identifier: "self-video")] {
            let controls = FakeTeamsAX.meeting()
            controls.nodes[1]!.children = [5]
            controls.nodes[5] = .init(metadata: metadata, children: [2])
            XCTAssertEqual(TeamsAccessibility(reader: controls).snapshot().result.speaker?.value, "Ada Lovelace")
            XCTAssertEqual(controls.labelReads, [2, 3, 4])
            let tile = FakeTeamsAX.meeting()
            tile.nodes[3]!.children = [5]
            tile.nodes[5] = .init(metadata: metadata, children: [4])
            XCTAssertEqual(TeamsAccessibility(reader: tile).snapshot().result, .unnamed(.unsupportedTile))
            XCTAssertEqual(tile.labelReads, [2])
        }
    }

    func testForbiddenAndSelfOwnersAtSeveralDepthsNeverReadCandidateLabels() {
        for depth in 1...3 {
            for (identifier, reason) in [("self-video", TeamsScanReason.selfTile), ("chat", .noHighlightedTile)] {
                let tree = FakeTeamsAX.meeting()
                tree.nodes[0]!.children = [1, 10]
                for offset in 0..<depth {
                    tree.nodes[10 + offset] = .init(children: [offset == depth - 1 ? 3 : 11 + offset])
                }
                tree.nodes[10 + depth - 1]!.metadata.identifier = identifier
                XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(reason))
                XCTAssertEqual(tree.labelReads, [2])
            }
        }
    }

    func testSelfMetadataAboveTileRejectsCandidateBeforeItsLabelsAreRead() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[0]!.children = [1, 5]
        tree.nodes[5] = .init(metadata: TeamsAXMetadata(classes: ["self-video"]), children: [3])
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.selfTile))
        XCTAssertEqual(tree.labelReads, [2])
    }

    func testToolbarOwnersMustHaveSupportedVisibleBoundedNonforbiddenScopeBeforeLabelsAreRead() {
        for owner in [TeamsAXMetadata(role: "AXUnknown"), TeamsAXMetadata(identifier: "meeting-chat"),
                      TeamsAXMetadata(classes: ["shared-content"]), TeamsAXMetadata(visible: false),
                      TeamsAXMetadata(bounds: .zero)] {
            for identifier in ["meeting-controls", ""] {
                let tree = FakeTeamsAX.meeting()
                tree.nodes[0]!.children = [5, 3]
                tree.nodes[5] = .init(metadata: owner, children: [1])
                tree.nodes[1]!.metadata.identifier = identifier
                tree.nodes[1]!.label = "Meeting controls"
                XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
                XCTAssertFalse(tree.labelReads.contains(1))
                XCTAssertFalse(tree.labelReads.contains(2))
            }
        }
    }

    func testOwnedTileNameRequiresTwoBorderClassesAndVideoScope() {
        let tree = FakeTeamsAX.meeting()
        let source = TeamsAccessibility(reader: tree)
        XCTAssertEqual(source.snapshot().result.speaker?.value, "Ada Lovelace")
        tree.nodes[3]!.metadata.classes = ["vdi-frame-occlusion"]
        XCTAssertEqual(source.snapshot().result, .unnamed(.noHighlightedTile))
        tree.nodes[3]!.metadata.classes = ["frwhdur", "f578s74"]
        XCTAssertEqual(source.snapshot().result, .unnamed(.noHighlightedTile))
    }

    func testNestedMarkersDeduplicateToTheCommonTile() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[3]!.metadata.classes = ["vdi-frame-occlusion"]
        tree.nodes[3]!.children += [5, 6]
        for node in [5, 6] {
            tree.nodes[node] = .init(metadata: TeamsAXMetadata(classes: ["frwhdur", "f578s74"]))
        }
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result.speaker?.value, "Ada Lovelace")
        tree.nodes[5]!.metadata.bounds.size.width = 99
        tree.nodes[6]!.metadata.bounds.size.width = 99
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noHighlightedTile))
    }

    func testTwoHighlightedTilesWithTheSameNameGiveThatName() {
        let tree = twoTiles()
        tree.nodes[6]!.label = "Ada Lovelace"
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result.speaker?.value, "Ada Lovelace")
    }

    func testCandidateRejectsForbiddenDescendantsWithoutReadingTheirText() {
        for identifier in ["chat", "captions", "shared-content", "document", "self-video"] {
            let tree = FakeTeamsAX.meeting()
            tree.nodes[3]!.children.append(5)
            tree.nodes[5] = .init(metadata: TeamsAXMetadata(identifier: identifier), children: [6], label: "Private")
            tree.nodes[6] = .init(metadata: TeamsAXMetadata(role: "AXStaticText"), label: "Private")
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile), identifier)
            XCTAssertEqual(tree.labelReads, [2], identifier)
        }
        for role in ["AXTextField", "AXSecureTextField", "AXTextArea", "AXDocument", "AXWebArea", "AXUnknown"] {
            let tree = FakeTeamsAX.meeting()
            tree.nodes[3]!.children.append(5)
            tree.nodes[5] = .init(metadata: TeamsAXMetadata(role: role), label: "Private")
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile), role)
            XCTAssertEqual(tree.labelReads, [2], role)
        }
    }

    func testUnrelatedBranchesArePrunedBeforeTheirLabelsOrChildrenAreRead() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[0]!.children += [5]
        tree.nodes[5] = .init(metadata: TeamsAXMetadata(identifier: "meeting-chat"), children: [6], label: "Private")
        tree.nodes[6] = .init(metadata: TeamsAXMetadata(role: "AXStaticText"), label: "Private")
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result.speaker?.value, "Ada Lovelace")
        XCTAssertEqual(tree.labelReads, [2, 3, 4])
        XCTAssertFalse(tree.metadataReads.contains(6))
    }

    func testExactlyOneVisibleOwnedNameWithValidBoundsIsRequired() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[4]!.metadata.bounds.origin.x = 200
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        tree.nodes[4]!.metadata.bounds.origin.x = 0
        tree.nodes[4]!.metadata.bounds.size.width = 0
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        tree.nodes[4]!.metadata.bounds.size.width = 100
        tree.nodes[4]!.metadata.visible = false
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        tree.nodes[4]!.metadata.visible = true
        tree.nodes[3]!.children += [5]
        tree.nodes[5] = tree.nodes[4]
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
    }

    func testWindowMustHaveVisibleEnabledCallControls() {
        for label in ["Hang up", "Leave"] {
            let tree = FakeTeamsAX.meeting()
            tree.nodes[2]!.label = label
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result.speaker?.value, "Ada Lovelace")
            tree.nodes[2]!.metadata.enabled = false
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
            tree.nodes[2]!.metadata.enabled = true
            tree.nodes[2]!.metadata.visible = false
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
        }
        let tree = FakeTeamsAX.meeting()
        tree.nodes[1]!.metadata.identifier = ""
        tree.nodes[1]!.label = "Calling controls"
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result.speaker?.value, "Ada Lovelace")
        tree.nodes[1]!.label = "Roster"
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
        XCTAssertFalse(tree.labelReads.contains(0))
    }

    func testScrollAreaAroundWebContentPreservesTheCallWindowScope() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[0]!.children = [5]
        tree.nodes[5] = .init(metadata: TeamsAXMetadata(role: "AXScrollArea"), children: [6])
        tree.nodes[6] = .init(metadata: TeamsAXMetadata(role: "AXWebArea"), children: [1, 3])

        let snapshot = TeamsAccessibility(reader: tree).snapshot()
        XCTAssertEqual(snapshot.result.speaker?.value, "Ada Lovelace", "\(snapshot.result)")
    }

    func testCallingControlsGroupBesideMeetingToolbarIdentifiesTheCall() {
        let snapshot = TeamsAccessibility(reader: FakeTeamsAX.callWithSeparateControls()).snapshot()
        XCTAssertEqual(snapshot.result.speaker?.value, "Ada Lovelace", "\(snapshot.result)")
    }

    func testShareViewParticipantItemOwnsTheNameBesideItsHighlight() {
        let tree = FakeTeamsAX.shareView()
        let snapshot = TeamsAccessibility(reader: tree).snapshot()
        XCTAssertEqual(snapshot.result.speaker?.value, "Lovelace, Ada", "\(snapshot.result)")
        tree.nodes[47]!.metadata.bounds.origin.y = 900
        tree.labelReads = []
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        XCTAssertFalse(tree.labelReads.contains(47))
    }

    func testSeparateCallingControlsNeedARecognisedToolbarWithTheSameParent() {
        let tree = FakeTeamsAX.callWithSeparateControls()
        tree.nodes[1]!.metadata.identifier = ""
        tree.nodes[1]!.label = "Other tools"
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
        XCTAssertFalse(tree.labelReads.contains(5))
        XCTAssertFalse(tree.labelReads.contains(2))

        tree.nodes[1]!.metadata.identifier = "meeting-controls"
        tree.nodes[0]!.children = [6, 3, 5]
        tree.nodes[6] = .init(children: [1])
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
        XCTAssertFalse(tree.labelReads.contains(5))
        XCTAssertFalse(tree.labelReads.contains(2))
    }

    func testSeparateCallingControlsRejectUnsafeGroupsBeforeReadingTheirLabels() {
        for metadata in [TeamsAXMetadata(identifier: "meeting-chat"), TeamsAXMetadata(classes: ["shared-content"]),
                         TeamsAXMetadata(identifier: "self-video"), TeamsAXMetadata(visible: false),
                         TeamsAXMetadata(bounds: .zero), TeamsAXMetadata(role: "AXUnknown")] {
            let tree = FakeTeamsAX.callWithSeparateControls()
            tree.nodes[5]!.metadata = metadata
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
            XCTAssertFalse(tree.labelReads.contains(5))
            XCTAssertFalse(tree.labelReads.contains(2))
        }
    }

    func testSeparateCallingControlsRequireTheirOwnNameBeforeReadingButtons() {
        for (label, reason) in [(nil, TeamsScanReason.noMeetingWindow), ("Other tools", .noMeetingWindow),
                                (String(repeating: "x", count: 257), .scanLimit(.text))] {
            let tree = FakeTeamsAX.callWithSeparateControls()
            tree.nodes[5]!.label = label
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(reason))
            XCTAssertFalse(tree.labelReads.contains(2))
        }
    }

    func testSeparateCallingControlsIgnoreIneligibleButtonsBeforeReadingAnyLabels() {
        for metadata in [TeamsAXMetadata(role: "AXButton", enabled: false),
                         TeamsAXMetadata(role: "AXButton", visible: false),
                         TeamsAXMetadata(role: "AXButton", bounds: .zero),
                         TeamsAXMetadata(role: "AXButton", identifier: "chat")] {
            let tree = FakeTeamsAX.callWithSeparateControls()
            tree.nodes[2]!.metadata = metadata
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
            XCTAssertFalse(tree.labelReads.contains(5))
            XCTAssertFalse(tree.labelReads.contains(2))
        }
    }

    func testNoTeamsDeniedRevokedAndTransportFailuresHaveTheirReasons() {
        let tree = FakeTeamsAX.meeting()
        let source = TeamsAccessibility(reader: tree)
        tree.trusted = false
        XCTAssertEqual(source.snapshot().result, .unnamed(.notTrusted))
        XCTAssertTrue(tree.metadataReads.isEmpty)
        tree.trusted = true
        XCTAssertNotNil(source.snapshot().result.speaker)
        tree.trusted = false
        XCTAssertEqual(source.snapshot().result, .unnamed(.notTrusted))
        tree.trusted = true
        tree.running = false
        XCTAssertEqual(source.snapshot().result, .unnamed(.noTeamsApp))
        tree.running = true
        tree.roots = []
        XCTAssertEqual(source.snapshot().result, .unnamed(.noMeetingWindow))
        tree.roots = [0]
        for operation in ["windows", "metadata", "children", "label"] {
            tree.failing = operation
            XCTAssertEqual(source.snapshot().result, .unnamed(.axError(-25204)), operation)
        }
    }

    func testAReaderErrorThatIsNoReasonCountsAsUnexpectedData() {
        let tree = FakeTeamsAX.meeting()
        tree.failing = "metadata"
        tree.failure = FakeTeamsAX.Failure.transport
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unexpectedAXValue))
    }

    func testPermissionRevokedDuringTheScanGivesNoName() {
        let tree = FakeTeamsAX.meeting()
        tree.onLabelRead = { node in if node == 4 { tree.trusted = false } }
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.notTrusted))
    }

    func testMultipleMeetingWindowsAreAmbiguousAndUnrelatedWindowsDoNotSupplyNames() {
        let tree = FakeTeamsAX.meeting()
        tree.roots += [10]
        tree.nodes[10] = .init(metadata: TeamsAXMetadata(role: "AXWindow"), children: [11])
        tree.nodes[11] = .init(metadata: TeamsAXMetadata(role: "AXStaticText"), label: "Other person")
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result.speaker?.value, "Ada Lovelace")
        tree.nodes[10]!.children += [1, 3]
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.multipleMeetingWindows))
        XCTAssertFalse(tree.labelReads.contains(11))
    }

    func testLabelsAreByteBoundedAndNamesValidated() {
        let tree = FakeTeamsAX.meeting()
        for label in [String(repeating: "é", count: 129), "Them"] {
            tree.nodes[4]!.label = label
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.nameRejected), label)
        }
        tree.nodes[4]!.label = nil
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.nameRejected))
        tree.nodes[4]!.label = "Ada Lovelace"
        tree.nodes[2]!.label = String(repeating: "x", count: 257)
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.scanLimit(.text)))
        tree.nodes[2]!.label = nil
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
        tree.nodes[2]!.label = "Hang up"
        tree.nodes[3]!.label = String(repeating: "x", count: 257)
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.scanLimit(.text)))
    }

    func testUnknownAncestorScopeAndInvisibleWindowCannotSupplyATile() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[0]!.children = [1, 5]
        tree.nodes[5] = .init(metadata: TeamsAXMetadata(role: "AXUnknown"), children: [3])
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        XCTAssertEqual(tree.labelReads, [2])
        tree.nodes[0]!.children = [1, 3]
        tree.nodes[0]!.metadata.visible = false
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
    }

    func testTileAndEveryOwnerMustContainTheMarkerAndName() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[0]!.children = [1, 5]
        tree.nodes[5] = .init(children: [3])
        tree.nodes[5]!.metadata.bounds.size.width = 50
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        XCTAssertEqual(tree.labelReads, [2])
    }

    func testWindowChildDepthNodeAndDeadlineLimitsInvalidateWholeSnapshot() {
        let windows = FakeTeamsAX.meeting()
        windows.roots = Array(repeating: 0, count: 9)
        XCTAssertEqual(TeamsAccessibility(reader: windows).snapshot().result, .unnamed(.scanLimit(.windows)))
        let children = FakeTeamsAX.meeting()
        children.nodes[0]!.children = Array(repeating: 1, count: 41)
        XCTAssertEqual(TeamsAccessibility(reader: children).snapshot().result, .unnamed(.scanLimit(.children)))
        let depth = FakeTeamsAX.meeting()
        depth.nodes[0]!.children += [10]
        for node in 10...42 { depth.nodes[node] = .init(children: node == 42 ? [] : [node + 1]) }
        XCTAssertEqual(TeamsAccessibility(reader: depth).snapshot().result, .unnamed(.scanLimit(.depth)))
        let nodes = FakeTeamsAX.meeting()
        nodes.nodes[0]!.children += Array(10..<23)
        for parent in 10..<23 {
            let ids = Array((parent * 100)..<(parent * 100 + 40))
            nodes.nodes[parent] = .init(children: ids)
            for node in ids { nodes.nodes[node] = .init() }
        }
        let limited = TeamsAccessibility(reader: nodes).snapshot()
        XCTAssertEqual(limited.result, .unnamed(.scanLimit(.nodes)))
        XCTAssertEqual(limited.nodes, 512)
        XCTAssertEqual(nodes.metadataReads.count, 512)
        let slow = FakeTeamsAX.meeting()
        var time = 0.0
        slow.onRead = { time += 0.03 }
        XCTAssertEqual(TeamsAccessibility(reader: slow, now: { time }).snapshot().result, .unnamed(.deadline))
        XCTAssertTrue(slow.timeouts.allSatisfy { $0 > 0 && $0 <= 0.05 })
        XCTAssertLessThan(slow.timeouts.last!, 0.05)
    }

    func testANodeThatAppearsTwiceInOneWindowIsUnexpectedData() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[3]!.children += [0]
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unexpectedAXValue))
    }

    func testSnapshotCountsTheNodesItRead() {
        XCTAssertEqual(TeamsAccessibility(reader: FakeTeamsAX.meeting()).snapshot().nodes, 5)
        let tree = FakeTeamsAX.meeting()
        tree.trusted = false
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().nodes, 0)
    }

    func testForbiddenToolbarAndButtonNeverHaveTheirLabelsRead() {
        for node in [1, 2] {
            let tree = FakeTeamsAX.meeting()
            tree.nodes[node]!.metadata.identifier = "chat-controls"
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
            XCTAssertFalse(tree.labelReads.contains(node))
        }
        let tree = FakeTeamsAX.meeting()
        tree.nodes[1]!.children = [5]
        tree.nodes[5] = .init(metadata: TeamsAXMetadata(role: "AXWebArea"), children: [2])
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
        XCTAssertFalse(tree.labelReads.contains(2))
    }

    func testControlsRequireFinitePositiveBoundsBeforeLabelsAreRead() {
        for node in [1, 2] {
            for bounds in [CGRect.zero, CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
                           CGRect(x: 100, y: 0, width: -100, height: 100)] {
                let tree = FakeTeamsAX.meeting()
                tree.nodes[node]!.metadata.bounds = bounds
                XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.noMeetingWindow))
                XCTAssertFalse(tree.labelReads.contains(node))
            }
        }
    }

    func testCandidateTileDescriptionAndExplicitYouNamesRejectSelf() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[3]!.label = "Myself video, Ada Lovelace, muted"
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.selfTile))
        XCTAssertFalse(tree.labelReads.contains(4))
        tree.nodes[3]!.label = "Ada Lovelace video"
        for name in ["You", "Ada Lovelace (you)", "Ada Lovelace (You)"] {
            tree.nodes[4]!.label = name
            XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.selfTile), name)
        }
        tree.nodes[4]!.label = "Ada Lovelace"
        tree.nodes[3]!.metadata.classes.insert("self-video")
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.selfTile))
    }

    func testClassAttributeAcceptsStringAndArrayAndTreatsAbsentAsMissingMetadata() {
        XCTAssertEqual(TeamsAXMetadata.domClasses("frwhdur f578s74"), ["frwhdur", "f578s74"])
        XCTAssertEqual(TeamsAXMetadata.domClasses(["frwhdur", "f578s74"]), ["frwhdur", "f578s74"])
        XCTAssertEqual(TeamsAXMetadata.domClasses(nil), [])
        XCTAssertNil(TeamsAXMetadata.domClasses(42))
        XCTAssertNil(TeamsAXMetadata.domClasses(["frwhdur", 42] as [Any]))
    }

    func testCancellationStopsTraversalBeforeAnotherAXRead() async {
        let tree = FakeTeamsAX.meeting()
        tree.onRead = { withUnsafeCurrentTask { $0?.cancel() } }
        let snapshot = await Task.detached { TeamsAccessibility(reader: tree).snapshot() }.value
        XCTAssertEqual(snapshot.result, .unnamed(.deadline))
        XCTAssertTrue(tree.metadataReads.isEmpty)
        XCTAssertTrue(tree.labelReads.isEmpty)
    }

    func testSourceContextIsStableForOneWindowAndChangesWhenTheWindowChanges() {
        let tree = FakeTeamsAX.meeting()
        let source = TeamsAccessibility(reader: tree)
        let first = source.snapshot()
        XCTAssertEqual(first.result.speaker?.value, "Ada Lovelace")
        XCTAssertNotNil(first.sourceID)
        XCTAssertEqual(source.snapshot().sourceID, first.sourceID)
        tree.nodes[10] = tree.nodes[0]
        tree.roots = [10]
        let second = source.snapshot()
        XCTAssertEqual(second.result.speaker?.value, "Ada Lovelace")
        XCTAssertNotNil(second.sourceID)
        XCTAssertNotEqual(second.sourceID, first.sourceID)
    }

    func testSourceContextStartsAgainAfterTeamsWasNotRunning() {
        let tree = FakeTeamsAX.meeting()
        let source = TeamsAccessibility(reader: tree)
        let first = source.snapshot()
        XCTAssertNotNil(first.sourceID)
        tree.running = false
        XCTAssertEqual(source.snapshot().result, .unnamed(.noTeamsApp))
        tree.running = true
        let second = source.snapshot()
        XCTAssertNotNil(second.sourceID)
        XCTAssertNotEqual(second.sourceID, first.sourceID)
    }

    func testMarkerCannotOwnItselfAsANameOrBorrowANameThroughSmallerBounds() {
        let tree = FakeTeamsAX.meeting()
        tree.nodes[3]!.metadata.role = "AXStaticText"
        tree.nodes[3]!.children = []
        tree.nodes[3]!.label = "Ada Lovelace"
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        XCTAssertFalse(tree.labelReads.contains(3))
        tree.nodes[3]!.metadata.role = "AXGroup"
        tree.nodes[3]!.label = nil
        tree.nodes[3]!.children = [5]
        tree.nodes[5] = .init(children: [4])
        tree.nodes[5]!.metadata.bounds.size.width = 50
        XCTAssertEqual(TeamsAccessibility(reader: tree).snapshot().result, .unnamed(.unsupportedTile))
        XCTAssertFalse(tree.labelReads.contains(4))
    }
}

final class FakeTeamsAX: TeamsAXReading {
    struct Entry {
        var metadata = TeamsAXMetadata()
        var children: [Int] = []
        var label: String?
    }
    var trusted = true
    var running = true
    var roots = [0]
    var nodes: [Int: Entry] = [:]
    var labelReads: [Int] = []
    var metadataReads: [Int] = []
    var timeouts: [TimeInterval] = []
    var failing: String?
    var failure: Error = TeamsScanReason.axError(-25204)
    var onRead: (() -> Void)?
    var onLabelRead: ((Int) -> Void)?
    enum Failure: Error { case transport }
    func read(_ operation: String, timeout: TimeInterval) throws {
        timeouts.append(timeout)
        onRead?()
        if failing == operation { throw failure }
    }
    func isTrusted() -> Bool { trusted }
    func windows(timeout: TimeInterval) throws -> [Int] {
        guard running else { throw TeamsScanReason.noTeamsApp }
        try read("windows", timeout: timeout)
        return roots
    }
    func metadata(_ node: Int, timeout: TimeInterval) throws -> TeamsAXMetadata {
        try read("metadata", timeout: timeout)
        metadataReads.append(node)
        return nodes[node]!.metadata
    }
    func children(_ node: Int, timeout: TimeInterval) throws -> [Int] {
        try read("children", timeout: timeout)
        return nodes[node]!.children
    }
    func label(_ node: Int, kind: TeamsAXLabel, timeout: TimeInterval) throws -> String? {
        labelReads.append(node)
        try read("label", timeout: timeout)
        onLabelRead?(node)
        return nodes[node]!.label
    }
    static func meeting() -> FakeTeamsAX {
        let tree = FakeTeamsAX()
        tree.nodes = [
            0: Entry(metadata: TeamsAXMetadata(role: "AXWindow"), children: [1, 3]),
            1: Entry(metadata: TeamsAXMetadata(role: "AXToolbar", identifier: "meeting-controls"), children: [2]),
            2: Entry(metadata: TeamsAXMetadata(role: "AXButton"), label: "Hang up"),
            3: Entry(metadata: TeamsAXMetadata(classes: ["vdi-frame-occlusion", "frwhdur", "f578s74"]), children: [4]),
            4: Entry(metadata: TeamsAXMetadata(role: "AXStaticText"), label: "Ada Lovelace")
        ]
        return tree
    }

    static func callWithSeparateControls() -> FakeTeamsAX {
        let tree = meeting()
        tree.nodes[1]!.children = []
        tree.nodes[0]!.children.append(5)
        tree.nodes[5] = .init(children: [2], label: "Calling controls")
        tree.nodes[2]!.label = "Leave"
        return tree
    }

    /// The participant strip beside a shared screen, measured in a real call on 2026-11-16. The item is at
    /// depth 22, the highlight is its last child, and the name chip lies above a 3 px bar, outside it.
    static func shareView() -> FakeTeamsAX {
        let tree = meeting()
        let screen = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
        tree.nodes[3] = nil
        tree.nodes[4] = nil
        tree.nodes[0]!.metadata.bounds = screen
        tree.nodes[0]!.children = [1, 10]
        for node in 10...30 {
            tree.nodes[node] = .init(metadata: TeamsAXMetadata(bounds: screen), children: [node == 30 ? 40 : node + 1])
        }
        tree.nodes[40] = .init(metadata: TeamsAXMetadata(role: "AXMenuItem", bounds: box(2661, 675, 164, 123)),
                               children: [41, 42, 43, 48])
        tree.nodes[41] = .init(metadata: TeamsAXMetadata(bounds: box(2663, 677, 160, 119)))
        tree.nodes[42] = .init(metadata: TeamsAXMetadata(bounds: box(2669, 798, 140, 0)))
        tree.nodes[43] = .init(metadata: TeamsAXMetadata(bounds: box(2663, 793, 160, 3)), children: [44])
        tree.nodes[44] = .init(metadata: TeamsAXMetadata(classes: ["vdi-occlusion"], bounds: box(2671, 764, 110, 24)),
                               children: [45])
        tree.nodes[45] = .init(metadata: TeamsAXMetadata(bounds: box(2671, 764, 110, 24)), children: [46])
        tree.nodes[46] = .init(metadata: TeamsAXMetadata(bounds: box(2677, 769, 98, 14)), children: [47])
        tree.nodes[47] = .init(metadata: TeamsAXMetadata(role: "AXStaticText", bounds: box(2677, 769, 98, 14)),
                               label: "Lovelace, Ada")
        tree.nodes[48] = .init(metadata: TeamsAXMetadata(classes: ["vdi-frame-occlusion", "frwhdur", "f3ve9t9"],
                                                         bounds: box(2663, 677, 160, 119)))
        return tree
    }
}
