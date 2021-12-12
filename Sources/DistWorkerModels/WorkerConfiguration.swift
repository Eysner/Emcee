import Foundation
import MetricsExtensions
import LoggingSetup
import QueueModels

public struct WorkerConfiguration: Codable, Equatable, CustomStringConvertible {
    public let globalAnalyticsConfiguration: AnalyticsConfiguration
    public let numberOfSimulators: UInt
    public let payloadSignature: PayloadSignature

    public init(
        globalAnalyticsConfiguration: AnalyticsConfiguration,
        numberOfSimulators: UInt,
        payloadSignature: PayloadSignature
    ) {
        self.globalAnalyticsConfiguration = globalAnalyticsConfiguration
        self.numberOfSimulators = numberOfSimulators
        self.payloadSignature = payloadSignature
    }
    
    public var description: String {
        "<\(type(of: self)): globalAnalyticsConfiguration=\(globalAnalyticsConfiguration), numberOfSimulators=\(numberOfSimulators)>"
    }
}
