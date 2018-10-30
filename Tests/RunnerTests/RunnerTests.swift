import EventBus
import Extensions
import fbxctest
import Foundation
import Models
import TempFolder
import TestingFakeFbxctest
import ResourceLocationResolver
import Runner
import ScheduleStrategy
import SimulatorPool
import XCTest


public final class RunnerTests: XCTestCase {
    
    let shimulator = Shimulator.shimulator(testDestination: try! TestDestination(deviceType: "iPhone SE", iOSVersion: "11.4"))
    let testClassName = "ClassName"
    let testMethod = "testMethod"
    var tempFolder: TempFolder!
    let testExceptionEvent = TestExceptionEvent(reason: "a reason", filePathInProject: "file", lineNumber: 12)
    
    public override func setUp() {
        XCTAssertNoThrow(try FakeFbxctestExecutableProducer.eraseFakeOutputEvents())
        XCTAssertNoThrow(tempFolder = try TempFolder())
    }
    
    func testRunningTestWithoutAnyFeedbackEventsGivesFailureResults() throws {
        // do not stub, simulating a crash/silent exit
        
        let testEntry = TestEntry(className: testClassName, methodName: testMethod, caseId: nil)
        let results = try runTestEntries([testEntry])
        
        XCTAssertEqual(results.count, 1)
        let testResult = results[0]
        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
        XCTAssertEqual(testResult.testRunResults[0].exceptions[0].reason, RunnerConstants.testDidNotRun.rawValue)
    }

    func testRunningSuccessfulTestGivesPositiveResults() throws {
        try stubFbxctestEvent(success: true)
        
        let testEntry = TestEntry(className: testClassName, methodName: testMethod, caseId: nil)
        let results = try runTestEntries([testEntry])
        
        XCTAssertEqual(results.count, 1)
        let testResult = results[0]
        XCTAssertTrue(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
    }
    
    func testRunningFailedTestGivesNegativeResults() throws {
        try stubFbxctestEvent(success: false)
        
        let testEntry = TestEntry(className: testClassName, methodName: testMethod, caseId: nil)
        let results = try runTestEntries([testEntry])
        
        XCTAssertEqual(results.count, 1)
        let testResult = results[0]
        XCTAssertFalse(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
        XCTAssertEqual(
            testResult.testRunResults[0].exceptions,
            [TestException(reason: "a reason", filePathInProject: "file", lineNumber: 12)])
    }
    
    func testRunningCrashedTestRevivesItAndIfTestSuccedsReturnsPositiveResults() throws {
        try FakeFbxctestExecutableProducer.setFakeOutputEvents(runIndex: 0, [
            AnyEncodableWrapper(
                TestStartedEvent(
                    test: "\(testClassName)/\(testMethod)",
                    className: testClassName,
                    methodName: testMethod,
                    timestamp: Date().timeIntervalSince1970)),
            ])
        try stubFbxctestEvent(success: true, runIndex: 1)
        
        let testEntry = TestEntry(className: testClassName, methodName: testMethod, caseId: nil)
        let results = try runTestEntries([testEntry])
        
        XCTAssertEqual(results.count, 1)
        let testResult = results[0]
        XCTAssertTrue(testResult.succeeded)
        XCTAssertEqual(testResult.testEntry, testEntry)
    }
    
    private func runTestEntries(_ testEntries: [TestEntry]) throws -> [TestEntryResult] {
        let runner = Runner(eventBus: EventBus(), configuration: createRunnerConfig(), tempFolder: tempFolder)
        return try runner.run(entries: testEntries, onSimulator: shimulator)
    }
    
    private func stubFbxctestEvent(success: Bool, runIndex: Int = 0) throws {
        try FakeFbxctestExecutableProducer.setFakeOutputEvents(runIndex: runIndex, [
            AnyEncodableWrapper(
                TestStartedEvent(
                    test: "\(testClassName)/\(testMethod)",
                    className: testClassName,
                    methodName: testMethod,
                    timestamp: Date().timeIntervalSince1970)),
            AnyEncodableWrapper(
                TestFinishedEvent(
                    test: "\(testClassName)/\(testMethod)",
                    result: success ? "success" : "failure",
                    className: testClassName,
                    methodName: testMethod,
                    totalDuration: 0.5,
                    exceptions: success ? [] : [testExceptionEvent],
                    succeeded: success,
                    output: "",
                    logs: [],
                    timestamp: Date().timeIntervalSince1970 + 0.5))
            ])
    }
    
    private func createRunnerConfig() -> RunnerConfiguration {
        guard let fbxctest = FakeFbxctestExecutableProducer.fakeFbxctestPath else {
            XCTFail("Expected to have fbxctest binary")
            fatalError()
        }
        let configuration = RunnerConfiguration(
            testType: .logicTest,
            fbxctest: ResolvableResourceLocationImpl(resourceLocation: .localFilePath(fbxctest), resolver: ResourceLocationResolver()),
            buildArtifacts: BuildArtifacts(
                appBundle: "",
                runner: "",
                xcTestBundle: "",
                additionalApplicationBundles: []),
            testExecutionBehavior: TestExecutionBehavior(
                numberOfRetries: 1,
                numberOfSimulators: 1,
                environment: [:],
                scheduleStrategy: .individual),
            simulatorSettings: SimulatorSettings(
                simulatorLocalizationSettings: "",
                watchdogSettings: ""),
            testTimeoutConfiguration: TestTimeoutConfiguration(singleTestMaximumDuration: 5),
            testDiagnosticOutput: TestDiagnosticOutput.nullOutput)
        return configuration
    }
}

extension TestException: Equatable {
    public static func == (l: TestException, r: TestException) -> Bool {
        return l.reason == r.reason &&
            l.filePathInProject == r.filePathInProject &&
            l.lineNumber == r.lineNumber
    }
}
