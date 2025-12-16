# Payment Method Selection for Delivery Orders

## Overview
This feature adds payment method selection (Cash or GCash) to the delivery app when marking orders as delivered. Riders can now:
- Select whether the order was paid by Cash or GCash
- For Cash: Enter cash received amount (with change calculation)
- For GCash: Display QR code and upload payment proof photo

## Implementation Summary

### 1. Delivery App Changes (`delivery_app/lib/orders_screen.dart`)
- Added payment method selection buttons (Cash/GCash) in the delivery proof dialog
- Cash selection shows cash received input with change calculation
- GCash selection shows:
  - GCash QR code image (`rodel_gcash_new.jpg`)
  - Button to upload proof of payment photo
- Updated `_markAsDelivered` function to handle both payment methods and upload payment proof

### 2. Supabase Service (`delivery_app/lib/services/supabase_service.dart`)
- Added `uploadPaymentProofImage()` function to upload payment proof to `delivery_proof_payment` bucket

### 3. Web Dashboard Changes (`webdashboards/staff.js`)
- Updated order fetching to include `payment_proof` field
- Added payment proof display in order details (both list view and modal)
- Payment proof displays for GCash orders with click-to-enlarge functionality

### 4. Database Changes
- Added `payment_proof` column to `delivery_orders` table
- Added `payment_proof` column to `orders` table (for consistency)

### 5. Storage Bucket
- Created `delivery_proof_payment` bucket for storing payment proof images
- Public access policies for view, insert, update, and delete

## SQL Commands to Run

### Step 1: Create Storage Bucket (via Supabase Dashboard)
1. Go to Supabase Dashboard > Storage
2. Click "New bucket"
3. Configure:
   - **Name**: `delivery_proof_payment`
   - **Public bucket**: ✅ Yes (checked)
   - **File size limit**: 50MB
   - **Allowed MIME types**: `image/jpeg`, `image/png`, `image/webp`
4. Click "Create bucket"

### Step 2: Create Storage Policies
Run the SQL file: `sql_and_md_files/create_delivery_proof_payment_bucket.sql`

This creates 4 policies:
- Allow public view of delivery proof payment images
- Allow public insert of delivery proof payment images
- Allow public update of delivery proof payment images
- Allow public delete of delivery proof payment images

### Step 3: Add Database Columns
Run the SQL file: `sql_and_md_files/add_payment_proof_to_delivery_orders.sql`

This adds:
- `payment_proof` column to `delivery_orders` table
- `payment_proof` column to `orders` table

## How It Works

### Delivery App Flow
1. Rider opens order and clicks "Mark as Delivered"
2. Rider selects delivery proof images (1-2 images)
3. Rider selects payment method:
   - **Cash**: Enter cash received amount, see change calculation
   - **GCash**: See GCash QR code, upload payment proof photo
4. Rider confirms delivery
5. System uploads:
   - Delivery proof images to `delivery_proof` bucket
   - Payment proof image (if GCash) to `delivery_proof_payment` bucket
6. System updates database with:
   - Delivery proof URLs
   - Payment method
   - Payment proof URL (if GCash)
   - Cash received and change (if Cash)

### Web Dashboard Display
- Payment proof displays automatically for GCash orders
- Click on image to view full size
- Shows in both order list view and order details modal

## File Structure

```
delivery_app/
  lib/
    orders_screen.dart          # Delivery proof dialog with payment method selection
    services/
      supabase_service.dart     # Payment proof upload function

webdashboards/
  staff.js                      # Payment proof display in web dashboard

sql_and_md_files/
  create_delivery_proof_payment_bucket.sql    # Storage bucket policies
  add_payment_proof_to_delivery_orders.sql    # Database columns
```

## Testing Checklist

- [ ] Storage bucket `delivery_proof_payment` created and public
- [ ] Storage policies created (4 policies)
- [ ] Database columns added (`payment_proof` in both tables)
- [ ] Delivery app shows payment method selection buttons
- [ ] Cash selection shows cash input and change calculation
- [ ] GCash selection shows QR code and upload button
- [ ] Payment proof uploads successfully for GCash
- [ ] Payment proof displays in web dashboard for GCash orders
- [ ] Cash orders show cash received and change in web dashboard

## Notes

- Payment proof is optional for GCash (delivery can proceed even if upload fails)
- GCash QR code image must exist at `delivery_app/assets/images/rodel_gcash_new.jpg`
- Payment proof images are stored with naming pattern: `{orderId}_{timestamp}_payment.{extension}`
- All images are publicly accessible via Supabase Storage URLs

