import EmceeLogging
import Foundation
import MetricsExtensions
import QueueModels

public protocol BucketPayloadExecutor {
    
    associatedtype T: BucketPayload
    
    func execute(
        analyticsConfiguration: AnalyticsConfiguration,
        bucketId: BucketId,
        logger: ContextualLogger,
        payload: T
    ) throws -> BucketResult
}
