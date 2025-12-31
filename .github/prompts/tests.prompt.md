# Test Generation Prompt

You are writing tests for a SwiftUI iOS application. Follow these guidelines strictly.

## Unit Tests (Swift Testing Framework)

Use the modern Swift Testing framework, NOT XCTest for unit tests.

### ViewModel Test Template
```swift
import Testing
@testable import MakeHay

@Suite("FeatureName ViewModel Tests")
@MainActor
struct FeatureNameViewModelTests {
    
    // MARK: - Properties
    let mockUseCase: MockUseCaseProtocol
    let sut: FeatureNameViewModel
    
    // MARK: - Setup
    init() {
        mockUseCase = MockUseCaseProtocol()
        sut = FeatureNameViewModel(useCase: mockUseCase)
    }
    
    // MARK: - Tests
    @Test("Initial state is correct")
    func initialState() {
        #expect(sut.isLoading == false)
        #expect(sut.errorMessage == nil)
    }
    
    @Test("Loading state updates correctly")
    func loadingState() async {
        // Given
        mockUseCase.result = .success(expectedData)
        
        // When
        await sut.loadData()
        
        // Then
        #expect(sut.isLoading == false)
        #expect(sut.data == expectedData)
    }
    
    @Test("Error handling works correctly")
    func errorHandling() async {
        // Given
        mockUseCase.result = .failure(TestError.networkError)
        
        // When
        await sut.loadData()
        
        // Then
        #expect(sut.errorMessage != nil)
    }
    
    @Test(.tags(.critical), arguments: [1, 2, 3])
    func parameterizedTest(value: Int) {
        #expect(value > 0)
    }
}
```

### Mock Generation Template
```swift
@MainActor
final class MockUseCaseProtocol: UseCaseProtocol {
    var result: Result<DataType, Error> = .success(DataType())
    var executeCallCount = 0
    
    func execute() async throws -> DataType {
        executeCallCount += 1
        return try result.get()
    }
}
```

## UI Tests (XCUITest with Robot Pattern)

Use XCTest for UI tests with the Robot Pattern for maintainability.

### Robot Template
```swift
import XCTest

final class FeatureNameRobot {
    private let app: XCUIApplication
    
    init(_ app: XCUIApplication) {
        self.app = app
    }
    
    // MARK: - Element References
    private var titleLabel: XCUIElement {
        app.staticTexts["feature-title"]
    }
    
    private var actionButton: XCUIElement {
        app.buttons["action-button"]
    }
    
    private var textField: XCUIElement {
        app.textFields["input-field"]
    }
    
    // MARK: - Actions
    @discardableResult
    func verifyScreenIsVisible() -> Self {
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 5))
        return self
    }
    
    @discardableResult
    func enterText(_ text: String) -> Self {
        textField.tap()
        textField.typeText(text)
        return self
    }
    
    @discardableResult
    func tapActionButton() -> NextScreenRobot {
        actionButton.tap()
        return NextScreenRobot(app)
    }
    
    // MARK: - Assertions
    @discardableResult
    func verifyTitle(_ expectedTitle: String) -> Self {
        XCTAssertEqual(titleLabel.label, expectedTitle)
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
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testFeatureFlow() {
        FeatureNameRobot(app)
            .verifyScreenIsVisible()
            .enterText("Test Input")
            .tapActionButton()
            .verifyNextScreenVisible()
    }
    
    func testErrorState() {
        // Configure app to show error state
        app.launchEnvironment["MOCK_ERROR"] = "true"
        app.launch()
        
        FeatureNameRobot(app)
            .verifyScreenIsVisible()
            .tapActionButton()
            .verifyErrorMessageVisible()
    }
}
```

## Test Checklist

### Unit Tests
- [ ] Use `@Test` macro, not `func test...()`
- [ ] Use `#expect()` for assertions, not `XCTAssert`
- [ ] Use `@Suite` for grouping related tests
- [ ] Use `@MainActor` for ViewModel tests
- [ ] Create protocol-based mocks for dependencies
- [ ] Test both success and error paths
- [ ] Use parameterized tests where applicable

### UI Tests
- [ ] Implement Robot Pattern for each screen
- [ ] Use accessibility identifiers, not text matching
- [ ] Robots return `Self` or next Robot for fluent API
- [ ] Keep assertions in test methods, not Robots
- [ ] Use `waitForExistence` for async elements
- [ ] Set up proper test data via launch arguments/environment
