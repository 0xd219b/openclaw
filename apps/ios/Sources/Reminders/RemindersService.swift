import EventKit
import Foundation
import OpenClawKit

final class RemindersService: RemindersServicing {
    func list(params: OpenClawRemindersListParams) async throws -> OpenClawRemindersListPayload {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let authorized = EventKitAuthorization.allowsRead(status: status)
        guard authorized else {
            throw NSError(domain: "Reminders", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "REMINDERS_PERMISSION_REQUIRED: grant Reminders permission",
            ])
        }

        let limit = max(1, min(params.limit ?? 50, 500))
        let statusFilter = params.status ?? .incomplete

        let predicate = store.predicateForReminders(in: nil)
        let payload: [OpenClawReminderPayload] = try await withCheckedThrowingContinuation { cont in
            store.fetchReminders(matching: predicate) { items in
                let filtered = (items ?? []).filter { reminder in
                    switch statusFilter {
                    case .all:
                        return true
                    case .completed:
                        return reminder.isCompleted
                    case .incomplete:
                        return !reminder.isCompleted
                    }
                }
                let selected = Array(filtered.prefix(limit))
                let payload = selected.map { Self.buildPayload(from: $0) }
                cont.resume(returning: payload)
            }
        }

        return OpenClawRemindersListPayload(reminders: payload)
    }

    func add(params: OpenClawRemindersAddParams) async throws -> OpenClawRemindersAddPayload {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let authorized = EventKitAuthorization.allowsWrite(status: status)
        guard authorized else {
            throw NSError(domain: "Reminders", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "REMINDERS_PERMISSION_REQUIRED: grant Reminders permission",
            ])
        }

        let title = params.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw NSError(domain: "Reminders", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "REMINDERS_INVALID: title required",
            ])
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let notes = params.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            reminder.notes = notes
        }
        reminder.calendar = try Self.resolveList(
            store: store,
            listId: params.listId,
            listName: params.listName)

        if let dueISO = params.dueISO?.trimmingCharacters(in: .whitespacesAndNewlines), !dueISO.isEmpty {
            let formatter = ISO8601DateFormatter()
            guard let dueDate = formatter.date(from: dueISO) else {
                throw NSError(domain: "Reminders", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "REMINDERS_INVALID: dueISO must be ISO-8601",
                ])
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueDate)
            // Add an alarm so the user receives a notification at the due time.
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        if let priority = params.priority {
            guard priority >= 0, priority <= 9 else {
                throw NSError(domain: "Reminders", code: 9, userInfo: [
                    NSLocalizedDescriptionKey: "REMINDERS_INVALID: priority must be 0-9",
                ])
            }
            reminder.priority = priority
        }

        if let recurrence = params.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !recurrence.isEmpty
        {
            guard let frequency = Self.parseRecurrenceFrequency(recurrence) else {
                throw NSError(domain: "Reminders", code: 7, userInfo: [
                    NSLocalizedDescriptionKey: "REMINDERS_INVALID: recurrence must be daily, weekly, monthly, or yearly",
                ])
            }
            guard reminder.dueDateComponents != nil else {
                throw NSError(domain: "Reminders", code: 8, userInfo: [
                    NSLocalizedDescriptionKey: "REMINDERS_INVALID: dueISO is required when setting recurrence",
                ])
            }
            let interval = max(1, params.recurrenceInterval ?? 1)
            var end: EKRecurrenceEnd?
            if let endISO = params.recurrenceEndISO?.trimmingCharacters(in: .whitespacesAndNewlines), !endISO.isEmpty {
                let endFormatter = ISO8601DateFormatter()
                if let endDate = endFormatter.date(from: endISO) {
                    end = EKRecurrenceEnd(end: endDate)
                }
            }
            let rule = EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: interval,
                end: end)
            reminder.recurrenceRules = [rule]
        }

        try store.save(reminder, commit: true)

        let payload = Self.buildPayload(from: reminder)

        return OpenClawRemindersAddPayload(reminder: payload)
    }

    private static func resolveList(
        store: EKEventStore,
        listId: String?,
        listName: String?) throws -> EKCalendar
    {
        if let id = listId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
           let calendar = store.calendar(withIdentifier: id)
        {
            return calendar
        }

        if let title = listName?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            if let calendar = store.calendars(for: .reminder).first(where: {
                $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return calendar
            }
            throw NSError(domain: "Reminders", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "REMINDERS_LIST_NOT_FOUND: no list named \(title)",
            ])
        }

        if let fallback = store.defaultCalendarForNewReminders() {
            return fallback
        }

        throw NSError(domain: "Reminders", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "REMINDERS_LIST_NOT_FOUND: no default list",
        ])
    }

    private static func buildPayload(from reminder: EKReminder) -> OpenClawReminderPayload {
        let formatter = ISO8601DateFormatter()
        let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let rule = reminder.recurrenceRules?.first
        return OpenClawReminderPayload(
            identifier: reminder.calendarItemIdentifier,
            title: reminder.title,
            dueISO: due.map { formatter.string(from: $0) },
            completed: reminder.isCompleted,
            listName: reminder.calendar.title,
            recurrence: rule.flatMap { Self.frequencyName($0.frequency) },
            recurrenceInterval: rule.map { $0.interval },
            priority: reminder.priority != 0 ? reminder.priority : nil)
    }

    private static func parseRecurrenceFrequency(_ value: String) -> EKRecurrenceFrequency? {
        switch value {
        case "daily": return .daily
        case "weekly": return .weekly
        case "monthly": return .monthly
        case "yearly": return .yearly
        default: return nil
        }
    }

    private static func frequencyName(_ frequency: EKRecurrenceFrequency) -> String? {
        switch frequency {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return nil
        }
    }
}
