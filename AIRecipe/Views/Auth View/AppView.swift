import SwiftUI
import Auth
import AuthenticationServices

struct LoginView: View{
    let onSignedIn: (ASAuthorizationAppleIDCredential) -> Void
    let onError: (Error) -> Void
    @State private var email = ""
    @State private var password: String = ""
    @Environment(AuthManager.self) private var authManager
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("Let Him Cook")
                    .font(.largeTitle)
                    .bold()
                    .fontDesign(Font.Design.serif)
                Text("Viral Reels To Recipe")
                    .font(.title2)
                    .fontDesign(Font.Design.serif)
                    .padding(.bottom,60)
                   
                VStack(spacing:8){
                    TextField("Enter your email", text: $email)
                        .autocapitalization(.none)
                        .font(.subheadline)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .boxStyle(cornerRadius: 10)
                        .cornerRadius(10)
                        .padding(.horizontal,24)
                    
                    SecureField("Enter your password", text:$password)
                        .font(.subheadline)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .boxStyle(cornerRadius: 10)
                        .cornerRadius(10)
                        .padding(.horizontal,24)
                }
                Button {signIn()} label: {
                    Text("Login")
                        .frame(width:300,height:54)
                        .font(.title2)
                        .fontDesign(.serif)
                        .background(Color.white)
                        .boxStyle(cornerRadius: 10)
                        .cornerRadius(8)
                        .foregroundColor(.black)
                }
                .padding(.vertical)
                
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task {
                        do {
                            switch result {
                            case .success(let authorization):
                                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                   let idToken = appleIDCredential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) {
                                    
                                    try await SupabaseService.shared.client.auth.signInWithIdToken(
                                        credentials: .init(provider: .apple, idToken: idToken)
                                    )
                                    
                                    // Apple only sends fullName on the very first login
                                    if let name = appleIDCredential.fullName {
                                        let firstName = name.givenName ?? ""
                                        let lastName = name.familyName ?? ""
                                        
                                        let attributes = UserAttributes(
                                            data: [
                                                "first_name": .string(firstName),
                                                "last_name": .string(lastName)
                                            ]
                                        )
                                        
                                        try await SupabaseService.shared.client.auth.update(user: attributes)
                                    }
                                    
                                    await authManager.getAuthState()
                                }
                            case .failure(let error):
                                print("Apple Auth failed: \(error.localizedDescription)")
                            }
                        } catch {
                            print("Apple Sign-In error: \(error.localizedDescription)")
                        }
                    }
                }
                .frame(width:300,height:54)
                
                        Spacer()
                        
                        Divider()
                        
                        NavigationLink {
                            RegistrationView()
                                .navigationBarBackButtonHidden(true)
                        } label: {
                            HStack(spacing: 3) {
                                Text("Don't have an account?")
                                Text("Sign Up")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
        }

private extension LoginView{
    func signIn(){
        Task{
            await authManager.login(withEmail:email, password: password)
        }
    }
}

#Preview {
    LoginView(onSignedIn: { _ in }, onError: { _ in })
        .environment(AuthManager(service: SupabaseService()))
}

   
    
