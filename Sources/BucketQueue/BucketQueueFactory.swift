import Foundation
import WorkerAlivenessTracker

public final class BucketQueueFactory {
    public static func create(
        workerAlivenessProvider: WorkerAlivenessProvider,
        testHistoryTracker: TestHistoryTracker)
        -> BucketQueue
    {
        return BucketQueueImpl(
            workerAlivenessProvider: workerAlivenessProvider,
            testHistoryTracker: testHistoryTracker
        )
    }
}