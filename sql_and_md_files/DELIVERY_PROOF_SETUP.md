# Delivery Proof Storage Setup Guide

## Overview
This guide explains how to set up the `delivery_proof` storage bucket in Supabase for uploading proof of delivery images from the delivery app.

## Steps to Complete

### 1. Create Storage Bucket (via Supabase Dashboard)

1. Go to your Supabase Dashboard: https://supabase.com/dashboard
2. Select your project
3. Navigate to **Storage** in the left sidebar
4. Click **"New bucket"** button
5. Configure the bucket:
   - **Name**: `delivery_proof` (must be exactly this name)
   - **Public bucket**: ✅ **Yes** (check this box - required for public access)
   - **File size limit**: 50MB (or adjust as needed)
   - **Allowed MIME types**: 
     - `image/jpeg`
     - `image/png`
     - `image/webp`
6. Click **"Create bucket"**

### 2. Create Storage Policies (via SQL Editor)

1. In Supabase Dashboard, go to **SQL Editor**
2. Open the file `create_delivery_proof_bucket.sql`
3. Copy and paste the SQL commands into the SQL Editor
4. Click **"Run"** to execute

This will create the following policies:
- **Public can view delivery proof images** (SELECT)
- **Public can upload delivery proof images** (INSERT)
- **Public can update delivery proof images** (UPDATE)
- **Public can delete delivery proof images** (DELETE)

### 3. Verify Setup

After running the SQL, verify the policies were created:

```sql
SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'storage' 
AND tablename = 'objects'
AND policyname LIKE '%delivery_proof%'
ORDER BY policyname;
```

You should see 4 policies listed.

## How It Works

### File Naming Convention
Images are uploaded with the following naming pattern:
```
{orderId}_{timestamp}_{index}.{extension}
```

Example: `order123_1234567890_0.jpg`

### Upload Process
1. Rider selects 1-2 images from camera or gallery
2. Images are uploaded to `delivery_proof` bucket
3. Public URLs are stored in `delivery_orders.delivery_proof` (JSONB array)
4. Images are displayed in the order details dialog

### Code Implementation
- **Upload function**: `SupabaseService.uploadDeliveryProofImage()`
- **Storage bucket**: `delivery_proof`
- **Database field**: `delivery_orders.delivery_proof` (JSONB array of URLs)

## Troubleshooting

### Images not uploading
1. Verify bucket exists: Check Storage > Buckets in Dashboard
2. Verify bucket is public: Bucket settings should show "Public bucket: Yes"
3. Check policies: Run the verification SQL query above
4. Check console logs: Look for upload errors in the delivery app

### Permission errors
- Ensure all 4 policies are created
- Verify policies allow `public` role (not authenticated)
- Check bucket is set to public in Dashboard

### Images not displaying
- Verify URLs are stored correctly in database
- Check URLs are accessible (open in browser)
- Verify bucket is public
- Check network connectivity

## Security Notes

⚠️ **Important**: These policies allow **public (unauthenticated)** access to the bucket. This means:
- Anyone with the URL can view images
- Anyone can upload/delete images (if they know the bucket name)

For production, consider:
- Adding authentication requirements
- Implementing file size limits
- Adding content validation
- Using signed URLs instead of public URLs

## Testing

1. Assign an order to a rider in the staff dashboard
2. Open the delivery app and log in as that rider
3. Open the assigned order
4. Click "Mark as Delivered"
5. Select 1-2 images
6. Click "Mark as Delivered"
7. Verify images upload successfully
8. Check order details to see uploaded images

