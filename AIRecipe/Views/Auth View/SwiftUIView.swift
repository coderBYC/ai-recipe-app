import SwiftUI

struct RegistrationView: View {
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var passwordsMatch = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    var body: some View {
        VStack {
            Spacer()
            Text("Let Him Cook")
                .appFont(.largeTitle)
                .fontWeight(.bold)
            Text("Viral Reels To Recipe")
                .appFont(.title2)
                .padding(.bottom,60)
            VStack(spacing:8){
                TextField("Enter your email", text: $email)
                    .autocapitalization(.none)
                    .appFont(.body)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .boxStyle(cornerRadius: 10)
                    .cornerRadius(10)
                    .padding(.horizontal,24)
                TextField("Enter your username", text: $username)
                    .autocapitalization(.none)
                    .appFont(.body)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .boxStyle(cornerRadius: 10)
                    .cornerRadius(10)
                    .padding(.horizontal,24)
                    
                ZStack(alignment: .trailing) {
                    SecureField("Enter your password", text: $password)
                        .appFont(.body)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .boxStyle(cornerRadius: 10)
                        .cornerRadius(10)
                    
                    if !password.isEmpty && !confirmedPassword.isEmpty {
                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(passwordsMatch ? .green : .red)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 24)
                
                ZStack(alignment: .trailing) {
                    SecureField("Confirm your password", text: $confirmedPassword)
                        .appFont(.body)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .boxStyle(cornerRadius: 10)
                        .cornerRadius(10)
                    
                    if !password.isEmpty && !confirmedPassword.isEmpty {
                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(passwordsMatch ? .green : .red)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 24)
                .onChange(of:confirmedPassword){ oldValue, newValue in
                    passwordsMatch = newValue == password
                }
            }
            Button {signUp()} label: {
                Text("Sign Up")
                    .frame(width:360,height:48)
                    .appFont(.headlineBold)
                    .background(Color.black)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            .padding(.vertical)
            
            Spacer()
            
            Divider()
            
            Button{dismiss()} label:{
                HStack(spacing: 3) {
                    Text("Already have an account? ")
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                        .appFont(.body)
            }
            .padding(.vertical, 16)
        }
        .errorPopup(message: Binding(
            get: { authManager.error?.localizedDescription },
            set: { newValue in
                if newValue == nil { authManager.error = nil }
            }
        ))
    }
}

private extension RegistrationView {
    func signUp() {
        Task{
            await authManager.signup(withEmail: email, password: password)
        }
    }
}

#Preview {
    RegistrationView()
        .environment(AuthManager(service: SupabaseService()))
}
