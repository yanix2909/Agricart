import 'dart:convert';

class Order {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String status; // pending, confirmed, processing, shipped, delivered, cancelled
  final String paymentMethod;
  final String paymentStatus; // pending, paid, failed
  // GCash fields
  final String? gcashReceiptUrl;
  final String? refundReceiptUrl;
  final DateTime? refundConfirmedAt;
  // New fields for enhanced ordering flow
  final String deliveryOption; // delivery or pickup
  final String? deliveryAddress; // explicit delivery address
  final String? pickupAddress; // explicit pickup location (if any)
  final String? pickupMapLink; // Google Maps link for pickup location
  // Structured pickup address fields
  final String? pickupName; // pickup location name
  final String? pickupStreet; // street
  final String? pickupSitio; // sitio
  final String? pickupBarangay; // barangay
  final String? pickupCity; // city
  final String? pickupProvince; // province
  final String? pickupLandmark; // landmark
  final String? pickupInstructions; // pickup instructions
  final DateTime orderDate;
  final DateTime? deliveryDate;
  final String deliveryNotes;
  final DateTime? estimatedDeliveryStart;
  final DateTime? estimatedDeliveryEnd;
  final String farmerId;
  final String farmerName;
  final String? trackingNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalOrders; // Total orders for the customer
  final double totalSpent; // Total amount spent by customer
  // Cancellation request flags
  final bool cancellationRequested;
  final DateTime? cancellationRequestedAt;
  final String? cancellationInitiatedBy; // 'customer' | 'staff'
  final String? cancellationReason;
  final String? rejectionReason;
  // Cancellation confirmation flags
  final bool? cancellationConfirmed;
  final DateTime? cancellationConfirmedAt;
  final String? cancellationConfirmedByName;
  final String? cancellationConfirmedByRole;
  // Refund decision flags
  final bool? refundDenied;
  final String? refundDeniedReason;
  final DateTime? refundDeniedAt;
  final String? refundDeniedBy;
  final String? refundDeniedByName;
  // Rider assignment fields
  final String? riderId;
  final String? riderName;
  final String? riderPhone;
  final DateTime? assignedAt;
  final DateTime? outForDeliveryAt;
  // Pickup ready flag
  final bool? readyForPickup;
  // Pickup ready timestamp (when marked as ready to pickup)
  final DateTime? readyForPickupAt;
  // Pickup completion timestamp
  final DateTime? pickedUpAt;
  // Failed pickup timestamp
  final DateTime? failedPickupAt;
  // Failed delivery timestamp
  final DateTime? failedAt;
  // Reschedule flag
  final bool? rescheduledNextWeek;
  // Rating fields
  final bool? isRated;
  final int? orderRating;
  final String? orderComment;
  final List<String>? orderMedia;
  final DateTime? orderRatedAt;
  final int? riderRating;
  final String? riderComment;
  final DateTime? riderRatedAt;
  final String? pickupExperienceComment;
  final DateTime? pickupExperienceRatedAt;

  Order({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    this.gcashReceiptUrl,
    this.refundReceiptUrl,
    this.refundConfirmedAt,
    required this.deliveryOption,
    this.deliveryAddress,
    this.pickupAddress,
    this.pickupMapLink,
    this.pickupName,
    this.pickupStreet,
    this.pickupSitio,
    this.pickupBarangay,
    this.pickupCity,
    this.pickupProvince,
    this.pickupLandmark,
    this.pickupInstructions,
    required this.orderDate,
    this.deliveryDate,
    this.deliveryNotes = '',
    this.estimatedDeliveryStart,
    this.estimatedDeliveryEnd,
    required this.farmerId,
    required this.farmerName,
    this.trackingNumber,
    required this.createdAt,
    required this.updatedAt,
    this.totalOrders = 0,
    this.totalSpent = 0.0,
    this.cancellationRequested = false,
    this.cancellationRequestedAt,
    this.cancellationInitiatedBy,
    this.cancellationReason,
    this.rejectionReason,
    this.cancellationConfirmed,
    this.cancellationConfirmedAt,
    this.cancellationConfirmedByName,
    this.cancellationConfirmedByRole,
    this.refundDenied,
    this.refundDeniedReason,
    this.refundDeniedAt,
    this.refundDeniedBy,
    this.refundDeniedByName,
    this.riderId,
    this.riderName,
    this.riderPhone,
    this.assignedAt,
    this.outForDeliveryAt,
    this.readyForPickup,
    this.readyForPickupAt,
    this.pickedUpAt,
    this.failedPickupAt,
    this.failedAt,
    this.rescheduledNextWeek,
    this.isRated,
    this.orderRating,
    this.orderComment,
    this.orderMedia,
    this.orderRatedAt,
    this.riderRating,
    this.riderComment,
    this.riderRatedAt,
    this.pickupExperienceComment,
    this.pickupExperienceRatedAt,
  });

