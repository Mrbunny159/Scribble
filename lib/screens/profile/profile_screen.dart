import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/firebase_service.dart';
import '../../widgets/scribble_logo.dart';
import '../legal/privacy_policy_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onSignedOut;

  const ProfileScreen({super.key, required this.onSignedOut});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  final TextEditingController _usernameController = TextEditingController();

  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  bool get _isGoogleUser {
    final user = FirebaseService().currentUser;
    if (user == null || user.isAnonymous) return false;
    return user.providerData.any((p) => p.providerId == 'google.com') ||
        (user.photoURL != null && user.photoURL!.contains('googleusercontent.com'));
  }

  Future<void> _loadProfile() async {
    final isGuest = await FirebaseService().isGuestSession();
    final uid = FirebaseService().currentUser?.uid;
    if (uid != null) {
      var p = await FirebaseService().getProfile(uid);
      if (!isGuest && (p?.avatarUrl == null || p!.avatarUrl!.isEmpty)) {
        // Automatically sync Google photo if user signed in with Google
        final synced = await FirebaseService().syncGooglePhotoIfAvailable();
        if (synced != null) p = synced;
      }
      if (mounted) {
        setState(() {
          _isGuest = isGuest;
          _profile = p;
          _usernameController.text = p?.username ?? '';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncGooglePhoto() async {
    setState(() => _isSaving = true);
    try {
      final updated = await FirebaseService().syncGooglePhotoIfAvailable();
      if (mounted) {
        setState(() {
          if (updated != null) _profile = updated;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google profile photo synced!'), backgroundColor: AppColors.secondary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sync Google photo: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isSaving = true);
      final Uint8List bytes = await image.readAsBytes();
      final ext = image.name.split('.').last;

      final newUrl = await FirebaseService().uploadAvatar(bytes, ext);
      if (mounted) {
        setState(() {
          _profile = _profile?.copyWith(avatarUrl: newUrl);
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar updated!'), backgroundColor: AppColors.secondary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update avatar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _saveUsername() async {
    final newName = _usernameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseService().updateProfile(
        username: newName,
        avatarUrl: _profile?.avatarUrl,
      );
      if (mounted) {
        setState(() {
          _profile = _profile?.copyWith(username: newName);
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'), backgroundColor: AppColors.secondary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _showDeleteAccountConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Account?',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'This will permanently delete your account, paired connections, shared scribbles, and drawing history.\n\nThis action cannot be undone.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppColors.onSurface),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Permanently Delete',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      try {
        await FirebaseService().deleteAccount();
        if (mounted) {
          widget.onSignedOut();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete account: $e. You may need to log out and log in again before deleting.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseService().currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryContainer))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      // Avatar Section
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primaryFixed, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryContainer.withAlpha(30),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 48,
                                backgroundColor: AppColors.surfaceContainerHigh,
                                backgroundImage: (_profile?.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty)
                                    ? NetworkImage(_profile!.avatarUrl!)
                                    : (FirebaseService().currentUser?.photoURL != null
                                        ? NetworkImage(FirebaseService().currentUser!.photoURL!)
                                        : null),
                                child: (_profile?.avatarUrl == null && FirebaseService().currentUser?.photoURL == null)
                                    ? Text(
                                        (_profile?.username.isNotEmpty == true)
                                            ? _profile!.username[0].toUpperCase()
                                            : '?',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: _isSaving ? null : _pickAndUploadAvatar,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isGoogleUser) ...[
                        OutlinedButton.icon(
                          onPressed: _isSaving ? null : _syncGooglePhoto,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primaryContainer, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 16, color: AppColors.primary),
                          label: Text(
                            'Sync Google Photo',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 16),

                      // Display Name Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Display Name',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _usernameController,
                                    style: GoogleFonts.plusJakartaSans(color: AppColors.onSurface, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter your name',
                                      prefixIcon: Icon(Icons.edit_rounded, color: AppColors.primary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: _isSaving ? null : _saveUsername,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryContainer,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text('Save', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Unique User ID Badge
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.fingerprint_rounded, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Unique User ID',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: uid));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('User ID copied to clipboard!'), duration: Duration(seconds: 2)),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        uid,
                                        style: GoogleFonts.sourceCodePro(
                                          fontSize: 12,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isGuest) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primaryFixed,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Guest Session • This session is temporary. Data is not synced across devices and will be wiped completely when you exit.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],


                      const SizedBox(height: 12),

                      // Sign Out / Exit Guest Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.outlineVariant, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          icon: Icon(_isGuest ? Icons.delete_sweep_rounded : Icons.logout_rounded, size: 20),
                          label: Text(
                            _isGuest ? 'Exit & Wipe Guest Data' : 'Sign Out',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            if (_isGuest) {
                              await FirebaseService().endGuestSessionAndClearData();
                            } else {
                              await FirebaseService().signOut();
                            }
                            widget.onSignedOut();
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Privacy Policy Link
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                            );
                          },
                          icon: const Icon(Icons.privacy_tip_outlined, size: 18, color: AppColors.onSurfaceVariant),
                          label: Text(
                            'Privacy Policy',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),

                      // Delete Account (Google Play Policy Compliance)
                      if (!_isGuest) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.delete_forever_rounded, size: 18, color: AppColors.error),
                            label: Text(
                              'Delete Account Permanently',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                color: AppColors.error,
                                fontSize: 13,
                              ),
                            ),
                            onPressed: _showDeleteAccountConfirmation,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // App Branding Footer
                      Center(
                        child: Column(
                          children: [
                            const ScribbleLogo(size: 34, showGlow: false),
                            const SizedBox(height: 8),
                            Text(
                              'Scribble v1.0.0',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.outline,
                              ),
                            ),
                            Text(
                              'Handwritten notes for couples & partners',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: AppColors.outlineVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
