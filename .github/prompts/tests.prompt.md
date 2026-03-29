# Test Generation Prompt

You are writing tests for a SwiftUI iOS application. Follow these guidelines strictly.

## Unit Tests (Swift Testing Framework)

Use the modern Swift Testing framework, not XCTest, for unit and feature logic tests.

### Unit Test Guidelines
- Import the app module as `@testable import Make_Hay`.
- Prefer small, focused tests around domain rules, ViewModel state transitions, async orchestration, persistence edge cases, and concurrency-sensitive behavior.
- Use protocol-based mocks and keep tests entitlement-free.
- Mark tests `@MainActor` when exercising UI-facing ViewModels or other main-actor-isolated types.
- Prefer descriptive `@Test("...")` names. Use parameterized tests when they materially reduce duplication.

### ViewModel Test Template
```swift
import Foundation
import Testing
@testable import Make_Hay

@MainActor
struct FeatureNameViewModelTests {
    private let mockService: MockFeatureService
    private let sut: FeatureNameViewModel

    init() {
        mockService = MockFeatureService()
        sut = FeatureNameViewModel(featureService: mockService)
    }

    @Test("Initial state is idle")
    func initialState() {
        #expect(sut.isLoading == false)
        #expect(sut.errorMessage == nil)
    }

    @Test("Successful load updates state")
    func loadSuccess() async {
        mockService.result = .success(.fixture())

        await sut.load()

        #expect(sut.isLoading == false)
        #expect(sut.errorMessage == nil)
        #expect(mockService.loadCallCount == 1)
    }

    @Test("Failed load surfaces an error")
    func loadFailure() async {
        mockService.result = .failure(MockFeatureService.ErrorStub.failed)

        await sut.load()

        #expect(sut.isLoading == false)
        #expect(sut.errorMessage != nil)
    }
}
```

### Mock Template
```swift
import Foundation
@testable import Make_Hay

@MainActor
final class MockFeatureService: FeatureServiceProtocol {
    enum ErrorStub: Error {
        case failed
    }

    var result: Result<FeatureData, Error> = .success(.fixture())
    private(set) var loadCallCount = 0

    func load() async throws -> FeatureData {
        loadCallCount += 1
        return try result.get()
    }
}
```

## UI Tests (XCUITest)

Use XCTest for UI tests. Prefer the Robot Pattern when a screen or flow has enough interaction to justify a reusable abstraction.

### Robot Template
```swift
import XCTest

final class FeatureNameRobot {
    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    private var titleLabel: XCUIElement {
        app.staticTexts["FeatureName.title"]
    }

    private var actionButton: XCUIElement {
        app.buttons["FeatureName.actionButton"]
    }

    @discardableResult
    func assertVisible(file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 5), file: file, line: line)
        return self
    }

    @discardableResult
    func tapActionButton() -> Self {
        actionButton.tap()
        return self
    }
}
```

### UI Test Template
```swift
import XCTest

final class FeatureNameUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testFeatureFlow() {
        app.launchArguments = ["--uitesting"]
        app.launch()

        FeatureNameRobot(app: app)
            .assertVisible()
            .tapActionButton()
    }

    func testErrorState() {
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["MOCK_ERROR"] = "true"
        app.launch()

        FeatureNameRobot(app: app)
            .assertVisible()
    }
}
```

## Test Checklist

### Unit Tests
- [ ] Use `@Test` and `#expect`, not XCTest assertions, for unit tests
- [ ] Import the module as `@testable import Make_Hay`
- [ ] Use `@MainActor` when testing UI-facing ViewModels or other main-actor-isolated types
- [ ] Create protocol-based mocks for dependencies
- [ ] Test both success and failure paths
- [ ] Cover state transitions, edge cases, and persistence behavior where relevant
- [ ] Use parameterized tests when they improve clarity

### UI Tests
- [ ] Use XCTest only for UI tests
- [ ] Prefer the Robot Pattern for non-trivial screens and flows
- [ ] Use accessibility identifiers, not visible text, for element lookup
- [ ] Build launch arguments and launch environment before calling `launch()`
- [ ] Use `waitForExistence` for async UI
- [ ] Keep robot APIs small, readable, and reuse-oriented
