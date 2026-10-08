import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/user_profile.dart';
import '../models/connection_model.dart';
import '../models/scribble_model.dart';
import 'cloudinary_service.dart';
import 'native_lockscreen_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get firestore => FirebaseFirestore.instance;
  FirebaseStorage get storage => FirebaseStorage.instance;

  User? get currentUser => auth.currentUser;

  final Map<String, StreamSubscription<DocumentSnapshot>> _scribbleSubscriptions = {};
  final Map<String, StreamController<ScribbleModel?>> _scribbleControllers = {};

  static const String keyIsGuest = 'scribble_is_guest_session';

  // ---------------------------------------------------------------------------
  // AUTHENTICATION & PROFILES
  // ---------------------------------------------------------------------------

  /// Sign up with email, password, and username
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(username);

      final now = DateTime.now().toUtc().toIso8601String();
      await firestore.collection('users').doc(user.uid).set({
        'id': user.uid,
        'username': username,
        'email': email.trim(),
        'created_at': now,
        'updated_at': now,
      }, SetOptions(merge: true));
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsGuest, false);

    return credential;
  }

  /// Sign in with email and password
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsGuest, false);

    return credential;
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in flow
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final googlePhoto = user.photoURL ?? googleUser.photoUrl;
        final userDoc = await firestore.collection('users').doc(user.uid).get();
        final now = DateTime.now().toUtc().toIso8601String();

        if (!userDoc.exists) {
          await firestore.collection('users').doc(user.uid).set({
            'id': user.uid,
            'username': user.displayName ?? googleUser.displayName ?? 'Google Scribbler',
            'email': user.email ?? googleUser.email,
            'avatar_url': googlePhoto,
            'created_at': now,
            'updated_at': now,
          });
        } else {
          final data = userDoc.data() ?? {};
          final currentAvatar = data['avatar_url'] as String?;
          await firestore.collection('users').doc(user.uid).update({
            'updated_at': now,
            if (googlePhoto != null && (currentAvatar == null || currentAvatar.isEmpty))
              'avatar_url': googlePhoto,
          });
        }

        if (googlePhoto != null && (user.photoURL == null || user.photoURL!.isEmpty)) {
          try {
            await user.updatePhotoURL(googlePhoto);
          } catch (_) {}
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyIsGuest, false);

      return userCredential;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      rethrow;
    }
  }

  /// Check if current session is an ephemeral Guest session
  Future<bool> isGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsGuest) ?? (currentUser?.isAnonymous ?? false);
  }

  /// Instant Guest/Anonymous sign in
  Future<UserCredential> signInAnonymously({String username = 'Guest Scribbler'}) async {
    final credential = await auth.signInAnonymously();
    final user = credential.user;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsGuest, true);

    if (user != null) {
      await user.updateDisplayName(username);
      final now = DateTime.now().toUtc().toIso8601String();
      await firestore.collection('users').doc(user.uid).set({
        'id': user.uid,
        'username': username,
        'is_guest': true,
        'created_at': now,
        'updated_at': now,
      });
    }

    return credential;
  }

  /// Clean up and permanently delete all data created by the guest session
  Future<void> endGuestSessionAndClearData() async {
    await signOut();
  }

  /// Sign out (purges guest records if guest session)
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool(keyIsGuest) ?? false;
    final uid = currentUser?.uid;

    if (isGuest && uid != null) {
      try {
        // Delete guest scribbles
        final scribblesQuery = await firestore.collection('scribbles').where('sender_id', isEqualTo: uid).get();
        for (final doc in scribblesQuery.docs) {
          await doc.reference.delete();
        }

        // Delete guest connections
        final c1 = await firestore.collection('connections').where('user_1', isEqualTo: uid).get();
        for (final doc in c1.docs) {
          await doc.reference.delete();
        }
        final c2 = await firestore.collection('connections').where('user_2', isEqualTo: uid).get();
        for (final doc in c2.docs) {
          await doc.reference.delete();
        }

        // Delete pairing codes
        final pc = await firestore.collection('pairing_codes').where('user_id', isEqualTo: uid).get();
        for (final doc in pc.docs) {
          await doc.reference.delete();
        }

        // Delete user doc
        await firestore.collection('users').doc(uid).delete();
      } catch (e) {
        debugPrint('Guest data purge note: $e');
      }
    }

    await prefs.remove(keyIsGuest);
    await unsubscribeFromScribbles();

    try {
      final googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (_) {}

    await auth.signOut();
  }

  /// Permanently deletes the user's account and all associated cloud and local data.
  /// Complies with Google Play Store User Data & Account Deletion Policy.
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      // 1. Delete all connections & scribble data where user is participant
      final q1 = await firestore.collection('connections').where('user_1', isEqualTo: uid).get();
      final q2 = await firestore.collection('connections').where('user_2', isEqualTo: uid).get();
      final allConns = {...q1.docs, ...q2.docs};

      for (final connDoc in allConns) {
        final connId = connDoc.id;
        try {
          final historyDocs = await firestore.collection('scribbles').doc(connId).collection('history').get();
          for (final hDoc in historyDocs.docs) {
            await hDoc.reference.delete();
          }
        } catch (_) {}

        try {
          await firestore.collection('scribbles').doc(connId).delete();
        } catch (_) {}

        try {
          await connDoc.reference.delete();
        } catch (_) {}
      }

      // 2. Delete user's active pairing codes
      final pc = await firestore.collection('pairing_codes').where('user_id', isEqualTo: uid).get();
      for (final doc in pc.docs) {
        await doc.reference.delete();
      }

      // 3. Delete user profile document
      await firestore.collection('users').doc(uid).delete();

      // 4. Wipe local lockscreen / widget cache & local preferences
      try {
        await NativeLockscreenService().clearLockscreenCache();
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await unsubscribeFromScribbles();

      // 5. Sign out of Google if signed in
      try {
        final googleSignIn = GoogleSignIn();
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
        }
      } catch (_) {}

      // 6. Permanently delete Firebase Auth user credentials
      await user.delete();
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      debugPrint('Error deleting account: $e');
      rethrow;
    }
  }

  /// Fetch user profile by ID
  Future<UserProfile?> getProfile(String userId) async {
    try {
      final doc = await firestore.collection('users').doc(userId).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return UserProfile.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('Error getting profile: $e');
      return null;
    }
  }

  /// Syncs current user's profile photo with Google account if signed in with Google
  Future<UserProfile?> syncGooglePhotoIfAvailable() async {
    final user = currentUser;
    if (user == null || user.isAnonymous) return null;

    String? photo = user.photoURL;
    if (photo == null || photo.isEmpty) {
      for (final p in user.providerData) {
        if (p.photoURL != null && p.photoURL!.isNotEmpty) {
          photo = p.photoURL;
          break;
        }
      }
    }

    if (photo != null && photo.isNotEmpty) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'avatar_url': photo,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, SetOptions(merge: true));

        if (user.photoURL == null || user.photoURL!.isEmpty) {
          await user.updatePhotoURL(photo);
        }
      } catch (e) {
        debugPrint('Error syncing Google photo: $e');
      }
    }

    return getProfile(user.uid);
  }

  /// Update current user's profile
  Future<void> updateProfile({
    required String username,
    String? avatarUrl,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final updates = <String, dynamic>{
      'id': uid,
      'username': username,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'updated_at': now,
    };

    await currentUser?.updateDisplayName(username);
    if (avatarUrl != null) {
      await currentUser?.updatePhotoURL(avatarUrl);
    }

    await firestore.collection('users').doc(uid).set(updates, SetOptions(merge: true));
  }

  /// Upload avatar image to Firebase Storage (with instant base64 fallback)
  Future<String?> uploadAvatar(Uint8List imageBytes, String fileExt) async {
    final uid = currentUser?.uid;
    if (uid == null) return null;

    String downloadUrl;
    try {
      final fileName = 'avatars/${uid}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final ref = storage.ref().child(fileName);

      final metadata = SettableMetadata(
        contentType: 'image/$fileExt',
        cacheControl: 'public, max-age=3600',
      );

      final uploadTask = await ref.putData(imageBytes, metadata);
      downloadUrl = await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Firebase Storage upload failed, falling back to base64: $e');
      final base64String = base64Encode(imageBytes);
      downloadUrl = 'data:image/$fileExt;base64,$base64String';
    }

    await updateProfile(
      username: (await getProfile(uid))?.username ?? 'Scribbler',
      avatarUrl: downloadUrl,
    );

    return downloadUrl;
  }

  // ---------------------------------------------------------------------------
  // PAIRING SYSTEM
  // ---------------------------------------------------------------------------

  /// Generate a unique 6-character alphanumeric pairing code
  Future<String> generatePairingCode() async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    // Remove any previous pairing codes for this user
    final existingCodes = await firestore.collection('pairing_codes').where('user_id', isEqualTo: uid).get();
    for (final doc in existingCodes.docs) {
      await doc.reference.delete();
    }

    // Generate random 6-character uppercase code
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final random = Random.secure();
    final code = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();

    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();

    await firestore.collection('pairing_codes').doc(code).set({
      'code': code,
      'user_id': uid,
      'expires_at': expiresAt,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return code;
  }

  /// Enter a friend's pairing code to establish a mutual connection
  Future<ConnectionModel> claimPairingCode(String code) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final cleanCode = code.trim().toUpperCase();

    // Find the code
    final codeDoc = await firestore.collection('pairing_codes').doc(cleanCode).get();
    if (!codeDoc.exists || codeDoc.data() == null) {
      throw Exception('Invalid or expired pairing code.');
    }

    final data = codeDoc.data()!;
    final partnerId = (data['user_id'] ?? '').toString();

    if (partnerId.isEmpty) {
      throw Exception('Invalid pairing code record.');
    }
    if (partnerId == uid) {
      throw Exception('You cannot pair with yourself!');
    }

    // Check expiration
    if (data['expires_at'] != null) {
      final exp = DateTime.tryParse(data['expires_at'].toString());
      if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
        await codeDoc.reference.delete();
        throw Exception('This pairing code has expired. Ask your partner for a new one.');
      }
    }

    // Check if connection already exists
    final q1 = await firestore.collection('connections')
        .where('user_1', isEqualTo: uid)
        .where('user_2', isEqualTo: partnerId)
        .limit(1)
        .get();

    final q2 = await firestore.collection('connections')
        .where('user_1', isEqualTo: partnerId)
        .where('user_2', isEqualTo: uid)
        .limit(1)
        .get();

    if (q1.docs.isNotEmpty || q2.docs.isNotEmpty) {
      final existingDoc = q1.docs.isNotEmpty ? q1.docs.first : q2.docs.first;
      try {
        await codeDoc.reference.delete();
      } catch (_) {}
      final conn = ConnectionModel.fromMap(existingDoc.data(), currentUserId: uid);
      conn.partnerProfile = await getProfile(partnerId);
      return conn;
    }

    // Create deterministic ID so both users share exactly the same connection document
    final docId = uid.compareTo(partnerId) < 0 ? '${uid}_$partnerId' : '${partnerId}_$uid';
    final now = DateTime.now().toUtc().toIso8601String();

    final connData = {
      'id': docId,
      'user_1': partnerId,
      'user_2': uid,
      'created_at': now,
    };

    await firestore.collection('connections').doc(docId).set(connData);

    // Delete used pairing code
    try {
      await codeDoc.reference.delete();
    } catch (_) {}

    final connection = ConnectionModel.fromMap(connData, currentUserId: uid);
    connection.partnerProfile = await getProfile(partnerId);
    return connection;
  }

  /// Retrieve all connections for current user with partner profiles
  Future<List<ConnectionModel>> getConnections() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];

    final List<ConnectionModel> connections = [];

    final q1 = await firestore.collection('connections').where('user_1', isEqualTo: uid).get();
    final q2 = await firestore.collection('connections').where('user_2', isEqualTo: uid).get();

    final allDocs = [...q1.docs, ...q2.docs];
    // Deduplicate by id if needed
    final seen = <String>{};

    for (final doc in allDocs) {
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);

      final conn = ConnectionModel.fromMap(doc.data(), currentUserId: uid);
      final partnerId = conn.getPartnerId(uid);
      conn.partnerProfile = await getProfile(partnerId);
      connections.add(conn);
    }

    connections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return connections;
  }

  /// Delete a connection
  Future<void> removeConnection(String connectionId) async {
    await firestore.collection('connections').doc(connectionId).delete();
    try {
      await firestore.collection('scribbles').doc(connectionId).delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SCRIBBLE SYSTEM & REAL-TIME SYNC
  // ---------------------------------------------------------------------------

  /// Fetch the latest scribble for a connection
  Future<ScribbleModel?> getLatestScribble(String connectionId) async {
    try {
      final doc = await firestore.collection('scribbles').doc(connectionId).get();
      if (!doc.exists || doc.data() == null) return null;
      return ScribbleModel.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('Error getting latest scribble: $e');
      return null;
    }
  }

  /// Send a new scribble (uploads to Cloudinary / Firebase Storage & updates scribble document)
  Future<ScribbleModel> sendScribble({
    required String connectionId,
    required Uint8List pngBytes,
    String? textContent,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final senderName = currentUser?.displayName ?? 'Partner';
    final now = DateTime.now().toUtc().toIso8601String();
    final scribbleId = '${connectionId}_${DateTime.now().millisecondsSinceEpoch}';

    // 1. First attempt upload to Cloudinary
    String? publicUrl;
    try {
      publicUrl = await CloudinaryService().uploadImage(
        bytes: pngBytes,
        folder: 'scribbles',
        publicId: scribbleId,
      );
    } catch (e) {
      debugPrint('Cloudinary upload attempt error: $e');
    }

    // 2. If Cloudinary is unconfigured or failed, fallback to Firebase Storage
    if (publicUrl == null || publicUrl.isEmpty) {
      try {
        final filePath = 'scribbles/$scribbleId.png';
        final ref = storage.ref().child(filePath);

        final metadata = SettableMetadata(
          contentType: 'image/png',
          cacheControl: 'public, max-age=86400',
        );

        final uploadTask = await ref.putData(pngBytes, metadata);
        publicUrl = await uploadTask.ref.getDownloadURL();
      } catch (storageError) {
        debugPrint('Firebase Storage unavailable ($storageError). Using instant Firestore image data.');
        final base64String = base64Encode(pngBytes);
        publicUrl = 'data:image/png;base64,$base64String';
      }
    }

    // 3. Fetch existing document to maintain multi-scribble active list for sliding carousel
    List<Map<String, dynamic>> activeList = [];
    try {
      final doc = await firestore.collection('scribbles').doc(connectionId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final isCleared = data['is_cleared'] as bool? ?? false;
        if (!isCleared && data['active_scribbles'] is List) {
          for (final raw in (data['active_scribbles'] as List)) {
            if (raw is Map) {
              activeList.add(Map<String, dynamic>.from(raw));
            }
          }
        } else if (!isCleared && data['image_url'] != null) {
          activeList.add({
            'id': (data['id'] ?? connectionId).toString(),
            'sender_id': (data['sender_id'] ?? '').toString(),
            'sender_name': (data['sender_name'] ?? 'Partner').toString(),
            'image_url': data['image_url'].toString(),
            'text_content': data['text_content'],
            'created_at': (data['created_at'] ?? now).toString(),
          });
        }
      }
    } catch (e) {
      debugPrint('Note loading active scribbles: $e');
    }

    // Prepend new scribble item at top of sliding list (keep up to 10 active items)
    final newItem = {
      'id': scribbleId,
      'sender_id': uid,
      'sender_name': senderName,
      'image_url': publicUrl,
      'text_content': textContent,
      'created_at': now,
    };
    activeList.insert(0, newItem);
    if (activeList.length > 10) {
      activeList = activeList.sublist(0, 10);
    }

    // 4. Write scribble document to Firestore
    final scribbleData = {
      'id': connectionId,
      'connection_id': connectionId,
      'sender_id': uid,
      'sender_name': senderName,
      'image_url': publicUrl,
      'text_content': textContent,
      'is_cleared': false,
      'created_at': now,
      'updated_at': now,
      'active_scribbles': activeList,
    };

    await firestore.collection('scribbles').doc(connectionId).set(scribbleData);

    // 5. Also save to scribble history subcollection for memory timeline
    try {
      await firestore.collection('scribbles').doc(connectionId).collection('history').add({
        'sender_id': uid,
        'sender_name': senderName,
        'image_url': publicUrl,
        'text_content': textContent,
        'created_at': now,
      });
    } catch (e) {
      debugPrint('History archive note: $e');
    }

    return ScribbleModel.fromMap(scribbleData);
  }

  /// Fetch chronological scribble history for a connection
  Future<List<ScribbleItem>> getScribbleHistory(String connectionId, {int limit = 60}) async {
    try {
      final snapshot = await firestore
          .collection('scribbles')
          .doc(connectionId)
          .collection('history')
          .orderBy('created_at', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return ScribbleItem(
          id: doc.id,
          senderId: (data['sender_id'] ?? '').toString(),
          senderName: data['sender_name'] as String?,
          imageUrl: (data['image_url'] ?? '').toString(),
          textContent: data['text_content'] as String?,
          createdAt: data['created_at'] != null
              ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
              : DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting scribble history: $e');
      return [];
    }
  }

  /// Clear the current active scribbles for a connection
  Future<void> clearScribble(String connectionId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await firestore.collection('scribbles').doc(connectionId).set({
      'id': connectionId,
      'connection_id': connectionId,
      'sender_id': uid,
      'image_url': null,
      'text_content': null,
      'active_scribbles': [],
      'is_cleared': true,
      'updated_at': now,
    }, SetOptions(merge: true));

    try {
      await NativeLockscreenService().clearLockscreen();
    } catch (_) {}
  }

  /// Move a scribble to trash / permanently delete it from connection's active notes and history
  Future<void> deleteScribbleFromConnection({
    required String connectionId,
    required String scribbleId,
    String? imageUrl,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final now = DateTime.now().toUtc().toIso8601String();
    final docRef = firestore.collection('scribbles').doc(connectionId);
    final doc = await docRef.get();

    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      List<dynamic> activeList = List.from(data['active_scribbles'] as List? ?? []);

      // Remove targeted item from active list
      activeList.removeWhere((item) {
        if (item is Map) {
          final idMatch = item['id']?.toString() == scribbleId;
          final urlMatch = imageUrl != null && item['image_url']?.toString() == imageUrl;
          return idMatch || urlMatch;
        }
        return false;
      });

      if (activeList.isEmpty) {
        // All active doodles cleared
        await docRef.set({
          'id': connectionId,
          'connection_id': connectionId,
          'sender_id': uid,
          'image_url': null,
          'text_content': null,
          'active_scribbles': [],
          'is_cleared': true,
          'updated_at': now,
        }, SetOptions(merge: true));

        try {
          await NativeLockscreenService().clearLockscreen();
        } catch (_) {}
      } else {
        // Promote top remaining scribble to primary
        final topItem = Map<String, dynamic>.from(activeList.first as Map);
        final newImageUrl = topItem['image_url'] as String?;
        final newText = topItem['text_content'] as String?;
        final newSenderName = (topItem['sender_name'] ?? 'Partner').toString();

        await docRef.set({
          'image_url': newImageUrl,
          'text_content': newText,
          'active_scribbles': activeList,
          'is_cleared': false,
          'updated_at': now,
        }, SetOptions(merge: true));

        if (newImageUrl != null && newImageUrl.isNotEmpty) {
          try {
            await NativeLockscreenService().updateLockscreenFromUrl(
              newImageUrl,
              senderName: newSenderName,
            );
          } catch (_) {}
        }
      }
    }

    // Also delete from history subcollection if present
    try {
      final historyQuery = await docRef.collection('history').get();
      for (final hDoc in historyQuery.docs) {
        final hData = hDoc.data();
        if (hDoc.id == scribbleId || (imageUrl != null && hData['image_url'] == imageUrl)) {
          await hDoc.reference.delete();
        }
      }
    } catch (e) {
      debugPrint('History subcollection delete notice: $e');
    }
  }

  /// Subscribe to Realtime updates for a connection's latest scribble
  Stream<ScribbleModel?> subscribeToScribble(String connectionId) {
    if (_scribbleControllers.containsKey(connectionId) && !_scribbleControllers[connectionId]!.isClosed) {
      return _scribbleControllers[connectionId]!.stream;
    }

    final controller = StreamController<ScribbleModel?>.broadcast();
    _scribbleControllers[connectionId] = controller;

    // Unsubscribe previous subscription if any
    _scribbleSubscriptions[connectionId]?.cancel();

    // Real-time Firestore snapshot listener
    final sub = firestore.collection('scribbles').doc(connectionId).snapshots().listen(
      (snapshot) async {
        if (!snapshot.exists || snapshot.data() == null) {
          if (!controller.isClosed) controller.add(null);
          return;
        }

        final scribble = ScribbleModel.fromMap(snapshot.data()!);
        if (!controller.isClosed) {
          controller.add(scribble);
        }

        // Automatic Lockscreen update if received from partner
        final myUid = currentUser?.uid;
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
      },
      onError: (e) {
        debugPrint('Error listening to scribble snapshots: $e');
      },
    );

    _scribbleSubscriptions[connectionId] = sub;
    return controller.stream;
  }

  /// Unsubscribe from realtime scribble events
  Future<void> unsubscribeFromScribbles([String? connectionId]) async {
    if (connectionId != null) {
      await _scribbleSubscriptions[connectionId]?.cancel();
      _scribbleSubscriptions.remove(connectionId);
      await _scribbleControllers[connectionId]?.close();
      _scribbleControllers.remove(connectionId);
    } else {
      for (final sub in _scribbleSubscriptions.values) {
        await sub.cancel();
      }
      _scribbleSubscriptions.clear();
      for (final c in _scribbleControllers.values) {
        await c.close();
      }
      _scribbleControllers.clear();
    }
  }
}
