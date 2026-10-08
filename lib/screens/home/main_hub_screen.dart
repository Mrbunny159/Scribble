import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/connection_model.dart';
import '../../models/scribble_model.dart';
import '../../models/user_profile.dart';
import '../../services/native_lockscreen_service.dart';
import '../../services/firebase_service.dart';
import '../../services/image_save_service.dart';
import '../canvas/scribble_canvas_screen.dart';
import '../pairing/pairing_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/scribble_logo.dart';
import 'widgets/multi_scribble_slider.dart';

class MainHubScreen extends StatefulWidget {
  final VoidCallback onSignOut;

  const MainHubScreen({super.key, required this.onSignOut});

  @override
  State<MainHubScreen> createState() => _MainHubScreenState();
}

class _MainHubScreenState extends State<MainHubScreen> {
  int _currentTabIndex = 0;
  List<ConnectionModel> _connections = [];
  ConnectionModel? _activeConnection;
  UserProfile? _myProfile;
  
  // Realtime scribble map per connection
  final Map<String, ScribbleModel?> _connectionScribbles = {};
  final Map<String, StreamSubscription<ScribbleModel?>> _connectionSubscriptions = {};

  bool _isLoading = true;
  bool _lockscreenEnabled = true;
  bool _isBatteryOptimized = false;
  bool _isAndroidPlatform = false;
  String? _heartReactionConnectionId;

  // Timeline History state
  bool _isLoadingTimeline = false;
  List<ScribbleItem> _timelineHistory = [];
  String? _timelineFilterConnectionId;

  @override
  void initState() {
    super.initState();
    _initHub();
  }

  @override
  void dispose() {
    for (final sub in _connectionSubscriptions.values) {
      sub.cancel();
    }
    _connectionSubscriptions.clear();
    super.dispose();
  }

