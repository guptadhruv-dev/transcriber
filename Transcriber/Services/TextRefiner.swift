import Foundation

enum RefinementLevel: String, CaseIterable, Identifiable {
    case off, quick, deep
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:   return "Off"
        case .quick: return "Quick"
        case .deep:  return "Deep"
        }
    }
}

final class TextRefiner {

    private let endpoint = URL(string: "http://localhost:11434/api/generate")!
    private let model = "qwen3:8b"

    private let systemPrompt = """
    You are a professional transcription editor. Your input is raw, unformatted speech-to-text output. Your task is to produce a clean, readable, and highly accurate final transcript.

    CORE DIRECTIVES:
    - Fix Mechanics: Correct punctuation, capitalization, run-on sentences, and obvious transcription errors (e.g., wrong homophones, missing apostrophes).
    - Resolve Self-Corrections (HIGHEST PRIORITY — overrides Strict Preservation): Speakers often misspeak and immediately correct themselves using words like "sorry", "I mean", "I meant", or "actually". When this happens, silently apply the correction, remove the false start and apology, and reconstruct the full corrected sentence. If the correction is fragmentary (just a replacement word or number), inherit the surrounding grammatical context from the original phrase to form a complete sentence.
        * Example Input: "The IP address is 192, sorry, I meant 168 point..."
        * Example Output: "The IP address is 168 point..."
        * Example Input: "I'm 32 years old, sorry, 28."
        * Example Output: "I'm 28 years old."
        * Example Input: "The meeting is at 3pm, actually 4."
        * Example Output: "The meeting is at 4pm."
    - Strict Preservation: Do not paraphrase, rewrite, or alter the speaker's tone, style, or vocabulary. Only edit for clarity and correction. This rule does not apply to self-corrections covered above.
    - No Formatting or Commentary: Output absolutely nothing but the finalized text. Do not acknowledge the prompt, provide reasoning, or add notes.
    """

    func refine(_ text: String, level: RefinementLevel) async -> String {
        guard level != .off else { return text }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "prompt": text,
            "system": systemPrompt,
            "stream": false,
            "think": level == .deep,
            "keep_alive": -1,
            "options": ["temperature": 0.1]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return text }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let refined = json["response"] as? String {
                let cleaned = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? text : cleaned
            }
        } catch {
            print("[TextRefiner] refinement failed: \(error)")
        }
        return text
    }
}