  // Robust date parser: handles millis (int/string) and ISO strings
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      // Try ISO first
      final iso = DateTime.tryParse(value);
      if (iso != null) return iso;
      // Try millis encoded as string
      final millis = int.tryParse(value);
      if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  factory Order.fromMap(Map<String, dynamic> map, String id) {
    // Debug: Print all map keys to see what's available
    print('🔍 Order.fromMap - Available keys: ${map.keys.toList()}');
    print('🔍 Order.fromMap - Looking for pickup fields:');
    print('  - pickupName: ${map['pickupName']}');
    print('  - pickupLandmark: ${map['pickupLandmark']}');
    print('  - pickupInstructions: ${map['pickupInstructions']}');
    print('  - pickupMapLink: ${map['pickupMapLink']}');
    
    String? _str(dynamic v) => v == null ? null : v.toString();
    String _strOrEmpty(dynamic v) => v == null ? '' : v.toString();
    T? _firstNonNull<T>(List<dynamic> keys) {
      for (final k in keys) {
        if (map.containsKey(k) && map[k] != null) {
          return map[k] as T?;
        }
      }
      return null;
    }

    final pickupInstructionsVal = _str(_firstNonNull<String>([
      'pickupInstructions', 'pickupInstruction', 'instructions'
    ]));
    final pickupLandmarkVal = _str(_firstNonNull<String>([
      'pickupLandmark', 'landmark'
    ]));
    final pickupMapLinkVal = _str(_firstNonNull<String>([
      'pickupMapLink', 'mapLink'
    ]));
    final pickupNameVal = _str(_firstNonNull<String>([
      'pickupName', 'name'
    ]));
    
    print('🔍 Order.fromMap - Parsed pickup values:');
    print('  - pickupNameVal: $pickupNameVal');
    print('  - pickupLandmarkVal: $pickupLandmarkVal');
    print('  - pickupInstructionsVal: $pickupInstructionsVal');
    print('  - pickupMapLinkVal: $pickupMapLinkVal');

    return Order(
      id: id,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      customerPhone: map['customerPhone'] ?? '',
      customerAddress: map['customerAddress'] ?? '',
      items: (map['items'] as List<dynamic>? ?? [])
          .map((item) => OrderItem.fromMap(item))
          .toList(),
      subtotal: (map['subtotal'] ?? 0.0).toDouble(),
      deliveryFee: (map['deliveryFee'] ?? 0.0).toDouble(),
      total: (map['total'] ?? 0.0).toDouble(),
      status: map['status'] ?? 'pending',
      paymentMethod: map['paymentMethod'] ?? 'cash',
      paymentStatus: map['paymentStatus'] ?? 'pending',
      gcashReceiptUrl: map['gcashReceiptUrl'],
      refundReceiptUrl: map['refundReceiptUrl'],
      refundConfirmedAt: map['refundConfirmedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['refundConfirmedAt'])
          : null,
      deliveryOption: map['deliveryOption'] ?? (map['deliveryAddress'] != null ? 'delivery' : 'pickup'),
      deliveryAddress: map['deliveryAddress'] ?? map['customerAddress'],
      pickupAddress: map['pickupAddress'],
      pickupMapLink: pickupMapLinkVal,
      pickupName: pickupNameVal,
      pickupStreet: map['pickupStreet'],
      pickupSitio: map['pickupSitio'],
      pickupBarangay: map['pickupBarangay'],
      pickupCity: map['pickupCity'],
      pickupProvince: map['pickupProvince'],
      pickupLandmark: pickupLandmarkVal,
      pickupInstructions: pickupInstructionsVal,
      orderDate: map['orderDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['orderDate'])
          : DateTime.now(),
      deliveryDate: map['deliveryDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['deliveryDate'])
          : null,
      deliveryNotes: map['deliveryNotes'] ?? map['order_notes'] ?? '',
      estimatedDeliveryStart: _parseDate(map['estimatedDeliveryStart']) ?? _parseDate(map['estimated_delivery_start']),
      estimatedDeliveryEnd: _parseDate(map['estimatedDeliveryEnd']) ?? _parseDate(map['estimated_delivery_end']),
      farmerId: map['farmerId'] ?? '',
      farmerName: map['farmerName'] ?? '',
      trackingNumber: map['trackingNumber'],
      createdAt: _parseDate(map['createdAt']) ?? _parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']) ?? _parseDate(map['updated_at']) ?? DateTime.now(),
      totalOrders: map['totalOrders'] ?? 0,
      totalSpent: (map['totalSpent'] ?? 0.0).toDouble(),
      cancellationRequested: (map['cancellationRequested'] ?? false) == true,
      cancellationRequestedAt: _parseDate(map['cancellationRequestedAt']),
      cancellationInitiatedBy: map['cancellationInitiatedBy'],
      cancellationReason: map['cancellationReason'],
      rejectionReason: map['rejectionReason'],
      cancellationConfirmed: map['cancellationConfirmed'] == true || map['cancellation_confirmed'] == true,
      cancellationConfirmedAt: _parseDate(map['cancellationConfirmedAt']) ?? _parseDate(map['cancellation_confirmed_at']),
      cancellationConfirmedByName: map['cancellationConfirmedByName'] ?? map['cancellation_confirmed_by_name'],
      cancellationConfirmedByRole: map['cancellationConfirmedByRole'] ?? map['cancellation_confirmed_by_role'],
      refundDenied: map['refundDenied'] == true || map['refund_denied'] == true,
      refundDeniedReason: map['refundDeniedReason'] ?? map['refund_denied_reason'],
      refundDeniedAt: _parseDate(map['refundDeniedAt']) ?? _parseDate(map['refund_denied_at']),
      refundDeniedBy: map['refundDeniedBy'],
      refundDeniedByName: map['refundDeniedByName'],
      riderId: map['riderId'],
      riderName: map['riderName'],
      riderPhone: map['riderPhone'],
      assignedAt: _parseDate(map['assignedAt']) ?? _parseDate(map['assigned_at']),
      outForDeliveryAt: _parseDate(map['outForDeliveryAt']) ?? _parseDate(map['out_for_delivery_at']),
      readyForPickup: map['readyForPickup'],
      readyForPickupAt: _parseDate(map['readyForPickupAt']) ?? _parseDate(map['ready_for_pickup_at']),
      pickedUpAt: _parseDate(map['pickedUpAt']) ?? _parseDate(map['picked_up_at']),
      failedPickupAt: _parseDate(map['failedPickupAt']) ?? _parseDate(map['failed_pickup_at']),
      failedAt: _parseDate(map['failedAt']) ??
          _parseDate(map['failed_at']) ??
          _parseDate(map['deliveryFailedAt']) ??
          _parseDate(map['delivery_failed_at']),
      rescheduledNextWeek: map['rescheduledNextWeek'],
      isRated: map['isRated'] == true || map['is_rated'] == true,
      orderRating: map['orderRating'] ?? map['order_rating'],
      orderComment: map['orderComment'] ?? map['order_comment'],
      orderMedia: (() {
        final media = map['orderMedia'] ?? map['order_media'];
        if (media == null) return null;
        if (media is String) {
          try {
            final List<dynamic> parsed = jsonDecode(media);
            return parsed.map((e) => e.toString()).toList();
          } catch (e) {
            return null;
          }
        }
        if (media is List) {
          return media.map((e) => e.toString()).toList();
        }
        return null;
      })(),
      orderRatedAt: map['orderRatedAt'] != null || map['order_rated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['orderRatedAt'] ?? map['order_rated_at'])
          : null,
      riderRating: map['riderRating'] ?? map['rider_rating'],
      riderComment: map['riderComment'] ?? map['rider_comment'],
      riderRatedAt: map['riderRatedAt'] != null || map['rider_rated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['riderRatedAt'] ?? map['rider_rated_at'])
          : null,
      pickupExperienceComment: map['pickupExperienceComment'] ?? map['pickup_experience_comment'],
      pickupExperienceRatedAt: map['pickupExperienceRatedAt'] != null || map['pickup_experience_rated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['pickupExperienceRatedAt'] ?? map['pickup_experience_rated_at'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerAddress': customerAddress,
      'items': items.map((item) => item.toMap()).toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'total': total,
      'status': status,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'gcashReceiptUrl': gcashReceiptUrl,
      'refundReceiptUrl': refundReceiptUrl,
      'refundConfirmedAt': refundConfirmedAt?.millisecondsSinceEpoch,
      'deliveryOption': deliveryOption,
      'deliveryAddress': deliveryAddress,
      'pickupAddress': pickupAddress,
      'pickupMapLink': pickupMapLink,
      'pickupName': pickupName,
      'pickupStreet': pickupStreet,
      'pickupSitio': pickupSitio,
      'pickupBarangay': pickupBarangay,
      'pickupCity': pickupCity,
      'pickupProvince': pickupProvince,
      'pickupLandmark': pickupLandmark,
      'pickupInstructions': pickupInstructions,
      'orderDate': orderDate.millisecondsSinceEpoch,
      'deliveryDate': deliveryDate?.millisecondsSinceEpoch,
      'deliveryNotes': deliveryNotes,
      'estimatedDeliveryStart': estimatedDeliveryStart?.millisecondsSinceEpoch,
      'estimatedDeliveryEnd': estimatedDeliveryEnd?.millisecondsSinceEpoch,
      'farmerId': farmerId,
      'farmerName': farmerName,
      'trackingNumber': trackingNumber,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'totalOrders': totalOrders,
      'totalSpent': totalSpent,
      'cancellationRequested': cancellationRequested,
      'cancellationRequestedAt': cancellationRequestedAt?.millisecondsSinceEpoch,
      'cancellationInitiatedBy': cancellationInitiatedBy,
      'cancellationReason': cancellationReason,
      'rejectionReason': rejectionReason,
      'cancellationConfirmed': cancellationConfirmed,
      'cancellationConfirmedAt': cancellationConfirmedAt?.millisecondsSinceEpoch,
      'cancellationConfirmedByName': cancellationConfirmedByName,
      'cancellationConfirmedByRole': cancellationConfirmedByRole,
      'refundDenied': refundDenied,
      'refundDeniedReason': refundDeniedReason,
      'refundDeniedAt': refundDeniedAt?.millisecondsSinceEpoch,
      'refundDeniedBy': refundDeniedBy,
      'refundDeniedByName': refundDeniedByName,
      'riderId': riderId,
      'riderName': riderName,
      'riderPhone': riderPhone,
      'assignedAt': assignedAt?.millisecondsSinceEpoch,
      'outForDeliveryAt': outForDeliveryAt?.millisecondsSinceEpoch,
      'readyForPickup': readyForPickup,
      'readyForPickupAt': readyForPickupAt?.millisecondsSinceEpoch,
      'pickedUpAt': pickedUpAt?.millisecondsSinceEpoch,
      'failedPickupAt': failedPickupAt?.millisecondsSinceEpoch,
      'failedAt': failedAt?.millisecondsSinceEpoch,
      'rescheduledNextWeek': rescheduledNextWeek,
      'isRated': isRated,
      'orderRating': orderRating,
      'orderComment': orderComment,
      'orderMedia': orderMedia != null ? jsonEncode(orderMedia) : null,
      'orderRatedAt': orderRatedAt?.millisecondsSinceEpoch,
      'riderRating': riderRating,
      'riderComment': riderComment,
      'riderRatedAt': riderRatedAt?.millisecondsSinceEpoch,
      'pickupExperienceComment': pickupExperienceComment,
      'pickupExperienceRatedAt': pickupExperienceRatedAt?.millisecondsSinceEpoch,
    };
  }

  Order copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    List<OrderItem>? items,
    double? subtotal,
    double? deliveryFee,
    double? total,
    String? status,
    String? paymentMethod,
    String? paymentStatus,
    String? gcashReceiptUrl,
    String? refundReceiptUrl,
    DateTime? refundConfirmedAt,
    String? deliveryOption,
    String? deliveryAddress,
    String? pickupAddress,
    String? pickupMapLink,
    String? pickupName,
    String? pickupStreet,
    String? pickupSitio,
    String? pickupBarangay,
    String? pickupCity,
    String? pickupProvince,
    String? pickupLandmark,
    String? pickupInstructions,
    DateTime? orderDate,
    DateTime? deliveryDate,
    String? deliveryNotes,
    String? farmerId,
    String? farmerName,
    String? trackingNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalOrders,
    double? totalSpent,
    bool? cancellationRequested,
    DateTime? cancellationRequestedAt,
    String? cancellationInitiatedBy,
    String? cancellationReason,
    String? rejectionReason,
    bool? cancellationConfirmed,
    DateTime? cancellationConfirmedAt,
    String? cancellationConfirmedByName,
    String? cancellationConfirmedByRole,
    bool? refundDenied,
    String? refundDeniedReason,
    DateTime? refundDeniedAt,
    String? refundDeniedBy,
    String? refundDeniedByName,
    String? riderId,
    String? riderName,
    String? riderPhone,
    DateTime? assignedAt,
    DateTime? outForDeliveryAt,
    bool? readyForPickup,
    DateTime? readyForPickupAt,
    DateTime? pickedUpAt,
    DateTime? failedPickupAt,
    DateTime? failedAt,
    bool? rescheduledNextWeek,
    bool? isRated,
    int? orderRating,
    String? orderComment,
    List<String>? orderMedia,
    DateTime? orderRatedAt,
    int? riderRating,
    String? riderComment,
    DateTime? riderRatedAt,
    String? pickupExperienceComment,
    DateTime? pickupExperienceRatedAt,
  }) {
    return Order(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      gcashReceiptUrl: gcashReceiptUrl ?? this.gcashReceiptUrl,
      refundReceiptUrl: refundReceiptUrl ?? this.refundReceiptUrl,
      refundConfirmedAt: refundConfirmedAt ?? this.refundConfirmedAt,
      deliveryOption: deliveryOption ?? this.deliveryOption,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupMapLink: pickupMapLink ?? this.pickupMapLink,
      pickupName: pickupName ?? this.pickupName,
      pickupStreet: pickupStreet ?? this.pickupStreet,
      pickupSitio: pickupSitio ?? this.pickupSitio,
      pickupBarangay: pickupBarangay ?? this.pickupBarangay,
      pickupCity: pickupCity ?? this.pickupCity,
      pickupProvince: pickupProvince ?? this.pickupProvince,
      pickupLandmark: pickupLandmark ?? this.pickupLandmark,
      pickupInstructions: pickupInstructions ?? this.pickupInstructions,
      orderDate: orderDate ?? this.orderDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      farmerId: farmerId ?? this.farmerId,
      farmerName: farmerName ?? this.farmerName,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalOrders: totalOrders ?? this.totalOrders,
      totalSpent: totalSpent ?? this.totalSpent,
      cancellationRequested: cancellationRequested ?? this.cancellationRequested,
      cancellationRequestedAt: cancellationRequestedAt ?? this.cancellationRequestedAt,
      cancellationInitiatedBy: cancellationInitiatedBy ?? this.cancellationInitiatedBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      cancellationConfirmed: cancellationConfirmed ?? this.cancellationConfirmed,
      cancellationConfirmedAt: cancellationConfirmedAt ?? this.cancellationConfirmedAt,
      cancellationConfirmedByName: cancellationConfirmedByName ?? this.cancellationConfirmedByName,
      cancellationConfirmedByRole: cancellationConfirmedByRole ?? this.cancellationConfirmedByRole,
      refundDenied: refundDenied ?? this.refundDenied,
      refundDeniedReason: refundDeniedReason ?? this.refundDeniedReason,
      refundDeniedAt: refundDeniedAt ?? this.refundDeniedAt,
      refundDeniedBy: refundDeniedBy ?? this.refundDeniedBy,
      refundDeniedByName: refundDeniedByName ?? this.refundDeniedByName,
      riderId: riderId ?? this.riderId,
      riderName: riderName ?? this.riderName,
      riderPhone: riderPhone ?? this.riderPhone,
      assignedAt: assignedAt ?? this.assignedAt,
      outForDeliveryAt: outForDeliveryAt ?? this.outForDeliveryAt,
      readyForPickup: readyForPickup ?? this.readyForPickup,
      readyForPickupAt: readyForPickupAt ?? this.readyForPickupAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      failedPickupAt: failedPickupAt ?? this.failedPickupAt,
      failedAt: failedAt ?? this.failedAt,
      rescheduledNextWeek: rescheduledNextWeek ?? this.rescheduledNextWeek,
      isRated: isRated ?? this.isRated,
      orderRating: orderRating ?? this.orderRating,
      orderComment: orderComment ?? this.orderComment,
      orderMedia: orderMedia ?? this.orderMedia,
      orderRatedAt: orderRatedAt ?? this.orderRatedAt,
      riderRating: riderRating ?? this.riderRating,
      riderComment: riderComment ?? this.riderComment,
      riderRatedAt: riderRatedAt ?? this.riderRatedAt,
      pickupExperienceComment: pickupExperienceComment ?? this.pickupExperienceComment,
      pickupExperienceRatedAt: pickupExperienceRatedAt ?? this.pickupExperienceRatedAt,
    );
  }

  @override
  String toString() {
    return 'Order(id: $id, customerId: $customerId, customerName: $customerName, customerPhone: $customerPhone, customerAddress: $customerAddress, items: $items, subtotal: $subtotal, deliveryFee: $deliveryFee, total: $total, status: $status, paymentMethod: $paymentMethod, paymentStatus: $paymentStatus, orderDate: $orderDate, deliveryDate: $deliveryDate, deliveryNotes: $deliveryNotes, farmerId: $farmerId, farmerName: $farmerName, trackingNumber: $trackingNumber, createdAt: $createdAt, updatedAt: $updatedAt, totalOrders: $totalOrders, totalSpent: $totalSpent, cancellationRequested: $cancellationRequested, cancellationRequestedAt: $cancellationRequestedAt, rejectionReason: $rejectionReason, refundDenied: $refundDenied, refundDeniedReason: $refundDeniedReason, refundDeniedAt: $refundDeniedAt, refundDeniedBy: $refundDeniedBy, refundDeniedByName: $refundDeniedByName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Order && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class OrderItem {
  final String productId;
  final String productName;
  final String productImage;
  final double price;
  final int quantity;
  final String unit;
  final double total;
  final String? farmerId;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.productImage,
    required this.price,
    required this.quantity,
    required this.unit,
    required this.total,
    this.farmerId,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    final price = (map['price'] ?? 0.0).toDouble();
    final quantity = map['quantity'] ?? 0;
    
    // Always calculate total from price × quantity to ensure accuracy
    // This fixes the issue where stored total might be 0 or missing
    final calculatedTotal = price * quantity;
    
    return OrderItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      productImage: map['productImage'] ?? '',
      price: price,
      quantity: quantity,
      unit: map['unit'] ?? 'kg',
      total: calculatedTotal, // Always use calculated total for accuracy
      farmerId: map['farmerId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'price': price,
      'quantity': quantity,
      'unit': unit,
      'total': total,
      'farmerId': farmerId,
    };
  }

  @override
  String toString() {
    return 'OrderItem(productId: $productId, productName: $productName, productImage: $productImage, price: $price, quantity: $quantity, unit: $unit, total: $total)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderItem && other.productId == productId;
  }

  @override
  int get hashCode => productId.hashCode;
}
