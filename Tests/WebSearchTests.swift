//
//  WebSearchTests.swift
//  VoicefinderTests
//
//  Reine Logik der Faktensuche: Trigger, Suchbegriffe, Passagenauswahl.
//  Fixtures stammen aus echten Wikipedia-Antworten (Messung vom 12.10.).
//

import Foundation
import Testing
@testable import Voicefinder

struct WebSearchTests {

    // MARK: - Trigger

    @Test(arguments: [
        "Wie hoch ist die Zugspitze?",
        "Was ist die Hauptstadt von Australien?",
        "Wie viele Beine hat eine Spinne?",
        "Wer war Franz Beckenbauer?",
        "Wann wurde die Berliner Mauer gebaut?",
        "Kennst du Franz Beckenbauer?",
        "Such mal im Internet, wie hoch die Zugspitze ist.",
        "Wetter in Hamburg",
    ])
    func faktenfragen_loesenDieSucheAus(_ question: String) {
        #expect(WebSearchHeuristic.shouldFetchWebContext(for: question), "\(question)")
    }

    @Test(arguments: [
        "Hallo",
        "Mir geht's gut",
        "Wie geht es dir?",
        "Wer bist du?",
        "Wie heißt du?",
        "Was machst du gerade?",
        "Welcher Wochentag ist heute?",
        "Welche Jahreszeit haben wir?",
        "Wie spät ist es?",
        "Was ist mein Lieblingsessen?",
        "Danke, das war's schon.",
        "Das ist ja interessant",
    ])
    func smalltalkUndPersoenliches_loestKeineSucheAus(_ text: String) {
        #expect(!WebSearchHeuristic.shouldFetchWebContext(for: text), "\(text)")
    }

    // MARK: - Suchbegriffe

    @Test
    func suchbegriffe_entfernenFrageUndFuellwoerter() {
        let query = WebSearchQuery.make(from: "Such mal im Internet, wie hoch die Zugspitze ist.")
        #expect(query.keywords == ["hoch", "Zugspitze"])
        #expect(query.expectsNumber)
    }

    @Test
    func suchbegriffe_hauptstadtFrage() {
        let query = WebSearchQuery.make(from: "Was ist die Hauptstadt von Australien?")
        #expect(query.keywords == ["Hauptstadt", "Australien"])
        #expect(!query.expectsNumber)
    }

    @Test
    func suchbegriffe_anzahlFrage() {
        let query = WebSearchQuery.make(from: "Wie viele Beine hat eine Spinne?")
        #expect(query.keywords == ["Beine", "Spinne"])
        #expect(query.expectsNumber)
    }

    @Test
    func suchbegriffe_kennstDuPraefix() {
        let query = WebSearchQuery.make(from: "Kennst du Franz Beckenbauer?")
        #expect(query.keywords == ["Franz", "Beckenbauer"])
    }

    // MARK: - Passagenauswahl

    private static let zugspitzePages = [
        WikipediaPage(
            title: "Liste von Todesfällen an der Zugspitze",
            index: 1,
            intro: "Dies ist eine chronologische Liste verbriefter Todesfälle an der Zugspitze, dem höchsten Berg Deutschlands. Ende des 19. Jahrhunderts begann der Tourismus.",
            snippets: []
        ),
        WikipediaPage(
            title: "Zugspitze",
            index: 2,
            intro: "Die Zugspitze ist mit 2962 m ü. NHN der höchste Gipfel des Wettersteingebirges und gleichzeitig Deutschlands höchster Berg. Sie liegt südlich von Garmisch-Partenkirchen an der Grenze zu Österreich.",
            snippets: []
        ),
    ]

    @Test
    func passage_waehltArtikelMitPassendemTitel() {
        let passage = WikipediaPassageSelector.bestPassage(
            pages: Self.zugspitzePages,
            query: WebSearchQuery.make(from: "Wie hoch ist die Zugspitze?"),
            maxCharacters: 450
        )
        #expect(passage?.contains("2962") == true)
        #expect(passage?.hasPrefix("Zugspitze:") == true)
    }

