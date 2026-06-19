//
//  PolicyView.swift
//
//  OutRun
//
//  SwiftUI replacement for PolicyViewController — renders the terms / privacy policy text.
//

import SwiftUI

struct PolicyView: View {

    let type: PolicyManager.PolicyType
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        Text(text ?? LS["Error"])
                            .font(.system(size: 14))
                            .foregroundStyle(Color.orPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.orBackground)
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.orSecondary)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        text = await withCheckedContinuation { continuation in
            PolicyManager.query(for: type) { _, error, string in
                if let error {
                    continuation.resume(returning: "Error - \(error.localizedDescription)")
                } else {
                    continuation.resume(returning: string ?? LS["Error"])
                }
            }
        }
        isLoading = false
    }
}
