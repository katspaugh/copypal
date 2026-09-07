import Cocoa

// What a clipboard entry semantically is, so the menu can format it.
enum Semantic: Equatable {
    case color(NSColor)
    case email
    case url
    case phone
    case filePath
    case shellCommand
    case uuid
    case hash
    case secret
    case plain
}

// Classifies clipboard text with cheap deterministic checks — no ML, no
// guessing. Detects CSS colors (hex, rgb(), hsl()), emails, URLs, phone
// numbers, file paths, popular unix commands, UUIDs, hex hashes, and
// secret-looking jumbles (passwords, API keys, base64 blobs); everything
// else stays plain.
enum SemanticClassifier {

    static func classify(_ text: String) -> Semantic {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = parseCSSColor(trimmed) { return .color(color) }
        if isEmail(trimmed) { return .email }
        if isURL(trimmed) { return .url }
        if isFilePath(trimmed) { return .filePath }
        if isShellCommand(trimmed) { return .shellCommand }
        if isUUID(trimmed) { return .uuid }
        if isHexHash(trimmed) { return .hash }
        if isSecret(trimmed) { return .secret }
        if isPhoneNumber(trimmed) { return .phone }
        return .plain
    }

    // MARK: - CSS colors

    static func parseCSSColor(_ text: String) -> NSColor? {
        parseHexColor(text) ?? parseFunctionalColor(text)
    }

