import SwiftUI

struct RejseplanenAPISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let showsDismissControls: Bool

    @State private var baseURLString: String
    @State private var accessID: String
    @State private var apiVersion: String
    @State private var bearerToken: String
    @State private var validationMessage: String?

    init(
        settings: RejseplanenAPISettings = AppConfig.currentAPISettings,
        showsDismissControls: Bool = false
    ) {
        self.showsDismissControls = showsDismissControls
        _baseURLString = State(initialValue: settings.baseURLString)
        _accessID = State(initialValue: settings.accessID)
        _apiVersion = State(initialValue: settings.apiVersion)
        _bearerToken = State(initialValue: settings.authorizationBearerToken ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("https://www.rejseplanen.dk/api", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                TextField(L10n.tr("settings.api.accessID"), text: $accessID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(L10n.tr("settings.api.version"), text: $apiVersion)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(L10n.tr("settings.api.bearer"), text: $bearerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(L10n.tr("settings.api.section"))
            } footer: {
                Text(validationMessage ?? L10n.tr("settings.api.footer"))
            }

            Section {
                Button(L10n.tr("settings.api.reset")) {
                    AppConfig.clearUserAPISettings()
                    dismiss()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle(L10n.tr("settings.api.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDismissControls {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.tr("common.save")) {
                    save()
                }
            }
        }
    }

    private func save() {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.isEmpty, URL(string: trimmedBaseURL) == nil {
            validationMessage = L10n.tr("settings.api.invalidBaseURL")
            return
        }

        AppConfig.saveAPISettings(
            baseURLString: baseURLString,
            accessID: accessID,
            apiVersion: apiVersion,
            authorizationBearerToken: bearerToken
        )
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RejseplanenAPISettingsView()
    }
}
