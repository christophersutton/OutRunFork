//
//  ContributorsView.swift
//
//  OutRun
//
//  Lists the people who contributed to OutRun, grouped into maintainers, code contributors and translators
//  (sourced from `Contribution`). Tapping a row opens that contributor's URL in the browser.
//

import SwiftUI

struct ContributorsView: View {

    var body: some View {
        Form {
            section(
                title: LS["Settings.Contribution.Maintainers"],
                contributors: Contribution.maintainers
            )
            section(
                title: LS["Settings.Contribution.CodeContributors"],
                contributors: Contribution.contributors
            )
            section(
                title: LS["Settings.Contribution.Translators"],
                contributors: Contribution.translators
            )
        }
        .navigationTitle(LS["Settings.Contribution"])
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(title: String, contributors: [Contribution.Contributor]) -> some View {
        if !contributors.isEmpty {
            Section {
                ForEach(contributors, id: \.url) { contributor in
                    Button {
                        if let url = URL(string: contributor.url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text(contributor.name)
                                .foregroundStyle(Color.orPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(Color.orSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
            } header: {
                Text(title)
            }
        }
    }
}