    private static func parseHexColor(_ text: String) -> NSColor? {
        var hex = text.lowercased()
        let hashPrefixed = hex.hasPrefix("#")
        if hashPrefixed {
            hex.removeFirst()
        } else if hex.hasPrefix("0x") {
            hex.removeFirst(2)
        } else {
            return nil
        }
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        // "#1966" is far more likely a PR/issue number than an #RGBA color, so
        // the 3/4-digit shorthand must contain a hex letter or a leading zero
        // (issue numbers are all-decimal with no leading zeros). Six- and
        // eight-digit forms like #000000 are kept as-is.
        if hashPrefixed, hex.count <= 4,
           !hex.hasPrefix("0"), !hex.contains(where: \.isLetter) {
            return nil
        }
        if hex.count <= 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        if hex.count == 8 {  // CSS #RRGGBBAA
            r = CGFloat((value >> 24) & 0xff) / 255
            g = CGFloat((value >> 16) & 0xff) / 255
            b = CGFloat((value >> 8) & 0xff) / 255
            a = CGFloat(value & 0xff) / 255
        } else {
            r = CGFloat((value >> 16) & 0xff) / 255
            g = CGFloat((value >> 8) & 0xff) / 255
            b = CGFloat(value & 0xff) / 255
            a = 1
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // rgb(255, 87, 51) / rgba(255, 87, 51, 0.5) / rgb(255 87 51 / 50%)
    // hsl(14, 100%, 60%) / hsla(14deg 100% 60% / 0.5)
    private static func parseFunctionalColor(_ text: String) -> NSColor? {
        let lower = text.lowercased()
        guard lower.hasSuffix(")"), let open = lower.firstIndex(of: "(") else { return nil }
        let name = String(lower[..<open])
        guard ["rgb", "rgba", "hsl", "hsla"].contains(name) else { return nil }

        let inner = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        let parts = inner.split { ", /".contains($0) }.map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }

        // "50%" → 0.5, "128" → 128 (caller scales), "14deg" → 14
        func number(_ raw: String) -> CGFloat? {
            if raw.hasSuffix("%") { return Double(raw.dropLast()).map { CGFloat($0) / 100 } }
            let bare = raw.hasSuffix("deg") ? String(raw.dropLast(3)) : raw
            return Double(bare).map { CGFloat($0) }
        }

        var alpha: CGFloat = 1
        if parts.count == 4 {
            guard let a = number(parts[3]) else { return nil }
            alpha = min(max(a, 0), 1)
        }

        if name.hasPrefix("rgb") {
            var rgb: [CGFloat] = []
            for part in parts.prefix(3) {
                guard let value = number(part) else { return nil }
                rgb.append(part.hasSuffix("%") ? value : value / 255)
            }
            return NSColor(srgbRed: min(max(rgb[0], 0), 1),
                           green: min(max(rgb[1], 0), 1),
                           blue: min(max(rgb[2], 0), 1),
                           alpha: alpha)
        }

        guard let h = number(parts[0]), let s = number(parts[1]), let l = number(parts[2]),
              parts[1].hasSuffix("%"), parts[2].hasSuffix("%") else { return nil }
        let (r, g, b) = hslToRGB(h: h, s: min(max(s, 0), 1), l: min(max(l, 0), 1))
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    private static func hslToRGB(h: CGFloat, s: CGFloat, l: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = (1 - abs(2 * l - 1)) * s
        let hp = hue / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch hp {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    // MARK: - Emails and URLs

    private static func isEmail(_ text: String) -> Bool {
        let candidate = text.hasPrefix("mailto:") ? String(text.dropFirst(7)) : text
        guard !candidate.contains(where: \.isWhitespace),
              !candidate.contains(":"), !candidate.contains("/") else { return false }
        return candidate.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s.]{2,}$",
                               options: .regularExpression) != nil
    }

    private static func isURL(_ text: String) -> Bool {
        // Anything that starts with a URL counts, even with more words after
        // it — that also covers URLs hard-wrapped by terminals.
        let first = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? text
        return isURLToken(first)
    }

    private static func isURLToken(_ text: String) -> Bool {
        if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("ftp://") {
            return true
        }
        return text.hasPrefix("www.") && text.dropFirst(4).contains(".")
    }

    private static func isFilePath(_ text: String) -> Bool {
        guard !text.contains("\n") else { return false }
        guard text.hasPrefix("/") || text.hasPrefix("~/") else { return false }
        if !text.contains(where: \.isWhitespace) { return true }
        // Paths with spaces are only believed if they actually exist on disk.
        return FileManager.default.fileExists(atPath: NSString(string: text).expandingTildeInPath)
    }

    // Commands that are rarely English words classify on sight; ambiguous
    // ones ("find", "open", …) also need a flag or path-like argument.
    private static let strongCommands: Set<String> = [
        "git", "brew", "sudo", "curl", "wget", "ssh", "scp", "rsync", "docker",
        "kubectl", "npm", "npx", "yarn", "pnpm", "pip", "pip3", "cargo", "swiftc",
        "xcodebuild", "xcrun", "chmod", "chown", "mkdir", "grep", "sed", "awk",
        "systemctl", "apt", "apt-get", "dnf", "tmux", "ffmpeg", "cd", "ls",
        "sh", "bash", "zsh",
    ]
    private static let weakCommands: Set<String> = [
        "cat", "find", "make", "go", "node", "python", "python3", "ruby", "swift",
        "open", "echo", "export", "kill", "rm", "cp", "mv", "tar", "head", "tail",
        "top", "ps", "man", "touch", "date", "which", "env", "diff", "sort",
    ]

    private static func isShellCommand(_ text: String) -> Bool {
        guard !text.contains("\n") else { return false }
        // Allow a leading "!" — the shell-escape prefix used by Claude Code,
        // Jupyter, vim and friends ("!git status").
        var body = Substring(text)
        if body.hasPrefix("!") {
            body = body.dropFirst().drop(while: \.isWhitespace)
        }
        let tokens = body.split(separator: " ")
        guard let first = tokens.first.map(String.init) else { return false }
        if strongCommands.contains(first) { return true }
        guard tokens.count > 1, weakCommands.contains(first) else { return false }
        return tokens.dropFirst().contains {
            $0.hasPrefix("-") || $0.contains("/") || $0.hasPrefix("~")
        }
    }

    // MARK: - UUIDs, hashes, secrets

    private static func isUUID(_ text: String) -> Bool {
        text.count == 36 && UUID(uuidString: text) != nil
    }

    // MD5 (32), SHA-1 (40), SHA-256 (64), SHA-512 (128) and friends: an even
    // run of hex digits. Requiring at least one letter and one digit rules
    // out long decimal IDs and hex-only English ("deadbeef" needs a digit).
    private static func isHexHash(_ text: String) -> Bool {
        guard text.count >= 32, text.count <= 128, text.count % 2 == 0,
              text.allSatisfy(\.isHexDigit) else { return false }
        return text.contains(where: \.isNumber) && text.contains(where: \.isLetter)
    }

    // Well-known machine-generated prefixes (API keys, tokens, "eyJ" = a JWT
    // or other base64 JSON) that earn the key icon even when the jumble
    // heuristic below wouldn't fire (e.g. AWS key IDs have no lowercase).
    private static let secretPrefixes = [
        "sk-", "sk_", "pk_", "ghp_", "gho_", "github_pat_", "glpat-", "npm_",
        "xox", "AKIA", "ASIA", "AIza", "ya29.", "eyJ",
    ]

    private static func isSecret(_ text: String) -> Bool {
        if text.hasPrefix("-----BEGIN ") { return true }  // PEM key/cert block
        guard !text.contains(where: \.isWhitespace) else { return false }
        if text.count >= 20, secretPrefixes.contains(where: text.hasPrefix) { return true }
        return looksLikeGibberish(text)
    }

    private enum CharClass {
        case upper, lower, digit, symbol

        init?(_ ch: Character) {
            if ch.isUppercase { self = .upper }
            else if ch.isLowercase { self = .lower }
            else if ch.isNumber { self = .digit }
            else if "-_+/=.:~!@#$%^&*?".contains(ch) { self = .symbol }
            else { return nil }
        }
    }

    // Passwords, API keys, and base64 blobs read as a jumble: upper case,
    // lower case, and digits interleaved every couple of characters. Prose
    // and camelCase identifiers switch character class far less often, so a
    // high transition rate separates the two without a dictionary
    // ("aB3xK9mQ2rTz" ≈ 1.0, "iPhone15ProMax256GB" = 0.5, stays plain).
    private static func looksLikeGibberish(_ text: String) -> Bool {
        guard text.count >= 12, text.count <= 512 else { return false }
        var upper = 0, lower = 0, digits = 0, transitions = 0
        var previous: CharClass?
        for ch in text {
            guard let current = CharClass(ch) else { return false }
            switch current {
            case .upper: upper += 1
            case .lower: lower += 1
            case .digit: digits += 1
            case .symbol: break
            }
            if let previous, previous != current { transitions += 1 }
            previous = current
        }
        guard upper > 0, lower > 0, digits >= 2 else { return false }
        return Double(transitions) / Double(text.count - 1) >= 0.6
    }

    // MARK: - Phone numbers

    private static let phoneDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    private static func isPhoneNumber(_ text: String) -> Bool {
        // Only treat the entry as a phone number if the whole string is one
        // (with enough digits to rule out dates and short codes).
        guard text.count <= 30, text.filter(\.isNumber).count >= 7,
              let detector = phoneDetector else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else {
            return false
        }
        return match.range == range
    }
}
