# Complete Order Rating System - Implementation Guide

## 🎯 Overview
This document describes the complete implementation of the order rating system with differentiated experiences for **delivery orders** and **pickup orders**.

---

## ✨ Features Implemented

### 1. Customer App - Rating Interface

#### 🚚 **DELIVERY ORDERS** (status: `delivered`)
When customers rate delivery orders, they provide feedback on:

**Order Feedback:**
- ⭐ Overall Rating (1-5 stars)
- 💬 Comment (optional)
- 📸 Upload Media: Up to 5 images/videos, max 50 MB total

**Delivery Rider Feedback:**
- ⭐ Overall Rating (1-5 stars)
- 💬 Comment (optional)

#### 🏪 **PICKUP ORDERS** (status: `picked_up`)
When customers rate pickup orders, they provide feedback on:

**Order Feedback:**
- ⭐ Overall Rating (1-5 stars)
- 💬 Comment (optional)
- 📸 Upload Media: Up to 5 images/videos, max 50 MB total

**Pickup Experience:**
- 💬 Comment (optional) - How was the pickup experience?

> **Key Difference:** Pickup orders do NOT rate delivery riders. Instead, they provide feedback about the pickup experience at the location.

---

### 2. Database Structure (Supabase)

#### New Columns Added to `orders` Table:

```sql
-- Order Feedback (Common to both delivery and pickup)
order_rating              INTEGER   -- Rating 1-5 stars
order_comment             TEXT      -- Customer comment about order
order_media               JSONB     -- Array of media URLs (images/videos)
order_rated_at            BIGINT    -- Unix timestamp (milliseconds)

-- Delivery Rider Feedback (DELIVERY ORDERS ONLY)
rider_rating              INTEGER   -- Rating 1-5 stars
rider_comment             TEXT      -- Comment about delivery rider
rider_rated_at            BIGINT    -- Unix timestamp (milliseconds)

-- Pickup Experience (PICKUP ORDERS ONLY)
pickup_experience_comment TEXT      -- Comment about pickup experience
pickup_experience_rated_at BIGINT   -- Unix timestamp (milliseconds)

-- Status Flag
is_rated                  BOOLEAN   -- Whether order has been rated
```

#### Storage Bucket: `rated_media`

- **Purpose**: Store customer-uploaded images and videos
- **Public Access**: Yes (public viewing enabled)
- **File Size Limit**: 50 MB
- **Allowed Types**: Images (JPEG, PNG, GIF, WEBP), Videos (MP4, MOV, WEBM)

---

### 3. Web Dashboard - Rating Display

#### 📊 **Rating Status Indicator**
Visible in the "Order Summary" section of every order:

- ✅ **"Rated"** (Green badge with star icon) - Order has been rated by customer
- ⚠️ **"Not Rated"** (Amber badge with star icon) - Delivered/picked up order awaiting rating
- ⬜ **"N/A"** (Gray badge) - Order not eligible for rating yet (pending, confirmed, etc.)

#### 📝 **Customer Feedback Section**
When order is rated (`is_rated = true`), shows:

**For All Orders:**
- Order rating with star display
- Order comment
- Media gallery (clickable images, video player)

**For Delivery Orders:**
- Rider rating with star display
- Rider comment

**For Pickup Orders:**
- Pickup experience comment

---

## 🔧 Implementation Details

### Customer App Files Modified

#### 1. `order_rating_screen.dart`
**Changes:**
- Added `_isPickupOrder` getter to detect order type
- Added `_pickupExperienceController` for pickup feedback
- Modified submit logic to send different data based on order type
- UI now shows either "Delivery Rider Feedback" OR "Pickup Experience"

```dart
bool get _isPickupOrder => widget.order.deliveryOption.toLowerCase() == 'pickup';
```

#### 2. `customer_provider.dart` - `submitOrderRating` method
**Changes:**
- Made `riderRating` and `riderComment` optional (`int?` and `String?`)
- Added `pickupExperienceComment` parameter
- Conditionally includes rider feedback (delivery) or pickup experience (pickup)

```dart
Future<bool> submitOrderRating({
  required String orderId,
  required int orderRating,
  required String orderComment,
  int? riderRating,              // Optional - for delivery orders
  String? riderComment,          // Optional - for delivery orders
  String? pickupExperienceComment, // Optional - for pickup orders
  List<XFile>? mediaFiles,
})
```

---

### Web Dashboard Files Modified

#### 1. `staff.js` - Order Details Display
**Changes Added:**

**Rating Status Indicator** (line ~13263):
```javascript
<span style="...">${(() => {
  const isRated = order.isRated || order.is_rated || false;
  if (isRated) {
    return '✅ Rated';
  } else if (status === 'delivered' || status === 'picked_up') {
    return '⚠️ Not Rated';
  } else {
    return 'N/A';
  }
})()}</span>
```

