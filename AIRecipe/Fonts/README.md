# Add Roboto Slab fonts

The app uses **[Roboto Slab](https://fonts.google.com/specimen/Roboto+Slab)** for body text. To load it:

## 1. Download the font

- Go to [Google Fonts: Roboto Slab](https://fonts.google.com/specimen/Roboto+Slab)
- Click **Download family** (ZIP)
- Unzip and add one of these options:
  - **Option A (static):** `RobotoSlab-Regular.ttf` and `RobotoSlab-Bold.ttf`
  - **Option B (variable):** `RobotoSlab-VariableFont_wght.ttf` (covers all weights)

## 2. Add the files to Xcode

1. In Xcode, in the **Project Navigator** (left sidebar), right‑click the **AIRecipe** group (or the **Fonts** folder).
2. Choose **Add Files to "AIRecipeApp"...**
3. Select the `.ttf` file(s) from step 1.
4. Leave **Copy items if needed** checked.
5. Under **Add to targets**, ensure **AIRecipeApp** is checked.
6. Click **Add**.

## 3. Register the fonts in Info.plist

The app’s **Info.plist** has **Fonts provided by application** (UIAppFonts) with:

- `RobotoSlab-Regular.ttf`
- `RobotoSlab-Bold.ttf`
- `RobotoSlab-VariableFont_wght.ttf`

Add only the filenames for the font files you actually added to the project. Remove any entries for fonts you didn’t add.

## 4. Confirm they’re in the app target

1. Click the **AIRecipeApp** project in the navigator.
2. Select the **AIRecipeApp** target.
3. Open the **Build Phases** tab.
4. Expand **Copy Bundle Resources**.
5. Ensure your `.ttf` file(s) appear. If not, click **+** and add them.

## 5. Run the app

Build and run. If the font loads, you’ll see in the Xcode console (Debug):

- `AppTheme: Loaded bold font: ...`

If you see **"Roboto Slab not found"**, the font files are not in the bundle or not listed in UIAppFonts. Recheck steps 2–4.

Reference: [Adding a custom font to your app](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app)
