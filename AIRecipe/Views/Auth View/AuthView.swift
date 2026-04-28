import SwiftUI
import Supabase

struct AuthView: View {
  @State var email = ""
  @State var isLoading = false
  @State var result: Result<Void, Error>?

  var body: some View {
    Form {
      Section {
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }

      Section {
        Button("Sign in") {
          signInButtonTapped()
        }

        if isLoading {
          ProgressView()
        }
      }

      if let result {
        Section {
          if case .success = result {
            Text("Check your inbox.")
          }
        }
      }
    }
    .onOpenURL(perform: { url in
      Task {
        do {
            try await SupabaseService.shared.client.auth.session(from: url)
        } catch {
          self.result = .failure(error)
        }
      }
    })
    .errorPopup(message: Binding(
      get: {
        guard case .failure(let error) = result else { return nil }
        return error.localizedDescription
      },
      set: { newValue in
        if newValue == nil { result = nil }
      }
    ))
  }

  func signInButtonTapped() {
    Task {
      isLoading = true
      defer { isLoading = false }

      do {
          try await SupabaseService.shared.client.auth.signInWithOTP(
            email: email,
            redirectTo: URL(string: "io.supabase.user-management://login-callback")
        )
        result = .success(())
      } catch {
        result = .failure(error)
      }
    }
  }
}
