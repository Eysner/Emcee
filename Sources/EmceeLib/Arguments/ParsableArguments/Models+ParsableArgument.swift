import ArgLib
import Foundation
import QueueModels
import ResourceLocation
import SocketModels
import TypedResourceLocation

extension TypedResourceLocation: ParsableArgument {
    public init(argumentValue: String) throws {
        let resourceLocation = try ResourceLocation.from(argumentValue)
        self.init(resourceLocation)
    }
}

extension SocketAddress: ParsableArgument {
    public init(argumentValue: String) throws {
        let parsedAddress = try SocketAddress.from(string: argumentValue)
        self.init(host: parsedAddress.host, port: parsedAddress.port)
    }
}

extension WorkerId: ParsableArgument {
    public convenience init(argumentValue: String) throws {
        self.init(value: argumentValue)
    }
}

extension Priority: ParsableArgument {
    public init(argumentValue: String) throws {
        try self.init(intValue: try UInt(argumentValue: argumentValue))
    }
}

extension JobId: ParsableArgument {
    public convenience init(argumentValue: String) throws {
        self.init(value: argumentValue)
    }
}

extension JobGroupId: ParsableArgument {
    public convenience init(argumentValue: String) throws {
        self.init(value: argumentValue)
    }
}

extension Version: ParsableArgument {
    public convenience init(argumentValue: String) throws {
        self.init(value: argumentValue)
    }
}

extension URL: ParsableArgument {
    public init(argumentValue: String) throws {
        guard let result = Self(string: argumentValue) else {
            throw GenericParseError<Self>(argumentValue: argumentValue)
        }
        self = result
    }
}
