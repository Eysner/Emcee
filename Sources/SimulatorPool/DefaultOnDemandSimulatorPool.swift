import Dispatch
import Foundation
import EmceeLogging
import RunnerModels
import Tmp

public class DefaultOnDemandSimulatorPool: OnDemandSimulatorPool {
    private let logger: ContextualLogger
    private let simulatorControllerProvider: SimulatorControllerProvider
    private let syncQueue = DispatchQueue(label: "ru.avito.OnDemandSimulatorPool")
    private let tempFolder: TemporaryFolder
    private var pools = [OnDemandSimulatorPoolKey: SimulatorPool]()
    
    public init(
        logger: ContextualLogger,
        simulatorControllerProvider: SimulatorControllerProvider,
        tempFolder: TemporaryFolder
    ) {
        self.logger = logger
        self.simulatorControllerProvider = simulatorControllerProvider
        self.tempFolder = tempFolder
    }
    
    deinit {
        deleteSimulators()
    }
    
    public func pool(key: OnDemandSimulatorPoolKey) throws -> SimulatorPool {
        return try syncQueue.sync {
            if let existingPool = pools[key] {
                return existingPool
            } else {
                let pool = try DefaultSimulatorPool(
                    developerDir: key.developerDir,
                    logger: logger,
                    simulatorControllerProvider: simulatorControllerProvider,
                    tempFolder: tempFolder,
                    testDestination: key.testDestination
                )
                pools[key] = pool
                return pool
            }
        }
    }
    
    public func enumeratePools(iterator: (OnDemandSimulatorPoolKey, SimulatorPool) -> ()) {
        for (key, value) in syncQueue.sync(execute: { pools }) {
            iterator(key, value)
        }
    }
}
