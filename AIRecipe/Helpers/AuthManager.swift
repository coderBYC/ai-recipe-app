import Foundation
@Observable @MainActor
final class AuthManager: ObservableObject{
    private let service:SupabaseService
    var error:Error?
    var profile: Profile?
    var authState:AuthState = .notDetermined
    init(service: SupabaseService) {
        self.service = service
    }
    func login(withEmail email:String, password: String) async{
        do{
            self.authState = try await service.login(withEmail: email, password: password)
        }catch{
            self.error = error
            print("Error: \(error)")
        }
    }
    
    func signup(withEmail email:String, password: String) async{
        do{
            self.authState = try await service.signUp(withEmail: email, password: password)
        }catch{
            self.error = error
            print("Error: \(error)")
        }
    }
    
    func signOut() async{
        do {
            try await service.signOut()
            self.authState = .notAuthenticated
        }catch{
            print("Error: \(error)")
        }
    }
    
    func getAuthState() async{
        do { self.authState = try await service.getAuthState()}
        catch{
            print("Error: \(error)")
        }
    }
    
    func fetchProfile() async {
            do {
                let user = try await SupabaseService.shared.client.auth.session.user
                let profile: Profile = try await SupabaseService.shared.client
                    .from("profiles")
                    .select()
                    .eq("id", value: user.id)
                    .single()
                    .execute()
                    .value
                
                self.profile = profile
            } catch {
                print("Error fetching profile: \(error)")
            }
        }
    
        func incrementAIUsage() async {
            guard let id = profile?.id else { return }
            try? await SupabaseService.shared.client
                .from("profiles")
                .update(["ai_usage_count": (profile?.aiUsageCount ?? 0) + 1])
                .eq("id", value: id)
                .execute()
        }
    
}

struct Profile: Codable {
    let id: UUID
    var isPro: Bool
    var aiUsageCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case isPro = "is_pro"
        case aiUsageCount = "ai_usage_count"
    }
}

