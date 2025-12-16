class CustomerNotification {
  final String id;
  final String title;
  final String message;
  final String type;
  final DateTime timestamp;
  final bool isRead;
  final String? orderId;
  final String? productId;

  CustomerNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.orderId,
    this.productId,
  });

  factory CustomerNotification.fromMap(Map<String, dynamic> map, String id) {
    return CustomerNotification(
      id: id,
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      type: map['type'] ?? '',
      timestamp: map['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'])
          : DateTime.now(),
      // Support both "isRead" and legacy "read" keys
      isRead: (map['isRead'] ?? map['read']) ?? false,
      orderId: map['orderId'] ?? map['order_id']?.toString(),
      productId: map['productId'] ?? map['product_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isRead': isRead,
      if (orderId != null) 'orderId': orderId,
      if (productId != null) 'productId': productId,
    };
  }

  CustomerNotification copyWith({
    String? id,
    String? title,
    String? message,
    String? type,
    DateTime? timestamp,
    bool? isRead,
    String? orderId,
    String? productId,
  }) {
    return CustomerNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
    );
  }

  @override
  String toString() {
    return 'CustomerNotification(id: $id, title: $title, message: $message, type: $type, timestamp: $timestamp, isRead: $isRead, orderId: $orderId, productId: $productId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomerNotification && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
