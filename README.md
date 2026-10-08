# Scribble 🎨

> **Leave handwritten scribbles and notes for each other in real-time. Appears directly on your recipient's Android lock screen.**

---

### 🚀 Google Play Store & Android Policy Compliance
For the complete step-by-step checklist, questionnaire answers (Data Safety, Foreground Services, Target Audience), and Keystore / Release App Bundle (`.aab`) building guide, refer to:
👉 **[PLAY_STORE_GUIDELINES.md](file:///c:/Users/Mr.Bunny159/Project/Scribble/PLAY_STORE_GUIDELINES.md)**

- ✅ **Account Deletion Compliant**: Full in-app account deletion + public web deletion portal.
- ✅ **Photo Picker Architecture**: Native Android Photo Picker used (`image_picker`); no restricted media storage permissions.
- ✅ **Foreground Service Justification**: `FOREGROUND_SERVICE_DATA_SYNC` declared with explicit widget/lockscreen rationale.
- ✅ **Modern Target SDK**: Configured for Android 15 (`targetSdk = 35`).
- ✅ **In-App & Web Privacy Policy**: Fully disclosures third-party services (Firebase, Cloudinary) and user rights.

---

## 🌟 Key Features

1. **Lock-Screen Integration (Android Native / Kotlin)**
   - View-only real-time lock screen display using Android `WallpaperManager.FLAG_LOCK`.
   - Automatically adapts to device screen resolution while leaving room for the system clock and notifications.
   - Clears automatically when the sender removes the scribble.
   - User toggle to enable/disable the lock-screen feature anytime.

2. **Web Version (Cross-Platform)**
   - The complete Scribble experience accessible from any desktop or mobile browser.
   - Full real-time synchronization with Android users.
   - **Interactive Android Lock Screen Simulator**: On Web, preview exactly how your scribble renders on your recipient's Android phone lock screen!

3. **Scribble Canvas Studio**
   - High-performance drawing engine with smooth quadratic bezier curve ink strokes.
   - Adjustable pen stroke widths (2px, 4px, 8px, 14px).
   - Rich color palette with instant visual feedback.
   - Eraser tool, undo, redo, and clear canvas with safety confirmation.
   - Draggable text insertion for handwritten-style messages.

4. **Pairing System**
   - Instant 6-character alphanumeric pairing code generation.
   - Connect with multiple friends or switch active partners effortlessly.

5. **User Profile System**
   - Supabase Authentication (Sign up / Sign in with email and password).
   - Custom display name and profile avatar image upload via Supabase Storage.
   - Unique User ID with 1-tap clipboard copy.

6. **Message System & Real-Time Sync**
   - Each connection holds one latest active scribble.
   - Sending a new scribble instantly replaces the previous one across all devices.
   - Realtime delivery powered by Supabase Realtime postgres channels.

---

## 🏗️ Project Architecture

```
                          ONE APK / WEB APP
                                 │
                 ┌───────────────┴───────────────┐
                 │                               │
           Flutter (Frontend)           Android / Kotlin (Native)
                 │                               │
        • UI & Theme System             • MainActivity.kt
        • Canvas Drawing Engine         • WallpaperManager (FLAG_LOCK)
        • Supabase Auth & Realtime      • Device Screen Resolution Sizing
        • Web Lockscreen Simulator      • Background Bitmap Compositor
                 │                               │
                 └───────────────┬───────────────┘
                                 │
                             Supabase
                 ┌───────────────┼───────────────┐
                 │               │               │
            PostgreSQL        Realtime        Storage
         (Profiles, Pairs,   (Instant Sync)  (Avatars,
           Connections,                       Scribbles)
            Scribbles)
```

---

## 🚀 Getting Started

### 1. Supabase Backend Setup
1. Create a project at [supabase.com](https://supabase.com).
2. Open the **SQL Editor** in your Supabase dashboard.
3. Open [`supabase_schema.sql`](file:///c:/Users/Mr.Bunny159/Project/Scribble/supabase_schema.sql) in this repository, copy its contents, and run it. This will:
   - Create `profiles`, `pairing_codes`, `connections`, and `scribbles` tables.
   - Enable Row Level Security (RLS) policies.
   - Add `scribbles` and `connections` to the `supabase_realtime` publication.
   - Create public Storage buckets: `avatars` and `scribbles`.

### 2. Configure Credentials
You can configure your credentials in either of two ways:
- **Option A (In-App UI)**: Launch the app; it will automatically show the **Supabase Setup Screen** where you can paste your Project URL (https://fcnxaewxgsaopwtrzwpn.supabase.co) and Anon Public Key (sb_publishable_O7n9d4rToLX8PuDhhbTYZw_5QDduE_Y).
- **Option B (Code)**: Open [`lib/core/constants.dart`](file:///c:/Users/Mr.Bunny159/Project/Scribble/lib/core/constants.dart) and replace `supabaseUrl` and `supabaseAnonKey`.

---

## 📱 Running the App

### Running on Web
```bash
flutter run -d chrome
```

### Running on Android
```bash
flutter run
```

### Building Release APK
```bash
flutter build apk --release
```

---

## 🔒 Android Permissions Explained

In [`android/app/src/main/AndroidManifest.xml`](file:///c:/Users/Mr.Bunny159/Project/Scribble/android/app/src/main/AndroidManifest.xml), we request only the necessary permissions:
- `INTERNET` & `ACCESS_NETWORK_STATE`: For Supabase / Firebase auth, realtime sync, and connection detection.
- `SET_WALLPAPER`: Required to set the device lock-screen wallpaper with received scribbles via `WallpaperManager.FLAG_LOCK`.
- `POST_NOTIFICATIONS`: To receive update alerts and support the lock-screen experience (Android 13+).
- `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`: For background update processing.
- `READ_MEDIA_IMAGES` & `READ_EXTERNAL_STORAGE`: For choosing a profile avatar image from the photo gallery.

---

## 🎨 App Logo & Branding

The Scribble app features a custom neon-gradient glowing ribbon forming an infinity heart and fountain pen nib.
- Asset path: `assets/images/app_logo.png`
- Reusable Flutter component: `ScribbleLogo` and `ScribbleBrandHeader` in [`lib/widgets/scribble_logo.dart`](lib/widgets/scribble_logo.dart)
- Native Android launcher icon: Mipmap resources across all densities (`mipmap-mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`).
- Present throughout the app:
  1. **Authentication Screen**: Large glowing branding hero.
  2. **Main Hub AppBar**: Header mark alongside active screen tabs.
  3. **Profile Screen**: Version and branding footer.
  4. **Home Screen**: Native Android App Launcher icon.

---

## ☁️ Cloudinary Image Hosting Setup (2-Minute Guide)

Scribble supports fast, high-speed CDN image hosting via Cloudinary (with automatic fallback to Firebase Storage). To use Cloudinary:

### 1. Create a Free Account
1. Visit **[cloudinary.com](https://cloudinary.com/)** and sign up for a free account (no credit card required).

### 2. Get Your Cloud Name
1. Once logged in, open the **Cloudinary Dashboard** / **Console**.
2. Look at the top-left or **Product Environment** section for your **Cloud Name** (e.g. `dxy123abc`).

### 3. Create an Unsigned Upload Preset
1. Click the **Gear icon (Settings)** in the bottom-left corner of Cloudinary.
2. Select the **Upload** tab.
3. Scroll down to **Upload presets** and click **Add upload preset**.
4. Set **Signing Mode** to **Unsigned** (*crucial: this allows the Flutter client to upload securely without exposing your API secret*).
5. Give your preset a name (e.g. `scribble_preset` or keep the auto-generated name).
6. Click **Save** in the top-right corner.

### 4. Activate in Scribble
You can connect Cloudinary in either of two ways:
- **Option A (In-App - Recommended)**:
  Open the app -> Go to **Profile** (top right) -> Tap **Cloudinary Image Hosting** -> Enter your **Cloud Name** and **Upload Preset** -> Tap **Save Cloudinary Settings**.
- **Option B (Code level)**:
  In [`lib/core/constants.dart`](lib/core/constants.dart), set:
  ```dart
  static const String cloudinaryCloudName = 'YOUR_ACTUAL_CLOUD_NAME';
  static const String cloudinaryUploadPreset = 'scribble_preset';
  ```
 #   S c r i b b l e  
 