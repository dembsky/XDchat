import Foundation

struct GiphyImage: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let previewUrl: URL
    let width: Int
    let height: Int
    let title: String

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

struct GiphySearchResponse: Decodable {
    let data: [GiphyGif]
    let pagination: GiphyPagination
}

struct GiphyGif: Decodable {
    let id: String
    let title: String
    let images: GiphyImages
}

struct GiphyImages: Decodable {
    let original: GiphyImageData
    let fixedWidth: GiphyImageData
    let fixedWidthSmall: GiphyImageData

    enum CodingKeys: String, CodingKey {
        case original
        case fixedWidth = "fixed_width"
        case fixedWidthSmall = "fixed_width_small"
    }
}

struct GiphyImageData: Decodable {
    let url: String
    let width: String
    let height: String
}

struct GiphyPagination: Decodable {
    let totalCount: Int
    let count: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case count
        case offset
    }
}

enum GiphyError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case noAPIKey
    case invalidAPIKey
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .noAPIKey:
            return "Giphy API key not configured. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid Giphy API key. Please get a new API key from developers.giphy.com and add it in Settings."
        case .httpError(let code):
            if code == 401 || code == 403 {
                return "Invalid Giphy API key. Please get a new API key from developers.giphy.com and add it in Settings."
            }
            return "Server error (code: \(code))"
        }
    }
}

@MainActor
class GiphyService: ObservableObject, GiphyServiceProtocol {
    static let shared = GiphyService()

    @Published var trendingGifs: [GiphyImage] = []
    @Published var searchResults: [GiphyImage] = []
    @Published var isLoading = false

    private let baseURL = "https://api.giphy.com/v1/gifs"

    private var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIPHY_API_KEY") as? String
    }

    private init() {}

    // MARK: - Trending

    func fetchTrending(limit: Int = 25, offset: Int = 0) async throws -> [GiphyImage] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GiphyError.noAPIKey
        }

        let urlString = "\(baseURL)/trending?api_key=\(apiKey)&limit=\(limit)&offset=\(offset)&rating=g"

        guard let url = URL(string: urlString) else {
            throw GiphyError.invalidURL
        }

        isLoading = true

        do {
            let images = try await performFetch(url: url)

            if offset == 0 {
                trendingGifs = images
            } else {
                trendingGifs.append(contentsOf: images)
            }

            isLoading = false
            return images
        } catch {
            isLoading = false
            throw error
        }
    }

    // MARK: - Search

    func search(query: String, limit: Int = 25, offset: Int = 0) async throws -> [GiphyImage] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GiphyError.noAPIKey
        }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/search?api_key=\(apiKey)&q=\(encodedQuery)&limit=\(limit)&offset=\(offset)&rating=g"

        guard let url = URL(string: urlString) else {
            throw GiphyError.invalidURL
        }

        isLoading = true

        do {
            let images = try await performFetch(url: url)

            if offset == 0 {
                searchResults = images
            } else {
                searchResults.append(contentsOf: images)
            }

            isLoading = false
            return images
        } catch {
            isLoading = false
            throw error
        }
    }

    // MARK: - Clear Results

    func clearSearch() {
        searchResults = []
    }

    // MARK: - Helpers

    private func performFetch(url: URL) async throws -> [GiphyImage] {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw GiphyError.httpError(httpResponse.statusCode)
                }
            }

            let giphyResponse = try JSONDecoder().decode(GiphySearchResponse.self, from: data)
            return giphyResponse.data.compactMap { mapToGiphyImage($0) }
        } catch let error as GiphyError {
            throw error
        } catch let error as DecodingError {
            throw GiphyError.decodingError(error)
        } catch {
            throw GiphyError.networkError(error)
        }
    }

    private func mapToGiphyImage(_ gif: GiphyGif) -> GiphyImage? {
        guard let originalUrl = URL(string: gif.images.original.url),
              let previewUrl = URL(string: gif.images.fixedWidth.url),
              let width = Int(gif.images.original.width),
              let height = Int(gif.images.original.height) else {
            return nil
        }

        return GiphyImage(
            id: gif.id,
            url: originalUrl,
            previewUrl: previewUrl,
            width: width,
            height: height,
            title: gif.title
        )
    }
}
