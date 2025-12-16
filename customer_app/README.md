# AgriCart Customer App

A Flutter mobile application for customers to browse and order fresh agricultural products directly from farmers.

## Features

- **User Authentication**: Secure login and registration
- **Product Browsing**: Browse available products with images and details
- **Order Management**: Place orders and track their status
- **Real-time Updates**: Get notifications for order updates
- **Profile Management**: Update personal information and preferences
- **Dark/Light Theme**: Toggle between themes
- **Push Notifications**: Receive order updates and promotions

## Technical Requirements

### Flutter & Dart
- **Flutter SDK**: 3.10.0 or higher
- **Dart**: 3.1.0 or higher
- **Android**: API level 23 (Android 6.0) or higher

### Dependencies
- **Firebase Core**: ^4.0.0
- **Firebase Auth**: ^6.0.1
- **Firebase Database**: ^12.0.0
- **Firebase Storage**: ^13.0.0
- **Firebase Messaging**: ^16.0.0
- **Provider**: ^6.1.1 (State Management)
- **Image Picker**: ^1.0.2
- **Cached Network Image**: ^3.2.3
- **Syncfusion Charts**: ^30.2.4
- **Google Fonts**: ^6.2.1

## Setup Instructions

### 1. Prerequisites
- Install Flutter SDK (3.10.0+)
- Install Android Studio
- Install Java Development Kit (JDK) 17
- Set up Android SDK (API 23+)

### 2. Firebase Setup
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use existing "agricart-53501"
3. Add Android app with package name: `com.agricart.customer`
4. Download `google-services.json` and place it in `android/app/`
5. Enable Authentication, Realtime Database, Storage, and Cloud Messaging

### 3. Project Setup
```bash
# Navigate to customer_app directory
cd customer_app

# Get dependencies
flutter pub get

# Run the app
flutter run
```

### 4. Firebase Configuration Steps

#### Step 1: Authentication
1. Go to Firebase Console > Authentication
2. Enable Email/Password authentication
3. Add test users or enable sign-up

#### Step 2: Realtime Database
1. Go to Firebase Console > Realtime Database
2. Create database in test mode
3. Set up security rules for customers:
```json
{
  "rules": {
    "customers": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    },
    "products": {
      ".read": "auth != null",
      ".write": "auth != null && root.child('farmers').child(auth.uid).exists()"
    },
    "orders": {
      "$orderId": {
        ".read": "auth != null && (data.child('customerId').val() === auth.uid || root.child('farmers').child(data.child('farmerId').val()).exists())",
        ".write": "auth != null && (data.child('customerId').val() === auth.uid || root.child('farmers').child(data.child('farmerId').val()).exists())"
      }
    }
  }
}
```

#### Step 3: Storage
1. Go to Firebase Console > Storage
2. Create storage bucket
3. Set up security rules for images:
```rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

#### Step 4: Cloud Messaging
1. Go to Firebase Console > Cloud Messaging
2. Create notification channel: `agricart_customer_channel`
3. Set up server key for push notifications

### 5. Build for Production
```bash
# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle --release
```

## Project Structure

```
customer_app/
├── lib/
│   ├── models/          # Data models
│   ├── providers/       # State management
│   ├── screens/         # UI screens
│   ├── services/        # Firebase services
│   ├── utils/           # Utilities and themes
│   ├── widgets/         # Reusable widgets
│   └── main.dart        # App entry point
├── android/             # Android configuration
└── pubspec.yaml         # Dependencies
```

## Troubleshooting

### Common Issues
1. **Firebase initialization failed**: Check `google-services.json` placement
2. **Permission denied**: Ensure proper Firebase security rules
3. **Build errors**: Verify Flutter and Dart versions
4. **Network issues**: Check internet connectivity and Firebase project settings

### Support
For issues related to:
- Flutter setup: Check [Flutter documentation](https://flutter.dev/docs)
- Firebase setup: Check [Firebase documentation](https://firebase.google.com/docs)
- Project-specific issues: Review Firebase console logs

## License

This project is part of the AgriCart ecosystem and follows the same licensing terms.
