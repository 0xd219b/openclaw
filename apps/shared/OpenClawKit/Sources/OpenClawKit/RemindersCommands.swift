import Foundation

public enum OpenClawRemindersCommand: String, Codable, Sendable {
    case list = "reminders.list"
    case add = "reminders.add"
}

public enum OpenClawReminderStatusFilter: String, Codable, Sendable {
    case incomplete
    case completed
    case all
}

public struct OpenClawRemindersListParams: Codable, Sendable, Equatable {
    public var status: OpenClawReminderStatusFilter?
    public var limit: Int?

    public init(status: OpenClawReminderStatusFilter? = nil, limit: Int? = nil) {
        self.status = status
        self.limit = limit
    }
}

public struct OpenClawRemindersAddParams: Codable, Sendable, Equatable {
    public var title: String
    public var dueISO: String?
    public var notes: String?
    public var listId: String?
    public var listName: String?
    /// Recurrence frequency: "daily", "weekly", "monthly", "yearly"
    public var recurrence: String?
    /// Number of frequency units between occurrences (default 1)
    public var recurrenceInterval: Int?
    /// ISO-8601 date when recurrence should stop
    public var recurrenceEndISO: String?
    /// Priority: 0 = none, 1 = high, 5 = medium, 9 = low (values outside 0-9 are rejected)
    public var priority: Int?

    public init(
        title: String,
        dueISO: String? = nil,
        notes: String? = nil,
        listId: String? = nil,
        listName: String? = nil,
        recurrence: String? = nil,
        recurrenceInterval: Int? = nil,
        recurrenceEndISO: String? = nil,
        priority: Int? = nil)
    {
        self.title = title
        self.dueISO = dueISO
        self.notes = notes
        self.listId = listId
        self.listName = listName
        self.recurrence = recurrence
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceEndISO = recurrenceEndISO
        self.priority = priority
    }
}

public struct OpenClawReminderPayload: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var dueISO: String?
    public var completed: Bool
    public var listName: String?
    public var recurrence: String?
    public var recurrenceInterval: Int?
    public var priority: Int?

    public init(
        identifier: String,
        title: String,
        dueISO: String? = nil,
        completed: Bool,
        listName: String? = nil,
        recurrence: String? = nil,
        recurrenceInterval: Int? = nil,
        priority: Int? = nil)
    {
        self.identifier = identifier
        self.title = title
        self.dueISO = dueISO
        self.completed = completed
        self.listName = listName
        self.recurrence = recurrence
        self.recurrenceInterval = recurrenceInterval
        self.priority = priority
    }
}

public struct OpenClawRemindersListPayload: Codable, Sendable, Equatable {
    public var reminders: [OpenClawReminderPayload]

    public init(reminders: [OpenClawReminderPayload]) {
        self.reminders = reminders
    }
}

public struct OpenClawRemindersAddPayload: Codable, Sendable, Equatable {
    public var reminder: OpenClawReminderPayload

    public init(reminder: OpenClawReminderPayload) {
        self.reminder = reminder
    }
}
