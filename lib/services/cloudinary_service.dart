import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  static const String keyCustomCloudName = 'cloudinary_custom_cloud_name';
  static const String keyCustomUploadPreset = 'cloudinary_custom_upload_preset';

  /// Check whether Cloudinary credentials are configured
  Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final customName = prefs.getString(keyCustomCloudName);
    final cloudName = customName?.isNotEmpty == true ? customName! : AppConstants.cloudinaryCloudName;
    return cloudName.isNotEmpty && cloudName != 'YOUR_CLOUDINARY_CLOUD_NAME';
  }

  /// Get active cloud name
  Future<String> getCloudName() async {
    final prefs = await SharedPreferences.getInstance();
    final customName = prefs.getString(keyCustomCloudName);
    if (customName != null && customName.trim().isNotEmpty) {
      return customName.trim();
    }
    return AppConstants.cloudinaryCloudName.trim();
  }

  /// Get active unsigned upload preset
  Future<String> getUploadPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final customPreset = prefs.getString(keyCustomUploadPreset);
    if (customPreset != null && customPreset.trim().isNotEmpty) {
      return customPreset.trim();
    }
    return AppConstants.cloudinaryUploadPreset.trim();
  }

  /// Save custom credentials at runtime
  Future<void> setCustomCredentials({
    required String cloudName,
    required String uploadPreset,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCustomCloudName, cloudName.trim());
    await prefs.setString(keyCustomUploadPreset, uploadPreset.trim());
  }

  /// Upload an image to Cloudinary using standard HTTPS REST API
  /// Returns the secure HTTPS URL on success, or null on failure.
  Future<String?> uploadImage({
    required Uint8List bytes,
    String folder = 'scribbles',
    String? publicId,
  }) async {
    try {
      final cloudName = await getCloudName();
      final uploadPreset = await getUploadPreset();

      if (cloudName.isEmpty || cloudName == 'YOUR_CLOUDINARY_CLOUD_NAME') {
        debugPrint('Cloudinary: Cloud name not configured yet.');
        return null;
      }

      final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      final base64Data = 'data:image/png;base64,${base64Encode(bytes)}';

      final payload = <String, dynamic>{
        'file': base64Data,
        'upload_preset': uploadPreset,
        'folder': folder,
        if (publicId != null) 'public_id': publicId,
      };

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> jsonResponse = jsonDecode(responseBody);
        final secureUrl = jsonResponse['secure_url'] as String?;
        if (secureUrl != null && secureUrl.isNotEmpty) {
          debugPrint('Cloudinary: Upload successful -> $secureUrl');
          return secureUrl;
        }
      }

      debugPrint('Cloudinary: Upload failed (${response.statusCode}): $responseBody');
      return null;
    } catch (e) {
      debugPrint('Cloudinary: Exception during upload: $e');
      return null;
    }
  }
}
