import SwiftUI
import MarkdownUI

// MARK: - Chat markdown theme

extension Theme {
    /// Chat-friendly markdown theme based on .gitHub but with fully adaptive
    /// colors. The stock .gitHub theme hard-codes near-black backgrounds for
    /// text (#18191D) and inline code (#25262A) in dark mode, which appear as
    /// solid dark boxes inside chat bubbles. We override all three affected
    /// element types to use system-adaptive semi-transparent colors instead.
    static let chat = Theme.gitHub
        // Remove the hardcoded #18191D dark-mode document background.
        .text {
            BackgroundColor(.clear)
        }
        // Replace the hardcoded #25262A inline-code background with an adaptive tint.
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            BackgroundColor(Color.secondary.opacity(0.15))
        }
        // Replace the hardcoded secondaryBackground code-block color and add copy button.
        .codeBlock { config in
            ZStack(alignment: .topTrailing) {
                ScrollView(.horizontal) {
                    config.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                        .padding(.top, 32)   // reserve space under copy button
                        .padding(.leading, 12)
                        .padding([.trailing, .bottom], 12)
                }
                CopyCodeButton(code: config.content)
                    .padding(6)
            }
            .background(Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
}

// MARK: - Copy button

/// Small clipboard button shown in the top-right corner of each code block.
/// Animates to a checkmark for 1.5 s after the user copies.
struct CopyCodeButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = code
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            #endif
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
                .foregroundStyle(copied ? .green : .secondary)
                .frame(width: 22, height: 22)
                .glassEffect(.clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Copy code")
    }
}

