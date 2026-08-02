//
//  AppDependencies.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

struct AppDependencies {
    let speechToTextEngine: any SpeechToTextEngine
    let languageEngine: any LanguageEngine
    let textToSpeechEngine: any TextToSpeechEngine
}
