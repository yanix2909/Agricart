# Supabase Setup Instructions

This document provides instructions for setting up Supabase for customer ID image uploads.

## Overview

The customer registration now uploads ID photos to Supabase Storage instead of storing them as base64 in Firebase. All form details are still saved to Firebase, but the image URLs (stored in `idFrontPhoto` and `idBackPhoto` columns) point to Supabase Storage.

## Setup Steps

### 1. Create Supabase Project (if not already created)

1. Go to [Supabase](https://supabase.com/)
2. Create a new project or use an existing one
3. Note down your project URL and anon key from: **Settings > API**

### 2. Create Storage Bucket

1. In Supabase Dashboard, go to **Storage**
2. Click **New Bucket**
3. Bucket name: `customerid_image`
4. Make it **Public** (uncheck "Private bucket")
5. Click **Create bucket**

### 3. Configure Supabase Credentials

1. Open `customer_app/lib/services/supabase_service.dart`
2. Replace `YOUR_SUPABASE_URL` with your actual Supabase project URL
3. Replace `YOUR_SUPABASE_ANON_KEY` with your actual Supabase anon key

Example:
```dart
static const String _supabaseUrl = 'https://your-project-id.supabase.co';
static const String _supabaseAnonKey = 'your-anon-key-here';
```

### 4. Set Up Storage Policies

1. In Supabase Dashboard, go to **SQL Editor**
2. Copy and paste the contents of `customer_app/supabase_policies.sql`
3. Run the SQL script to create the policies

**OR** set up policies manually:

1. Go to **Storage > Policies**
2. Select the `customerid_image` bucket
3. Create policies for:
   - **SELECT** (view/download): Allow public access
   - **INSERT** (upload): Allow public access
   - **UPDATE** (update): Allow public access
   - **DELETE** (delete): Allow public access

### 5. Install Dependencies

Run the following command in the `customer_app` directory:

```bash
flutter pub get
```

## How It Works

1. When a customer registers:
   - Form data is saved to Firebase `customers` table
   - ID photos (front and back) are uploaded to Supabase Storage bucket `customerid_image`
   - The Supabase public URLs are stored in Firebase columns:
     - `idFrontPhoto`: URL to the front ID photo in Supabase
     - `idBackPhoto`: URL to the back ID photo in Supabase

2. File naming convention:
   - Front: `{customerId}/front_{timestamp}.{extension}`
   - Back: `{customerId}/back_{timestamp}.{extension}`

## Firebase Customers Table Structure

The `customers` table in Firebase should have these columns:
- `idFrontPhoto` (String): Supabase Storage URL for front ID photo
- `idBackPhoto` (String): Supabase Storage URL for back ID photo
- All other customer data (username, email, name, etc.)

## Testing

After setup, test the registration flow:

1. Register a new customer account
2. Upload ID photos
3. Check Supabase Storage to verify images are uploaded
4. Check Firebase to verify URLs are stored correctly

## Troubleshooting

### "Supabase credentials not configured" error
- Make sure you've updated `_supabaseUrl` and `_supabaseAnonKey` in `supabase_service.dart`

### "Failed to upload image to Supabase" error
- Check that the bucket `customerid_image` exists and is public
- Verify the storage policies are set up correctly
- Check your Supabase project status

### Images not accessible
- Ensure the bucket is set to **Public** in Supabase Dashboard
- Verify the SELECT policy allows public access

## Security Note

The current setup allows public (unauthenticated) access to the bucket. This is intentional for customer registration, but you may want to add authentication checks for production use depending on your security requirements.

