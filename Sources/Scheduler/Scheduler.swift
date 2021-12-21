import EmceeDI
import DateProvider
import DeveloperDirLocator
import Dispatch
import FileSystem
import Foundation
import ListeningSemaphore
import LocalHostDeterminer
import EmceeLogging
import Metrics
import MetricsExtensions
import PluginManager
import ProcessController
import QueueModels
import ResourceLocationResolver
import Runner
import RunnerModels
import ScheduleStrategy
import SimulatorPool
import SimulatorPoolModels
import SynchronousWaiter
import Tmp
import UniqueIdentifierGenerator

public final class Scheduler {
    private let di: DI
    private let dateProvider: DateProvider
    private let rootLogger: ContextualLogger
    private let queue = OperationQueue()
    private let resourceSemaphore: ListeningSemaphore<ResourceAmounts>
    private let version: Version
    private weak var schedulerDataSource: SchedulerDataSource?
    private weak var schedulerDelegate: SchedulerDelegate?
    
    public init(
        di: DI,
        dateProvider: DateProvider,
        logger: ContextualLogger,
        numberOfSimulators: UInt,
        schedulerDataSource: SchedulerDataSource,
        schedulerDelegate: SchedulerDelegate,
        version: Version
    ) {
        self.di = di
        self.dateProvider = dateProvider
        self.rootLogger = logger
        self.resourceSemaphore = ListeningSemaphore(
            maximumValues: .of(
                runningTests: Int(numberOfSimulators)
            )
        )
        self.schedulerDataSource = schedulerDataSource
        self.schedulerDelegate = schedulerDelegate
        self.version = version
    }
    
    public func run() throws {
        startFetchingAndRunningTests()
        
        try SynchronousWaiter().waitWhile(pollPeriod: 1.0) {
            queue.operationCount > 0
        }
    }
    
    // MARK: - Running on Queue
    
    private func startFetchingAndRunningTests() {
        for _ in 0 ..< resourceSemaphore.availableResources.runningTests {
            fetchAndRunBucket()
        }
    }
    
    private func fetchAndRunBucket() {
        queue.addOperation {
            if self.resourceSemaphore.availableResources.runningTests == 0 {
                return
            }
            guard let bucket = self.schedulerDataSource?.nextBucket() else {
                self.rootLogger.debug("Data Source returned no bucket")
                return
            }
            let logger = self.rootLogger.with(
                analyticsConfiguration: bucket.analyticsConfiguration
            )
            logger.debug("Data Source returned bucket: \(bucket)")
            self.runFetchedBucket(bucket: bucket, logger: logger)
        }
    }
    
    private func runFetchedBucket(
        bucket: SchedulerBucket,
        logger: ContextualLogger
    ) {
        do {
            let acquireResources = try resourceSemaphore.acquire(.of(runningTests: 1))
            let runTestsInBucketAfterAcquiringResources = BlockOperation { [weak self] in
                guard let strongSelf = self else {
                    return logger.error("`self` died unexpectedly")
                }
                
                do {
                    let bucketResult: BucketResult
                    switch bucket.bucketPayloadContainer {
                    case .runIosTests(let runIosTestsPayload):
                        bucketResult = try strongSelf.createRunIosTestsPayloadExecutor().execute(
                            analyticsConfiguration: bucket.analyticsConfiguration,
                            bucketId: bucket.bucketId,
                            logger: logger,
                            payload: runIosTestsPayload
                        )
                    case .runAndroidTests(let runAndroidTestsPayload):
                        bucketResult = try strongSelf.createRunAndroidTestsPayloadExecutor().execute(
                            analyticsConfiguration: bucket.analyticsConfiguration,
                            bucketId: bucket.bucketId,
                            logger: logger,
                            payload: runAndroidTestsPayload
                        )
                    }
                    try strongSelf.resourceSemaphore.release(.of(runningTests: 1))
                    strongSelf.schedulerDelegate?.scheduler(
                        strongSelf,
                        obtainedBucketResult: bucketResult,
                        forBucket: bucket
                    )
                    strongSelf.fetchAndRunBucket()
                } catch {
                    logger.error("Error running tests from fetched bucket with error: \(error). Bucket: \(bucket)")
                }
            }
            acquireResources.addCascadeCancellableDependency(runTestsInBucketAfterAcquiringResources)
            queue.addOperation(runTestsInBucketAfterAcquiringResources)
        } catch {
            logger.error("Failed to run tests from bucket: \(error). Bucket: \(bucket)")
        }
    }
    
    private func createRunIosTestsPayloadExecutor() throws -> RunIosTestsPayloadExecutor {
        RunIosTestsPayloadExecutor(
            dateProvider: try di.get(),
            globalMetricRecorder: try di.get(),
            onDemandSimulatorPool: try di.get(),
            runnerProvider: try di.get(),
            simulatorSettingsModifier: try di.get(),
            specificMetricRecorderProvider: try di.get(),
            version: try di.get()
        )
    }
    
    private func createRunAndroidTestsPayloadExecutor() throws -> RunAndroidTestsPayloadExecutor {
        RunAndroidTestsPayloadExecutor(
            dateProvider: try di.get()
        )
    }
    
}
