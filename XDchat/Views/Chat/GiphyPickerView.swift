import SwiftUI
import SDWebImageSwiftUI

struct GiphyPickerView: View {
    @StateObject private var giphyService = GiphyService.shared
    @State private var searchQuery = ""
    @State private var selectedCategory: GiphyCategory = .trending
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    let onSelectGif: (GiphyImage) -> Void

    enum GiphyCategory: String, CaseIterable {
        case trending = "Trending"
        case reactions = "Reactions"
        case entertainment = "Entertainment"
        case sports = "Sports"
        case stickers = "Stickers"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Search
            searchBar
                .padding(Theme.Spacing.md)

            // Category tabs
            categoryTabs
                .padding(.horizontal, Theme.Spacing.md)

            Divider()
                .padding(.top, Theme.Spacing.sm)

            // GIF Grid
            gifGrid
        }
        .frame(width: 500, height: 600)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadTrending()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.Colors.accent)

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                Image("GiphyLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 20)

                Text("GIPHY")
                    .font(Theme.Typography.headline)
                    .fontWeight(.bold)
            }

            Spacer()

            // Placeholder for symmetry
            Button("Cancel") { }
                .buttonStyle(.plain)
                .opacity(0)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search GIPHY", text: $searchQuery)
                .textFieldStyle(.plain)
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    loadTrending()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color(.textBackgroundColor))
        .cornerRadius(Theme.CornerRadius.medium)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(GiphyCategory.allCases, id: \.self) { category in
                    categoryTab(category)
                }
            }
        }
    }

    private func categoryTab(_ category: GiphyCategory) -> some View {
        Button {
            selectedCategory = category
            searchForCategory(category)
        } label: {
            Text(category.rawValue)
                .font(Theme.Typography.callout)
                .fontWeight(selectedCategory == category ? .semibold : .regular)
                .foregroundColor(selectedCategory == category ? .white : .primary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    selectedCategory == category
                        ? AnyView(Theme.messengerGradient)
                        : AnyView(Color(.textBackgroundColor))
                )
                .cornerRadius(Theme.CornerRadius.large)
        }
        .buttonStyle(.plain)
    }

    // MARK: - GIF Grid

    private var gifGrid: some View {
        ScrollView {
            if giphyService.isLoading && displayedGifs.isEmpty {
                loadingView
            } else if displayedGifs.isEmpty {
                emptyView
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 150), spacing: Theme.Spacing.sm)
                ], spacing: Theme.Spacing.sm) {
                    ForEach(displayedGifs) { gif in
                        gifCell(gif)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private func gifCell(_ gif: GiphyImage) -> some View {
        Button {
            onSelectGif(gif)
            dismiss()
        } label: {
            WebImage(url: gif.previewUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView().scaleEffect(0.7))
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("Loading GIFs...")
                .font(Theme.Typography.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: errorMessage != nil ? "exclamationmark.triangle" : "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(errorMessage != nil ? .orange : .secondary.opacity(0.5))

            if let error = errorMessage {
                Text("GIPHY Error")
                    .font(Theme.Typography.callout)
                    .foregroundColor(.secondary)

                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if error.contains("API key") {
                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Theme.Spacing.sm)
                }
            } else {
                Text("No GIFs found")
                    .font(Theme.Typography.callout)
                    .foregroundColor(.secondary)

                if !searchQuery.isEmpty {
                    Text("Try a different search term")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Helpers

    private var displayedGifs: [GiphyImage] {
        searchQuery.isEmpty ? giphyService.trendingGifs : giphyService.searchResults
    }

    private func loadTrending() {
        Task {
            do {
                errorMessage = nil
                _ = try await giphyService.fetchTrending()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.trimmed.isEmpty else {
            loadTrending()
            return
        }

        Task {
            do {
                errorMessage = nil
                _ = try await giphyService.search(query: searchQuery.trimmed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func searchForCategory(_ category: GiphyCategory) {
        switch category {
        case .trending:
            searchQuery = ""
            loadTrending()
        case .reactions:
            searchQuery = "reaction"
            performSearch()
        case .entertainment:
            searchQuery = "entertainment"
            performSearch()
        case .sports:
            searchQuery = "sports"
            performSearch()
        case .stickers:
            searchQuery = "sticker"
            performSearch()
        }
    }
}

#Preview {
    GiphyPickerView { _ in }
}
