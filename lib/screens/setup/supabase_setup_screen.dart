import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class SupabaseSetupScreen extends StatefulWidget {
  final Future<void> Function(String url, String anonKey) onSaveCredentials;

  const SupabaseSetupScreen({super.key, required this.onSaveCredentials});

  @override
  State<SupabaseSetupScreen> createState() => _SupabaseSetupScreenState();
}

class _SupabaseSetupScreenState extends State<SupabaseSetupScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = AppConstants.supabaseUrl;
    _keyController.text = AppConstants.supabaseAnonKey;
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();

    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Supabase URL and Anon Key'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.onSaveCredentials(url, key);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: AppColors.primary, size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connect to Supabase',
                    style: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your Supabase project credentials to enable authentication, realtime lock screen delivery, and image storage.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 16, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _urlController,
                          style: GoogleFonts.plusJakartaSans(color: AppColors.onSurface),
                          decoration: const InputDecoration(
                            labelText: 'Project URL',
                            hintText: 'https://xyz.supabase.co',
                            prefixIcon: Icon(Icons.link_rounded, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _keyController,
                          style: GoogleFonts.plusJakartaSans(color: AppColors.onSurface),
                          decoration: const InputDecoration(
                            labelText: 'Project Anon Public Key',
                            hintText: 'sb_publishable_...',
                            prefixIcon: Icon(Icons.key_rounded, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _save,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text('Save & Connect', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '💡 Quick Setup Guide:',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '1. Open Supabase Dashboard -> Project Settings -> API\n'
                          '2. Copy the Project URL and anon public key\n'
                          '3. Run the schema in supabase_schema.sql in SQL Editor\n'
                          '4. In Auth -> Providers -> Email, disable "Confirm email" for testing',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
