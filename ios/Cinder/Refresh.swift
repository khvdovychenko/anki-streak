import Foundation
import Security

/// "Refresh now": asks GitHub to run the sync workflow immediately, then reads the fresh
/// stats straight from the repository (no waiting for GitHub Pages to redeploy).
/// Needs a fine-grained GitHub token limited to this repo: Actions read/write, Contents read.
enum Refresh {
    static let repo = "khvdovychenko/anki-streak"

    enum Failure: LocalizedError {
        case noToken, rejected(Int), timedOut
        var errorDescription: String? {
            switch self {
            case .noToken: return "Add your GitHub key in Settings first."
            case .rejected(let code) where code == 401 || code == 403:
                return "GitHub rejected the key (\(code)). Check it has Actions: read and write for anki-streak."
            case .rejected(let code): return "GitHub said \(code). Try again in a minute."
            case .timedOut: return "Still running on GitHub. Pull down in a minute to see the result."
            }
        }
    }

    /// Triggers the workflow and waits until stats.json in the repo has a newer timestamp.
    static func run(after previous: String?, progress: @escaping (String) -> Void) async throws -> Stats {
        guard let token = TokenStore.token else { throw Failure.noToken }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/actions/workflows/update.yml/dispatches")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.httpBody = #"{"ref":"main"}"#.data(using: .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 204 else { throw Failure.rejected(code) }

        progress("Cinder is checking Anki…")
        let started = Date.now
        while Date.now.timeIntervalSince(started) < 240 {
            try await Task.sleep(for: .seconds(10))
            let seconds = Int(Date.now.timeIntervalSince(started))
            progress(seconds < 60 ? "Cinder is checking Anki…" : "Crunching your stats… \(seconds)s")
            if let fresh = try? await fetchFromRepo(token: token), fresh.generated_at != previous {
                return fresh
            }
        }
        throw Failure.timedOut
    }

    /// Reads docs/data/stats.json from the repository through the API (always up to date).
    static func fetchFromRepo(token: String) async throws -> Stats {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/contents/docs/data/stats.json?ref=main")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.rejected((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return try JSONDecoder().decode(Stats.self, from: data)
    }
}

/// Keeps the GitHub key in the iPhone Keychain.
enum TokenStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "cinder.github",
        kSecAttrAccount as String: "refresh-token",
    ]

    static var token: String? {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        SecItemDelete(query as CFDictionary)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
