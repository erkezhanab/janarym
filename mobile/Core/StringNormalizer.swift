import Foundation

enum StringNormalizer {

    static func normalize(_ input: String) -> String {
        var s = input.lowercased()
        // Remove punctuation, keep letters and digits
        s = s.unicodeScalars
            .filter { CharacterSet.letters.union(.decimalDigits).union(.whitespaces).contains($0) }
            .map { String($0) }
            .joined()
        // Collapse spaces
        return s.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Tolerant check for wake word "жанарым" across kk/ru/en recognition engines.
    static func containsWakeWord(_ text: String) -> Bool {
        let n = normalize(text)

        // 1. Exact substring match — "жанар" тізбегі кез-келген жерде болса жеткілікті
        //    (ru-RU "Жанр Жанар", "Жанар", "Жана Жанар" сияқты нұсқалар)
        let corePatterns = [
            "жанарым", "жанарим", "жанары", "жанар",
            "джанарым", "джанарим", "джанары", "джанар",
            "жанрым", "жанарм",
        ]
        for p in corePatterns where n.contains(p) { return true }

        // 2. ru-RU ASR splits "Жанарым" → "Жанры я" / "Жанна" / etc.
        let splitPatterns = [
            "жанры я", "жанры м", "жанры им", "жанры ым",
            "джанры я", "джанры м",
            "жанна р", "жанна",  // ru-RU вариант
        ]
        for p in splitPatterns where n.contains(p) { return true }

        // 3. Latin phonetic — en-US engine
        let latin = [
            "janarym", "zhanarym", "zhanarim", "janarim",
            "janary",  "zhanary",  "shanarym", "zanarym",
            "janareem","zanarim",  "yanarim",  "janaram",
            "zanaram", "jhanary",  "janaree",  "janar",
            "zhanar",
        ]
        for w in latin where n.contains(w) { return true }

        return false
    }

    /// Wake word жоқта тікелей режим командасын анықтайды.
    /// Мысалы: "навигация", "сауда режімі", "чтение" → modeKey қайтарады.
    static func detectModeKey(_ text: String) -> String? {
        let n = normalize(text)
        let pairs: [(String, [String])] = [
            ("navigation", ["навигация режімі", "навигация режим", "навигация", "режим навигации"]),
            ("security",   ["қауіпсіздік режімі", "қауіпсіздік режим", "қауіпсіздік",
                            "антискам", "режим безопасности", "antiscam"]),
            ("shopping",   ["сауда режімі", "сауда режим", "сауда",
                            "покупки режим", "режим покупок"]),
            ("reading",    ["мәтін оқу режімі", "мәтін оқу", "оқу режімі", "оқу режим",
                            "режим чтения", "чтение"]),
            ("arglasses",  ["ar режімі", "ar режимі", "ar режим", "ar көзілдірік",
                            "көзілдірік режімі", "көзілдірік режимі",
                            "ar очки", "режим ar очков"]),
            ("general",    ["жалпы режімі", "жалпы режим", "жалпы", "общий режим", "general mode"]),
            ("agent",      ["агент режімі", "агент режим", "агент", "режим агента", "agent mode"]),
        ]
        for (key, keywords) in pairs {
            if keywords.contains(where: { n.contains($0) }) { return key }
        }
        return nil
    }
}
