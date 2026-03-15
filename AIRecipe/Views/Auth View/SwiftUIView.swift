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
            Image(.youTubeIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .padding()
            VStack(spacing:8){
                TextField("Enter your email", text: $email)
                    .autocapitalization(.none)
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .boxStyle(cornerRadius: 10)
                    .cornerRadius(10)
                    .padding(.horizontal,24)
                TextField("Enter your username", text: $username)
                    .autocapitalization(.none)
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .boxStyle(cornerRadius: 10)
                    .cornerRadius(10)
                    .padding(.horizontal,24)
                    
                ZStack(alignment: .trailing) {
                    SecureField("Enter your password", text: $password)
                        .font(.subheadline)
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
                        .font(.subheadline)
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
                    .font(.headline)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            .padding(.vertical)
            
            if let error = authManager.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Divider()
            
            Button{dismiss()} label:{
                HStack(spacing: 3) {
                    Text("Already have an account? ")
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 16)
        }
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
