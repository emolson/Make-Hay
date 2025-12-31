# New Feature Development Prompt

You are implementing a new feature for a SwiftUI iOS application. Follow these guidelines strictly.

## Architecture Requirements

### File Structure
Create files following Clean Architecture vertical slices:
```
Features/
  └── [FeatureName]/
      ├── Domain/
      │   ├── [Entity].swift          # Pure Swift struct, Sendable, Codable
      │   └── [UseCase].swift         # Business logic, protocol-based
      ├── Presentation/
      │   ├── [FeatureName]ViewModel.swift
      │   └── [FeatureName]View.swift
      └── Data/
          └── [FeatureName]Repository.swift
```

### ViewModel Template
```swift
import SwiftUI

@Observable
@MainActor
final class [FeatureName]ViewModel {
    // MARK: - State
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - Dependencies
    private let useCase: [UseCaseProtocol]
    
    // MARK: - Init
    init(useCase: [UseCaseProtocol]) {
        self.useCase = useCase
    }
    
    // MARK: - Actions
    func performAction() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Call use case
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### View Template
```swift
import SwiftUI

struct [FeatureName]View: View {
    @State private var viewModel: [FeatureName]ViewModel
    @EnvironmentObject private var coordinator: AppCoordinator
    
    init(viewModel: [FeatureName]ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        content
            .task { await viewModel.onAppear() }
    }
    
    @ViewBuilder
    private var content: some View {
        // UI implementation
        // .accessibilityIdentifier("[FeatureName].content")
    }
}

#Preview {
    [FeatureName]View(viewModel: .init(useCase: Mock[UseCase]()))
}
```

## Checklist Before Generating Code

1. [ ] Entity is a `struct` with `Sendable` and `Codable` conformance
2. [ ] UseCase depends on protocol, not concrete repository
3. [ ] ViewModel is `@MainActor` and uses `@Observable`
4. [ ] View contains NO business logic
5. [ ] All async operations use `async/await`
6. [ ] Navigation uses Coordinator pattern
7. [ ] `#Preview` is included with mock data
8. [ ] Colors/fonts use semantic design system names
9. [ ] Accessibility identifiers added for UI testing

## When Generating This Feature

1. First, show the Entity/Domain model
2. Then, show the UseCase protocol and implementation
3. Then, show the ViewModel
4. Finally, show the View with Preview
5. Include any necessary Coordinator updates
