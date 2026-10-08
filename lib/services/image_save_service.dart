import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ImageSaveService {
  static const MethodChannel _channel = MethodChannel('com.scribble.app/lockscreen');

  /// Saves image bytes to the device's public Photos & Gallery (Pictures/Scribble).
  /// Returns a user-friendly string message on success or throws an exception on failure.
  static Future<String> saveImageToDevice({
    required Uint8List bytes,
    String? customTitle,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final title = customTitle ?? 'scribble_$timestamp';

    // 1. Native Android MediaStore (indexes directly into Google Photos / Device Gallery)
    try {
      final res = await _channel.invokeMethod('saveImageToGallery', {
        'bytes': bytes,
        'title': title,
      });
      if (res is Map && res['success'] == true) {
        return 'Saved to Photos & Gallery (Pictures/Scribble)! 🖼️';
      }
    } catch (e) {
      debugPrint('MediaStore save channel notice: $e');
    }

    // 2. Direct public storage fallback: Pictures/Scribble or Download folder
    try {
      final publicDirs = [
        Directory('/storage/emulated/0/Pictures/Scribble'),
        Directory('/storage/emulated/0/Download'),
      ];

      for (final dir in publicDirs) {
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final file = File('${dir.path}/$title.png');
          await file.writeAsBytes(bytes, flush: true);
          return 'Saved to ${dir.path.split('/').last}/$title.png! 🖼️';
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('Public dir fallback notice: $e');
    }

    // 3. External storage directory from path_provider
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final file = File('${extDir.path}/$title.png');
        await file.writeAsBytes(bytes, flush: true);
        return 'Saved to device storage: $title.png';
      }
    } catch (e) {
      debugPrint('External dir fallback notice: $e');
    }

    // 4. Safe app documents directory fallback
    final appDir = await getApplicationDocumentsDirectory();
    final fallbackFile = File('${appDir.path}/$title.png');
    await fallbackFile.writeAsBytes(bytes, flush: true);
    return 'Saved to Scribble storage: $title.png';
  }

  /// Downloads and saves image bytes from a URL (supports data: URI and HTTPS URLs)
  static Future<String> saveImageUrlToDevice(String imageUrl, {String? customTitle}) async {
    Uint8List? bytes;
    if (imageUrl.startsWith('data:image')) {
      final comma = imageUrl.indexOf(',');
      if (comma != -1) {
        bytes = base64Decode(imageUrl.substring(comma + 1));
      }
    } else {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(imageUrl));
      final resp = await req.close();
      final byteList = <int>[];
      await for (final chunk in resp) {
        byteList.addAll(chunk);
      }
      bytes = Uint8List.fromList(byteList);
    }

    if (bytes == null || bytes.isEmpty) {
      throw Exception('Image bytes could not be retrieved');
    }

    return await saveImageToDevice(bytes: bytes, customTitle: customTitle);
  }
}
