import Foundation
import SwiftUI

enum AgentDomain: String {
    case meal
}

enum AgentShellPhase: String {
    case idle
    case chatInput = "chat-input"
    case planning
    case executing
    case completed
    case cancelled
}

enum MealScenario: String {
    case create = "meal-create"
    case edit = "meal-edit"
}

enum MealStepType: String {
    case create
    case edit
}

enum MealStepState: Equatable {
    case draft
    case needsResolve
    case readyForConfirm
    case committed
    case failed(String)
}

enum MealResolveKind: Equatable {
    case createConflict(existingWindowId: String)
    case missingMealSlot
}

enum MealResolveEngine {
    static func resolveKind(
        for step: MealExecutionStep,
        existingEvent: MealEvent?
    ) -> MealResolveKind? {
        if step.windowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingMealSlot
        }
        if step.type == .create, existingEvent != nil {
            return .createConflict(existingWindowId: step.windowId)
        }
        return nil
    }

    static func applyResolveState(
        to step: inout MealExecutionStep,
        existingEvent: MealEvent?
    ) {
        if let resolveKind = resolveKind(for: step, existingEvent: existingEvent) {
            step.resolveKind = resolveKind
            step.state = .needsResolve
        } else {
            step.resolveKind = nil
            step.state = .readyForConfirm
        }
    }
}

struct MealProductDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var grams: Double
    var estimatedCalories: Double
    var estimatedProteins: Double
    var estimatedFats: Double
    var estimatedCarbs: Double
    var impactScore: Double
    var reason: String
    var saturatedFats: Double
    var sugar: Double
    var fiber: Double
    var sodium: Double
    var foodCategory: String?

    init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        estimatedCalories: Double,
        estimatedProteins: Double,
        estimatedFats: Double,
        estimatedCarbs: Double,
        impactScore: Double = 0,
        reason: String = "",
        saturatedFats: Double = 0,
        sugar: Double = 0,
        fiber: Double = 0,
        sodium: Double = 0,
        foodCategory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.estimatedCalories = estimatedCalories
        self.estimatedProteins = estimatedProteins
        self.estimatedFats = estimatedFats
        self.estimatedCarbs = estimatedCarbs
        self.impactScore = impactScore
        self.reason = reason
        self.saturatedFats = saturatedFats
        self.sugar = sugar
        self.fiber = fiber
        self.sodium = sodium
        self.foodCategory = foodCategory
    }

    var baseGrams: Double {
        max(0.1, grams)
    }

    mutating func updateGrams(_ newValue: Double) {
        let clamped = max(1, newValue)
        let scale = clamped / baseGrams
        grams = clamped
        estimatedCalories *= scale
        estimatedProteins *= scale
        estimatedFats *= scale
        estimatedCarbs *= scale
        saturatedFats *= scale
        sugar *= scale
        fiber *= scale
        sodium *= scale
    }
}

struct MealExecutionStep: Identifiable, Equatable {
    let id: UUID
    var type: MealStepType
    var day: Date
    var windowId: String
    var title: String
    var products: [MealProductDraft]
    var sourceText: String
    var state: MealStepState
    var resolveKind: MealResolveKind?

    init(
        id: UUID = UUID(),
        type: MealStepType,
        day: Date,
        windowId: String,
        title: String,
        products: [MealProductDraft],
        sourceText: String,
        state: MealStepState = .readyForConfirm,
        resolveKind: MealResolveKind? = nil
    ) {
        self.id = id
        self.type = type
        self.day = DashboardDateLogic.startOfDay(day)
        self.windowId = windowId
        self.title = title
        self.products = products
        self.sourceText = sourceText
        self.state = state
        self.resolveKind = resolveKind
    }
}

struct MealExecutionSession: Equatable {
    let id: UUID
    var scenario: MealScenario
    var originalMessage: String
    var steps: [MealExecutionStep]
    var activeStepIndex: Int

    init(
        id: UUID = UUID(),
        scenario: MealScenario,
        originalMessage: String,
        steps: [MealExecutionStep],
        activeStepIndex: Int = 0
    ) {
        self.id = id
        self.scenario = scenario
        self.originalMessage = originalMessage
        self.steps = steps
        self.activeStepIndex = activeStepIndex
    }

    var activeStep: MealExecutionStep? {
        guard steps.indices.contains(activeStepIndex) else { return nil }
        return steps[activeStepIndex]
    }
}

@MainActor
final class AgentSessionStore: ObservableObject {
    @Published var phase: AgentShellPhase = .idle
    @Published var activeDomain: AgentDomain?
    @Published var mealSession: MealExecutionSession?

    var isChatPresented: Bool {
        phase == .chatInput || phase == .planning
    }

    var hasActiveSession: Bool {
        activeDomain != nil && phase != .idle && phase != .cancelled && phase != .completed
    }

    func presentChat(for domain: AgentDomain) {
        guard !hasActiveSession else { return }
        activeDomain = domain
        phase = .chatInput
    }

    func beginPlanning() {
        phase = .planning
    }

    func startMealExecution(_ session: MealExecutionSession) {
        activeDomain = .meal
        mealSession = session
        phase = .executing
    }

    func handleChatPresentationChange(isPresented: Bool) {
        guard !isPresented else { return }
        guard phase == .chatInput || phase == .planning else { return }
        resetToIdle()
    }

    func updateMealSession(_ mutate: (inout MealExecutionSession) -> Void) {
        guard var session = mealSession else { return }
        mutate(&session)
        mealSession = session
    }

    func markCompleted() {
        phase = .completed
    }

    func cancel() {
        mealSession = nil
        phase = .cancelled
        activeDomain = nil
    }

    func resetToIdle() {
        mealSession = nil
        phase = .idle
        activeDomain = nil
    }
}

struct MealScenarioClassification: Equatable {
    let scenario: MealScenario
    let resolvedDay: Date
}

enum AgentRouteResult: Equatable {
    case meal
}

enum AgentScenarioRouter {
    static func route(message: String) -> AgentRouteResult {
        _ = message
        return .meal
    }
}
