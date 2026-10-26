import Foundation

/// Modern Hangul composition from compatibility jamo. No prediction or network.
public enum HangulComposer {
    public static let initials = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".map(String.init)
    public static let vowels = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ".map(String.init)
    public static let finals = [""] + "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ".map(String.init)
    public static let finalJoins = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"
    ]
    public static let split = Dictionary(uniqueKeysWithValues: finalJoins.map { ($0.value, $0.key.map(String.init)) })

    public static func syllable(_ initial: String, _ vowel: String, _ final: String = "") -> String {
        guard let l = initials.firstIndex(of: initial), let v = vowels.firstIndex(of: vowel),
              let t = finals.firstIndex(of: final), let scalar = UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t) else {
            return initial + vowel + final
        }
        return String(scalar)
    }

    public static func decompose(_ value: String) -> [String]? {
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first,
              scalar.value >= 0xAC00, scalar.value <= 0xD7A3 else { return nil }
        let n = Int(scalar.value) - 0xAC00
        let tail = finals[n % 28]
        return [initials[n / 588], vowels[(n / 28) % 21]] + (tail.isEmpty ? [] : split[tail] ?? [tail])
    }

    public static func compose(_ components: [String]) -> String {
        var output = "", initial = "", vowel = "", final = ""
        func flush() {
            output += initial.isEmpty ? vowel : (vowel.isEmpty ? initial : syllable(initial, vowel, final))
            initial = ""; vowel = ""; final = ""
        }
        for component in components {
            if initials.contains(component) {
                if initial.isEmpty {
                    if !vowel.isEmpty { flush() }
                    initial = component
                } else if vowel.isEmpty {
                    flush(); initial = component
                } else if final.isEmpty && finals.contains(component) {
                    final = component
                } else if let joined = finalJoins[final + component], !final.isEmpty {
                    final = joined
                } else {
                    flush(); initial = component
                }
            } else if vowels.contains(component) {
                if initial.isEmpty {
                    if let joined = ThreePadMapping.joins[vowel + component], !vowel.isEmpty {
                        vowel = joined
                    } else {
                        if !vowel.isEmpty { flush() }
                        vowel = component
                    }
                } else if vowel.isEmpty {
                    vowel = component
                } else if !final.isEmpty {
                    if let pair = split[final] {
                        output += syllable(initial, vowel, pair[0])
                        initial = pair[1]
                    } else {
                        output += syllable(initial, vowel)
                        initial = final
                    }
                    vowel = component; final = ""
                } else if let joined = ThreePadMapping.joins[vowel + component] {
                    vowel = joined
                } else {
                    flush(); vowel = component
                }
            } else {
                flush(); output += component
            }
        }
        flush()
        return output
    }
}
