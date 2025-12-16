class DeliveryAddress {
  final String id;
  final String customerId;
  final String address;
  final String label; // e.g., "Home", "Office", "Mom's House"
  final String? phoneNumber; // Phone number for this address
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  DeliveryAddress({
    required this.id,
    required this.customerId,
    required this.address,
    required this.label,
    this.phoneNumber,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeliveryAddress.fromMap(Map<String, dynamic> map, String id) {
    return DeliveryAddress(
      id: id,
      customerId: map['customerId'] ?? '',
      address: map['address'] ?? '',
      label: map['label'] ?? 'Address',
      phoneNumber: map['phoneNumber'] ?? map['phone_number'],
      isDefault: map['isDefault'] ?? map['is_default'] ?? false,
      createdAt: map['createdAt'] != null || map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? map['created_at'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null || map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] ?? map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'address': address,
      'label': label,
      'phoneNumber': phoneNumber,
      'isDefault': isDefault,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  DeliveryAddress copyWith({
    String? id,
    String? customerId,
    String? address,
    String? label,
    String? phoneNumber,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeliveryAddress(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      address: address ?? this.address,
      label: label ?? this.label,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'DeliveryAddress(id: $id, customerId: $customerId, address: $address, label: $label, phoneNumber: $phoneNumber, isDefault: $isDefault, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeliveryAddress && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
