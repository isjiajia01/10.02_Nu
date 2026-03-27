import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RejseplanenAPISettingsView()
                    } label: {
                        Label(L10n.tr("settings.api.title"), systemImage: "key.horizontal")
                    }
                } footer: {
                    Text(L10n.tr("settings.footer"))
                }
            }
            .navigationTitle(L10n.tr("settings.title"))
        }
    }
}

#Preview {
    SettingsView()
}
