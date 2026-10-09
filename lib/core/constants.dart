import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // Method Channel for native Android Lockscreen interaction
  static const String lockScreenChannel = 'com.scribble.app/lockscreen';

  // Storage Buckets
  static const String avatarBucket = 'avatars';
  static const String scribbleBucket = 'scribbles';

  // Cloudinary Configuration
  // Unsigned upload endpoint: https://api.cloudinary.com/v1_1/<cloud_name>/image/upload
  static String get cloudinaryCloudName =>
      dotenv.maybeGet('CLOUDINARY_CLOUD_NAME') ??
      const String.fromEnvironment(
        'CLOUDINARY_CLOUD_NAME',
        defaultValue: 'eulvkmms',
      );

  static String get cloudinaryUploadPreset =>
      dotenv.maybeGet('CLOUDINARY_UPLOAD_PRESET') ??
      const String.fromEnvironment(
        'CLOUDINARY_UPLOAD_PRESET',
        defaultValue: 'scribble_preset',
      );

  // Shared Preferences Keys
  static const String keyLockScreenEnabled = 'scribble_lockscreen_enabled';
  static const String keyActiveConnectionId = 'scribble_active_connection_id';
}