**Pickup Experience Display** (line ~13472):
```javascript
${(() => {
  const pickupExperience = order.pickupExperienceComment || 
                           order.pickup_experience_comment || '';
  const isPickupOrder = (order.deliveryOption || '').toLowerCase() === 'pickup';
  if (pickupExperience && isPickupOrder) {
    return `<div>Pickup Experience: ${pickupExperience}</div>`;
  }
  return '';
})()}
```

---

### SQL Setup File

#### `setup_order_rating_system.sql`
**What it does:**
1. ✅ Adds all rating columns to `orders` table
2. ✅ Creates `rated_media` storage bucket
3. ✅ Sets up public access policies (view, insert, update, delete)
4. ✅ Creates indexes for performance
5. ✅ Adds constraints (ratings must be 1-5)

**Run this SQL in Supabase SQL Editor to set up the system.**

---

## 📋 Data Flow

### Delivery Order Rating Flow
```
Customer rates delivered order
  ↓
Fills: Order Rating, Order Comment, Media
Fills: Rider Rating, Rider Comment
  ↓
Submit → CustomerProvider.submitOrderRating()
  ↓
Upload media to rated_media bucket
  ↓
Update orders table:
  - order_rating, order_comment, order_media
  - rider_rating, rider_comment, rider_rated_at
  - is_rated = true
  ↓
Web dashboard shows:
  - "Rated" indicator
  - Order feedback
  - Rider feedback
```

### Pickup Order Rating Flow
```
Customer rates picked-up order
  ↓
Fills: Order Rating, Order Comment, Media
Fills: Pickup Experience Comment
  ↓
Submit → CustomerProvider.submitOrderRating()
  ↓
Upload media to rated_media bucket
  ↓
Update orders table:
  - order_rating, order_comment, order_media
  - pickup_experience_comment, pickup_experience_rated_at
  - is_rated = true
  ↓
Web dashboard shows:
  - "Rated" indicator
  - Order feedback
  - Pickup experience
```

---

## 🎨 Visual Design

### Customer App
- **Card-based UI** with elevation
- **Color Coding:**
  - Green (Order Feedback): `Colors.green[700]`
  - Blue (Rider Feedback): `Colors.blue[700]`
  - Orange (Pickup Experience): `Colors.orange[700]`
- **Star Slider**: Interactive 1-5 rating with visual stars
- **Media Gallery**: Grid display with image/video icons

### Web Dashboard
- **Rating Status Badge:**
  - ✅ Rated: Green background (`#dcfce7`), green text (`#166534`)
  - ⚠️ Not Rated: Amber background (`#fef3c7`), amber text (`#92400e`)
  - N/A: Gray background (`#f3f4f6`), gray text (`#6b7280`)
- **Feedback Section**: Orange/amber themed card with icons
- **Star Display**: Gold stars (⭐) for rating visualization
- **Media Gallery**: Clickable thumbnails, video players

---

## 🧪 Testing Checklist

### Customer App - Delivery Orders
- [ ] Order with status `delivered` appears in "To Rate" tab
- [ ] "Rate Order!" button shows for unrated delivery orders
- [ ] Rating screen shows "Delivery Rider Feedback" section
- [ ] Can rate order (1-5 stars) and add comment
- [ ] Can rate rider (1-5 stars) and add comment
- [ ] Can upload up to 5 media files (50 MB max)
- [ ] Successfully submits to Supabase
- [ ] Order marked as rated (`is_rated = true`)
- [ ] "Rate Order!" button disappears after rating

### Customer App - Pickup Orders
- [ ] Order with status `picked_up` appears in "To Rate" tab
- [ ] "Rate Order!" button shows for unrated pickup orders
- [ ] Rating screen shows "Pickup Experience" section (NOT rider feedback)
- [ ] Can rate order (1-5 stars) and add comment
- [ ] Can add pickup experience comment
- [ ] Can upload up to 5 media files (50 MB max)
- [ ] Successfully submits to Supabase
- [ ] `pickup_experience_comment` is saved
- [ ] Order marked as rated (`is_rated = true`)

### Web Dashboard
- [ ] "Rated" indicator shows for rated orders (green badge)
- [ ] "Not Rated" indicator shows for delivered/picked_up unrated orders (amber badge)
- [ ] "N/A" shows for orders not eligible for rating (gray badge)
- [ ] Order feedback displays with stars and comment
- [ ] Rider feedback displays for delivery orders
- [ ] Pickup experience displays for pickup orders
- [ ] Media gallery shows images and videos correctly
- [ ] Clicking images enlarges them
- [ ] Video player works correctly

