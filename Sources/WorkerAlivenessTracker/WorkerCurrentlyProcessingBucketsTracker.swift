import Foundation
import Logging

public final class WorkerCurrentlyProcessingBucketsTracker {
    
    private var values = [String: Set<String>]()
    
    public init() {}
    
    public func bucketIdsBeingProcessedBy(workerId: String) -> Set<String> {
        return values[workerId] ?? Set()
    }
    
    public func set(bucketIdsBeingProcessed bucketIds: Set<String>, byWorkerId workerId: String) {
        if values[workerId] != bucketIds {
            values[workerId] = bucketIds
            Logger.verboseDebug("Worker \(workerId) is processing \(bucketIds.count) buckets: \(bucketIds)")
        }
    }
    
    public func append(bucketId: String, workerId: String) {
        set(
            bucketIdsBeingProcessed: Set(bucketIdsBeingProcessedBy(workerId: workerId) + [bucketId]),
            byWorkerId: workerId
        )
    }
    
    public func resetBucketIdsBeingProcessedBy(workerId: String) {
        set(bucketIdsBeingProcessed: [], byWorkerId: workerId)
    }
}
