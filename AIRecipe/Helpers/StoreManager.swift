//
//  StoreManager.swift
//  AIRecipeApp
//
//  Created by Bryan Chen on 2026/3/14.
//

import Foundation
import StoreKit
@Observable class StoreManager {
    var products: [Product] = []
    
    // 1. Fetch products from App Store Connect
    func fetchProducts() async {
        do {
            self.products = try await Product.products(for: ["com.airecipe.unlimited"])
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }

    // 2. Start the purchase process
    func purchase() async {
        guard let product = products.first else { return }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // verification.jwsRepresentation is the encrypted receipt
                // We send this to Supabase to unlock "Pro" features
                //await verifyWithSupabase(jws: verification.jwsRepresentation)
                print("User bought")
            case .userCancelled:
                print("User backed out")
            default:
                break
            }
        } catch {
            print("Purchase failed")
        }
    }
}
