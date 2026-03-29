# New Feature Development Prompt

You are implementing a new feature for a SwiftUI iOS application. Follow these guidelines strictly.

## Architecture Requirements

### Project Structure
Fit new code into the existing project layout instead of forcing a new architecture layer.

Typical placement:
```
Make Hay/
  Features/
    [FeatureName]/
      [FeatureName]View.swift
      [FeatureName]ViewModel.swift
      [SupportingView].swift
  Models/
    [SharedModel].swift
  Services/
    [FeatureService].swift
    Protocols/
      [FeatureServiceProtocol].swift
  Mocks/
    Mock[FeatureService].swift
```

Only add new shared models, services, or protocols when the feature genuinely needs them. Do not force UseCase, Repository, or Coordinator layers for simple SwiftUI flows.

### Feature Rules
- Use MVVM with SwiftUI state-driven routing.
- Keep Views presentation-focused. No business logic, persistence, or entitlement orchestration in `body`.
- Use `@Observable` ViewModels for feature state and user intents. In this project, prefer main-actor-isolated ViewModels for UI-facing state.
- Prefer `NavigationStack`, `navigationDestination`, and enum-backed `.sheet` or `.fullScreenCover` presentation. Introduce a dedicated router or coordinator only when navigation becomes cross-feature, reusable, or deep-link-driven.
- Inject shared dependencies through custom `@Environment` keys when they are root-owned and reused broadly. Use `init` injection for leaf views and single-hop handoffs.
- Use App Group-backed persistence for data shared with extensions or background processes. Use SwiftData only for app-local data that does not cross runtime boundaries.
- The project uses modern Swift 6-era concurrency with Approachable Concurrency and MainActor-by-default settings. Mark pure helpers, parsing, formatting, and Codable plumbing `nonisolated` when appropriate.

### ViewModel Template
```swift
import Observation
import SwiftUI

@Observable
@MainActor
final class [FeatureName]ViewModel {
    // MARK: - State
    var isLoading = false
    var errorMessage: String?
    var route: Route?

    // MARK: - Dependencies
    private let featureService: any [FeatureServiceProtocol]

    init(featureService: any [FeatureServiceProtocol]) {
        self.featureService = featureService
    }

    func onAppear() async {
        guard !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch or derive feature state here.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension [FeatureName]ViewModel {
    enum Route: Identifiable {
        case detail

        var id: String {
            switch self {
            case .detail: return "detail"
            }
        }
    }
}
```

### View Template
```swift
import SwiftUI

struct [FeatureName]View: View {
    @State private var viewModel: [FeatureName]ViewModel

    init(viewModel: [FeatureName]ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(String(localized: "[Feature Name]"))
            .task {
                await viewModel.onAppear()
            }
            .sheet(item: Binding(
                get: { viewModel.route },
                set: { viewModel.route = $0 }
            )) { route in
                destination(for: route)
            }
    }

    @ViewBuilder
    private var content: some View {
        // UI implementation
        // .accessibilityIdentifier("[FeatureName].content")
    }

    @ViewBuilder
    private func destination(for route: [FeatureName]ViewModel.Route) -> some View {
        switch route {
        case .detail:
            Text("Detail")
        }
    }
}

#Preview {
    NavigationStack {
        [FeatureName]View(
            viewModel: .init(featureService: Mock[FeatureService]())
        )
    }
}
```

## Checklist Before Generating Code

1. [ ] New files fit the existing repo structure instead of forcing extra layers
2. [ ] Shared models use `struct` and conform to `Codable` and `Sendable` when appropriate
3. [ ] Dependencies are protocol-based and injected via `@Environment` or `init` as appropriate
4. [ ] ViewModel uses `@Observable` and is main-actor-isolated for UI-facing state
5. [ ] Views contain NO business logic, persistence, or entitlement orchestration
6. [ ] All async work uses `async/await` and structured concurrency
7. [ ] Navigation is state-driven; no default coordinator requirement
8. [ ] `#Preview` is included with mock data or mock environment dependencies
9. [ ] Colors, typography, and assets use the design system
10. [ ] Accessibility identifiers, labels, and traits are added where appropriate
11. [ ] Pure helpers or Codable-heavy utilities are marked `nonisolated` if they should not inherit UI isolation
12. [ ] Add or update tests for meaningful feature logic

## When Generating This Feature

1. Start by identifying which existing files and folders should own the new feature code
2. Add or update shared models and service protocols only if the feature needs them
3. Implement the ViewModel with feature state, async work, and routing state
4. Implement the View and any focused subviews with previews
5. Add routing changes only when required by the feature
6. Add or update tests for non-trivial state transitions, domain logic, and persistence behavior
