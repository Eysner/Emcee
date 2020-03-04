import DistWorkerModels
import Foundation
import RequestSender

public class CurrentlyProcessingBucketsNetworkRequest: NetworkRequest {
    public typealias Payload = VoidPayload
    public typealias Response = CurrentlyProcessingBucketsResponse
    
    public let httpMethod: HTTPMethod = .get
    public let pathWithLeadingSlash: String = CurrentlyProcessingBuckets.path.withPrependedSlash
    public let payload: VoidPayload? = nil
    public let timeout: TimeInterval

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }
}