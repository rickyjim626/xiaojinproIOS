//
//  Date+Extensions.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

extension String {
    var iso8601Date: Date? {
        ISO8601DateFormatter().date(from: self)
    }
}
