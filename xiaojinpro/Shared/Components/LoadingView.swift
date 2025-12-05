//
//  LoadingView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct LoadingView: View {
    var message: String = "加载中..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let action = action, let actionTitle = actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let error: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("出错了")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let retryAction = retryAction {
                Button("重试", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Loading") {
    LoadingView()
}

#Preview("Empty") {
    EmptyStateView(
        icon: "bubble.left.and.bubble.right",
        title: "暂无对话",
        message: "开始一个新对话吧",
        action: {},
        actionTitle: "新建对话"
    )
}

#Preview("Error") {
    ErrorView(error: "网络连接失败", retryAction: {})
}