    @Test
    func passage_findetAnzahlAuchInSpaeteremSatz() {
        let pages = [
            WikipediaPage(
                title: "Nosferatu-Spinne",
                index: 1,
                intro: "Die Nosferatu-Spinne ist eine Art aus der Familie der Kräuseljagdspinnen. Sie stammt ursprünglich aus dem Mittelmeerraum.",
                snippets: []
            ),
            WikipediaPage(
                title: "Webspinnen",
                index: 2,
                intro: "Die Webspinnen sind eine Ordnung der Spinnentiere. Wie alle Spinnentiere haben sie acht Beine. Sie leben auf allen Kontinenten.",
                snippets: []
            ),
        ]
        let passage = WikipediaPassageSelector.bestPassage(
            pages: pages,
            query: WebSearchQuery.make(from: "Wie viele Beine hat eine Spinne?"),
            maxCharacters: 450
        )
        #expect(passage?.contains("acht Beine") == true)
    }

    @Test
    func passage_nutztSnippetAlsKandidat() {
        let pages = [
            WikipediaPage(
                title: "Liste der höchsten Berge in Deutschland",
                index: 1,
                intro: "Die Liste der höchsten Berge in Deutschland führt die Berge mit den höchsten Gipfeln auf.",
                snippets: ["Die höchsten Hauptgipfel Deutschlands sind Zugspitze (2962 m) und Hochwanner (2746 m)"]
            ),
        ]
        let passage = WikipediaPassageSelector.bestPassage(
            pages: pages,
            query: WebSearchQuery.make(from: "Wie hoch ist die Zugspitze?"),
            maxCharacters: 450
        )
        #expect(passage?.contains("2962") == true)
    }

    @Test
    func passage_begrenztDieLaenge() {
        let long = String(repeating: "Die Zugspitze ist ein sehr hoher Berg in Deutschland. ", count: 30)
        let passage = WikipediaPassageSelector.bestPassage(
            pages: [WikipediaPage(title: "Zugspitze", index: 1, intro: long, snippets: [])],
            query: WebSearchQuery.make(from: "Wie hoch ist die Zugspitze?"),
            maxCharacters: 300
        )
        #expect((passage?.count ?? 0) <= 300)
    }

    @Test
    func navigationszeile_wirdNichtAlsPassageGenommen() {
        let nav = "Hauptstädte der Erde Hauptstädte Australiens Hauptstädte Brasiliens Hauptstädte Deutschlands Hauptstädte Kanadas"
        #expect(WikipediaPassageSelector.looksLikeNavigationList(nav))
        #expect(!WikipediaPassageSelector.looksLikeNavigationList(
            "Die Zugspitze ist mit 2962 m ü. NHN der höchste Gipfel des Wettersteingebirges."
        ))
        #expect(!WikipediaPassageSelector.looksLikeNavigationList("Franz Anton Beckenbauer"))
    }

    @Test
    func passage_ueberspringtNavigationszeilen() {
        let pages = [
            WikipediaPage(
                title: "Hauptstadt",
                index: 1,
                intro: "Eine Hauptstadt ist ein politisches Zentrum eines Staates. Hauptstädte der Erde Hauptstädte Australiens Hauptstädte Brasiliens Hauptstädte Deutschlands Hauptstädte Kanadas",
                snippets: []
            ),
        ]
        let passage = WikipediaPassageSelector.bestPassage(
            pages: pages,
            query: WebSearchQuery.make(from: "Was ist die Hauptstadt von Australien?"),
            maxCharacters: 450
        )
        #expect(passage?.contains("Brasiliens") == false)
    }

    @Test
    func passage_ohneTreffer_istNil() {
        let passage = WikipediaPassageSelector.bestPassage(
            pages: [],
            query: WebSearchQuery.make(from: "Wie hoch ist die Zugspitze?"),
            maxCharacters: 450
        )
        #expect(passage == nil)
    }

    @Test
    func satzgrenzen_zerlegenNichtBeiZahlenUndAbkuerzungen() {
        let sentences = WikipediaPassageSelector.sentences(
            in: "Die Zugspitze ist mit 2962 m ü. NHN der höchste Gipfel. Sie liegt z. B. an der Grenze. Am 27. August 1820 wurde sie erstiegen."
        )
        #expect(sentences.count == 3)
        #expect(sentences[0].contains("ü. NHN"))
    }
}
