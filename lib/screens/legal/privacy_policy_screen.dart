import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../widgets/scribble_logo.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const ScribbleLogo(size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Scribble Privacy Policy',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Last Updated: October 2026 • Effective Date: October 2026',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'At Scribble, we believe handwritten moments between loved ones deserve absolute privacy and transparency. This policy outlines how your data is handled in strict compliance with Google Play Developer Policies.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildSection(
              icon: Icons.person_outline_rounded,
              title: '1. Information We Collect',
              content: [
                '• Account Credentials: When you sign up or sign in, we collect your email address, username, and authentication tokens via Google Firebase.',
                '• Google Profile Information: If you choose "Sign in with Google", we receive your public profile display name, email, and Google profile picture to personalize your partner avatar.',
                '• Scribbles & Content: Handwritten stroke coordinates, canvas drawings, custom text notes, and doodle images you explicitly share with your paired partner.',
                '• Device & Push Tokens: Firebase Cloud Messaging (FCM) tokens required to notify your device when your partner sends a new scribble.',
                '• Guest Sessions: If you use "Continue as Guest", a temporary anonymous account is generated. No personal identifiable email is collected.',
              ],
            ),

            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.sync_rounded,
              title: '2. How We Use Your Data',
              content: [
                '• Real-Time Pairing: Delivering scribbles between paired devices securely.',
                '• Lock Screen & Home Screen Updates: Updating your Android Lockscreen and Interactive Home Screen Widget with your partner\'s latest note.',
                '• Account Management: Facilitating secure login and profile customization.',
                '• We NEVER sell your personal data or user-generated drawings to third parties or advertisers.',
              ],
            ),

            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.cloud_done_outlined,
              title: '3. Data Storage & Third-Party Processors',
              content: [
                '• Google Firebase (Google LLC): Cloud Firestore, Firebase Authentication, and Firebase Cloud Messaging for encrypted database and messaging infrastructure. Complies with ISO 27001, SOC 1/2/3.',
                '• Cloudinary: Used for optimized, encrypted cloud content delivery of shared doodle graphics.',
                '• Local Storage: Recent color selections and widget cache are stored strictly on your device using Android SharedPreferences.',
              ],
            ),

            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.security_rounded,
              title: '4. Android Permissions & Justification',
              content: [
                '• Notifications (POST_NOTIFICATIONS): Used strictly to alert you when your paired partner sends a doodle or note.',
                '• Foreground Service (DATA_SYNC): Used briefly to update your Android Home Screen Widget and Lock Screen background when a doodle arrives.',
                '• Media / Photos: Scribble utilizes the native Android Photo Picker. We DO NOT request broad READ_MEDIA_IMAGES or READ_EXTERNAL_STORAGE permissions.',
              ],
            ),

            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.delete_forever_rounded,
              title: '5. Account & Data Deletion (User Rights)',
              content: [
                '• In-App Deletion: You can permanently delete your account and all associated scribbles anytime by opening Profile -> "Delete Account Permanently".',
                '• Instant Data Wipe: Account deletion immediately purges all pairing relationships, drawings, history archives, and Firebase user credentials.',
                '• Web Deletion Request: If you have uninstalled the app, you can request full data deletion through our public web portal or by emailing support.',
              ],
            ),

            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.child_care_rounded,
              title: '6. Children\'s Privacy',
              content: [
                'Scribble is not directed at children under the age of 13. We do not knowingly collect personal information from children under 13. If you believe such data exists, contact us for immediate removal.',
              ],
            ),

            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.contact_support_outlined,
              title: '7. Contact Us',
              content: [
                'For privacy queries, data requests, or support, please reach out to:',
                'Email: support@scribble-app.internal',
                'Application: Scribble for Android',
              ],
            ),

            const SizedBox(height: 32),
            Center(
              child: Text(
                '© 2026 Scribble. All rights reserved.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<String> content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...content.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                item,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
