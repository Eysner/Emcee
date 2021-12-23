import AppleTools
import AppleToolsTestHelpers
import BuildArtifacts
import DateProvider
import DateProviderTestHelpers
import DeveloperDirLocator
import DeveloperDirLocatorTestHelpers
import DeveloperDirModels
import EmceeTypes
import FileCache
import FileSystemTestHelpers
import Foundation
import PathLib
import ProcessController
import ProcessControllerTestHelpers
import ResourceLocationResolver
import ResourceLocationResolverTestHelpers
import ResultStreamModels
import ResultStreamModelsTestHelpers
import Runner
import RunnerModels
import RunnerTestHelpers
import SimulatorPoolModels
import SimulatorPoolTestHelpers
import Tmp
import TestHelpers
import URLResource
import XCTest

final class XcodebuildBasedTestRunnerTests: XCTestCase {
    private lazy var fileSystem = FakeFileSystem(rootPath: tempFolder.absolutePath)
    private lazy var tempFolder = assertDoesNotThrow { try TemporaryFolder() }
    private let testRunnerStream = AccumulatingTestRunnerStream()
    private let dateProvider = DateProviderFixture(Date(timeIntervalSince1970: 100500))
    private lazy var contextId = UUID().uuidString
    private lazy var processControllerProvider = FakeProcessControllerProvider()
    private lazy var resourceLocationResolver = FakeResourceLocationResolver(
        resolvingResult: .directlyAccessibleFile(path: tempFolder.absolutePath)
    )
    private lazy var simulator = Simulator(
        testDestination: TestDestinationFixtures.testDestination,
        udid: UDID(value: UUID().uuidString),
        path: assertDoesNotThrow {
            try tempFolder.createDirectory(components: ["simulator"])
        }
    )
    private lazy var testContext = assertDoesNotThrow { try createTestContext() }
    private lazy var xcResultTool = FakeXcResultTool()
    private lazy var runner = XcodebuildBasedTestRunner(
        dateProvider: dateProvider,
        fileSystem: fileSystem,
        processControllerProvider: processControllerProvider,
        resourceLocationResolver: resourceLocationResolver,
        xcResultTool: xcResultTool
    )
    private lazy var developerDirLocator = FakeDeveloperDirLocator(
        result: tempFolder.absolutePath.appending("xcode.app")
    )
    private lazy var appBundlePath: AbsolutePath = assertDoesNotThrow {
        let path = try tempFolder.createDirectory(components: ["appbundle.app"])
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": hostAppBundleId],
            format: .xml,
            options: 0
        )
        try tempFolder.createFile(
            components: ["appbundle.app"],
            filename: "Info.plist",
            contents: data
        )
        return path
    }
    private lazy var runnerAppPath = tempFolder.absolutePath.appending("xctrunner.app")
    private let hostAppBundleId = "host.app.bundle.id"
    private let testBundleName = "SomeTestProductName"
    private lazy var testBundlePath: AbsolutePath = {
        let testBundlePlistPath = assertDoesNotThrow {
            try tempFolder.createFile(
                components: ["xctrunner.app", "PlugIns", "testbundle.xctest"],
                filename: "Info.plist",
                contents: try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleName": testBundleName],
                    format: .xml,
                    options: 0
                )
            )
        }
        return testBundlePlistPath.removingLastComponent
    }()
    private lazy var additionalAppPath = tempFolder.absolutePath.appending("additionalapp.app")
    private lazy var xcTestBundle = XcTestBundle(
        location: TestBundleLocation(.localFilePath(testBundlePath.pathString)),
        testDiscoveryMode: .runtimeLogicTest
    )
    private lazy var uiTestBuildArtifacts = BuildArtifacts.iosUiTests(
        xcTestBundle: xcTestBundle,
        appBundle: AppBundleLocation(.localFilePath(appBundlePath.pathString)),
        runner: RunnerAppLocation(.localFilePath(runnerAppPath.pathString)),
        additionalApplicationBundles: [
            AdditionalAppBundleLocation(.localFilePath(additionalAppPath.pathString)),
        ]
    )
    private lazy var appTestBuildArtifacts = BuildArtifacts.iosApplicationTests(
        xcTestBundle: xcTestBundle,
        appBundle: AppBundleLocation(.localFilePath(appBundlePath.pathString))
    )
    private lazy var logicTestBuildArtifacts = BuildArtifacts.iosLogicTests(
        xcTestBundle: xcTestBundle
    )
    private lazy var runnerWasteCollector = RunnerWasteCollectorImpl()
    
    private var testRunnerWorkingDirectory: AbsolutePath {
        assertDoesNotThrow {
            try tempFolder.createDirectory(components: [Runner.runnerWorkingDir, contextId])
        }
    }
    
    private var testsWorkingDirectory: AbsolutePath {
        assertDoesNotThrow {
            try tempFolder.createDirectory(components: [Runner.testsWorkingDir, contextId])
        }
    }
    
    private func createTestContext(environment: [String: String] = [:]) throws -> TestContext {
        TestContext(
            contextId: contextId,
            developerDir: DeveloperDir.current,
            environment: environment,
            userInsertedLibraries: [
                "__TESTHOST__/Frameworks/FrameworkToInsert.framework/FrameworkToInsert",
            ],
            simulatorPath: simulator.path,
            simulatorUdid: simulator.udid,
            testDestination: simulator.testDestination,
            testRunnerWorkingDirectory: testRunnerWorkingDirectory,
            testsWorkingDirectory: testsWorkingDirectory
        )
    }
    
    func test___logic_test_arguments() throws {
        let argsValidatedExpectation = expectation(description: "Arguments have been validated")
        
        processControllerProvider.creator = { subprocess -> ProcessController in
            guard !(try subprocess.arguments[0].stringValue().contains("tail")) else {
                return FakeProcessController(subprocess: subprocess)
            }
            
            self.assertArgumentsAreCorrect(arguments: subprocess.arguments)
            
            XCTAssertEqual(
                try self.createdXcTestRun(),
                XcTestRun(
                    testTargetName: self.testBundleName,
                    bundleIdentifiersForCrashReportEmphasis: [],
                    dependentProductPaths: [self.testBundlePath.pathString],
                    testBundlePath: self.testBundlePath.pathString,
                    testHostPath: "__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest",
                    testHostBundleIdentifier: "com.apple.dt.xctest.tool",
                    uiTargetAppPath: nil,
                    environmentVariables: [:],
                    commandLineArguments: [],
                    uiTargetAppEnvironmentVariables: [:],
                    uiTargetAppCommandLineArguments: [],
                    uiTargetAppMainThreadCheckerEnabled: false,
                    skipTestIdentifiers: [],
                    onlyTestIdentifiers: [TestEntryFixtures.testEntry().testName.stringValue],
                    testingEnvironmentVariables: [
                        "DYLD_INSERT_LIBRARIES": "__TESTHOST__/Frameworks/FrameworkToInsert.framework/FrameworkToInsert:__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib/libXCTestBundleInject.dylib",
                        "XCInjectBundleInto": "__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest",
                    ],
                    isUITestBundle: false,
                    isAppHostedTestBundle: false,
                    isXCTRunnerHostedTestBundle: false,
                    testTargetProductModuleName: self.testBundleName,
                    systemAttachmentLifetime: .deleteOnSuccess,
                    userAttachmentLifetime: .deleteOnSuccess
                )
            )
            
            argsValidatedExpectation.fulfill()
            
            let controller = FakeProcessController(subprocess: subprocess)
            controller.overridedProcessStatus = .terminated(exitCode: 0)
            return controller
        }
        
        assertDoesNotThrow {
            let invocation = try runner.prepareTestRun(
                buildArtifacts: logicTestBuildArtifacts,
                developerDirLocator: developerDirLocator,
                entriesToRun: [
                    TestEntryFixtures.testEntry()
                ],
                logger: .noOp,
                runnerWasteCollector: runnerWasteCollector,
                simulator: simulator,
                testContext: testContext,
                testRunnerStream: testRunnerStream
            )
            try invocation.startExecutingTests().wait()
        }
        
        wait(for: [argsValidatedExpectation], timeout: 15)
    }
    
    func test___application_test_arguments() throws {
        let argsValidatedExpectation = expectation(description: "Arguments have been validated")
        
        processControllerProvider.creator = { subprocess -> ProcessController in
            guard !(try subprocess.arguments[0].stringValue().contains("tail")) else {
                return FakeProcessController(subprocess: subprocess)
            }
            
            self.assertArgumentsAreCorrect(arguments: subprocess.arguments)
            
            XCTAssertEqual(
                try self.createdXcTestRun(),
                XcTestRun(
                    testTargetName: self.testBundleName,
                    bundleIdentifiersForCrashReportEmphasis: [],
                    dependentProductPaths: [
                        self.appBundlePath.pathString,
                        self.testBundlePath.pathString,
                    ],
                    testBundlePath: self.testBundlePath.pathString,
                    testHostPath: self.appBundlePath.pathString,
                    testHostBundleIdentifier: self.hostAppBundleId,
                    uiTargetAppPath: nil,
                    environmentVariables: [:],
                    commandLineArguments: [],
                    uiTargetAppEnvironmentVariables: [:],
                    uiTargetAppCommandLineArguments: [],
                    uiTargetAppMainThreadCheckerEnabled: false,
                    skipTestIdentifiers: [],
                    onlyTestIdentifiers: [TestEntryFixtures.testEntry().testName.stringValue],
                    testingEnvironmentVariables: [
                        "DYLD_INSERT_LIBRARIES": "__TESTHOST__/Frameworks/FrameworkToInsert.framework/FrameworkToInsert:__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib/libXCTestBundleInject.dylib",
                        "XCInjectBundleInto": self.appBundlePath.pathString,
                    ],
                    isUITestBundle: false,
                    isAppHostedTestBundle: true,
                    isXCTRunnerHostedTestBundle: false,
                    testTargetProductModuleName: self.testBundleName,
                    systemAttachmentLifetime: .deleteOnSuccess,
                    userAttachmentLifetime: .deleteOnSuccess
                )
            )
            
            argsValidatedExpectation.fulfill()
            
            let controller = FakeProcessController(subprocess: subprocess)
            controller.overridedProcessStatus = .terminated(exitCode: 0)
            return controller
        }
        
        assertDoesNotThrow {
            let invocation = try runner.prepareTestRun(
                buildArtifacts: appTestBuildArtifacts,
                developerDirLocator: developerDirLocator,
                entriesToRun: [
                    TestEntryFixtures.testEntry()
                ],
                logger: .noOp,
                runnerWasteCollector: runnerWasteCollector,
                simulator: simulator,
                testContext: testContext,
                testRunnerStream: testRunnerStream
            )
            try invocation.startExecutingTests().wait()
        }
        
        wait(for: [argsValidatedExpectation], timeout: 15)
    }
    
    func test___ui_test_arguments() throws {
        let argsValidatedExpectation = expectation(description: "Arguments have been validated")
        
        processControllerProvider.creator = { subprocess -> ProcessController in
            guard !(try subprocess.arguments[0].stringValue().contains("tail")) else {
                return FakeProcessController(subprocess: subprocess)
            }
            
            self.assertArgumentsAreCorrect(arguments: subprocess.arguments)
            
            XCTAssertEqual(
                try self.createdXcTestRun(),
                XcTestRun(
                    testTargetName: self.testBundleName,
                    bundleIdentifiersForCrashReportEmphasis: [],
                    dependentProductPaths: [
                        self.appBundlePath.pathString,
                        self.testBundlePath.pathString,
                        self.runnerAppPath.pathString,
                        self.additionalAppPath.pathString,
                    ],
                    testBundlePath: self.testBundlePath.pathString,
                    testHostPath: self.runnerAppPath.pathString,
                    testHostBundleIdentifier: "StubBundleId",
                    uiTargetAppPath: self.appBundlePath.pathString,
                    environmentVariables: [:],
                    commandLineArguments: [],
                    uiTargetAppEnvironmentVariables: [:],
                    uiTargetAppCommandLineArguments: [],
                    uiTargetAppMainThreadCheckerEnabled: false,
                    skipTestIdentifiers: [],
                    onlyTestIdentifiers: [TestEntryFixtures.testEntry().testName.stringValue],
                    testingEnvironmentVariables: [
                        "DYLD_FRAMEWORK_PATH": "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
                        "DYLD_INSERT_LIBRARIES": "__TESTHOST__/Frameworks/FrameworkToInsert.framework/FrameworkToInsert",
                        "DYLD_LIBRARY_PATH": "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
                    ],
                    isUITestBundle: true,
                    isAppHostedTestBundle: false,
                    isXCTRunnerHostedTestBundle: true,
                    testTargetProductModuleName: self.testBundleName,
                    systemAttachmentLifetime: .deleteOnSuccess,
                    userAttachmentLifetime: .deleteOnSuccess
                )
            )
            
            argsValidatedExpectation.fulfill()
            
            let controller = FakeProcessController(subprocess: subprocess)
            controller.overridedProcessStatus = .terminated(exitCode: 0)
            return controller
        }
        
        assertDoesNotThrow {
            let invocation = try runner.prepareTestRun(
                buildArtifacts: uiTestBuildArtifacts,
                developerDirLocator: developerDirLocator,
                entriesToRun: [
                    TestEntryFixtures.testEntry()
                ],
                logger: .noOp,
                runnerWasteCollector: runnerWasteCollector,
                simulator: simulator,
                testContext: testContext,
                testRunnerStream: testRunnerStream
            )
            try invocation.startExecutingTests().wait()
        }
        
        wait(for: [argsValidatedExpectation], timeout: 15)
    }
        
    func test___open_stream_called___when_test_runner_starts() throws {
        testRunnerStream.streamIsOpen = false
        
        let invocation = try runner.prepareTestRun(
            buildArtifacts: logicTestBuildArtifacts,
            developerDirLocator: developerDirLocator,
            entriesToRun: [
                TestEntryFixtures.testEntry()
            ],
            logger: .noOp,
            runnerWasteCollector: runnerWasteCollector,
            simulator: simulator,
            testContext: testContext,
            testRunnerStream: testRunnerStream
        )
        _ = try invocation.startExecutingTests()
        
        XCTAssertTrue(testRunnerStream.streamIsOpen)
    }
    
    func test___close_stream_called___when_test_runner_cancelled() throws {
        testRunnerStream.streamIsOpen = true
        
        let invocation = try runner.prepareTestRun(
            buildArtifacts: logicTestBuildArtifacts,
            developerDirLocator: developerDirLocator,
            entriesToRun: [
                TestEntryFixtures.testEntry()
            ],
            logger: .noOp,
            runnerWasteCollector: runnerWasteCollector,
            simulator: simulator,
            testContext: testContext,
            testRunnerStream: testRunnerStream
        )
        
        let streamIsClosed = XCTestExpectation(description: "Stream closed")
        testRunnerStream.onCloseStream = streamIsClosed.fulfill
        
        try invocation.startExecutingTests().cancel()
        
        wait(for: [streamIsClosed], timeout: 10)
    }
    
    func test___working_with_result_stream() throws {
        let testName = TestName(className: "Class", methodName: "test")
        let impactQueue = DispatchQueue(label: "impact.queue")
        
        var tailProcessController: FakeProcessController?
        var xcodebuildProcessController: FakeProcessController?
        
        processControllerProvider.creator = { subprocess -> ProcessController in
            let controller = FakeProcessController(subprocess: subprocess)
            controller.overridedProcessStatus = .stillRunning
            
            if xcodebuildProcessController == nil, try subprocess.arguments[0].stringValue().contains("xcrun") {
                xcodebuildProcessController = controller
            } else if tailProcessController == nil, try subprocess.arguments[0].stringValue().contains("tail") {
                tailProcessController = controller
            }
            
            return controller
        }
        
        let invocation = try runner.prepareTestRun(
            buildArtifacts: logicTestBuildArtifacts,
            developerDirLocator: developerDirLocator,
            entriesToRun: [TestEntry(testName: testName, tags: [], caseId: nil)],
            logger: .noOp,
            runnerWasteCollector: runnerWasteCollector,
            simulator: simulator,
            testContext: testContext,
            testRunnerStream: testRunnerStream
        )
        let runningInvocation = try invocation.startExecutingTests()
        
        impactQueue.async {
            tailProcessController?.broadcastStdout(data: Data(RSTestStartedTestInput.input(testName: testName).utf8))
            impactQueue.async {
                tailProcessController?.broadcastStdout(data: Data(RSTestFinishedTestInput.input(testName: testName, duration: 5).utf8))
                impactQueue.async {
                    xcodebuildProcessController?.overridedProcessStatus = .terminated(exitCode: 0)
                }
            }
        }
        
        runningInvocation.wait()
        
        guard testRunnerStream.accumulatedData.count == 2 else {
            failTest("Unexpected number of events in test stream")
        }
        
        XCTAssertEqual(
            testRunnerStream.castTo(TestName.self, index: 0),
            testName
        )
        
        XCTAssertEqual(
            testRunnerStream.castTo(TestStoppedEvent.self, index: 1),
            TestStoppedEvent(
                testName: testName,
                result: .success,
                testDuration: 5,
                testExceptions: [],
                logs: [],
                testStartTimestamp: dateProvider.dateSince1970ReferenceDate() - 5
            )
        )
    }
    
    func test___providing_xcresultool_errors() throws {
        xcResultTool.result = RSActionsInvocationRecord(
            actions: [],
            issues: RSResultIssueSummaries(testFailureSummaries: [
                RSTestFailureIssueSummary(
                    issueType: "whatever",
                    message: "message",
                    producingTarget: nil,
                    documentLocationInCreatingWorkspace: nil,
                    testCaseName: "ClassName.testMethod()"
                )
            ]),
            metadataRef: RSReference(id: "metadataRef"),
            metrics: RSResultMetrics(testsCount: nil, testsFailedCount: nil, warningCount: nil)
        )
        
        testRunnerStream.streamIsOpen = true
        
        let invocation = try runner.prepareTestRun(
            buildArtifacts: logicTestBuildArtifacts,
            developerDirLocator: developerDirLocator,
            entriesToRun: [
                TestEntryFixtures.testEntry(className: "ClassName", methodName: "testMethod"),
            ],
            logger: .noOp,
            runnerWasteCollector: runnerWasteCollector,
            simulator: simulator,
            testContext: testContext,
            testRunnerStream: testRunnerStream
        )
        
        let streamIsClosed = XCTestExpectation(description: "Stream closed")
        testRunnerStream.onCloseStream = streamIsClosed.fulfill
        
        try invocation.startExecutingTests().cancel()
        
        wait(for: [streamIsClosed], timeout: 10)
        
        assert {
            TestException(
                reason: "message",
                filePathInProject: "Unknown",
                lineNumber: 0,
                relatedTestName: TestName(className: "ClassName", methodName: "testMethod")
            )
        } equals: {
            testRunnerStream.castTo(TestException.self, index: 0)
        }
    }
    
    private func pathToXctestrunFile() throws -> AbsolutePath {
        let contents = try FileManager().contentsOfDirectory(atPath: testRunnerWorkingDirectory.pathString)
        let xctestrunFileName: String = contents.first(where: { $0.hasSuffix("xctestrun") }) ?? "NOT_FOUND"
        return testRunnerWorkingDirectory.appending(xctestrunFileName)
    }
    
    private func createdXcTestRun() throws -> XcTestRun {
        return try XcTestRunPlist.readPlist(
            data: try Data(
                contentsOf: try self.pathToXctestrunFile().fileUrl,
                options: .mappedIfSafe
            )
        ).xcTestRun
    }
    
    private func assertArgumentsAreCorrect(arguments: [SubprocessArgument]) {
        XCTAssertEqual(
            try arguments.map { try $0.stringValue() },
            [
                "/usr/bin/xcrun",
                "xcodebuild",
                "-destination", "platform=iOS Simulator,id=" + simulator.udid.value,
                "-derivedDataPath", testRunnerWorkingDirectory.appending("derivedData").pathString,
                "-resultBundlePath", testRunnerWorkingDirectory.appending("resultBundle.xcresult").pathString,
                "-resultStreamPath", testRunnerWorkingDirectory.appending("result_stream.json").pathString,
                "-xctestrun", try pathToXctestrunFile().pathString,
                "-parallel-testing-enabled", "NO",
                "test-without-building"
            ]
        )
    }
}
