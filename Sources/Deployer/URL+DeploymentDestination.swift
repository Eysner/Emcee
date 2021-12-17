import Foundation
import PathLib

public struct UrlAnalysisError: Error, CustomStringConvertible {
    public let text: String
    public var description: String { text }
}

extension URL {
    public func deploymentDestination() throws -> DeploymentDestination {
        guard let schemeValue = self.scheme else { throw UrlAnalysisError(text: "Missing scheme") }
        let scheme = schemeValue.lowercased()
        
        guard scheme == "ssh" else { throw UrlAnalysisError(text: "Only ssh:// URL scheme is supported") }
        guard let host = self.host else { throw UrlAnalysisError(text: "Missing host") }
        let port = self.port ?? 22
        guard let user = self.user else { throw UrlAnalysisError(text: "Missing user") }
        var path = self.path
        if path.isEmpty {
            path = "/Users/\(user)/emcee.noindex"
        }
        
        let authenticationType: DeploymentDestinationAuthenticationType
        if let password = self.password {
            authenticationType = .password(password)
        } else if let query = self.query {
            authenticationType = .keyInDefaultSshLocation(filename: query)
        } else if let fragment = self.fragment {
            authenticationType = .key(path: try AbsolutePath.validating(string: fragment))
        } else {
            throw UrlAnalysisError(text: "Can't determine authentication method. Either provide password (ssh://user:pass@example.com/path) or provide ssh key name in default (~/.ssh/) (e.g. ssh://user@example.com/path?some_id) or custom (e.g. ssh://user@example.com/path#/path/to/some_id) location")
        }
        
        return DeploymentDestination(
            host: host,
            port: Int32(port),
            username: user,
            authentication: authenticationType,
            remoteDeploymentPath: AbsolutePath(path)
        )
    }
}
