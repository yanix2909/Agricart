class Customer {
  final String uid;
  final String email;
  final String fullName;
  final String firstName;
  final String lastName;
  final String middleInitial;
  final String suffix;
  final String username;
  final int age;
  final String gender;
  final String phoneNumber;
  final String address;
  final String street;
  final String sitio;
  final String barangay;
  final String city;
  final String state;
  final String zipCode;
  final String profileImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOnline;
  final DateTime? lastSeen;
  final String status;
  final String accountStatus;
  final String verificationStatus;
  final String? rejectionReason;
  final String idType;
  final DateTime? verificationDate;
  final String? verifiedBy;
  final List<String> favoriteProducts;
  final int totalOrders;
  final double totalSpent;
  final bool hasLoggedInBefore;

  Customer({
    required this.uid,
    required this.email,
    required this.fullName,
    this.firstName = '',
    this.lastName = '',
    this.middleInitial = '',
    this.suffix = '',
    this.username = '',
    required this.age,
    required this.gender,
    required this.phoneNumber,
    required this.address,
    this.street = '',
    this.sitio = '',
    required this.barangay,
    required this.city,
    required this.state,
    required this.zipCode,
    this.profileImageUrl = '',
    required this.createdAt,
    required this.updatedAt,
    this.isOnline = false,
    this.lastSeen,
    this.status = 'active',
    this.accountStatus = 'pending',
    this.verificationStatus = 'pending',
    this.rejectionReason,
    this.idType = 'Not specified',
    this.verificationDate,
    this.verifiedBy,
    this.favoriteProducts = const [],
    this.totalOrders = 0,
    this.totalSpent = 0.0,
    this.hasLoggedInBefore = false,
  });

  factory Customer.fromMap(Map<String, dynamic> map, String uid) {
    return Customer(
      uid: uid,
      email: map['email'] ?? '',
      fullName: map['fullName'] ?? '',
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      middleInitial: map['middleInitial'] ?? '',
      suffix: map['suffix'] ?? '',
      username: map['username'] ?? '',
      age: map['age'] ?? 0,
      gender: map['gender'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      address: map['address'] ?? '',
      street: map['street'] ?? '',
      sitio: map['sitio'] ?? '',
      barangay: map['barangay'] ?? '',
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      zipCode: map['zipCode'] ?? '',
      profileImageUrl: map['profileImageUrl'] ?? '',
      createdAt: map['createdAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : DateTime.now(),
      isOnline: map['isOnline'] ?? false,
      lastSeen: map['lastSeen'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen'])
          : null,
      status: map['status'] ?? 'active',
      accountStatus: map['accountStatus'] ?? 'pending',
      verificationStatus: map['verificationStatus'] ?? 'pending',
      rejectionReason: map['rejectionReason'],
      verificationDate: map['verificationDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['verificationDate'])
          : null,
      verifiedBy: map['verifiedBy'],
      favoriteProducts: List<String>.from(map['favoriteProducts'] ?? []),
      totalOrders: map['totalOrders'] ?? 0,
      totalSpent: (map['totalSpent'] ?? 0.0).toDouble(),
      idType: map['idType'] ?? 'Not specified',
      // Read existing value or default to false for new accounts
      hasLoggedInBefore: map['hasLoggedInBefore'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'firstName': firstName,
      'lastName': lastName,
      'middleInitial': middleInitial,
      'suffix': suffix,
      'username': username,
      'age': age,
      'gender': gender,
      'phoneNumber': phoneNumber,
      'address': address,
      'street': street,
      'sitio': sitio,
      'barangay': barangay,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'profileImageUrl': profileImageUrl,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'status': status,
      'accountStatus': accountStatus,
      'verificationStatus': verificationStatus,
      'rejectionReason': rejectionReason,
      'verificationDate': verificationDate?.millisecondsSinceEpoch,
      'verifiedBy': verifiedBy,
      'favoriteProducts': favoriteProducts,
      'totalOrders': totalOrders,
      'totalSpent': totalSpent,
      'idType': idType,
      'hasLoggedInBefore': hasLoggedInBefore,
    };
  }

  Customer copyWith({
    String? uid,
    String? email,
    String? fullName,
    String? firstName,
    String? lastName,
    String? middleInitial,
    String? suffix,
    String? username,
    int? age,
    String? gender,
    String? phoneNumber,
    String? address,
    String? street,
    String? sitio,
    String? barangay,
    String? city,
    String? state,
    String? zipCode,
    String? profileImageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isOnline,
    DateTime? lastSeen,
    String? status,
    String? accountStatus,
    String? verificationStatus,
    String? rejectionReason,
    DateTime? verificationDate,
    String? verifiedBy,
    List<String>? favoriteProducts,
    int? totalOrders,
    double? totalSpent,
    String? idType,
    bool? hasLoggedInBefore,
  }) {
    return Customer(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleInitial: middleInitial ?? this.middleInitial,
      suffix: suffix ?? this.suffix,
      username: username ?? this.username,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      street: street ?? this.street,
      sitio: sitio ?? this.sitio,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      accountStatus: accountStatus ?? this.accountStatus,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      verificationDate: verificationDate ?? this.verificationDate,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      favoriteProducts: favoriteProducts ?? this.favoriteProducts,
      totalOrders: totalOrders ?? this.totalOrders,
      totalSpent: totalSpent ?? this.totalSpent,
      idType: idType ?? this.idType,
      hasLoggedInBefore: hasLoggedInBefore ?? this.hasLoggedInBefore,
    );
  }

  @override
  String toString() {
    return 'Customer(uid: $uid, email: $email, fullName: $fullName, firstName: $firstName, lastName: $lastName, middleInitial: $middleInitial, suffix: $suffix, username: $username, age: $age, gender: $gender, phoneNumber: $phoneNumber, address: $address, street: $street, sitio: $sitio, barangay: $barangay, city: $city, state: $state, zipCode: $zipCode, profileImageUrl: $profileImageUrl, createdAt: $createdAt, updatedAt: $updatedAt, isOnline: $isOnline, lastSeen: $lastSeen, status: $status, accountStatus: $accountStatus, verificationStatus: $verificationStatus, rejectionReason: $rejectionReason, verificationDate: $verificationDate, verifiedBy: $verifiedBy, favoriteProducts: $favoriteProducts, totalOrders: $totalOrders, totalSpent: $totalSpent, idType: $idType, hasLoggedInBefore: $hasLoggedInBefore)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Customer && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