  Future<void> _initHub() async {
    setState(() => _isLoading = true);
    final enabled = await NativeLockscreenService().isLockscreenEnabled();
    final isSupported = await NativeLockscreenService().isSupported();
    bool isBatteryOpt = false;
    if (isSupported) {
      final ignored = await NativeLockscreenService().isIgnoringBatteryOptimizations();
      isBatteryOpt = !ignored;
    }
    if (mounted) {
      setState(() {
        _lockscreenEnabled = enabled;
        _isAndroidPlatform = isSupported;
        _isBatteryOptimized = isBatteryOpt;
      });
    }

    final uid = FirebaseService().currentUser?.uid;
    if (uid != null) {
      FirebaseService().getProfile(uid).then((p) {
        if (mounted) setState(() => _myProfile = p);
      });
      FirebaseService().syncGooglePhotoIfAvailable().then((p) {
        if (mounted && p != null) setState(() => _myProfile = p);
      });
    }

    await _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final myUid = FirebaseService().currentUser?.uid;
      if (myUid != null) {
        FirebaseService().getProfile(myUid).then((p) {
          if (mounted) setState(() => _myProfile = p);
        });
      }

      final list = await FirebaseService().getConnections();
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final savedConnId = prefs.getString(AppConstants.keyActiveConnectionId);

      ConnectionModel? active;
      if (list.isNotEmpty) {
        active = list.firstWhere(
          (c) => c.id == savedConnId,
          orElse: () => list.first,
        );
      }

      // Concurrently fetch latest scribble for each connection
      final scribbleResults = await Future.wait(
        list.map((c) => FirebaseService().getLatestScribble(c.id)),
      );

      final Map<String, ScribbleModel?> scribblesMap = {};
      for (int i = 0; i < list.length; i++) {
        scribblesMap[list[i].id] = scribbleResults[i];
      }

      setState(() {
        _connections = list;
        _activeConnection = active;
        _connectionScribbles.clear();
        _connectionScribbles.addAll(scribblesMap);
        _isLoading = false;
      });

      _subscribeToAllConnections(list);

      // On launch, ensure the active partner's scribble is synced to widgets/lockscreen silently without popup
      if (_lockscreenEnabled && active != null && scribblesMap[active.id] != null) {
        final scribble = scribblesMap[active.id]!;
        if (!scribble.isCleared && scribble.imageUrl != null) {
          // Mark as seen so opening the app never pops up an existing scribble
          NativeLockscreenService().markScribbleAsSeen(scribble.id);
          NativeLockscreenService().updateLockscreenFromUrl(
            scribble.imageUrl!,
            senderName: active.partnerProfile?.username ?? 'Partner',
            showPopup: false,
          );
        }
      }

      // Start Android foreground sync service to keep lock screen updated when app is closed / phone locked
      if (_lockscreenEnabled && active != null) {
        NativeLockscreenService().startBackgroundSync(
          connectionId: active.id,
          myUserId: FirebaseService().currentUser?.uid ?? '',
          partnerName: active.partnerProfile?.username ?? 'Partner',
        );
      }

      // Check if launched from Home Screen Widget to jump directly into Canvas
      final launchExtras = await NativeLockscreenService().getLaunchExtras();
      final currentActive = active;
      if (launchExtras['openCanvas'] == true && currentActive != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScribbleCanvasScreen(
              connectionId: currentActive.id,
              partnerName: currentActive.partnerProfile?.username ?? 'Partner',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToAllConnections(List<ConnectionModel> list) {
    for (final sub in _connectionSubscriptions.values) {
      sub.cancel();
    }
    _connectionSubscriptions.clear();

    for (final conn in list) {
      final sub = FirebaseService()
          .subscribeToScribble(conn.id)
          .listen((scribble) async {
        if (mounted) {
          setState(() {
            _connectionScribbles[conn.id] = scribble;
          });
        }
        final myUid = FirebaseService().currentUser?.uid;
        if (_lockscreenEnabled &&
            _activeConnection?.id == conn.id &&
            scribble != null &&
            scribble.senderId != myUid &&
            !scribble.isCleared &&
            scribble.imageUrl != null) {
          // Only show popup if user has NOT seen this specific scribble yet!
          final alreadySeen = await NativeLockscreenService().hasSeenScribble(scribble.id);
          if (!alreadySeen) {
            await NativeLockscreenService().markScribbleAsSeen(scribble.id);
            NativeLockscreenService().updateLockscreenFromUrl(
              scribble.imageUrl!,
              senderName: conn.partnerProfile?.username ?? 'Partner',
              showPopup: true, // Only pop up once!
            );
          } else {
            // Already seen: update silently without popping up
            NativeLockscreenService().updateLockscreenFromUrl(
              scribble.imageUrl!,
              senderName: conn.partnerProfile?.username ?? 'Partner',
              showPopup: false,
            );
          }
        }
      });
      _connectionSubscriptions[conn.id] = sub;
    }
  }

  /// Load complete chronological history across connected partners
  Future<void> _loadTimelineHistory() async {
    if (!mounted) return;
    setState(() => _isLoadingTimeline = true);
    try {
      final List<ScribbleItem> allHistory = [];
      final targetConns = _timelineFilterConnectionId != null
          ? _connections.where((c) => c.id == _timelineFilterConnectionId).toList()
          : _connections;

      for (final conn in targetConns) {
        final items = await FirebaseService().getScribbleHistory(conn.id);
        allHistory.addAll(items);
      }

      allHistory.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _timelineHistory = allHistory;
          _isLoadingTimeline = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading timeline history: $e');
      if (mounted) {
        setState(() => _isLoadingTimeline = false);
      }
    }
  }

  /// Download and save scribble image bytes directly to device storage / Gallery
  Future<void> _saveImageUrlToDevice(String imageUrl) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving doodle to device...'), duration: Duration(seconds: 1)),
      );

      final msg = await ImageSaveService.saveImageUrlToDevice(imageUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    msg,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.secondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _setActiveConnection(ConnectionModel conn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyActiveConnectionId, conn.id);
    setState(() {
      _activeConnection = conn;
    });

    final partnerName = conn.partnerProfile?.username ?? 'Partner';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$partnerName set as active lock-screen partner'),
          backgroundColor: AppColors.secondary,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final scribble = _connectionScribbles[conn.id];
    if (_lockscreenEnabled && scribble != null && !scribble.isCleared && scribble.imageUrl != null) {
      await NativeLockscreenService().updateLockscreenFromUrl(
        scribble.imageUrl!,
        senderName: partnerName,
      );
    }

    if (_lockscreenEnabled) {
      await NativeLockscreenService().startBackgroundSync(
        connectionId: conn.id,
        myUserId: FirebaseService().currentUser?.uid ?? '',
        partnerName: partnerName,
      );
    }
  }

  Future<void> _testLockscreenSync(ConnectionModel conn) async {
    final partnerName = conn.partnerProfile?.username ?? 'Partner';
    final scribble = _connectionScribbles[conn.id];

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Displaying scribble lock screen overlay...'),
          ],
        ),
        backgroundColor: AppColors.surfaceContainer,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    Map<String, dynamic> result;
    if (scribble != null && !scribble.isCleared && scribble.imageUrl != null) {
      result = await NativeLockscreenService().updateLockscreenFromUrl(
        scribble.imageUrl!,
        senderName: partnerName,
      );
    } else {
      // Create a test sample bitmap bytes if no scribble exists yet
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 800));
      final bgPaint = Paint()..color = const Color(0xFF161922);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 800, 800), const Radius.circular(32)), bgPaint);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '✨ Scribble Test ✨\n\nConnected to $partnerName!\nLock screen sync is active.',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 700);
      textPainter.paint(canvas, Offset((800 - textPainter.width) / 2, (800 - textPainter.height) / 2));
      final picture = recorder.endRecording();
      final img = await picture.toImage(800, 800);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      result = await NativeLockscreenService().updateLockscreenImage(bytes, senderName: partnerName);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🎉 Lock screen overlay displayed! Lock your phone to verify.'),
          backgroundColor: AppColors.secondary,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      final err = result['error'] ?? 'Unknown error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Lock screen update failed: $err. Check phone wallpaper settings.'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _triggerHeartReaction(String connectionId, String partnerName) {
    HapticFeedback.lightImpact();
    setState(() {
      _heartReactionConnectionId = connectionId;
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Sent ❤️ reaction to $partnerName!'),
          ],
        ),
        backgroundColor: AppColors.primaryContainer,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _heartReactionConnectionId == connectionId) {
        setState(() {
          _heartReactionConnectionId = null;
        });
      }
    });
  }

  Future<void> _clearScribbleForConnection(String connectionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Scribble?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        content: Text(
          'This will remove the current scribble from the app and the recipient\'s lock screen.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseService().clearScribble(connectionId);
        if (_activeConnection?.id == connectionId) {
          await NativeLockscreenService().clearLockscreen();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _confirmUnpair(ConnectionModel conn) async {
    final partnerName = conn.partnerProfile?.username ?? 'Partner';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Unpair $partnerName?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        content: Text(
          'You will no longer exchange live notes with $partnerName on your lock screen.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Unpair', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseService().removeConnection(conn.id);
        await _loadConnections();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unpaired from $partnerName')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to unpair: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _showPersonOptionsSheet(ConnectionModel conn) {
    final partnerName = conn.partnerProfile?.username ?? 'Partner';
    final isActive = _activeConnection?.id == conn.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Text(
                    '$partnerName Options',
                    style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: _lockscreenEnabled,
                    activeColor: AppColors.primaryContainer,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Lock Screen Overlay',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Float notes over lock screen (keeps your original wallpaper intact)',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.outline),
                    ),
                    onChanged: (val) async {
                      await NativeLockscreenService().setLockscreenEnabled(val);
                      setState(() => _lockscreenEnabled = val);
                      setModalState(() {});
                      if (!val) {
                        await NativeLockscreenService().stopBackgroundSync();
                        await NativeLockscreenService().clearLockscreen();
                      } else {
                        await NativeLockscreenService().startBackgroundSync(
                          connectionId: conn.id,
                          myUserId: FirebaseService().currentUser?.uid ?? '',
                          partnerName: partnerName,
                        );
                        final scribble = _connectionScribbles[conn.id];
                        if (scribble != null && !scribble.isCleared && scribble.imageUrl != null) {
                          await NativeLockscreenService().updateLockscreenFromUrl(
                            scribble.imageUrl!,
                            senderName: partnerName,
                          );
                        }
                      }
                    },
                  ),
                  if (_isAndroidPlatform && _lockscreenEnabled) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _testLockscreenSync(conn);
                        },
                        icon: const Icon(Icons.layers_rounded, size: 18),
                        label: const Text('Test Lock Screen Overlay Now'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryContainer,
                          side: BorderSide(color: AppColors.primaryContainer.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                  if (!isActive) ...[
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_clock_rounded, color: AppColors.secondary),
                      title: Text(
                        'Set as Primary Lock Screen Partner',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppColors.secondary),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _setActiveConnection(conn);
                      },
                    ),
                  ],
                  if (_isAndroidPlatform) ...[
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bolt_rounded, color: AppColors.secondary),
                      title: Text(
                        'Background Lock Screen Sync',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _isBatteryOptimized ? 'Requires background permission' : 'Active (unrestricted battery)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _isBatteryOptimized ? AppColors.error : AppColors.secondary,
                        ),
                      ),
                      trailing: _isBatteryOptimized
                          ? TextButton(
                              onPressed: () async {
                                await NativeLockscreenService().requestIgnoreBatteryOptimization();
                                Future.delayed(const Duration(seconds: 2), () async {
                                  final ignored = await NativeLockscreenService().isIgnoringBatteryOptimizations();
                                  if (mounted) {
                                    setState(() => _isBatteryOptimized = !ignored);
                                    setModalState(() {});
                                  }
                                });
                              },
                              child: const Text('Allow'),
                            )
                          : const Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 20),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.secondary),
                      title: Text(
                        'Display Over Other Apps (Lock Screen)',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Pops note onto lock screen immediately without opening the app',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.outline),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await NativeLockscreenService().requestOverlayPermission();
                        },
                        child: const Text('Allow'),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active_outlined, color: AppColors.outline),
                      title: Text(
                        'Lock Screen Notification Settings',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Configure alerts and lock-screen privacy',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.outline),
                      ),
                      onTap: () {
                        NativeLockscreenService().openNotificationSettings();
                      },
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    title: Text(
                      'Clear Current Scribble',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.error, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _clearScribbleForConnection(conn.id);
                    },
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_off_rounded, color: AppColors.outline),
                    title: Text(
                      'Unpair $partnerName',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.outline, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmUnpair(conn);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScribbleImage(String? url, {BoxFit fit = BoxFit.contain}) {
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    if (url.startsWith('data:image')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex != -1) {
        final base64String = url.substring(commaIndex + 1);
        try {
          return Image.memory(
            base64Decode(base64String),
            fit: fit,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 28),
            ),
          );
        } catch (_) {}
      }
    }
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 28),
      ),
    );
  }

  Future<void> _deleteScribbleFromPreview({
    required String connId,
    required String sId,
    required String? imgUrl,
    required BuildContext dialogCtx,
  }) async {
    final confirmed = await showDialog<bool>(
      context: dialogCtx,
      builder: (confirmCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E202B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            Text(
              'Move to Trash?',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Text(
          'This will permanently delete this doodle from active notes and memory history.',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(confirmCtx, true),
            child: Text('Delete Doodle', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Automatically close the preview dialog
    if (dialogCtx.mounted) {
      Navigator.pop(dialogCtx);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moving doodle to trash bin...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      await FirebaseService().deleteScribbleFromConnection(
        connectionId: connId,
        scribbleId: sId,
        imageUrl: imgUrl,
      );

      // Immediately update local state
      if (mounted) {
        setState(() {
          if (_connectionScribbles.containsKey(connId)) {
            final cur = _connectionScribbles[connId];
            if (cur != null) {
              final remaining = cur.activeScribbles.where((i) => i.id != sId && i.imageUrl != imgUrl).toList();
              if (remaining.isEmpty) {
                _connectionScribbles[connId] = ScribbleModel(
                  id: cur.id,
                  connectionId: cur.connectionId,
                  senderId: cur.senderId,
                  imageUrl: null,
                  textContent: null,
                  isCleared: true,
                  createdAt: cur.createdAt,
                  updatedAt: DateTime.now(),
                  activeScribbles: const [],
                );
              } else {
                _connectionScribbles[connId] = ScribbleModel(
                  id: cur.id,
                  connectionId: cur.connectionId,
                  senderId: cur.senderId,
                  imageUrl: remaining.first.imageUrl,
                  textContent: remaining.first.textContent,
                  isCleared: false,
                  createdAt: cur.createdAt,
                  updatedAt: DateTime.now(),
                  activeScribbles: remaining,
                );
              }
            }
          }
        });
        _loadTimelineHistory();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.delete_sweep_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Scribble moved to trash bin and deleted.',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.secondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete scribble: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showLockScreenPreviewDialog({
    ScribbleModel? scribble,
    ScribbleItem? item,
    String? connectionId,
    String? senderName,
  }) {
    final active = _activeConnection;
    final connId = connectionId ?? scribble?.connectionId ?? active?.id ?? '';
    final partner = senderName ?? item?.senderName ?? active?.partnerProfile?.username ?? 'Partner';
    final targetScribble = scribble ?? (active != null ? _connectionScribbles[active.id] : null);

    final imageUrl = item?.imageUrl ?? targetScribble?.imageUrl;
    final textContent = item?.textContent ?? targetScribble?.textContent;
    final scribbleId = item?.id ?? targetScribble?.id ?? connId;
    final createdAt = item?.createdAt ?? targetScribble?.createdAt ?? DateTime.now();

    final timeFormatted = DateFormat.yMMMd().add_jm().format(createdAt.toLocal());

    final media = MediaQuery.of(context).size;
    final maxDialogWidth = math.min(media.width * 0.94, 620.0);
    final maxDialogHeight = math.min(media.height * 0.88, 760.0);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Center(
          child: Container(
            width: maxDialogWidth,
            height: maxDialogHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF13151F),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white12, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(180),
                  blurRadius: 36,
                  spreadRadius: 6,
                ),
                BoxShadow(
                  color: AppColors.primaryContainer.withAlpha(40),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Column(
                children: [
                  // Sleek Top Header Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1C28),
                      border: Border(bottom: BorderSide(color: Colors.white.withAlpha(15))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Partner Info / Timestamp
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryFixed,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    partner.isNotEmpty ? partner[0].toUpperCase() : '?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      partner,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      timeFormatted,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Action Icons: Save, Trash, Close
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty) ...[
                              IconButton(
                                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                                tooltip: 'Save to Gallery',
                                onPressed: () => _saveImageUrlToDevice(imageUrl),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                tooltip: 'Move to Trash Bin',
                                onPressed: () => _deleteScribbleFromPreview(
                                  connId: connId,
                                  sId: scribbleId,
                                  imgUrl: imageUrl,
                                  dialogCtx: ctx,
                                ),
                              ),
                            ],
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                              tooltip: 'Close Preview',
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Main Big Picture Viewing Area
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: const Color(0xFF0A0B10),
                      child: (imageUrl != null && imageUrl.isNotEmpty)
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                // Interactive Zoomable Scribble Area
                                InteractiveViewer(
                                  minScale: 0.8,
                                  maxScale: 4.0,
                                  clipBehavior: Clip.antiAlias,
                                  child: Center(
                                    child: Container(
                                      margin: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withAlpha(90),
                                            blurRadius: 18,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Tactile Notebook Lines Background
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                              children: List.generate(
                                                12,
                                                (_) => Container(height: 1, color: AppColors.outlineVariant.withAlpha(45)),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: _buildScribbleImage(
                                                imageUrl,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Floating Caption if text was attached
                                if (textContent != null && textContent.trim().isNotEmpty)
                                  Positioned(
                                    bottom: 14,
                                    left: 20,
                                    right: 20,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(200),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white24, width: 1.2),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 10),
                                        ],
                                      ),
                                      child: Text(
                                        textContent,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),

                                // Subtle Zoom Tip
                                Positioned(
                                  top: 12,
                                  right: 14,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.pinch_rounded, size: 12, color: Colors.white70),
                                        const SizedBox(width: 4),
                                        Text('Pinch to zoom', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white70)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.draw_rounded, color: Colors.white24, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No active scribble available',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),

                  // Bottom Dock Bar: Action Buttons
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1C28),
                        border: Border(top: BorderSide(color: Colors.white.withAlpha(15))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _deleteScribbleFromPreview(
                              connId: connId,
                              sId: scribbleId,
                              imgUrl: imageUrl,
                              dialogCtx: ctx,
                            ),
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                            label: Text(
                              'Move to Trash',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.error,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.error, width: 1.2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _saveImageUrlToDevice(imageUrl),
                            icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                            label: Text(
                              'Save to Gallery',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryContainer,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
      ),
    );
  }


  void _openDrawingCanvas(ConnectionModel conn) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScribbleCanvasScreen(
          connectionId: conn.id,
          partnerName: conn.partnerProfile?.username ?? 'Partner',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Fixed Top Navigation Header matching design
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withAlpha(220),
            border: const Border(bottom: BorderSide(color: AppColors.surfaceContainer, width: 1)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // App Logo & Title
                  Row(
                    children: [
                      const ScribbleLogo(size: 38, showGlow: true),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Scribble',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurface,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            _currentTabIndex == 1
                                ? 'Timeline'
                                : (_currentTabIndex == 2 ? 'Pair Partners' : 'Live Lock Screen'),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Top Right Actions (Notifications & Profile)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded, size: 24, color: AppColors.onSurfaceVariant),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Notifications are active!'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(onSignedOut: widget.onSignOut),
                            ),
                          ).then((_) {
                            final uid = FirebaseService().currentUser?.uid;
                            if (uid != null) {
                              FirebaseService().getProfile(uid).then((p) {
                                if (mounted) setState(() => _myProfile = p);
                              });
                            }
                          });
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primaryContainer.withAlpha(80), width: 2),
                          ),
                          child: CircleAvatar(
                            backgroundColor: AppColors.surfaceContainerHigh,
                            backgroundImage: (_myProfile?.avatarUrl != null && _myProfile!.avatarUrl!.isNotEmpty)
                                ? NetworkImage(_myProfile!.avatarUrl!)
                                : (FirebaseService().currentUser?.photoURL != null
                                    ? NetworkImage(FirebaseService().currentUser!.photoURL!)
                                    : null),
                            child: (_myProfile?.avatarUrl == null && FirebaseService().currentUser?.photoURL == null)
                                ? const Icon(Icons.person_rounded, size: 20, color: AppColors.primary)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // TAB 0: HOME FEED
          _buildHomeFeed(),

          // TAB 1: TIMELINE
          _buildTimelineView(),

          // TAB 2: PAIR SCREEN
          PairingScreen(onConnectionsChanged: _loadConnections),
        ],
      ),

      // Anchored Floating Action Button: '+ New Scribble'
      floatingActionButton: _currentTabIndex == 0
          ? Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_connections.isNotEmpty) {
                    _openDrawingCanvas(_activeConnection ?? _connections.first);
                  } else {
                    setState(() => _currentTabIndex = 2);
                  }
                },
                icon: const Icon(Icons.draw_rounded, size: 22, color: Colors.white),
                label: Text(
                  '+ New Scribble',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 6,
                  shadowColor: AppColors.primaryContainer.withAlpha(120),
                ),
              ),
            )
          : null,

      // Fixed Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest.withAlpha(240),
          border: const Border(top: BorderSide(color: AppColors.surfaceContainer, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(
                      index: 0,
                      icon: Icons.dashboard_rounded,
                      label: 'Home',
                    ),
                    _buildNavItem(
                      index: 1,
                      icon: Icons.history_edu_rounded,
                      label: 'Timeline',
                    ),
                    _buildNavItem(
                      index: 2,
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Pair',
                    ),
                  ],
                ),
              ),
              // Home indicator pill
              Container(
                width: 120,
                height: 4,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.onSurface.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({required int index, required IconData icon, required String label}) {
    final isSelected = _currentTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() => _currentTabIndex = index);
        if (index == 1) {
          _loadTimelineHistory();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.primaryContainer : AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primaryContainer : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Real Dynamic Streak Banner (keeps the feature, powered by real data!)
  Widget _buildRealStreakBanner() {
    if (_connections.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceContainerHigh),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primaryFixed,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                size: 24,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Daily scribble streak',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withAlpha(40),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'READY',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pair with a friend to unlock daily drawing streaks!',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() => _currentTabIndex = 2),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                    Text(
                      'Pair',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Active connection streak calculation
    final activeConn = _activeConnection ?? _connections.first;
    final partnerName = activeConn.partnerProfile?.username ?? 'Partner';
    final scribble = _connectionScribbles[activeConn.id];

    final now = DateTime.now();
    final daysConnected = now.difference(activeConn.createdAt).inDays + 1;
    
    // Check if scribble was exchanged today
    bool sentToday = false;
    if (scribble != null && !scribble.isCleared && scribble.imageUrl != null) {
      final scribbleDate = scribble.updatedAt.toLocal();
      sentToday = scribbleDate.year == now.year &&
          scribbleDate.month == now.month &&
          scribbleDate.day == now.day;
    }

    final streakDays = daysConnected;
    final activeScribblesCount = _connectionScribbles.values.where((s) => s != null && !s.isCleared && s.imageUrl != null).length;
    final energy = (streakDays * 4) + (activeScribblesCount * 2);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceContainerHigh),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Fire Icon & Streak Info
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    size: 24,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$streakDays-day scribble streak',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: sentToday ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              sentToday ? 'ACTIVE' : 'KEEP ALIVE',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: sentToday ? Colors.white : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sentToday
                            ? 'Shared with $partnerName • Streak active for today!'
                            : 'Shared with $partnerName • Keep ink flowing today!',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right: Real ⚡ Energy Counter pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚡', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 4),
                Text(
                  '$energy',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryOptimizationBanner() {
    if (!_isAndroidPlatform || !_isBatteryOptimized) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondaryFixed.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable Background Lock Screen Sync',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Allow Scribble to update your lock screen immediately even when your phone is asleep.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              await NativeLockscreenService().requestIgnoreBatteryOptimization();
              Future.delayed(const Duration(seconds: 2), () async {
                final ignored = await NativeLockscreenService().isIgnoringBatteryOptimizations();
                if (mounted) {
                  setState(() => _isBatteryOptimized = !ignored);
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              elevation: 0,
            ),
            child: Text(
              'Allow',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeFeed() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primaryContainer))
        : RefreshIndicator(
            onRefresh: _loadConnections,
            color: AppColors.primaryContainer,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Real Streak Banner
                      _buildRealStreakBanner(),

                      // Background Sync & Battery Optimization Banner (Android only)
                      _buildBatteryOptimizationBanner(),

                      // 2. Section Header: "Your people"
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Your people',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.secondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryFixed,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_connections.length} Connected',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Connected friends who receive your notes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 3. Authentic People Cards Stack
                      if (_connections.isEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.people_outline_rounded, size: 28, color: AppColors.outline),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No connected friends yet',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pair with a friend below to start exchanging real-time scribbles on your lock screen.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        for (final conn in _connections)
                          _buildPersonCard(conn),
                      ],

                      const SizedBox(height: 16),

                      // 4. "Pair someone new" Action Tile
                      InkWell(
                        onTap: () => setState(() => _currentTabIndex = 2),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.surfaceContainerHigh),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: AppColors.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_add_rounded,
                                  size: 28,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Pair someone new',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Share an invite code or tap phones to send secret desk notes',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryFixed.withAlpha(180),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.qr_code_2_rounded, size: 18, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Scan or Share Link',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
  }

  Widget _buildPersonCard(ConnectionModel conn) {
    final partner = conn.partnerProfile;
    final partnerName = partner?.username ?? 'Partner';
    final scribble = _connectionScribbles[conn.id];
    final hasActiveScribble = scribble != null &&
        !scribble.isCleared &&
        scribble.imageUrl != null;
    final isActiveLockscreen = _activeConnection?.id == conn.id;

    // Formatting pairing time
    String pairedText = 'Paired today';
    final diffDays = DateTime.now().difference(conn.createdAt).inDays;
    if (diffDays >= 7) {
      pairedText = 'Paired ${(diffDays / 7).floor()}w ago';
    } else if (diffDays >= 1) {
      pairedText = 'Paired ${diffDays}d ago';
    }


    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: isActiveLockscreen ? Border.all(color: AppColors.secondary.withAlpha(80), width: 1.5) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Meta Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primaryFixed,
                          backgroundImage: partner?.avatarUrl != null ? NetworkImage(partner!.avatarUrl!) : null,
                          child: partner?.avatarUrl == null
                              ? Text(
                                  partnerName.isNotEmpty ? partnerName[0].toUpperCase() : '?',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  partnerName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.favorite_rounded, size: 16, color: AppColors.primary),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  pairedText,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.onSurfaceVariant),
                                ),
                              ),
                              if (isActiveLockscreen) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryFixed,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lock_rounded, size: 10, color: AppColors.secondary),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Lock Screen Active',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                InkWell(
                                  onTap: () => _setActiveConnection(conn),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Text(
                                    'Tap to set Lock Screen',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.onSurfaceVariant),
                onPressed: () => _showPersonOptionsSheet(conn),
                tooltip: 'Options & Lock Screen',
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Tactile Scribble Canvas Preview (with faint lined notebook background!)
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MultiScribbleSlider(
                  items: (scribble != null && scribble.activeScribbles.isNotEmpty)
                      ? scribble.activeScribbles
                      : (hasActiveScribble
                          ? [
                              ScribbleItem(
                                id: scribble.id,
                                senderId: scribble.senderId,
                                senderName: partnerName,
                                imageUrl: scribble.imageUrl!,
                                textContent: scribble.textContent,
                                createdAt: scribble.updatedAt,
                              )
                            ]
                          : []),
                  partnerName: partnerName,
                  connectionId: conn.id,
                  isHeartReacted: _heartReactionConnectionId == conn.id,
                  onDoubleTap: () => _triggerHeartReaction(conn.id, partnerName),
                  onView: (item) => _showLockScreenPreviewDialog(
                    item: item,
                    connectionId: conn.id,
                    senderName: item.senderName ?? partnerName,
                  ),
                ),

                const SizedBox(height: 10),

                // Bottom Quick Response Dock (Responsive Wrap to prevent overflow)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InkWell(
                      onTap: () => _triggerHeartReaction(conn.id, partnerName),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _heartReactionConnectionId == conn.id
                              ? AppColors.primaryFixed
                              : AppColors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite_rounded,
                              size: 13,
                              color: _heartReactionConnectionId == conn.id
                                  ? AppColors.primary
                                  : AppColors.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Double tap to ❤️',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _heartReactionConnectionId == conn.id
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showLockScreenPreviewDialog(
                            scribble: scribble,
                            senderName: partnerName,
                          ),
                          icon: const Icon(Icons.visibility_rounded, size: 16),
                          label: Text(
                            'View',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceContainer,
                            foregroundColor: AppColors.onSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _openDrawingCanvas(conn),
                          icon: const Icon(Icons.reply_rounded, size: 16, color: Colors.white),
                          label: Text(
                            'Reply',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    return _isLoadingTimeline && _timelineHistory.isEmpty
        ? const Center(child: CircularProgressIndicator(color: AppColors.primaryContainer))
        : RefreshIndicator(
            onRefresh: _loadTimelineHistory,
            color: AppColors.primaryContainer,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scribble Timeline',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'A living memory stream of exchanged doodles',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                            onPressed: _loadTimelineHistory,
                            tooltip: 'Refresh Timeline',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Filter chips if multiple partners
                      if (_connections.length > 1) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('All Partners'),
                                selected: _timelineFilterConnectionId == null,
                                onSelected: (sel) {
                                  setState(() => _timelineFilterConnectionId = null);
                                  _loadTimelineHistory();
                                },
                                selectedColor: AppColors.primaryContainer.withAlpha(40),
                                checkmarkColor: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              ..._connections.map((c) {
                                final isSelected = _timelineFilterConnectionId == c.id;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(c.partnerProfile?.username ?? 'Partner'),
                                    selected: isSelected,
                                    onSelected: (sel) {
                                      setState(() => _timelineFilterConnectionId = sel ? c.id : null);
                                      _loadTimelineHistory();
                                    },
                                    selectedColor: AppColors.primaryContainer.withAlpha(40),
                                    checkmarkColor: AppColors.primary,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_timelineHistory.isEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.history_edu_rounded, size: 48, color: AppColors.outline),
                                const SizedBox(height: 12),
                                Text(
                                  'No archived doodles yet',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Scribbles sent and received will automatically populate your memory stream.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        for (int i = 0; i < _timelineHistory.length; i++)
                          _buildTimelineCard(_timelineHistory[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
  }

  Widget _buildTimelineCard(ScribbleItem item) {
    final sender = item.senderName ?? 'Partner';
    final timeStr = DateFormat.yMMMd().add_jm().format(item.createdAt.toLocal());
    final isMe = item.senderId == FirebaseService().currentUser?.uid;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, and Formatted Timestamp
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryFixed,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        isMe ? 'Me' : (sender.isNotEmpty ? sender[0].toUpperCase() : '?'),
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isMe ? 'You' : sender,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                timeStr,
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.outline),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Scribble Canvas Container
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 180,
              width: double.infinity,
              color: Colors.white,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Notebook Faint Ruled Lines
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      6,
                      (_) => Container(height: 1, color: AppColors.outlineVariant.withAlpha(60)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildScribbleImage(item.imageUrl, fit: BoxFit.contain),
                  ),
                  if (item.textContent != null && item.textContent!.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.textContent!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Action Buttons: Save to Device, Lock Screen View, Reply
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: () => _saveImageUrlToDevice(item.imageUrl),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text(
                  'Save',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface,
                  side: const BorderSide(color: AppColors.surfaceContainerHigh),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _showLockScreenPreviewDialog(
                      item: item,
                      connectionId: _activeConnection?.id ?? item.id,
                      senderName: sender,
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: Text(
                      'Preview',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_connections.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => _openDrawingCanvas(_activeConnection ?? _connections.first),
                      icon: const Icon(Icons.reply_rounded, size: 15, color: Colors.white),
                      label: Text(
                        'Reply',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
