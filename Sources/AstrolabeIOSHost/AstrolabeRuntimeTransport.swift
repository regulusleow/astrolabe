//
//  AstrolabeRuntimeTransport.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import Foundation
import Network

protocol AstrolabeRuntimeTransport: AnyObject {
    func connect() throws
    func send(_ data: Data) throws
    func receive(byteCount: Int) throws -> Data
    func close()
}

protocol AstrolabeRuntimeTransportCreating {
    func makeTransport(
        endpoint: AstrolabeRuntimeEndpoint
    ) throws -> any AstrolabeRuntimeTransport
}

struct TCPAstrolabeRuntimeTransportFactory: AstrolabeRuntimeTransportCreating {
    func makeTransport(
        endpoint: AstrolabeRuntimeEndpoint
    ) throws -> any AstrolabeRuntimeTransport {
        try TCPAstrolabeRuntimeTransport(endpoint: endpoint)
    }
}

private final class TCPAstrolabeRuntimeTransport: AstrolabeRuntimeTransport {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let connectTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private var didConnect = false

    init(
        endpoint: AstrolabeRuntimeEndpoint,
        connectTimeout: TimeInterval = 0.25,
        requestTimeout: TimeInterval = 30
    ) throws {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw AstrolabeRuntimeClientError.connectionFailed(
                "Invalid Runtime endpoint port: \(endpoint.port)"
            )
        }
        connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: port,
            using: .tcp
        )
        queue = DispatchQueue(
            label: "com.astrolabe.runtime-host.\(endpoint.port)"
        )
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
    }

    func connect() throws {
        guard !didConnect else {
            return
        }
        let waiter = AstrolabeRuntimeOperationWaiter<Void>()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                waiter.resolve(.success(()))
            case let .failed(error):
                waiter.resolve(
                    .failure(
                        AstrolabeRuntimeClientError.connectionFailed(
                            String(describing: error)
                        )
                    )
                )
            case .cancelled:
                waiter.resolve(.failure(AstrolabeRuntimeClientError.connectionClosed))
            default:
                break
            }
        }
        connection.start(queue: queue)
        try waiter.wait(
            timeout: connectTimeout,
            operation: "Connect to Astrolabe iOS Runtime"
        )
        didConnect = true
    }

    func send(_ data: Data) throws {
        guard didConnect else {
            throw AstrolabeRuntimeClientError.connectionClosed
        }
        let waiter = AstrolabeRuntimeOperationWaiter<Void>()
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                waiter.resolve(
                    .failure(
                        AstrolabeRuntimeClientError.connectionFailed(
                            String(describing: error)
                        )
                    )
                )
            } else {
                waiter.resolve(.success(()))
            }
        })
        try waiter.wait(
            timeout: requestTimeout,
            operation: "Send an Astrolabe Runtime request"
        )
    }

    func receive(byteCount: Int) throws -> Data {
        guard didConnect else {
            throw AstrolabeRuntimeClientError.connectionClosed
        }
        guard byteCount >= 0 else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Response read length cannot be negative"
            )
        }

        var result = Data()
        while result.count < byteCount {
            let remainingCount = byteCount - result.count
            let waiter = AstrolabeRuntimeOperationWaiter<Data>()
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: remainingCount
            ) { data, _, isComplete, error in
                if let error {
                    waiter.resolve(
                        .failure(
                            AstrolabeRuntimeClientError.connectionFailed(
                                String(describing: error)
                            )
                        )
                    )
                } else if let data, !data.isEmpty {
                    waiter.resolve(.success(data))
                } else if isComplete {
                    waiter.resolve(
                        .failure(AstrolabeRuntimeClientError.connectionClosed)
                    )
                } else {
                    waiter.resolve(
                        .failure(
                            AstrolabeRuntimeClientError.invalidResponse(
                                "The Runtime returned an empty data block"
                            )
                        )
                    )
                }
            }
            result.append(
                try waiter.wait(
                    timeout: requestTimeout,
                    operation: "Read an Astrolabe Runtime response"
                )
            )
        }
        return result
    }

    func close() {
        didConnect = false
        connection.cancel()
    }
}

private final class AstrolabeRuntimeOperationWaiter<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<Value, Error>?

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval, operation: String) throws -> Value {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw AstrolabeRuntimeClientError.timeout(operation)
        }
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "The asynchronous operation ended without a result"
            )
        }
        return try result.get()
    }
}
