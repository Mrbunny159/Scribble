# 🚀 Scribble - Google Play Store Compliance & Publishing Guide

This document outlines the **Google Play Developer Policies, Android Regulations, and Step-by-Step Instructions** implemented in Scribble to ensure 100% compliance and pass Google Play Store review without rejections.

---

## 📋 Table of Contents
1. [Summary of Implemented Compliance Features](#1-summary-of-implemented-compliance-features)
2. [Critical Google Play Policy Rules & How Scribble Complies](#2-critical-google-play-policy-rules--how-scribble-complies)
3. [Play Console Submission Questionnaire (Exact Answers)](#3-play-console-submission-questionnaire-exact-answers)
4. [How to Host the Privacy Policy & Deletion URL (Free & Instant)](#4-how-to-host-the-privacy-policy--deletion-url-free--instant)
5. [Production Keystore & Release App Bundle (.aab) Build Guide](#5-production-keystore--release-app-bundle-aab-build-guide)

---

## 1. Summary of Implemented Compliance Features

| Requirement | Google Policy Rule | Status in Scribble | Location in Code |
| :--- | :--- | :--- | :--- |
| **In-App Account Deletion** | Mandatory for apps with account creation | ✅ **Implemented** | `lib/screens/profile/profile_screen.dart`<br>`lib/services/firebase_service.dart` (`deleteAccount()`) |
| **Web Account Deletion Portal** | External link required if user uninstalls app | ✅ **Implemented** | `web/privacy.html` (Section 6: Deletion Form) |
| **In-App Privacy Policy** | Must be accessible within app & before sign-in | ✅ **Implemented** | `lib/screens/legal/privacy_policy_screen.dart`<br>Linked in `AuthScreen` & `ProfileScreen` |
| **Storage Permissions Sanitization** | `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE` restricted | ✅ **Compliant** | Android Photo Picker used (`image_picker`); broad storage permissions removed from `AndroidManifest.xml` |
| **Alarm Permission Sanitization** | `SCHEDULE_EXACT_ALARM` restricted to Alarm/Calendar apps | ✅ **Compliant** | Removed unnecessary exact alarm declarations from `AndroidManifest.xml` |
| **Foreground Service Justification** | Strict policy for `FOREGROUND_SERVICE` types | ✅ **Compliant** | Declared `FOREGROUND_SERVICE_DATA_SYNC` with explicit rationale for lockscreen/widget sync |
| **Target SDK Version** | Must target Android 14 (API 34) or Android 15 (API 35) | ✅ **Compliant** | `android/app/build.gradle.kts` configured with `targetSdk = 35` |

---

## 2. Critical Google Play Policy Rules & How Scribble Complies

### A. Account Deletion Requirement (User Data Policy)
* **Policy Mandate:** If an app enables users to create an account, developers **MUST** provide:
  1. An easily discoverable in-app pathway to permanently delete their account and associated data.
  2. A public web link where users can request account and data deletion without reinstalling the app.
* **Scribble Implementation:**
  - **In-App:** In `ProfileScreen`, non-guest users have a red **"Delete Account Permanently"** button. Confirming this dialog triggers `FirebaseService().deleteAccount()`, which:
    - Permanently deletes all active connections with partners.
    - Purges drawing history archives in Cloud Firestore.
    - Clears native lockscreen cache and widget preferences.
    - Deletes the Firebase Auth user record.
  - **Web Link:** `web/privacy.html` includes a dedicated section and form for web-based account deletion requests.

### B. Photo & Media Permissions Restriction
* **Policy Mandate:** Apps that only require images for user avatars or profile customization **are strictly forbidden** from declaring `READ_MEDIA_IMAGES` or `READ_EXTERNAL_STORAGE`. Apps must instead use system pickers.
* **Scribble Implementation:**
  - Storage permissions have been removed from `android/app/src/main/AndroidManifest.xml`.
  - The `image_picker` package utilizes the native Android Photo Picker (zero broad storage permissions requested from user).

### C. Foreground Service Declaration (`FOREGROUND_SERVICE_DATA_SYNC`)
* **Policy Mandate:** All foreground services must declare a specific service type in the manifest and be justified in the Google Play Console.
* **Scribble Implementation:**
  - Declared `android:foregroundServiceType="dataSync"` in `AndroidManifest.xml`.
  - **Play Console Justification:** Used to briefly download new partner drawings and render them to the Android Lockscreen and Interactive Home Screen Widget in real time when a push notification is received.

### D. Target SDK Level
* **Policy Mandate:** New apps and updates submitted to Google Play must target Android 14 (API level 34) or higher (Android 15 / API 35 recommended).
* **Scribble Implementation:**
  - Configured in `android/app/build.gradle.kts`: `minSdk = 24`, `targetSdk = 35`, `compileSdk = 35`.

---

## 3. Play Console Submission Questionnaire (Exact Answers)

When filling out your app listing on the [Google Play Console](https://play.google.com/console), use these exact answers:

### 1. App Content -> Data Safety Section
Google requires you to disclose what user data is collected and how it is protected.

* **Data Collection & Security:**
  * Does your app collect or share any of the required user data types? ➔ **Yes**
  * Is all user data collected by your app encrypted in transit? ➔ **Yes** (All Firebase and Cloudinary connections use TLS / HTTPS).
  * Do you provide a way for users to request that their data is deleted? ➔ **Yes** (Provide your hosted `privacy.html#deletion` URL).

* **Data Types Collected:**
  1. **Personal Info:**
     * **Name (Username):** Collected (Yes), Shared (No), Optional (No), Purpose: *App functionality, Account management*.
     * **Email Address:** Collected (Yes), Shared (No), Optional (No), Purpose: *App functionality, Account management*.
  2. **Photos and Videos:**
     * **Photos (Drawings / Profile Avatars):** Collected (Yes), Shared (No - only sent to user's paired partner), Ephemeral (No), Optional (Yes), Purpose: *App functionality*.
  3. **Device or Other IDs:**
     * **Device / FCM Push Tokens:** Collected (Yes), Shared (No), Ephemeral (No), Purpose: *App functionality, Push notifications*.

### 2. Advertising ID (AD_ID)
* Does your app use advertising ID? ➔ **No** (Scribble does not display ads or track users for advertising).

### 3. App Access / Reviewer Credentials
* Google testers must be able to log in to test the app.
* In Play Console ➔ **App access** ➔ Select **"All or some functionality is restricted"** ➔ **Add instructions**:
  * **Test Account Email:** `tester@scribble-demo.com`
  * **Test Account Password:** *(Provide credentials for a test Firebase account you create)*
  * **Note:** Reviewers can also tap **"Continue as Guest"** for instant 1-tap testing without credentials.

### 4. Target Audience and Content (Age Rating)
* **Target Age:** Select **13 and older** (e.g. 13-15, 16-17, 18+).
* **Could your app appeal to children?** ➔ **No**.
  > *Note: Choosing under 13 subjects the app to Google's strict Families Policy and COPPA regulations.*

### 5. Foreground Service Declaration Form
* When asked about `FOREGROUND_SERVICE_DATA_SYNC`:
  * **Use case category:** *Data sync*.
  * **Description text:** *"Scribble is a real-time couple doodle app. When a user receives a push notification that their partner has sent a new handwritten doodle, a brief background data sync task downloads the doodle image and renders it to the user's Android Home Screen AppWidget and Lock Screen wallpaper so it is immediately visible."*

---

## 4. Your Live Privacy Policy, Deletion URL & Web App

Your web application and policy portal are **already deployed and live** on Firebase Hosting:

* 🌐 **Live Web Application:** `https://scribble-6d33a.web.app`
* 🛡️ **Google Play Privacy Policy URL:** `https://scribble-6d33a.web.app/privacy.html`
* 🗑️ **Google Play Account Deletion URL:** `https://scribble-6d33a.web.app/privacy.html#deletion`

*(You can copy and paste these exact links directly into Google Play Console!)*

### How to Re-Deploy Web Updates Anytime:
Whenever you make updates to the web app:
```bash
flutter build web
firebase deploy --only hosting
```

---

## 5. Production Keystore & Release App Bundle (.aab) Build Guide

Google Play requires an **Android App Bundle (`.aab`)** signed with a production release keystore (not debug keys).

### Step 1: Generate Release Keystore
Run this command in PowerShell (replace `my-upload-key` and passwords with your own):

```powershell
keytool -genkey -v -keystore C:\Users\Mr.Bunny159\upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
*(Keep this keystore file and its password safe! If you lose it, you cannot update your app on Google Play).*

### Step 2: Configure `android/key.properties`
Create a file at `android/key.properties` (this file is already in `.gitignore` so your keys stay private):
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:\\Users\\Mr.Bunny159\\upload-keystore.jks
```

### Step 3: Link Signing Config in `android/app/build.gradle.kts`
Ensure your `android/app/build.gradle.kts` reads `key.properties`:
```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (keystorePropertiesFile.exists()) "release" else "debug"
            )
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
```

### Step 4: Build the Release App Bundle
When you are ready to produce the bundle for Google Play Console:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

The resulting file will be generated at:
`build/app/outputs/bundle/release/app-release.aab`

Upload this `.aab` file directly to Google Play Console under **Production** or **Internal Testing**!
