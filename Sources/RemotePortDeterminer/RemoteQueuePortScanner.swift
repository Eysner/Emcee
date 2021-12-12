import AtomicModels
import Dispatch
import Foundation
import EmceeLogging
import QueueClient
import QueueModels
import RequestSender
import SocketModels
import Types

public final class RemoteQueuePortScanner: RemotePortDeterminer {
    private let hosts: [String]
    private let logger: ContextualLogger
    private let portRange: ClosedRange<SocketModels.Port>
    private let requestSenderProvider: RequestSenderProvider
    private let workQueue = DispatchQueue(label: "RemoteQueuePortScanner.workQueue")
    
    public init(
        hosts: [String],
        logger: ContextualLogger,
        portRange: ClosedRange<SocketModels.Port>,
        requestSenderProvider: RequestSenderProvider
    ) {
        self.hosts = hosts
        self.logger = logger
        self.portRange = portRange
        self.requestSenderProvider = requestSenderProvider
    }
    
    public func queryPortAndQueueServerVersion(timeout: TimeInterval) -> [SocketAddress: Version] {
        let group = DispatchGroup()
        
        let socketToVersion = AtomicValue<[SocketAddress: Version]>([:])

        for host in hosts {
            for port in portRange {
                group.enter()
                let socketAddress = SocketAddress(host: host, port: port)
                logger.trace("Checking queue presence at \(socketAddress)")

                let queueServerVersionFetcher = QueueServerVersionFetcherImpl(
                    requestSender: requestSenderProvider.requestSender(
                        socketAddress: socketAddress
                    )
                )

                queueServerVersionFetcher.fetchQueueServerVersion(
                    callbackQueue: workQueue
                ) { (result: Either<Version, Error>) in
                    if let version = try? result.dematerialize() {
                        self.logger.trace("Found queue server with \(version) version at \(socketAddress)")
                        socketToVersion.withExclusiveAccess {
                            $0[socketAddress] = version
                        }
                    }
                    group.leave()
                }
            }
        }
        
        _ = group.wait(timeout: .now() + timeout)
        return socketToVersion.currentValue()
    }
}
