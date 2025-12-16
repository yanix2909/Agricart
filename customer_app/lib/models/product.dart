class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String farmerId;
  final String farmerName;
  final String imageUrl;
  final List<String> imageUrls;
  final String videoUrl;
  final List<String> videoUrls;
  final int availableQuantity;
  final String unit; // kg, pieces, etc.
  final DateTime harvestDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isAvailable;
  final double rating;
  final int reviewCount;
  final List<String> tags;
  final String location;
  final int? soldQuantity;
  final int? currentReserved;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.farmerId,
    required this.farmerName,
    required this.imageUrl,
    this.imageUrls = const [],
    this.videoUrl = '',
    this.videoUrls = const [],
    required this.availableQuantity,
    required this.unit,
    required this.harvestDate,
    required this.createdAt,
    required this.updatedAt,
    this.isAvailable = true,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.tags = const [],
    this.location = '',
    this.soldQuantity,
    this.currentReserved,
  });

  factory Product.fromMap(Map<String, dynamic> map, String id) {
    return Product(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      category: map['category'] ?? '',
      farmerId: map['farmerId'] ?? '',
      farmerName: map['farmerName'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      imageUrls: _parseImageUrls(map),
      availableQuantity: _parseInt(map['availableQuantity']) ?? _parseInt(map['quantity']) ?? 0,
      unit: map['unit'] ?? 'kg',
      harvestDate: map['harvestDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(_parseInt(map['harvestDate']) ?? DateTime.now().millisecondsSinceEpoch)
          : DateTime.now(),
      createdAt: map['createdAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(_parseInt(map['createdAt']) ?? DateTime.now().millisecondsSinceEpoch)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(_parseInt(map['updatedAt']) ?? DateTime.now().millisecondsSinceEpoch)
          : DateTime.now(),
      isAvailable: map['isAvailable'] ?? 
                   (map['status'] == 'active') ?? 
                   true,
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: _parseInt(map['reviewCount']) ?? 0,
      tags: List<String>.from(map['tags'] ?? []),
      location: map['location'] ?? '',
      soldQuantity: _parseInt(map['soldQuantity']),
      currentReserved: _parseInt(map['currentReserved']),
      videoUrl: map['videoUrl'] ?? map['video_url'] ?? '',
      videoUrls: _parseVideoUrls(map),
    );
  }

  // Helper method to safely parse integers from various types
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is double) return value.toInt();
    return null;
  }

  // Helper method to parse image URLs from various formats
  static List<String> _parseImageUrls(Map<String, dynamic> map) {
    return _parseUrlCandidates(map, [
      'imageUrls',
      'images',
      'photos',
      'imageUrl',
      'image_url',
    ]);
  }

  static List<String> _parseVideoUrls(Map<String, dynamic> map) {
    return _parseUrlCandidates(map, [
      'videoUrls',
      'video_urls',
      'videos',
      'videoClips',
      'video_url',
      'videoUrl',
    ]);
  }

  static List<String> _parseUrlCandidates(Map<String, dynamic> map, List<String> keys) {
    final List<String> urls = [];
    for (final key in keys) {
      final candidate = map[key];
      if (candidate == null) continue;

      if (candidate is List) {
        for (final item in candidate) {
          if (item is String && item.isNotEmpty) {
            urls.add(item);
          }
        }
      } else if (candidate is Map) {
        for (final value in candidate.values) {
          if (value is String && value.isNotEmpty) {
            urls.add(value);
          }
        }
      } else if (candidate is String && candidate.isNotEmpty) {
        urls.add(candidate);
      }
    }
    return urls.toSet().toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'farmerId': farmerId,
      'farmerName': farmerName,
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
      'videoUrl': videoUrl,
      'videoUrls': videoUrls,
      'availableQuantity': availableQuantity,
      'unit': unit,
      'harvestDate': harvestDate.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'isAvailable': isAvailable,
      'rating': rating,
      'reviewCount': reviewCount,
      'tags': tags,
      'location': location,
      'soldQuantity': soldQuantity,
      'currentReserved': currentReserved,
    };
  }

  Product copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? category,
    String? farmerId,
    String? farmerName,
    String? imageUrl,
    List<String>? imageUrls,
    int? availableQuantity,
    String? unit,
    DateTime? harvestDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isAvailable,
    double? rating,
    int? reviewCount,
    List<String>? tags,
    String? location,
    int? soldQuantity,
    int? currentReserved,
      String? videoUrl,
      List<String>? videoUrls,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      farmerId: farmerId ?? this.farmerId,
      farmerName: farmerName ?? this.farmerName,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrl: videoUrl ?? this.videoUrl,
      videoUrls: videoUrls ?? this.videoUrls,
      availableQuantity: availableQuantity ?? this.availableQuantity,
      unit: unit ?? this.unit,
      harvestDate: harvestDate ?? this.harvestDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isAvailable: isAvailable ?? this.isAvailable,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      tags: tags ?? this.tags,
      location: location ?? this.location,
      soldQuantity: soldQuantity ?? this.soldQuantity,
      currentReserved: currentReserved ?? this.currentReserved,
    );
  }

  @override
  String toString() {
    return 'Product(id: $id, name: $name, description: $description, price: $price, category: $category, farmerId: $farmerId, farmerName: $farmerName, imageUrl: $imageUrl, videoUrl: $videoUrl, availableQuantity: $availableQuantity, unit: $unit, harvestDate: $harvestDate, createdAt: $createdAt, updatedAt: $updatedAt, isAvailable: $isAvailable, rating: $rating, reviewCount: $reviewCount, tags: $tags, location: $location, soldQuantity: $soldQuantity, currentReserved: $currentReserved)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Product && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
