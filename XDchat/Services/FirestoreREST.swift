import Foundation

/// Firestore REST API client - uses ID token from REST auth
final class FirestoreREST {
    static let shared = FirestoreREST()

    private let projectId: String
    private let session: URLSession

    private init() {
        // Get project ID from GoogleService-Info.plist
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let id = plist["PROJECT_ID"] as? String else {
            fatalError("Missing PROJECT_ID in GoogleService-Info.plist")
        }
        self.projectId = id

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Get Document

    func getDocument(collection: String, documentId: String, idToken: String) async throws -> [String: Any]? {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)/\(documentId)"

        guard let url = URL(string: urlString) else {
            throw FirestoreError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil // Document doesn't exist
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FirestoreError.serverError(message)
            }
            throw FirestoreError.serverError("Status: \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any] else {
            throw FirestoreError.parseError
        }

        return parseFirestoreFields(fields)
    }

    // MARK: - Update Document

    func updateDocument(collection: String, documentId: String, fields: [String: Any], idToken: String) async throws {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)/\(documentId)"

        guard let url = URL(string: urlString) else {
            throw FirestoreError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let firestoreFields = convertToFirestoreFields(fields)
        let body: [String: Any] = ["fields": firestoreFields]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FirestoreError.serverError(message)
            }
            throw FirestoreError.serverError("Status: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Parse Firestore Format

    private func parseFirestoreFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in fields {
            guard let valueDict = value as? [String: Any] else { continue }

            if let stringValue = valueDict["stringValue"] as? String {
                result[key] = stringValue
            } else if let boolValue = valueDict["booleanValue"] as? Bool {
                result[key] = boolValue
            } else if let intValue = valueDict["integerValue"] as? String {
                result[key] = Int(intValue) ?? 0
            } else if let doubleValue = valueDict["doubleValue"] as? Double {
                result[key] = doubleValue
            } else if let timestampValue = valueDict["timestampValue"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                result[key] = formatter.date(from: timestampValue) ?? Date()
            } else if valueDict["nullValue"] != nil {
                result[key] = NSNull()
            } else if let arrayValue = valueDict["arrayValue"] as? [String: Any],
                      let values = arrayValue["values"] as? [[String: Any]] {
                // Parse array of strings
                let stringArray = values.compactMap { $0["stringValue"] as? String }
                result[key] = stringArray
            }
        }

        return result
    }

    private func convertToFirestoreFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in fields {
            if let stringValue = value as? String {
                result[key] = ["stringValue": stringValue]
            } else if let boolValue = value as? Bool {
                result[key] = ["booleanValue": boolValue]
            } else if let intValue = value as? Int {
                result[key] = ["integerValue": String(intValue)]
            } else if let doubleValue = value as? Double {
                result[key] = ["doubleValue": doubleValue]
            } else if let dateValue = value as? Date {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                result[key] = ["timestampValue": formatter.string(from: dateValue)]
            } else if let arrayValue = value as? [String] {
                let arrayItems = arrayValue.map { ["stringValue": $0] }
                result[key] = ["arrayValue": ["values": arrayItems]]
            }
        }

        return result
    }

    // MARK: - List Documents (for getting all users)

    func listDocuments(collection: String, idToken: String, limit: Int = 50) async throws -> [[String: Any]] {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)?pageSize=\(limit)"

        print("[FirestoreREST] Listing documents from: \(collection)")

        guard let url = URL(string: urlString) else {
            throw FirestoreError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreError.invalidResponse
        }

        print("[FirestoreREST] Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseStr = String(data: data, encoding: .utf8) {
                print("[FirestoreREST] Error response: \(responseStr)")
            }
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FirestoreError.serverError(message)
            }
            throw FirestoreError.serverError("Status: \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documents = json["documents"] as? [[String: Any]] else {
            print("[FirestoreREST] No documents found in response")
            return []
        }

        print("[FirestoreREST] Found \(documents.count) documents")

        return documents.compactMap { doc -> [String: Any]? in
            guard let fields = doc["fields"] as? [String: Any],
                  let name = doc["name"] as? String else { return nil }

            // Extract document ID from name path
            let docId = name.components(separatedBy: "/").last ?? ""

            var parsed = parseFirestoreFields(fields)
            parsed["id"] = docId
            return parsed
        }
    }

    // MARK: - Query Documents (for finding existing conversation)

    func queryDocuments(collection: String, field: String, values: [String], idToken: String) async throws -> [[String: Any]] {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents:runQuery"

        guard let url = URL(string: urlString) else {
            throw FirestoreError.invalidURL
        }

        // Build structured query for array equality
        let arrayValues = values.map { ["stringValue": $0] }
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": collection]],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": field],
                        "op": "EQUAL",
                        "value": ["arrayValue": ["values": arrayValues]]
                    ]
                ],
                "limit": 1
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: query)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let responseStr = String(data: data, encoding: .utf8) {
                print("[FirestoreREST] Query error: \(responseStr)")
            }
            throw FirestoreError.serverError("Query failed: \(httpResponse.statusCode)")
        }

        guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return results.compactMap { result -> [String: Any]? in
            guard let document = result["document"] as? [String: Any],
                  let fields = document["fields"] as? [String: Any],
                  let name = document["name"] as? String else { return nil }

            let docId = name.components(separatedBy: "/").last ?? ""
            var parsed = parseFirestoreFields(fields)
            parsed["id"] = docId
            return parsed
        }
    }

    // MARK: - Create Document

    func createDocument(collection: String, documentId: String?, fields: [String: Any], idToken: String) async throws -> String {
        var urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)"
        if let docId = documentId {
            urlString += "?documentId=\(docId)"
        }

        guard let url = URL(string: urlString) else {
            throw FirestoreError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let firestoreFields = convertToFirestoreFields(fields)
        let body: [String: Any] = ["fields": firestoreFields]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FirestoreError.serverError(message)
            }
            throw FirestoreError.serverError("Status: \(httpResponse.statusCode)")
        }

        // Return document ID
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String {
            return name.components(separatedBy: "/").last ?? ""
        }

        return documentId ?? ""
    }

    // MARK: - Errors

    enum FirestoreError: LocalizedError {
        case invalidURL
        case invalidResponse
        case parseError
        case serverError(String)
        case notAuthenticated
        case tokenExpired

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Firestore URL"
            case .invalidResponse:
                return "Invalid response from Firestore"
            case .parseError:
                return "Failed to parse Firestore response"
            case .serverError(let message):
                return "Firestore error: \(message)"
            case .notAuthenticated:
                return "Not authenticated. Please log in again."
            case .tokenExpired:
                return "Session expired. Please log in again."
            }
        }
    }
}
