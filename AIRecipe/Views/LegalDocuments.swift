import SwiftUI

// MARK: - Presentation

enum LegalDocumentKind: String, Identifiable {
    case termsOfService
    case privacyAndAI

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .termsOfService: return "Terms of Service"
        case .privacyAndAI: return "Privacy & AI Policy"
        }
    }
}

struct LegalDocumentReaderView: View {
    let kind: LegalDocumentKind
    @Environment(\.dismiss) private var dismiss

    /// Strips markdown emphasis markers from copy for plain-text display.
    private var displayText: String {
        kind.bodyText.replacingOccurrences(of: "**", with: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(displayText)
                    .appFont(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationTitle(kind.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Copy (Let Him Cook · Taiwan · June 1, 2026)

private extension LegalDocumentKind {
    var bodyText: String {
        switch self {
        case .termsOfService: return Self.termsOfServiceMarkdown
        case .privacyAndAI: return Self.privacyAndAIMarkdown
        }
    }

    static let termsOfServiceMarkdown = """
    Last updated: June 1, 2026

    These Terms of Service (“Terms”) govern your use of the mobile application Let Him Cook (“App”), offered by the developer based in Taiwan (“we,” “us,” “our”). By downloading, accessing, or using the App, you agree to these Terms. If you do not agree, do not use the App.

    1. The service
    The App helps you save, organize, and edit recipes and related content, including by processing links or media you submit. Features may include recipe import and editing, cook mode, meal planning, grocery lists (including AI-assisted merging for subscribers), fridge inventory tracking (including optional photo scanning for subscribers), bookmarks, and recipe export (including PDF for subscribers). Features may change; we may modify, suspend, or discontinue any part of the App where permitted by law.

    2. Eligibility and account
    You must be able to enter a binding agreement in your jurisdiction. You are responsible for your account credentials and for all activity under your account. Provide accurate information when requested.

    3. Acceptable use
    You agree not to: (a) misuse, reverse engineer, or attempt to gain unauthorized access to the App or our systems; (b) interfere with the App’s operation or other users; (c) use the App for unlawful purposes or to infringe others’ rights; (d) submit content you do not have the right to use. We may suspend or terminate access for violations.

    4. User content and third-party links
    You may submit URLs (e.g. to videos), **select videos or photos from your photo library** for upload and analysis, enter fridge and grocery items, and other inputs. You represent that you have the right to submit them and that doing so complies with the relevant platform’s terms. Third-party sites and content are not controlled by us; your use of third-party services is at your own risk.

    5. Subscriptions and payments
    Paid features (“Let Him Cook Pro” or similar) may be offered via Apple’s In-App Purchase system and related tools. Pro may include, among other things: fridge tracking and AI photo scanning, AI grocery list merging, per-recipe nutrition estimates, and PDF recipe export. Free-tier limits (e.g. on imports or exports) may apply as shown in the App. Pricing, renewal, cancellation, and refunds are subject to Apple’s terms and policies and the disclosures shown in the App at purchase. Subscription benefits are described in the App before you buy.

    6. Third-party services
    The App may rely on service providers (e.g. authentication, cloud infrastructure, subscription status, analytics, AI processing). Their processing is described in our Privacy & AI Policy and subject to their respective terms.

    7. Disclaimers
    THE APP IS PROVIDED “AS IS” AND “AS AVAILABLE.” WE DISCLAIM WARRANTIES TO THE FULLEST EXTENT PERMITTED BY LAW, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

    Cooking and food safety: Recipe information in the App may be incomplete or inaccurate. You are solely responsible for allergies, dietary needs, food safety, and verifying information before cooking or consuming food.

    AI-assisted features: Outputs from recipe import, grocery merge, fridge photo scanning, and nutrition estimates are **automated estimates only**. They may be wrong about ingredients, quantities, expiration dates, or nutritional values. **Always rely on your own inspection of food and packaging**, not on AI-generated dates or scanner readings. Nutrition information is **not medical or dietary advice**.

    8. Limitation of liability
    TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW (INCLUDING THE LAWS OF THE REPUBLIC OF CHINA (TAIWAN)), WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, DATA, OR GOODWILL. OUR TOTAL LIABILITY FOR ANY CLAIM ARISING OUT OF OR RELATED TO THE APP SHALL NOT EXCEED THE GREATER OF (A) THE AMOUNT YOU PAID US FOR THE APP OR IN-APP PURCHASES IN THE TWELVE (12) MONTHS BEFORE THE CLAIM OR (B) NT$1,000, EXCEPT WHERE SUCH LIMITATION IS PROHIBITED BY MANDATORY CONSUMER LAW.

    9. Indemnity
    You agree to indemnify and hold us harmless from claims arising from your use of the App, your content, or your breach of these Terms, to the extent permitted by law.

    10. Governing law and jurisdiction
    These Terms are governed by the laws of the **Republic of China (Taiwan)**, without regard to conflict-of-law rules. You agree that the courts of **Taipei, Taiwan** shall have exclusive jurisdiction over disputes arising from these Terms or the App, subject to any mandatory rights you have under consumer protection laws that cannot be waived.

    11. Changes
    We may update these Terms. We will post the revised Terms in the App and update the “Last updated” date. Continued use after changes constitutes acceptance, except where stricter notice or consent is required by law.

    12. Contact
    For questions about these Terms, contact us using the support channel listed on the App’s App Store product page.
    """

    static let privacyAndAIMarkdown = """
    Last updated: June 1, 2026

    This Privacy & AI Policy describes how **Let Him Cook** (“App”), offered by the developer based in **Taiwan** (“we,” “us”), collects, uses, and shares information when you use the App.

    1. Scope
    This policy applies to personal data processed through the App. It should be read together with Apple’s data practices for the App Store and your device settings.

    2. Information we collect
    • **Account and sign-in:** Identifiers and contact information needed to create or access an account (e.g. email), depending on the sign-in methods we offer.
    • **Content you provide:** URLs you submit for recipe extraction; recipes you save or edit (including ingredients, steps, notes, and ratings); meal-plan entries; grocery list items; and fridge inventory items (names, quantities, zones, and expiration dates you enter or confirm).
    • **Photo library and camera (optional):** If you allow access, the App may read **Photos** to detect **recently added videos** so we can suggest building a recipe, to let you **choose a video** to send to our servers for recipe extraction, and to let you **choose up to three photos** (or take a photo with the camera) to scan fridge contents. We do **not** upload your entire library—only files you explicitly select or capture for a feature are sent for processing.
    • **Usage and device data:** App interactions, subscription or entitlement status, diagnostics, app version, and device/OS information needed to operate and secure the service. Export-related usage (e.g. PDF or text share quotas) may be recorded to enforce plan limits.
    • **Purchase data:** Information from Apple and our subscription partners to verify purchases and entitlements.

    We do **not** knowingly sell your personal data in the sense of “sale” under applicable U.S. state privacy laws, and we do not use your data for cross-context behavioral advertising unless we disclose that separately and obtain consent where required.

    3. How we use information
    We use information to: provide and improve the App; authenticate users; sync your library when you use a paid account; process URLs and content you submit; run fridge, grocery, and export features; enforce usage limits and prevent abuse; deliver subscription features; communicate about the service (e.g. support); comply with law; and protect rights and safety.

    4. Legal bases (Taiwan and similar regions)
    Where the **Personal Data Protection Act** and related laws apply, we process personal data based on: performance of a contract with you; our **legitimate interests** (security, fraud prevention, service improvement); **consent** where required (e.g. optional analytics or marketing); and **legal obligations**.

    5. AI and automated processing
    **What happens:** When you submit a supported link, a **video you choose from Photos**, **photos for fridge scanning**, or **grocery ingredients for merging**, our systems—including **third-party AI or cloud services**—may process the text, metadata, images, or related content needed to generate or organize information in the App. Examples include: extracting recipes from video; merging grocery lines; identifying food items and suggested expiration dates from fridge photos; and estimating per-serving nutrition on recipes (Pro).

    **Fridge photos:** Images you submit for fridge scanning are transmitted to our servers for real-time analysis and are **not stored by us as photo files** after processing completes. Structured results (item names, quantities, dates you save) are stored in your account/device as fridge inventory.

    **Accuracy:** AI-assisted output may be **wrong, incomplete, or unsuitable** (e.g. ingredients, steps, times, allergens, item names, expiration dates, or nutrition values). You must verify information, especially for allergies, medical diets, or food safety. **Do not rely on AI for expiration or nutrition decisions.**

    **Human review:** We do not guarantee human review of your inputs or outputs.

    **Model training:** Unless we notify you otherwise in the App, we do **not** use your personal content to train third-party foundation models. If that changes, we will update this policy and obtain consent where required.

    **Retention:** We retain account and recipe data as long as your account is active and as needed to provide the App. Fridge scan **images** are processed transiently and not kept as images on our servers. Other retention may depend on the feature (e.g. cached media thumbnails or analysis results tied to recipes).

    6. Sharing and subprocessors
    We share information with **service providers** who process data on our behalf, such as:
    • Authentication and backend providers (e.g. cloud database/auth services).
    • Subscription and entitlement verification (e.g. RevenueCat or similar) and **Apple** for in-app purchases.
    • AI or cloud providers (e.g. Google Gemini, OpenAI, or similar) that process content you submit to return recipe, grocery, fridge, or nutrition results.
    • Analytics providers, if enabled, as described in the App or your device settings.

    We require appropriate contractual protections. Their privacy policies also apply.

    7. International transfers
    Your information may be processed in **Taiwan** and other countries where we or our providers operate, including the United States. We implement safeguards consistent with applicable law.

    8. Your rights
    Depending on applicable law (including Taiwan’s PDPA where it applies), you may have the right to **access**, **correct**, **delete**, **restrict processing**, **object**, or **export** your personal data, and to **withdraw consent** where processing is consent-based. You may exercise rights by contacting us via the support channel on the App Store listing. You can also adjust some permissions in **iOS Settings** for the App and delete local or synced content (e.g. recipes, fridge items) within the App where available.

    9. Children
    The App is **not directed at children** under the age required by applicable law (e.g. under 13, or the age of digital consent in your country). We do not knowingly collect personal data from children. If you believe we have, contact us and we will delete it promptly.

    10. Security
    We use reasonable technical and organizational measures to protect personal data. No method of transmission or storage is 100% secure.

    11. Changes
    We may update this policy. We will post the new version in the App and change the “Last updated” date. Material changes may require additional notice or consent where required by law.

    12. Contact
    For privacy questions, contact us using the support channel listed on the App’s App Store product page.
    """
}
