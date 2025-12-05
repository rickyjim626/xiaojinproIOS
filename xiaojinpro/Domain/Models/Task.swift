//
//  Task.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Task Status
enum TaskStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case succeeded = "succeeded"
    case failed = "failed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .pending: return "等待中"
        case .running: return "执行中"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .pending: return "gray"
        case .running: return "blue"
        case .succeeded: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        default: return false
        }
    }
}

// MARK: - Task Source
enum TaskSource: String, Codable {
    case cli = "cli"
    case ios = "ios"
    case web = "web"
    case scheduler = "scheduler"
    case unknown = "unknown"
}

// MARK: - Task
struct XJPTask: Codable, Identifiable {
    var id: String
    let skillName: String
    var status: TaskStatus
    let createdBy: String?
    let createdFrom: TaskSource
    let arguments: [String: AnyCodable]?
    var result: AnyCodable?
    var error: String?
    var progress: Int?
    var progressMessage: String?
    let startedAt: Date?
    let completedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case skillName = "skill_name"
        case status
        case createdBy = "created_by"
        case createdFrom = "created_from"
        case arguments
        case result
        case error
        case progress
        case progressMessage = "progress_message"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    var duration: TimeInterval? {
        guard let startedAt = startedAt else { return nil }
        let endTime = completedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Task Log Entry
struct TaskLogEntry: Codable, Identifiable {
    let id: String
    let taskId: String
    let level: LogLevel
    let message: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case level
        case message
        case timestamp
    }

    enum LogLevel: String, Codable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
    }
}

// MARK: - Tasks Response
struct TasksResponse: Codable {
    let tasks: [XJPTask]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case tasks
        case total
        case hasMore = "has_more"
    }
}

// MARK: - Task Filter
struct TaskFilter {
    var status: TaskStatus?
    var skillName: String?
    var source: TaskSource?
    var fromDate: Date?
    var toDate: Date?
    var limit: Int = 50
    var offset: Int = 0

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let status = status {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let skillName = skillName {
            items.append(URLQueryItem(name: "skill", value: skillName))
        }
        if let source = source {
            items.append(URLQueryItem(name: "source", value: source.rawValue))
        }
        if let fromDate = fromDate {
            items.append(URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: fromDate)))
        }
        if let toDate = toDate {
            items.append(URLQueryItem(name: "to", value: ISO8601DateFormatter().string(from: toDate)))
        }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        items.append(URLQueryItem(name: "offset", value: String(offset)))

        return items
    }
}
