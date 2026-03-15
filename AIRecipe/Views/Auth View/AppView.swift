import SwiftUI

struct LoginView: View{
    @State private var email = ""
    @State private var password: String = ""
    var body: some View {
        NavigationStack {
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
                        .boxStyle(cornerRadius: 5)
                        .cornerRadius(10)
                        .padding(.horizontal,24)
                    
                    SecureField("Enter your password", text:$password)
                        .font(.subheadline)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .boxStyle(cornerRadius: 5)
                        .cornerRadius(10)
                        .padding(.horizontal,24)
                }
                Button {} label: {
                    Text("Login")
                        .frame(width:360,height:48)
                        .font(.headline)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                .padding(.vertical)
                
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

#Preview {
    LoginView()
}