/// A `CodeSyntaxHighlighter` for MarkdownUI that provides basic token-level coloring
/// (keywords, strings, comments, numbers) for the languages Claude commonly outputs.
/// No external dependencies — uses NSRegularExpression for tokenization.
struct AppCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    static let shared = AppCodeSyntaxHighlighter()

    func highlightCode(_ code: String, language: String?) -> Text {
        let lang = language?.lowercased()
        let tokens = tokenize(code, language: lang)
        return tokens.reduce(Text("")) { result, token in
            let t = Text(token.text)
            switch token.kind {
            case .keyword: return result + t.foregroundColor(Color.blue)
            case .string:  return result + t.foregroundColor(Color(red: 0.76, green: 0.13, blue: 0.28))
            case .comment: return result + t.foregroundColor(Color(red: 0.40, green: 0.55, blue: 0.40))
            case .number:  return result + t.foregroundColor(Color.purple)
            case .plain:   return result + t
            }
        }
    }

    // MARK: - Token types

    private enum Kind { case plain, keyword, string, comment, number }
    private struct Tok { let text: String; let kind: Kind }

    // MARK: - Tokenizer

    private func tokenize(_ code: String, language: String?) -> [Tok] {
        let nsCode = code as NSString
        let length = nsCode.length
        var pos = 0
        var tokens: [Tok] = []
        var pendingPlain = ""

        let patterns: [(NSRegularExpression, Kind)] = buildPatterns(language: language)

        func flushPlain() {
            if !pendingPlain.isEmpty {
                tokens.append(Tok(text: pendingPlain, kind: .plain))
                pendingPlain = ""
            }
        }

        while pos < length {
            var best: (NSRange, Kind)?
            for (regex, kind) in patterns {
                let searchRange = NSRange(location: pos, length: length - pos)
                if let m = regex.firstMatch(in: code, range: searchRange),
                   m.range.location == pos,
                   m.range.length > 0 {
                    if best == nil || m.range.length > best!.0.length {
                        best = (m.range, kind)
                    }
                }
            }
            if let (range, kind) = best {
                flushPlain()
                tokens.append(Tok(text: nsCode.substring(with: range), kind: kind))
                pos += range.length
            } else {
                pendingPlain += nsCode.substring(with: NSRange(location: pos, length: 1))
                pos += 1
            }
        }
        flushPlain()
        return tokens
    }

    // MARK: - Pattern builders

    private func buildPatterns(language: String?) -> [(NSRegularExpression, Kind)] {
        var result: [(NSRegularExpression, Kind)] = []

        // Block comments (C-style) — before line comments so /* isn't eaten by //
        if let r = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: .dotMatchesLineSeparators) {
            result.append((r, .comment))
        }

        // Line comments — language-specific prefix
        let lineCommentStart: String
        switch language {
        case "python", "py", "ruby", "rb", "bash", "sh", "shell", "zsh", "yaml", "yml":
            lineCommentStart = "#"
        case "sql":
            lineCommentStart = "--"
        case "lua":
            lineCommentStart = "--"
        default:
            lineCommentStart = "//"
        }
        if let r = try? NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: lineCommentStart) + "[^\n]*"
        ) {
            result.append((r, .comment))
        }

        // Strings (double-quoted, single-quoted, backtick template literals)
        if let r = try? NSRegularExpression(
            pattern: #"("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)"#,
            options: .dotMatchesLineSeparators
        ) {
            result.append((r, .string))
        }

        // Numbers (hex, binary, octal, decimal/float/scientific)
        if let r = try? NSRegularExpression(
            pattern: #"\b(0x[0-9A-Fa-f][0-9A-Fa-f_]*|0b[01][01_]*|0o[0-7][0-7_]*|\d[\d_]*\.?\d*(?:[eE][+-]?\d+)?)\b"#
        ) {
            result.append((r, .number))
        }

        // Keywords
        let kw = keywords(for: language)
        if !kw.isEmpty {
            // Sort longer keywords first so `instanceof` beats `in`
            let sorted = kw.sorted { $0.count > $1.count }.joined(separator: "|")
            if let r = try? NSRegularExpression(pattern: "\\b(?:\(sorted))\\b") {
                result.append((r, .keyword))
            }
        }

        return result
    }

    // MARK: - Keyword sets

    // swiftlint:disable function_body_length
    private func keywords(for language: String?) -> [String] {
        switch language {
        case "swift":
            return [
                "class", "struct", "enum", "func", "var", "let", "if", "else", "guard", "return",
                "for", "while", "do", "try", "catch", "throw", "throws", "async", "await", "import",
                "public", "private", "internal", "fileprivate", "open", "static", "final", "override",
                "init", "deinit", "extension", "protocol", "typealias", "where", "in", "switch",
                "case", "default", "break", "continue", "true", "false", "nil", "self", "Self",
                "super", "any", "some", "weak", "unowned", "lazy", "mutating", "nonmutating",
                "inout", "willSet", "didSet", "get", "set",
            ]
        case "typescript", "ts", "tsx":
            return [
                "const", "let", "var", "function", "class", "interface", "type", "enum",
                "import", "export", "from", "return", "if", "else", "for", "while", "do",
                "switch", "case", "default", "break", "continue", "try", "catch", "throw",
                "async", "await", "new", "this", "extends", "implements", "public", "private",
                "protected", "static", "readonly", "typeof", "instanceof", "in", "of",
                "true", "false", "null", "undefined", "void", "never", "any", "string",
                "number", "boolean", "object", "as", "satisfies", "keyof", "infer", "declare",
            ]
        case "javascript", "js", "jsx":
            return [
                "const", "let", "var", "function", "class", "return", "if", "else", "for",
                "while", "do", "switch", "case", "default", "break", "continue", "try",
                "catch", "throw", "async", "await", "new", "this", "extends", "typeof",
                "instanceof", "in", "of", "true", "false", "null", "undefined", "void",
                "import", "export", "from", "as", "delete",
            ]
        case "python", "py":
            return [
                "def", "class", "import", "from", "return", "if", "elif", "else", "for",
                "while", "with", "as", "try", "except", "finally", "raise", "pass", "break",
                "continue", "lambda", "yield", "async", "await", "True", "False", "None",
                "and", "or", "not", "in", "is", "global", "nonlocal", "del", "assert",
            ]
        case "bash", "sh", "shell", "zsh":
            return [
                "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
                "esac", "function", "return", "export", "local", "readonly", "echo", "exit",
                "source", "alias", "unset", "true", "false",
            ]
        case "go":
            return [
                "func", "var", "const", "type", "struct", "interface", "map", "chan", "go",
                "select", "case", "default", "switch", "for", "range", "if", "else", "return",
                "break", "continue", "import", "package", "defer", "true", "false", "nil",
                "int", "int64", "int32", "string", "bool", "error", "byte", "rune",
            ]
        case "rust", "rs":
            return [
                "fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "for", "while",
                "loop", "if", "else", "match", "return", "use", "mod", "pub", "crate",
                "super", "self", "Self", "type", "where", "async", "await", "move", "ref",
                "true", "false", "None", "Some", "Ok", "Err",
            ]
        case "php":
            return [
                "function", "class", "if", "else", "elseif", "for", "foreach", "while", "do",
                "return", "echo", "print", "var", "const", "public", "private", "protected",
                "static", "abstract", "final", "interface", "extends", "implements", "use",
                "namespace", "new", "true", "false", "null", "array", "try", "catch", "throw",
                "switch", "case", "default", "break",
            ]
        case "java":
            return [
                "class", "interface", "if", "else", "for", "while", "do", "return", "switch",
                "case", "break", "continue", "import", "package", "public", "private", "protected",
                "static", "final", "abstract", "null", "true", "false", "this", "super", "new",
                "try", "catch", "throw", "throws", "extends", "implements", "void", "int", "long",
                "double", "float", "boolean", "char", "byte", "short", "String",
            ]
        case "kotlin", "kt":
            return [
                "class", "interface", "fun", "val", "var", "if", "else", "for", "while", "do",
                "return", "when", "switch", "case", "break", "continue", "import", "package",
                "public", "private", "protected", "override", "null", "true", "false", "this",
                "super", "object", "companion", "data", "sealed", "open", "suspend", "inline",
                "try", "catch", "throw", "as", "is", "in", "out", "by", "init",
            ]
        case "sql":
            return [
                "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL",
                "ON", "GROUP", "BY", "ORDER", "HAVING", "INSERT", "INTO", "VALUES", "UPDATE",
                "SET", "DELETE", "CREATE", "TABLE", "INDEX", "DROP", "ALTER", "ADD", "COLUMN",
                "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "NULL", "NOT", "AND", "OR", "IN",
                "LIKE", "BETWEEN", "EXISTS", "DISTINCT", "AS", "WITH", "UNION", "ALL",
                "LIMIT", "OFFSET", "RETURNING", "CASCADE", "DEFAULT", "UNIQUE", "CHECK",
            ]
        case "css":
            return [
                "important", "inherit", "initial", "unset", "none", "auto", "normal",
                "flex", "grid", "block", "inline", "absolute", "relative", "fixed", "sticky",
            ]
        default:
            // Generic fallback covers most C-like and scripting languages
            return [
                "if", "else", "for", "while", "do", "return", "function", "class", "import",
                "export", "const", "let", "var", "true", "false", "null", "nil", "undefined",
                "new", "this", "self", "try", "catch", "throw", "async", "await", "switch",
                "case", "default", "break", "continue", "and", "or", "not", "in", "is",
            ]
        }
    }
}
