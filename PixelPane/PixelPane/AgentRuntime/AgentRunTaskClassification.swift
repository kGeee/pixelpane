//
//  AgentRunTaskClassification.swift
//  PixelPane
//
//  Task class, classifier, temporal context, run task profile, and operation intent.
//

import Foundation

nonisolated enum AgentRunTaskClass: String, Codable, Equatable, Sendable {
    case plainChat
    case temporalQuery
    case grantQuestion
    case sessionMemoryQuestion
    case localListing
    case localSearch
    case localFileRead
    case fileSelection
    case writeProposal
    case commandObservation
    case commandPlusWrite
    case visualContext

    var usesLocalEvidencePlanner: Bool {
        switch self {
        case .grantQuestion, .localListing, .localSearch, .localFileRead, .fileSelection, .writeProposal:
            true
        case .plainChat, .temporalQuery, .sessionMemoryQuestion, .commandObservation, .commandPlusWrite, .visualContext:
            false
        }
    }

    var isLocalStateRequest: Bool {
        switch self {
        case .grantQuestion, .localListing, .localSearch, .localFileRead, .fileSelection, .commandObservation, .commandPlusWrite, .visualContext:
            true
        case .plainChat, .temporalQuery, .sessionMemoryQuestion, .writeProposal:
            false
        }
    }

    var requiresTemporalContext: Bool {
        self == .temporalQuery
    }
}

nonisolated struct AgentRunTaskClassifier: Sendable {
    static func classify(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        context: AgentToolRunContext,
        taskFrame: AgentTaskFrame? = nil
    ) -> AgentRunTaskClass {
        let taskFrame = taskFrame ?? AgentTaskFrame.build(
            userMessage: userMessage,
            tools: tools,
            context: context
        )

        if taskFrame.temporalDayOffset != nil {
            return .temporalQuery
        }
        if taskFrame.hasVisualAttachment {
            return .visualContext
        }

        let write = taskFrame.requiresWriteProposal
        let command = taskFrame.requiresCommandEvidence
        if write && command {
            return .commandPlusWrite
        }
        if command {
            return .commandObservation
        }
        if write {
            return .writeProposal
        }
        if !taskFrame.exactSearchQueries.isEmpty {
            return .localSearch
        }
        if taskFrame.hasStructuralLocalReference {
            return taskFrame.localReferences.contains(where: { $0.isDirectory == false && $0.source != .explicitWriteTarget })
                ? .localFileRead
                : .localListing
        }

        return .plainChat
    }

    static func writeTargetPath(from userMessage: String) -> String? {
        AgentTaskFrame.build(
            userMessage: userMessage,
            tools: [AgentKernelToolSchemaV2(name: "stage_write_proposal", summary: "", arguments: [])],
            context: .plainChat
        ).writeTargetPath
    }
}

nonisolated struct AgentTemporalContext: Codable, Equatable, Sendable {
    let currentDate: String
    let localTime: String
    let timeZoneIdentifier: String
    let utcOffset: String
    let weekday: String
    let source: String

    init(date: Date = Date(), timeZone: TimeZone = .current) {
        let calendar = Calendar(identifier: .gregorian)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        currentDate = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm:ss"
        localTime = timeFormatter.string(from: date)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"
        weekday = weekdayFormatter.string(from: date)

        timeZoneIdentifier = timeZone.identifier
        utcOffset = Self.utcOffsetString(seconds: timeZone.secondsFromGMT(for: date))
        source = "app-runtime"
    }

    var modelObservation: String {
        """
        App-owned temporal context
        source: \(source)
        currentDate: \(currentDate)
        localTime: \(localTime)
        weekday: \(weekday)
        timeZone: \(timeZoneIdentifier)
        utcOffset: \(utcOffset)
        Use this context for current date, current time, today, tomorrow, and yesterday. Do not use model pretraining for current temporal facts.
        """
    }

    private static func utcOffsetString(seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3_600
        let minutes = (absSeconds % 3_600) / 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }
}

