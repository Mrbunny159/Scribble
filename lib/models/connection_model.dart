import 'user_profile.dart';

class ConnectionModel {
  final String id;
  final String user1;
  final String user2;
  final DateTime createdAt;
  UserProfile? partnerProfile;

  ConnectionModel({
    required this.id,
    required this.user1,
    required this.user2,
    required this.createdAt,
    this.partnerProfile,
  });

  factory ConnectionModel.fromMap(Map<String, dynamic> map, {String? currentUserId}) {
    return ConnectionModel(
      id: (map['id'] ?? '').toString(),
      user1: (map['user_1'] ?? map['user1'] ?? '').toString(),
      user2: (map['user_2'] ?? map['user2'] ?? '').toString(),
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now() 
          : DateTime.now(),
    );
  }

  String getPartnerId(String currentUserId) {
    return user1 == currentUserId ? user2 : user1;
  }
}
