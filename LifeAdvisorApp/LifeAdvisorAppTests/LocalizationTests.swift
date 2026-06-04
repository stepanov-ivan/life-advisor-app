import XCTest
@testable import LifeAdvisorApp

@MainActor
final class LocalizationTests: XCTestCase {
    private var originalOverride: String?

    override func setUp() {
        super.setUp()
        originalOverride = UserDefaults.standard.string(forKey: AppLanguageManager.overrideKey)
    }

    override func tearDown() {
        if let originalOverride {
            UserDefaults.standard.set(originalOverride, forKey: AppLanguageManager.overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguageManager.overrideKey)
        }
        super.tearDown()
    }

    func testLocalizableHasMatchingRuAndEnKeys() throws {
        try assertSameKeys(tableName: "Localizable")
    }

    func testRulesHasMatchingRuAndEnKeys() throws {
        try assertSameKeys(tableName: "Rules")
    }

    func testPromptsHasMatchingRuAndEnKeys() throws {
        try assertSameKeys(tableName: "Prompts")
    }

    func testExplicitEnglishOverrideWins() {
        UserDefaults.standard.set(AppLanguage.en.rawValue, forKey: AppLanguageManager.overrideKey)
        XCTAssertEqual(AppLanguageManager.currentEffectiveLanguage, .en)
    }

    func testExplicitRussianOverrideWins() {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguageManager.overrideKey)
        XCTAssertEqual(AppLanguageManager.currentEffectiveLanguage, .ru)
    }

    func testSystemOverrideResolvesToConcreteLanguage() {
        UserDefaults.standard.set(AppLanguage.system.rawValue, forKey: AppLanguageManager.overrideKey)
        XCTAssertNotEqual(AppLanguageManager.currentEffectiveLanguage, .system)
    }

    func testSetOverridePersistsSelection() {
        AppLanguageManager.shared.setOverride(.en)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppLanguageManager.overrideKey), AppLanguage.en.rawValue)
        XCTAssertEqual(AppLanguageManager.shared.override, .en)
    }

    private func assertSameKeys(tableName: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let ru = try loadStrings(language: "ru", tableName: tableName)
        let en = try loadStrings(language: "en", tableName: tableName)

        let ruKeys = Set(ru.keys)
        let enKeys = Set(en.keys)

        XCTAssertEqual(ruKeys, enKeys, "Mismatched keys in \(tableName)", file: file, line: line)
    }

    private func loadStrings(language: String, tableName: String) throws -> [String: String] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = repoRoot
            .appendingPathComponent("LifeAdvisorApp")
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(language).lproj")
            .appendingPathComponent("\(tableName).strings")

        guard let dict = NSDictionary(contentsOf: fileURL) as? [String: String] else {
            XCTFail("Unable to load strings file at \(fileURL.path)")
            return [:]
        }
        return dict
    }
}
