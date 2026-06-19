//
//  ChangelogView.swift
//
//  OutRun
//
//  SwiftUI replacement for ChangeLogViewController — a dimmed, tap-to-dismiss card shown after an update.
//

import SwiftUI

struct ChangelogView: View {

    let changelog: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.orSecondary)
                            .imageScale(.large)
                    }
                }

                Text("\(LS["ChangeLog"]) - \(Config.version)")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.orAccent)
                    .lineLimit(1)

                ScrollView {
                    Text(changelog)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .background(Color.orBackground, in: RoundedRectangle(cornerRadius: 25))
            .padding(.horizontal, 25)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 40)
        }
    }
}
