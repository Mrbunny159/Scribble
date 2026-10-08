import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class NativeLockscreenService {
  static const MethodChannel _channel = MethodChannel(AppConstants.lockScreenChannel);

  // Singleton instance
  static final NativeLockscreenService _instance = NativeLockscreenService._internal();
  factory NativeLockscreenService() => _instance;
  NativeLockscreenService._internal();

  /// Check if Lockscreen updates are enabled in local preferences
  Future<bool> isLockscreenEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyLockScreenEnabled) ?? true;
  }

  /// Toggle Lockscreen updates on or off
  Future<void> setLockscreenEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyLockScreenEnabled, enabled);
  }

  /// Check if the native platform supports lockscreen wallpaper updates
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    try {
      final bool? supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Check if the app is exempt from Android battery optimization (Doze mode)
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? true;
    } on PlatformException {
      return true;
    }
  }

  /// Launch Android system intent asking user to exempt app from battery optimization
  Future<bool> requestIgnoreBatteryOptimization() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimization');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open system notification settings for Scribble
  Future<bool> openNotificationSettings() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('openNotificationSettings');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Check if the app has permission to draw overlays over other apps and lock screen
  Future<bool> canDrawOverlays() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('canDrawOverlays');
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Open system settings to request "Display over other apps" overlay permission
  Future<bool> requestOverlayPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('requestOverlayPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Check if app was launched via home screen widget or lockscreen notification with openCanvas extra
  Future<Map<String, dynamic>> getLaunchExtras() async {
    if (kIsWeb || !Platform.isAndroid) return {};
    try {
      final dynamic res = await _channel.invokeMethod('getLaunchExtras');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Wake up physical device screen for 3 seconds
  Future<bool> wakeUpScreen() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('wakeUpScreen');
      return result ?? false;
    } catch (e) {
      debugPrint('Wake screen error: $e');
      return false;
    }
  }

  /// Trigger a heads-up notification and wake up the screen
  Future<bool> notifyScribble(String senderName) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'notifyScribble',
        {'senderName': senderName},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Notify scribble error: $e');
      return false;
    }
  }

  /// Start Android foreground background service to keep lock screen syncing even when app is closed / phone locked
  Future<bool> startBackgroundSync({
    String projectId = 'scribble-6d33a',
    String? supabaseUrl,
    String? anonKey,
    required String connectionId,
    required String myUserId,
    String partnerName = 'Partner',
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'startBackgroundSync',
        {
          'projectId': projectId,
          'connectionId': connectionId,
          'myUserId': myUserId,
          'partnerName': partnerName,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Start background sync error: $e');
      return false;
    }
  }

  /// Stop Android foreground sync service
  Future<bool> stopBackgroundSync() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('stopBackgroundSync');
      return result ?? false;
    } catch (e) {
      debugPrint('Stop background sync error: $e');
      return false;
    }
  }

  /// Helper to safely fetch raw PNG bytes directly from base64 data URI or public HTTP/HTTPS URL
  Future<Uint8List?> fetchImageBytes(String url) async {
    try {
      if (url.startsWith('data:image')) {
        final commaIndex = url.indexOf(',');
        if (commaIndex != -1) {
          final base64Str = url.substring(commaIndex + 1);
          return base64Decode(base64Str);
        }
      }

      final uri = Uri.parse(url);
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        return await consolidateHttpClientResponseBytes(response);
      } else {
        debugPrint('Failed to download image bytes: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading image bytes from $url: $e');
      return null;
    }
  }

  /// Check if a scribble has already been seen by the user
  Future<bool> hasSeenScribble(String scribbleId) async {
    if (scribbleId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('seen_scribble_ids') ?? [];
    return seen.contains(scribbleId);
  }

  /// Mark a scribble as seen so it will never trigger a popup again
  Future<void> markScribbleAsSeen(String scribbleId) async {
    if (scribbleId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList('seen_scribble_ids') ?? []).toSet();
    seen.add(scribbleId);
    final list = seen.toList();
    if (list.length > 100) {
      list.removeRange(0, list.length - 100);
    }
    await prefs.setStringList('seen_scribble_ids', list);
  }

  /// Downloads scribble from public URL and sets it directly as lockscreen wallpaper
  Future<Map<String, dynamic>> updateLockscreenFromUrl(
    String url, {
    String? senderName,
    bool showPopup = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return {'success': false, 'error': 'Unsupported platform'};
    }
    final bytes = await fetchImageBytes(url);
    if (bytes == null || bytes.isEmpty) {
      return {'success': false, 'error': 'Could not download scribble image bytes'};
    }
    return updateLockscreenImage(bytes, senderName: senderName, showPopup: showPopup);
  }

  /// Send rendered scribble image bytes to Kotlin to update Android Lock Screen
  Future<Map<String, dynamic>> updateLockscreenImage(
    Uint8List imageBytes, {
    String? senderName,
    bool showPopup = false,
  }) async {
    if (kIsWeb) return {'success': false, 'error': 'Not supported on Web'};
    final enabled = await isLockscreenEnabled();
    if (!enabled) return {'success': false, 'error': 'Lockscreen display is disabled in settings'};
    if (!Platform.isAndroid) return {'success': false, 'error': 'Not an Android device'};

    try {
      final dynamic rawResult = await _channel.invokeMethod(
        'setLockscreenWallpaper',
        {
          'bytes': imageBytes,
          'senderName': senderName,
          'showPopup': showPopup,
        },
      );

      if (rawResult is Map) {
        final map = Map<String, dynamic>.from(rawResult);
        return map;
      }
      return {'success': true};
    } on PlatformException catch (e) {
      debugPrint('Lockscreen update error: ${e.message}');
      return {'success': false, 'error': e.message ?? 'Platform error'};
    } catch (e) {
      debugPrint('Unexpected lockscreen error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Clear the lock screen scribble (replaces with clean dark ambient screen)
  Future<bool> clearLockscreen() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('clearLockscreen');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Lockscreen clear error: ${e.message}');
      return false;
    }
  }

  /// Clear native lockscreen and widget cache and stop sync
  Future<void> clearLockscreenCache() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await stopBackgroundSync();
      await clearLockscreen();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('seen_scribble_ids');
    } catch (e) {
      debugPrint('Error clearing lockscreen cache: $e');
    }
  }
}