### Database
- [ ] All rating columns exist in `orders` table
- [ ] `rated_media` bucket exists with 50 MB limit
- [ ] Public policies allow view/insert/update/delete
- [ ] Constraints enforce 1-5 star ratings
- [ ] Indexes created successfully

---

## 📊 Database Queries

### Get All Rated Orders
```sql
SELECT * FROM orders 
WHERE is_rated = true 
ORDER BY order_rated_at DESC;
```

### Get Unrated Delivered Orders
```sql
SELECT * FROM orders 
WHERE (status = 'delivered' OR status = 'picked_up')
  AND is_rated = false
ORDER BY created_at DESC;
```

### Get Average Rider Ratings
```sql
SELECT 
  rider_id,
  rider_name,
  COUNT(*) as total_ratings,
  AVG(rider_rating) as avg_rating
FROM orders
WHERE rider_rating IS NOT NULL
GROUP BY rider_id, rider_name
ORDER BY avg_rating DESC;
```

### Get Pickup Orders with Experience Feedback
```sql
SELECT 
  id,
  customer_name,
  order_rating,
  pickup_experience_comment,
  created_at
FROM orders
WHERE delivery_option = 'pickup'
  AND pickup_experience_comment IS NOT NULL
ORDER BY order_rated_at DESC;
```

---

## 🔐 Security Notes

1. **Public Storage Access**: The `rated_media` bucket allows public access for ease of use. Files are accessible via public URLs.
2. **File Size Limits**: Enforced at bucket level (50 MB) and client-side validation.
3. **MIME Type Restrictions**: Only images and videos allowed, prevents malicious uploads.
4. **Rating Constraints**: Database constraints ensure ratings are between 1-5.
5. **No User Authentication Required**: Current implementation allows public access for simplicity. Consider adding RLS policies if authentication is required in future.

---

## 📦 Files Summary

### Customer App
- `lib/screens/orders/order_rating_screen.dart` - Rating UI
- `lib/screens/orders/order_phases_screen.dart` - "To Rate" tab
- `lib/providers/customer_provider.dart` - Rating submission logic
- `lib/models/order.dart` - Order model (unchanged)

### Web Dashboard
- `webdashboards/staff.js` - Order display with ratings
- `webdashboards/staff-dashboard.html` - Dashboard UI

### SQL Setup
- `webdashboards/setup_order_rating_system.sql` - Complete database setup

### Documentation
- `ORDER_RATING_SYSTEM_IMPLEMENTATION.md` - Original implementation guide
- `ORDER_RATING_SYSTEM_COMPLETE.md` - This file (updated with pickup/delivery differentiation)

---

## 🚀 Deployment Steps

1. **Run SQL Script**
   ```
   Open Supabase SQL Editor
   → Copy contents of setup_order_rating_system.sql
   → Execute script
   → Verify all columns and bucket created
   ```

2. **Update Customer App**
   ```
   No changes needed - Already implemented!
   Files already updated:
   - order_rating_screen.dart
   - customer_provider.dart
   ```

3. **Update Web Dashboard**
   ```
   No changes needed - Already implemented!
   File already updated:
   - staff.js (rating indicator and pickup experience display)
   ```

4. **Test End-to-End**
   ```
   1. Create test order (delivery)
   2. Mark as delivered
   3. Rate order in customer app
   4. Verify rating shows in web dashboard
   
   5. Create test order (pickup)
   6. Mark as picked_up
   7. Rate order in customer app (should show pickup experience)
   8. Verify rating shows in web dashboard
   ```

---

## 🎉 Summary

### What's Different Between Delivery and Pickup?

| Feature | Delivery Orders | Pickup Orders |
|---------|----------------|---------------|
| Order Rating | ✅ Yes (1-5 stars) | ✅ Yes (1-5 stars) |
| Order Comment | ✅ Yes | ✅ Yes |
| Order Media | ✅ Yes (up to 5, 50 MB) | ✅ Yes (up to 5, 50 MB) |
| Rider Rating | ✅ Yes (1-5 stars) | ❌ No |
| Rider Comment | ✅ Yes | ❌ No |
| Pickup Experience | ❌ No | ✅ Yes (comment only) |

### Key Benefits
- ✅ Separate feedback paths for delivery and pickup orders
- ✅ Relevant feedback collection (riders for delivery, experience for pickup)
- ✅ Visual indicator on web dashboard (Rated/Not Rated/N/A)
- ✅ Media upload support for visual feedback
- ✅ All data stored in single `orders` table
- ✅ Same storage bucket (`rated_media`) for all media

---

**Implementation Status**: ✅ Complete and Ready for Testing  
**Last Updated**: November 26, 2025  
**Version**: 2.0 (with Pickup/Delivery Differentiation)

