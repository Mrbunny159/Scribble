class AppConstants {
  // Configured Supabase project credentials
  static const String supabaseUrl = 'https://fcnxaewxgsaopwtrzwpn.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_O7n9d4rToLX8PuDhhbTYZw_5QDduE_Y';

  // Method Channel for native Android Lockscreen interaction
  static const String lockScreenChannel = 'com.scribble.app/lockscreen';

  // Storage Buckets
  static const String avatarBucket = 'avatars';
  static const String scribbleBucket = 'scribbles';

  // Cloudinary Configuration
  // Unsigned upload endpoint: https://api.cloudinary.com/v1_1/<cloud_name>/image/upload
  static const String cloudinaryCloudName = 'eulvkmms';
  static const String cloudinaryUploadPreset = 'scribble_preset';

  // Shared Preferences Keys
  static const String keyLockScreenEnabled = 'scribble_lockscreen_enabled';
  static const String keyActiveConnectionId = 'scribble_active_connection_id';
}
