import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/user_profile.dart';
import '../models/connection_model.dart';
import '../models/scribble_model.dart';
import 'native_lockscreen_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;

  final Map<String, RealtimeChannel> _scribbleChannels = {};
  final Map<String, StreamController<ScribbleModel?>> _scribbleControllers = {};

  // ---------------------------------------------------------------------------
  // AUTHENTICATION & PROFILES
  // ---------------------------------------------------------------------------

  /// Sign up with email, password, and username
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );

    if (response.user != null) {
      // Create profile row in profiles table
      await client.from('profiles').upsert({
        'id': response.user!.id,
        'username': username,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    return response;
  }

  /// Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static const String keyIsGuest = 'scribble_is_guest_session';

  /// Check if current session is an ephemeral Guest session
  Future<bool> isGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsGuest) ?? (currentUser?.isAnonymous ?? false);
  }

  /// Instant Guest/Anonymous sign in (temporary session, not synced across devices)
  Future<AuthResponse> signInAnonymously({String username = 'Guest Scribbler'}) async {
    final response = await client.auth.signInAnonymously(
      data: {'username': username},
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsGuest, true);

    if (response.user != null) {
      await client.from('profiles').upsert({
        'id': response.user!.id,
        'username': username,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    return response;
  }

  /// Clean up and permanently delete all data created by the guest session
  Future<void> endGuestSessionAndClearData() async {
    await signOut();
  }

  /// Sign out (automatically purges guest data if in a guest session)
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool(keyIsGuest) ?? false;
    final uid = currentUser?.id;

    if (isGuest && uid != null) {
      try {
        await client.from('scribbles').delete().eq('sender_id', uid);
        await client.from('connections').delete().or('user_1.eq.$uid,user_2.eq.$uid');
        await client.from('pairing_codes').delete().eq('user_id', uid);
        await client.from('profiles').delete().eq('id', uid);
      } catch (e) {
        debugPrint('Guest data purge note: $e');
      }
    }

    await prefs.remove(keyIsGuest);
    await unsubscribeFromScribbles();
    await client.auth.signOut();
  }

  /// Fetch user profile by ID
  Future<UserProfile?> getProfile(String userId) async {
    try {
      final data = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) return null;
      return UserProfile.fromMap(data);
    } catch (e) {
      debugPrint('Error getting profile: $e');
      return null;
    }
  }

  /// Update current user's profile
  Future<void> updateProfile({
    required String username,
    String? avatarUrl,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    final updates = {
      'id': uid,
      'username': username,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await client.from('profiles').upsert(updates);
  }

  /// Upload avatar image to Supabase Storage
  Future<String?> uploadAvatar(Uint8List imageBytes, String fileExt) async {
    final uid = currentUser?.id;
    if (uid == null) return null;

    final fileName = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from(AppConstants.avatarBucket).uploadBinary(
      fileName,
      imageBytes,
      fileOptions: const FileOptions(upsert: true),
    );

    final publicUrl = client.storage.from(AppConstants.avatarBucket).getPublicUrl(fileName);
    await updateProfile(
      username: (await getProfile(uid))?.username ?? 'Scribbler',
      avatarUrl: publicUrl,
    );
    return publicUrl;
  }

  // ---------------------------------------------------------------------------
  // PAIRING SYSTEM
  // ---------------------------------------------------------------------------

  /// Generate a unique 6-character alphanumeric pairing code
  Future<String> generatePairingCode() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('User not authenticated');

    // Remove any previous pairing codes for this user
    await client.from('pairing_codes').delete().eq('user_id', uid);

    // Generate random 6-character uppercase code (avoiding confusing chars like 0/O, 1/I)
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final random = Random.secure();
    final code = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();

    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));

    await client.from('pairing_codes').insert({
      'code': code,
      'user_id': uid,
      'expires_at': expiresAt.toIso8601String(),
    });

    return code;
  }

  /// Enter a friend's pairing code to establish a mutual connection
  Future<ConnectionModel> claimPairingCode(String code) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('User not authenticated');

    final cleanCode = code.trim().toUpperCase();

    // Find the code
    final codeData = await client
        .from('pairing_codes')
        .select()
        .eq('code', cleanCode)
        .maybeSingle();

    if (codeData == null) {
      throw Exception('Invalid or expired pairing code.');
    }

    final partnerId = (codeData['user_id'] ?? '').toString();
    if (partnerId.isEmpty) {
      throw Exception('Invalid pairing code record.');
    }
    if (partnerId == uid) {
      throw Exception('You cannot pair with yourself!');
    }

    // Check if connection already exists
    final existing = await client
        .from('connections')
        .select()
        .or('and(user_1.eq.$uid,user_2.eq.$partnerId),and(user_1.eq.$partnerId,user_2.eq.$uid)')
        .maybeSingle();

    if (existing != null) {
      try {
        await client.from('pairing_codes').delete().eq('code', cleanCode);
      } catch (_) {}
      final conn = ConnectionModel.fromMap(existing, currentUserId: uid);
      conn.partnerProfile = await getProfile(partnerId);
      return conn;
    }

    // Create new connection
    final newConn = await client.from('connections').insert({
      'user_1': partnerId,
      'user_2': uid,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    // Delete used pairing code
    try {
      await client.from('pairing_codes').delete().eq('code', cleanCode);
    } catch (_) {}

    final connection = ConnectionModel.fromMap(newConn, currentUserId: uid);
    connection.partnerProfile = await getProfile(partnerId);
    return connection;
  }

  /// Retrieve all connections for current user with partner profiles
  Future<List<ConnectionModel>> getConnections() async {
    final uid = currentUser?.id;
    if (uid == null) return [];

    final data = await client
        .from('connections')
        .select()
        .or('user_1.eq.$uid,user_2.eq.$uid')
        .order('created_at', ascending: false);

    final List<ConnectionModel> connections = [];

    for (final item in data) {
      final conn = ConnectionModel.fromMap(item, currentUserId: uid);
      final partnerId = conn.getPartnerId(uid);
      conn.partnerProfile = await getProfile(partnerId);
      connections.add(conn);
    }

    return connections;
  }

  /// Delete a connection
  Future<void> removeConnection(String connectionId) async {
    await client.from('connections').delete().eq('id', connectionId);
  }

  // ---------------------------------------------------------------------------
  // SCRIBBLE SYSTEM & REAL-TIME SYNC
  // ---------------------------------------------------------------------------

  /// Fetch the latest scribble for a connection
  Future<ScribbleModel?> getLatestScribble(String connectionId) async {
    try {
      final data = await client
          .from('scribbles')
          .select()
          .eq('connection_id', connectionId)
          .maybeSingle();

      if (data == null) return null;
      return ScribbleModel.fromMap(data);
    } catch (e) {
      debugPrint('Error getting latest scribble: $e');
      return null;
    }
  }

  /// Send a new scribble (uploads image & replaces previous scribble for connection)
  Future<ScribbleModel> sendScribble({
    required String connectionId,
    required Uint8List pngBytes,
    String? textContent,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('User not authenticated');

    // 1. Upload scribble image to Supabase Storage
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = 'scribbles/${connectionId}_$timestamp.png';

    await client.storage.from(AppConstants.scribbleBucket).uploadBinary(
      filePath,
      pngBytes,
      fileOptions: const FileOptions(
        contentType: 'image/png',
        upsert: true,
      ),
    );

    final publicUrl = client.storage.from(AppConstants.scribbleBucket).getPublicUrl(filePath);

    // 2. Upsert scribble record (replaces previous scribble for this connection)
    final upsertData = {
      'connection_id': connectionId,
      'sender_id': uid,
      'image_url': publicUrl,
      'text_content': textContent,
      'is_cleared': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final result = await client
        .from('scribbles')
        .upsert(
          upsertData,
          onConflict: 'connection_id',
        )
        .select()
        .single();

    return ScribbleModel.fromMap(result);
  }

  /// Clear the current scribble for a connection
  Future<void> clearScribble(String connectionId) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    await client.from('scribbles').upsert({
      'connection_id': connectionId,
      'sender_id': uid,
      'image_url': null,
      'text_content': null,
      'is_cleared': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'connection_id');
  }

  /// Subscribe to Realtime updates for a connection's latest scribble
  Stream<ScribbleModel?> subscribeToScribble(String connectionId) {
    if (_scribbleControllers.containsKey(connectionId) && !_scribbleControllers[connectionId]!.isClosed) {
      return _scribbleControllers[connectionId]!.stream;
    }

    final controller = StreamController<ScribbleModel?>.broadcast();
    _scribbleControllers[connectionId] = controller;

    // Initial fetch
    getLatestScribble(connectionId).then((scribble) {
      if (!controller.isClosed) {
        controller.add(scribble);
      }
    });

    // Unsubscribe previous channel for this connection if open
    _scribbleChannels[connectionId]?.unsubscribe();

    // Listen to real-time postgres changes
    final channel = client
        .channel('realtime:scribbles:$connectionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'scribbles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'connection_id',
            value: connectionId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty) {
              final scribble = ScribbleModel.fromMap(newRecord);
              if (!controller.isClosed) {
                controller.add(scribble);
              }

              // Realtime lockscreen update if received from partner
              final myUid = currentUser?.id;
              if (scribble.senderId != myUid) {
                if (scribble.isCleared || scribble.imageUrl == null) {
                  await NativeLockscreenService().clearLockscreen();
                } else {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    final activeConnId = prefs.getString(AppConstants.keyActiveConnectionId);
                    if (activeConnId == null || activeConnId == connectionId) {
                      await NativeLockscreenService().updateLockscreenFromUrl(
                        scribble.imageUrl!,
                        senderName: 'Partner',
                      );
                    }
                  } catch (e) {
                    debugPrint('Error applying lockscreen update: $e');
                  }
                }
              }
            }
          },
        )
        .subscribe();

    _scribbleChannels[connectionId] = channel;
    return controller.stream;
  }

  /// Unsubscribe from realtime scribble events
  Future<void> unsubscribeFromScribbles([String? connectionId]) async {
    if (connectionId != null) {
      await _scribbleChannels[connectionId]?.unsubscribe();
      _scribbleChannels.remove(connectionId);
      await _scribbleControllers[connectionId]?.close();
      _scribbleControllers.remove(connectionId);
    } else {
      for (final ch in _scribbleChannels.values) {
        await ch.unsubscribe();
      }
      _scribbleChannels.clear();
      for (final c in _scribbleControllers.values) {
        await c.close();
      }
      _scribbleControllers.clear();
    }
  }
}
