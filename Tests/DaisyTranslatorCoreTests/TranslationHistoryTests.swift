import Foundation
import XCTest
import DaisyTranslatorCore

final class TranslationHistoryTests: XCTestCase {
    func testHistoryKeepsAtMostFiveHundredEntries() {
        XCTAssertEqual(TranslationHistory.maximumEntryCount, 500)
    }

    func testCollapsesReplacesTheNewestEntryWhileTheSameInputKeepsGrowing() {
        let latest = makeEntry(sourceText: "Ship the release")

        let cases: [(name: String, incoming: String, expected: Bool)] = [
            (name: "typing continued past the recorded fragment", incoming: "Ship the release notes", expected: true),
            (name: "identical source is a retry of the same request", incoming: "Ship the release", expected: true),
            (name: "unrelated source starts a new entry", incoming: "Ship it tomorrow", expected: false),
            (name: "shortened source starts a new entry", incoming: "Ship the", expected: false),
            (name: "source sharing only a suffix starts a new entry", incoming: "Please ship the release", expected: false)
        ]

        for testCase in cases {
            XCTAssertEqual(
                TranslationHistory.collapses(
                    incomingSourceText: testCase.incoming,
                    provider: latest.provider,
                    targetLanguage: latest.targetLanguage,
                    into: latest,
                    now: latest.createdAt.addingTimeInterval(5)
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testCollapsesRequiresTheSameRequestShapeAndARecentEntry() {
        let latest = makeEntry(sourceText: "Ship the release", provider: .deepSeek, targetLanguage: .chinese)

        XCTAssertFalse(
            TranslationHistory.collapses(
                incomingSourceText: "Ship the release notes",
                provider: .appleSystem,
                targetLanguage: latest.targetLanguage,
                into: latest,
                now: latest.createdAt
            ),
            "a different provider is a different request"
        )
        XCTAssertFalse(
            TranslationHistory.collapses(
                incomingSourceText: "Ship the release notes",
                provider: latest.provider,
                targetLanguage: .english,
                into: latest,
                now: latest.createdAt
            ),
            "a different target language is a different request"
        )
        XCTAssertFalse(
            TranslationHistory.collapses(
                incomingSourceText: "Ship the release notes",
                provider: latest.provider,
                targetLanguage: latest.targetLanguage,
                into: latest,
                now: latest.createdAt.addingTimeInterval(TranslationHistory.collapseWindow + 1)
            ),
            "an entry older than the collapse window must be kept"
        )
        XCTAssertTrue(
            TranslationHistory.collapses(
                incomingSourceText: "Ship the release notes",
                provider: latest.provider,
                targetLanguage: latest.targetLanguage,
                into: latest,
                now: latest.createdAt.addingTimeInterval(TranslationHistory.collapseWindow)
            ),
            "the window boundary itself still collapses"
        )
    }

    func testCollapsesNeverFiresOnAnEmptyHistory() {
        XCTAssertFalse(
            TranslationHistory.collapses(
                incomingSourceText: "Ship the release",
                provider: .appleSystem,
                targetLanguage: .auto,
                into: nil
            )
        )
    }

    func testSearchPatternWrapsTheTermAndEscapesWildcards() {
        let cases: [(name: String, term: String, expected: String?)] = [
            (name: "plain term matches as a substring", term: "release", expected: "%release%"),
            (name: "surrounding whitespace is trimmed", term: "  release \n", expected: "%release%"),
            (name: "percent is matched literally", term: "100%", expected: "%100\\%%"),
            (name: "underscore is matched literally", term: "snake_case", expected: "%snake\\_case%"),
            (name: "backslash is matched literally", term: "a\\b", expected: "%a\\\\b%"),
            (name: "CJK term is untouched", term: "发布说明", expected: "%发布说明%"),
            (name: "blank term lists everything", term: "   ", expected: nil),
            (name: "empty term lists everything", term: "", expected: nil)
        ]

        for testCase in cases {
            XCTAssertEqual(TranslationHistory.searchPattern(for: testCase.term), testCase.expected, testCase.name)
        }
    }

    private func makeEntry(
        sourceText: String,
        provider: ModelProvider = .appleSystem,
        targetLanguage: TargetLanguage = .auto
    ) -> TranslationHistoryEntry {
        TranslationHistoryEntry(
            id: 1,
            sourceText: sourceText,
            translatedText: "发布版本说明",
            provider: provider,
            targetLanguage: targetLanguage,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
