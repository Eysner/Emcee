import EmceeDI
import EmceeLogging
import Types
import Deployer
import DistDeployer
import Foundation
import LoggingSetup
import MetricsExtensions
import TestArgFile
import TestDiscovery
import Tmp
import QueueClient
import QueueCommunication
import QueueModels
import QueueServer
import QueueServerConfiguration
import RESTServer
import RemotePortDeterminer
import SocketModels
import SignalHandling
import SimulatorPool
import RequestSender
import SynchronousWaiter
import UniqueIdentifierGenerator

final class RunTestsOnRemoteQueueLogic {
    private let di: DI
    
    private let callbackQueue = DispatchQueue(label: "RunTestsOnRemoteQueueLogic.callbackQueue")
    
    init(di: DI) {
        self.di = di
    }
    
    func run(
        commonReportOutput: ReportOutput,
        emceeVersion: Version,
        logger: ContextualLogger,
        queueServerConfiguration: QueueServerConfiguration,
        remoteCacheConfig: RuntimeDumpRemoteCacheConfig?,
        tempFolder: TemporaryFolder,
        testArgFile: TestArgFile,
        httpRestServer: HTTPRESTServer
    ) throws {
        
        let runningQueueServerAddress = try detectRemotelyRunningQueueServerPortsOrStartRemoteQueueIfNeeded(
            emceeVersion: emceeVersion,
            queueServerDeploymentDestinations: queueServerConfiguration.queueServerDeploymentDestinations,
            queueServerConfiguration: queueServerConfiguration,
            logger: logger
        )
        
        di.set(
            SwifterRemotelyAccessibleUrlForLocalFileProvider(
                server: httpRestServer,
                requestSenderProvider: try di.get(),
                queueServerAddress: runningQueueServerAddress,
                serverRoot: "/build-artifacts/",
                uniqueIdentifierGenerator: try di.get()
            ),
            for: RemotelyAccessibleUrlForLocalFileProvider.self
        )
        
        let localTypedResourceLocationPreparer = LocalTypedResourceLocationPreparerImpl(
            logger: try di.get(),
            pathForStoringArchives: try tempFolder.createDirectory(
                components: ["job_prepatation"]
            ),
            remotelyAccessibleUrlForLocalFileProvider: try di.get(),
            uniqueIdentifierGenerator: try di.get(),
            zipCompressor: try di.get()
        )
        di.set(localTypedResourceLocationPreparer, for: LocalTypedResourceLocationPreparer.self)
        
        let buildArtifactsPreparer = BuildArtifactsPreparerImpl(
            localTypedResourceLocationPreparer: try di.get(),
            logger: try di.get()
        )
        di.set(buildArtifactsPreparer, for: BuildArtifactsPreparer.self)
        
        let testArgFile = try preprocessTestArgFile(
            testArgFile: testArgFile,
            buildArtifactsPreparer: buildArtifactsPreparer,
            logger: logger
        )
        
        if let kibanaConfiguration = testArgFile.prioritizedJob.analyticsConfiguration.kibanaConfiguration {
            try di.get(LoggingSetup.self).set(kibanaConfiguration: kibanaConfiguration)
        }
        try di.get(GlobalMetricRecorder.self).set(
            analyticsConfiguration: testArgFile.prioritizedJob.analyticsConfiguration
        )
        di.set(
            try di.get(ContextualLogger.self).with(
                analyticsConfiguration: testArgFile.prioritizedJob.analyticsConfiguration
            )
        )
        
        let jobResults = try runTestsOnRemotelyRunningQueue(
            queueServerAddress: runningQueueServerAddress,
            remoteCacheConfig: remoteCacheConfig,
            tempFolder: tempFolder,
            testArgFile: testArgFile,
            version: emceeVersion,
            logger: logger
        )
        let resultOutputGenerator = ResultingOutputGenerator(
            logger: logger,
            bucketResults: jobResults.bucketResults,
            commonReportOutput: commonReportOutput,
            testDestinationConfigurations: testArgFile.testDestinationConfigurations
        )
        try resultOutputGenerator.generateOutput()
    }
    
    private func preprocessTestArgFile(
        testArgFile: TestArgFile,
        buildArtifactsPreparer: BuildArtifactsPreparer,
        logger: ContextualLogger
    ) throws -> TestArgFile {
        logger.info("Preparing build artifacts to be accessible by workers...")
        defer {
            logger.info("Build artifacts are now accessible by workers")
        }
        
        return testArgFile.with(
            entries: try testArgFile.entries.map { testArgFileEntry in
                testArgFileEntry.with(
                    buildArtifacts: try buildArtifactsPreparer.prepare(
                        buildArtifacts: testArgFileEntry.buildArtifacts
                    )
                )
            }
        )
    }
    
