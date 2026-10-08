class ScribbleItem {
  final String id;
  final String senderId;
  final String? senderName;
  final String imageUrl;
  final String? textContent;
  final DateTime createdAt;

  ScribbleItem({
    required this.id,
    required this.senderId,
    this.senderName,
    required this.imageUrl,
    this.textContent,
    required this.createdAt,
  });

  factory ScribbleItem.fromMap(Map<String, dynamic> map) {
    return ScribbleItem(
      id: (map['id'] ?? '').toString(),
      senderId: (map['sender_id'] ?? map['senderId'] ?? '').toString(),
      senderName: map['sender_name'] as String?,
      imageUrl: (map['image_url'] ?? '').toString(),
      textContent: map['text_content'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'image_url': imageUrl,
      'text_content': textContent,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

class ScribbleModel {
  final String id;
  final String connectionId;
  final String senderId;
  final String? imageUrl;
  final String? textContent;
  final bool isCleared;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScribbleItem> activeScribbles;

  ScribbleModel({
    required this.id,
    required this.connectionId,
    required this.senderId,
    this.imageUrl,
    this.textContent,
    required this.isCleared,
    required this.createdAt,
    required this.updatedAt,
    this.activeScribbles = const [],
  });

  factory ScribbleModel.fromMap(Map<String, dynamic> map) {
    final List<ScribbleItem> items = [];
    if (map['active_scribbles'] is List) {
      for (final raw in (map['active_scribbles'] as List)) {
        if (raw is Map) {
          final item = ScribbleItem.fromMap(Map<String, dynamic>.from(raw));
          if (item.imageUrl.isNotEmpty) {
            items.add(item);
          }
        }
      }
    }

    final mainImageUrl = map['image_url'] as String?;
    final isCleared = map['is_cleared'] as bool? ?? false;

    // If active_scribbles list is empty but a main image exists, add it as first item
    if (items.isEmpty && mainImageUrl != null && mainImageUrl.isNotEmpty && !isCleared) {
      items.add(ScribbleItem(
        id: (map['id'] ?? map['connection_id'] ?? '').toString(),
        senderId: (map['sender_id'] ?? '').toString(),
        senderName: map['sender_name'] as String?,
        imageUrl: mainImageUrl,
        textContent: map['text_content'] as String?,
        createdAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      ));
    }

    return ScribbleModel(
      id: (map['id'] ?? map['connection_id'] ?? '').toString(),
      connectionId: (map['connection_id'] ?? map['connectionId'] ?? '').toString(),
      senderId: (map['sender_id'] ?? map['senderId'] ?? '').toString(),
      imageUrl: mainImageUrl,
      textContent: map['text_content'] as String?,
      isCleared: isCleared,
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      updatedAt: map['updated_at'] != null 
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      activeScribbles: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'connection_id': connectionId,
      'sender_id': senderId,
      'image_url': imageUrl,
      'text_content': textContent,
      'is_cleared': isCleared,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'active_scribbles': activeScribbles.map((i) => i.toMap()).toList(),
    };
  }
}
