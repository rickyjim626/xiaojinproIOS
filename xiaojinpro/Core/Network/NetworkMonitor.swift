//
//  NetworkMonitor.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation
import Network
import Combine

// MARK: - Network Monitor
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    @Published private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown

        var displayName: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "蜂窝网络"
            case .ethernet: return "以太网"
            case .unknown: return "未知"
            }
        }

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .ethernet: return "cable.connector"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let status = path.status
            let isExpensivePath = path.isExpensive
            let usesWifi = path.usesInterfaceType(.wifi)
            let usesCellular = path.usesInterfaceType(.cellular)
            let usesEthernet = path.usesInterfaceType(.wiredEthernet)

            Task { @MainActor [weak self] in
                self?.updateConnectionStatusFromPath(
                    status: status,
                    isExpensive: isExpensivePath,
                    usesWifi: usesWifi,
                    usesCellular: usesCellular,
                    usesEthernet: usesEthernet
                )
            }
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    private func updateConnectionStatusFromPath(
        status: NWPath.Status,
        isExpensive isExpensivePath: Bool,
        usesWifi: Bool,
        usesCellular: Bool,
        usesEthernet: Bool
    ) {
        isConnected = status == .satisfied
        isExpensive = isExpensivePath

        if usesWifi {
            connectionType = .wifi
        } else if usesCellular {
            connectionType = .cellular
        } else if usesEthernet {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }

        // Trigger sync when connection is restored
        if isConnected {
            Task {
                await OfflineQueueManager.shared.syncPendingActions()
            }
        }
    }
}

// MARK: - Network Status Banner
import SwiftUI

struct NetworkStatusBanner: View {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showBanner = false

    var body: some View {
        VStack {
            if showBanner && !networkMonitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)

                    Text("网络连接已断开")
                        .font(.caption)

                    Spacer()

                    Button {
                        withAnimation {
                            showBanner = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red)
                .foregroundColor(.white)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: networkMonitor.isConnected)
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            withAnimation {
                showBanner = !isConnected
            }
        }
    }
}

// MARK: - Connection Status View
struct ConnectionStatusView: View {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var offlineQueue = OfflineQueueManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Connection indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(networkMonitor.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Image(systemName: networkMonitor.connectionType.icon)
                    .font(.caption)

                Text(networkMonitor.isConnected ? "已连接" : "已断开")
                    .font(.caption)
            }

            // Pending actions indicator
            if !offlineQueue.pendingActions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)

                    Text("\(offlineQueue.pendingActions.count) 待同步")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }

            // Syncing indicator
            if offlineQueue.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)

                    Text("同步中...")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Retry Manager
@MainActor
class RetryManager: ObservableObject {
    static let shared = RetryManager()

    @Published var retryingRequests: [String: RetryInfo] = [:]

    struct RetryInfo {
        let requestId: String
        var attempts: Int
        var lastError: String?
        var nextRetryAt: Date?
    }

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2.0

    func executeWithRetry<T>(
        requestId: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempts = 0
        var lastError: Error?

        while attempts < maxRetries {
            do {
                let result = try await operation()
                retryingRequests.removeValue(forKey: requestId)
                return result
            } catch {
                attempts += 1
                lastError = error

                let delay = baseDelay * pow(2, Double(attempts - 1))
                let nextRetry = Date().addingTimeInterval(delay)

                retryingRequests[requestId] = RetryInfo(
                    requestId: requestId,
                    attempts: attempts,
                    lastError: error.localizedDescription,
                    nextRetryAt: nextRetry
                )

                if attempts < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        retryingRequests.removeValue(forKey: requestId)
        throw lastError ?? NetworkError.maxRetriesExceeded
    }
}

enum NetworkError: Error, LocalizedError {
    case maxRetriesExceeded
    case noConnection

    var errorDescription: String? {
        switch self {
        case .maxRetriesExceeded: return "重试次数已达上限"
        case .noConnection: return "无网络连接"
        }
    }
}

// MARK: - Offline Aware View Modifier
struct OfflineAwareModifier: ViewModifier {
    @StateObject private var networkMonitor = NetworkMonitor.shared

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
                .disabled(!networkMonitor.isConnected)
                .opacity(networkMonitor.isConnected ? 1 : 0.6)

            NetworkStatusBanner()
        }
    }
}

extension View {
    func offlineAware() -> some View {
        modifier(OfflineAwareModifier())
    }
}