    private func detectRemotelyRunningQueueServerPortsOrStartRemoteQueueIfNeeded(
        emceeVersion: Version,
        queueServerDeploymentDestinations: [DeploymentDestination],
        queueServerConfiguration: QueueServerConfiguration,
        logger: ContextualLogger
    ) throws -> SocketAddress {
        logger.info("Searching for queue server on '\(queueServerDeploymentDestinations.map(\.host))' with queue version \(emceeVersion)")
        let remoteQueueDetector = DefaultRemoteQueueDetector(
            emceeVersion: emceeVersion,
            logger: logger,
            remotePortDeterminer: RemoteQueuePortScanner(
                hosts: queueServerDeploymentDestinations.map(\.host),
                logger: logger,
                portRange: EmceePorts.defaultQueuePortRange,
                requestSenderProvider: try di.get()
            )
        )
        var suitableAddresses = try remoteQueueDetector.findSuitableRemoteRunningQueuePorts(timeout: 10)
        if !suitableAddresses.isEmpty {
            logger.info("Found \(suitableAddresses.count) queue server(s) at '\(suitableAddresses)'")
            return try selectAddress(addresses: suitableAddresses)
        }
        
        try startNewInstanceOfRemoteQueueServer(
            queueServerDeploymentDestinations: queueServerDeploymentDestinations,
            emceeVersion: emceeVersion,
            queueServerConfiguration: queueServerConfiguration,
            logger: logger
        )
        
        try di.get(Waiter.self).waitWhile(pollPeriod: 1.0, timeout: 30.0, description: "Wait for remote queue to start") {
            suitableAddresses = try remoteQueueDetector.findSuitableRemoteRunningQueuePorts(timeout: 10)
            return suitableAddresses.isEmpty
        }
        
        let queueServerAddress = try selectAddress(addresses: suitableAddresses)
        logger.info("Using queue server at '\(queueServerAddress)'")
        return queueServerAddress
    }
    
    private func startNewInstanceOfRemoteQueueServer(
        queueServerDeploymentDestinations: [DeploymentDestination],
        emceeVersion: Version,
        queueServerConfiguration: QueueServerConfiguration,
        logger: ContextualLogger
    ) throws {
        logger.info("No running queue server has been found. Will deploy and start remote queue.")
        
        for queueServerDeploymentDestination in queueServerDeploymentDestinations {
            do {
                logger.debug("Trying to start queue on \(queueServerDeploymentDestination.host)")
                let remoteQueueStarter = RemoteQueueStarter(
                    deploymentId: try di.get(UniqueIdentifierGenerator.self).generate(),
                    deploymentDestination: queueServerDeploymentDestination,
                    emceeVersion: emceeVersion,
                    fileSystem: try di.get(),
                    logger: logger,
                    queueServerConfiguration: queueServerConfiguration,
                    tempFolder: try di.get(),
                    uniqueIdentifierGenerator: try di.get(),
                    zipCompressor: try di.get()
                )
                try remoteQueueStarter.deployAndStart()
                logger.debug("Started queue on \(queueServerDeploymentDestination.host)")
                // The code starts only one queue.
                // Since queue is started, return from function to avoid starting any additional queues.
                return
            } catch {
                logger.warning("Error starting queue on \(queueServerDeploymentDestination.host): \(error). This error will be ignored.")
            }
        }
        logger.error("Failed to start queue on all \(queueServerDeploymentDestinations.count) hosts.")
    }
    
