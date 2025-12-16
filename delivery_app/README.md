# Delivery App (Rider)

A lightweight Flutter app for riders to view orders assigned by staff. It reads from Firebase Realtime Database `/orders` filtered by `riderId` (the signed-in rider's UID).

## Features
- Anonymous sign-in (for quick start; replace with proper auth later)
- Orders list streamed from `/orders` where `riderId == currentUser.uid`

## Setup
1. Install Flutter and Dart.
2. From `delivery_app/` run:
```bash
flutter pub get
```
3. Firebase:
   - Add `android/app/google-services.json` for your project.
   - Enable Anonymous Auth (or adjust code for email/password sign-in).
   - Ensure Realtime Database rules allow reads on `/orders` and query by `riderId`.
4. Android:
```bash
flutter run
```

## Data contract
Orders are expected to contain fields:
- `id`, `riderId`, `customerName`, `status`, `total` or `totalAmount`, `createdAt` or `orderDate`.

## Notes
- This app listens to `/orders` with `orderByChild('riderId').equalTo(<uid>)`.
- Staff side should set `riderId` and optionally `riderName` on assignment.
