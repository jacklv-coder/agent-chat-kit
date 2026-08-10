import Foundation

/// Errors produced by the high-level session coordinator.
public enum AgentChatSessionError: Error, Hashable, Sendable {
    /// A command was sent before a connection was established.
    case notStarted
}

/// Coordinates one runtime connection, reducer, and main-actor store.
public actor AgentChatSession {
    private let adapter: any AgentRuntimeAdapter
    private let runtimeConfiguration: AgentRuntimeConfiguration
    private let reducer: AgentConversationReducer
    private let store: AgentConversationStore
    private let logger: any AgentChatLogging

    private var connection: (any AgentRuntimeConnection)?
    private var eventTask: Task<Void, Never>?

    /// Creates a scene-scoped session.
    @MainActor
    public init(
        adapter: any AgentRuntimeAdapter,
        configuration: AgentRuntimeConfiguration,
        reducerConfiguration: AgentReducerConfiguration = .init(),
        store: AgentConversationStore,
        logger: any AgentChatLogging = NoOpAgentChatLogger()
    ) {
        self.adapter = adapter
        var resolvedConfiguration = configuration
        if resolvedConfiguration.conversationID == "default" {
            resolvedConfiguration.conversationID = store.snapshot.id
        }
        self.runtimeConfiguration = resolvedConfiguration
        self.reducer = AgentConversationReducer(
            snapshot: store.snapshot,
            configuration: reducerConfiguration
        )
        self.store = store
        self.logger = logger
    }

    /// Connects and starts consuming events. Calling while started is idempotent.
    public func start() async throws {
        guard connection == nil else { return }
        let connected = try await adapter.connect(configuration: runtimeConfiguration)
        connection = connected
        let stream = connected.makeEventStream()
        let conversationID = runtimeConfiguration.conversationID
        let reducer = self.reducer
        let store = self.store
        let logger = self.logger

        eventTask = Task { [weak self] in
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    let result = await reducer.consume(event)
                    await store.apply(result)
                    if result.requiresSnapshot {
                        try await connected.send(.requestSnapshot(conversationID))
                    }
                }
                await self?.handleDisconnection()
            } catch is CancellationError {
                return
            } catch {
                logger.log(
                    .init(
                        level: .warning,
                        name: "runtime.stream.disconnected",
                        metadata: [:]
                    )
                )
                await self?.handleDisconnection()
            }
        }
    }

    /// Sends a structured command through the active connection.
    public func send(_ command: AgentRuntimeCommand) async throws {
        guard let connection else { throw AgentChatSessionError.notStarted }
        try await connection.send(command)
    }

    /// The active runtime capabilities, or an empty set before start.
    public func capabilities() -> AgentRuntimeCapabilities {
        connection?.capabilities ?? []
    }

    /// Cancels event consumption and closes the connection idempotently.
    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        let closing = connection
        connection = nil
        await closing?.close()
    }

    private func handleDisconnection() async {
        guard let disconnectedConnection = connection else { return }
        connection = nil
        eventTask = nil
        await disconnectedConnection.close()
        let current = await MainActor.run { store.snapshot }
        var offline = current
        offline.state = .offline(message: "Runtime connection lost")
        let result = await reducer.replaceSnapshot(offline)
        await store.apply(result)
    }
}