    private func runTestsOnRemotelyRunningQueue(
        queueServerAddress: SocketAddress,
        remoteCacheConfig: RuntimeDumpRemoteCacheConfig?,
        tempFolder: TemporaryFolder,
        testArgFile: TestArgFile,
        version: Version,
        logger: ContextualLogger
    ) throws -> JobResults {
        let onDemandSimulatorPool = try OnDemandSimulatorPoolFactory.create(
            di: di,
            logger: logger,
            version: version
        )
        defer { onDemandSimulatorPool.deleteSimulators() }
        
        di.set(onDemandSimulatorPool, for: OnDemandSimulatorPool.self)
        di.set(
            TestDiscoveryQuerierImpl(
                dateProvider: try di.get(),
                developerDirLocator: try di.get(),
                fileSystem: try di.get(),
                globalMetricRecorder: try di.get(),
                specificMetricRecorderProvider: try di.get(),
                onDemandSimulatorPool: try di.get(),
                pluginEventBusProvider: try di.get(),
                processControllerProvider: try di.get(),
                resourceLocationResolver: try di.get(),
                runnerWasteCollectorProvider: try di.get(),
                tempFolder: try di.get(),
                testRunnerProvider: try di.get(),
                uniqueIdentifierGenerator: try di.get(),
                version: version,
                waiter: try di.get()
            ),
            for: TestDiscoveryQuerier.self
        )
        di.set(
            JobStateFetcherImpl(
                requestSender: try di.get(RequestSenderProvider.self).requestSender(socketAddress: queueServerAddress)
            ),
            for: JobStateFetcher.self
        )
        di.set(
            JobResultsFetcherImpl(
                requestSender: try di.get(RequestSenderProvider.self).requestSender(socketAddress: queueServerAddress)
            ),
            for: JobResultsFetcher.self
        )
        di.set(
            JobDeleterImpl(
                requestSender: try di.get(RequestSenderProvider.self).requestSender(socketAddress: queueServerAddress)
            ),
            for: JobDeleter.self
        )
        defer {
            deleteJob(jobId: testArgFile.prioritizedJob.jobId, logger: logger)
        }
        
        try JobPreparer(di: di).formJob(
            emceeVersion: version,
            queueServerAddress: queueServerAddress,
            remoteCacheConfig: remoteCacheConfig,
            testArgFile: testArgFile
        )
        
        try waitForJobQueueToDeplete(jobId: testArgFile.prioritizedJob.jobId, logger: logger)
        return try fetchJobResults(jobId: testArgFile.prioritizedJob.jobId)
    }
    
    private func waitForJobQueueToDeplete(jobId: JobId, logger: ContextualLogger) throws {
        var caughtSignal = false
        SignalHandling.addSignalHandler(signals: [.int, .term]) { [logger] signal in
            logger.info("Caught \(signal) signal")
            caughtSignal = true
        }
        
        try di.get(Waiter.self).waitWhile(pollPeriod: 30.0, description: "Waiting for job queue to deplete") {
            if caughtSignal { return false }
            
            let state = try fetchJobState(jobId: jobId)
            switch state.queueState {
            case .deleted:
                return false
            case .running(let queueState):
                BucketQueueStateLogger(runningQueueState: queueState, logger: logger).printQueueSize()
                return !queueState.isDepleted
            }
        }
    }
    
    private func fetchJobResults(jobId: JobId) throws -> JobResults {
        let callbackWaiter: CallbackWaiter<Either<JobResults, Error>> = try di.get(Waiter.self).createCallbackWaiter()
        try di.get(JobResultsFetcher.self).fetch(
            jobId: jobId,
            callbackQueue: callbackQueue,
            completion: callbackWaiter.set
        )
        return try callbackWaiter.wait(timeout: .infinity, description: "Fetching job results").dematerialize()
    }
    
    private func fetchJobState(jobId: JobId) throws -> JobState {
        let callbackWaiter: CallbackWaiter<Either<JobState, Error>> =  try di.get(Waiter.self).createCallbackWaiter()
        try di.get(JobStateFetcher.self).fetch(
            jobId: jobId,
            callbackQueue: callbackQueue,
            completion: callbackWaiter.set
        )
        return try callbackWaiter.wait(timeout: .infinity, description: "Fetch job state").dematerialize()
    }
    
    private func selectAddress(addresses: Set<SocketAddress>) throws -> SocketAddress {
        struct NoRunningQueueFoundError: Error, CustomStringConvertible {
            var description: String { "No running queue server found" }
        }
        
        guard let address = addresses.sorted().last else { throw NoRunningQueueFoundError() }
        return address
    }
    
    private func deleteJob(jobId: JobId, logger: ContextualLogger) {
        do {
            let callbackWaiter: CallbackWaiter<Either<(), Error>> = try di.get(Waiter.self).createCallbackWaiter()
            try di.get(JobDeleter.self).delete(
                jobId: jobId,
                callbackQueue: callbackQueue,
                completion: callbackWaiter.set
            )
            try callbackWaiter.wait(timeout: .infinity, description: "Deleting job").dematerialize()
        } catch {
            logger.warning("Failed to delete job")
        }
    }
}

extension SocketAddress: Comparable {
    public static func < (lhs: SocketAddress, rhs: SocketAddress) -> Bool {
        lhs.asString < rhs.asString
    }
}