nonisolated struct AgentRunTaskProfile: Codable, Equatable, Sendable {
    let userMessage: String
    let taskFrame: AgentTaskFrame
    let taskClass: AgentRunTaskClass
    let hasToolPath: Bool
    let isLocalStateRequest: Bool
    let isSideEffectRequest: Bool
    let isEditRequest: Bool
    let requiredSideEffectToolNames: [String]

    var requiresEvidenceBeforeFinalAnswer: Bool {
        (hasToolPath && isLocalStateRequest && !isSideEffectRequest) || taskClass.requiresTemporalContext
    }

    var requiresSideEffectEvidenceBeforeCompletion: Bool {
        hasToolPath && isSideEffectRequest
    }

    var shouldRunEditPreflight: Bool {
        hasToolPath && isEditRequest
    }

    var requiresTemporalContext: Bool {
        taskClass.requiresTemporalContext
    }

    static func classify(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        context: AgentToolRunContext,
        providerTier: AgentModelCapabilityTier? = nil,
        attachments: [AgentKernelModelAttachmentV2] = [],
        selectedAction: String? = nil,
        contextID: String? = nil,
        contextKind: String? = nil,
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations,
        pendingWaits: [AgentRunWaitRecord] = [],
        completedSideEffects: [AgentRunSideEffectRecord] = []
    ) -> AgentRunTaskProfile {
        let hasToolPath = context.runMode != .plainChat
            && (!tools.isEmpty || !context.localGrants.isEmpty)
        let taskFrame = AgentTaskFrame.build(
            userMessage: userMessage,
            tools: tools,
            context: context,
            providerTier: providerTier,
            attachments: attachments,
            selectedAction: selectedAction,
            contextID: contextID,
            contextKind: contextKind,
            supportedOperations: supportedOperations,
            pendingWaits: pendingWaits,
            completedSideEffects: completedSideEffects
        )
        let taskClass = AgentRunTaskClassifier.classify(
            userMessage: userMessage,
            tools: tools,
            context: context,
            taskFrame: taskFrame
        )
        let localEvidencePlan = AgentLocalEvidencePlanner().plan(
            messages: [AgentKernelMessageV2(role: .user, content: userMessage)],
            tools: tools,
            context: context,
            taskFrame: taskFrame
        )
        let intent = AgentRunOperationIntent.classify(
            userMessage: userMessage,
            tools: tools,
            taskFrame: taskFrame
        )
        let localState = !localEvidencePlan.requirements.isEmpty
            || intent.requiresCommandEvidence
            || taskFrame.hasVisualEvidenceRequest
        let sideEffectToolNames = intent.requiredSideEffectToolNames
        let sideEffect = !sideEffectToolNames.isEmpty
        let edit = sideEffectToolNames.contains("stage_write_proposal")
        return AgentRunTaskProfile(
            userMessage: userMessage,
            taskFrame: taskFrame,
            taskClass: taskClass,
            hasToolPath: hasToolPath,
            isLocalStateRequest: localState,
            isSideEffectRequest: sideEffect,
            isEditRequest: edit,
            requiredSideEffectToolNames: sideEffectToolNames
        )
    }

    static func latestUserMessage(from messages: [AgentKernelMessageV2]) -> String {
        messages.reversed().first { $0.role == .user }?.content ?? ""
    }
}

nonisolated struct AgentRunOperationIntent: Equatable, Sendable {
    let requiredSideEffectToolNames: [String]
    let requiresCommandEvidence: Bool

    static func classify(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        taskFrame: AgentTaskFrame? = nil
    ) -> AgentRunOperationIntent {
        let frame = taskFrame ?? AgentTaskFrame.build(
            userMessage: userMessage,
            tools: tools,
            context: .plainChat
        )
        let required = frame.requiredSideEffectToolNames
        let commandEvidence = frame.requiresCommandEvidence

        return AgentRunOperationIntent(
            requiredSideEffectToolNames: unique(required),
            requiresCommandEvidence: commandEvidence
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
