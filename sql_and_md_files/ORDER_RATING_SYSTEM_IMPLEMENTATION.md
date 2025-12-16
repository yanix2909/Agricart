# Order Rating System Implementation Guide

## Overview
This document describes the complete implementation of the order rating system for successfully delivered and picked-up orders in the AgriCart platform.

## Features Implemented

### Customer App - Rating Interface
✅ **Rate Order Button**
- Appears on the "To Rate" tab for orders with status `delivered` or `picked_up`
- Only shows for orders that haven't been rated yet (`is_rated = false`)
- Location: `customer_app/lib/screens/orders/order_phases_screen.dart` (lines 1101-1122)

✅ **Order Feedback Section**
- **Overall Rating**: 1-5 star rating system with slider
- **Comment**: Text field for customer feedback (optional)
- **Media Upload**: 
  - Maximum 5 files (images or videos)
  - Maximum total size: 50 MB
  - Supports: JPG, PNG, GIF, WEBP, MP4, MOV, WEBM
- Implementation: `customer_app/lib/screens/orders/order_rating_screen.dart`

✅ **Delivery Rider Feedback Section**
- **Overall Rating**: 1-5 star rating system with slider
- **Comment**: Text field for rider feedback (optional)
- Shows rider name if available
- Implementation: `customer_app/lib/screens/orders/order_rating_screen.dart` (lines 332-407)

### Backend - Database Structure

#### Supabase Database Tables

**orders table** - New columns added:
```sql
-- Order Feedback
order_rating INTEGER         -- Rating 1-5 stars (with constraint check)
order_comment TEXT           -- Customer comment about order
order_media JSONB            -- Array of media URLs (images/videos)
order_rated_at BIGINT        -- Unix timestamp (milliseconds)

-- Rider Feedback
rider_rating INTEGER         -- Rating 1-5 stars (with constraint check)
rider_comment TEXT           -- Customer comment about rider
rider_rated_at BIGINT        -- Unix timestamp (milliseconds)

-- Status Flag
is_rated BOOLEAN DEFAULT FALSE  -- Whether order has been rated
```

#### Indexes Created
- `idx_orders_is_rated` - For querying rated/unrated orders
- `idx_orders_order_rating` - For querying by order rating
- `idx_orders_rider_rating` - For querying by rider rating
- `idx_orders_customer_rated` - Composite index (customer_id, is_rated)
- `idx_orders_rider_rating_performance` - For rider performance analytics

#### Constraints
- `check_order_rating`: Ensures order_rating is NULL or between 1-5
- `check_rider_rating`: Ensures rider_rating is NULL or between 1-5

### Storage Bucket - rated_media

**Bucket Configuration:**
- **Name**: `rated_media`
- **Public**: Yes (allows public viewing of URLs)
- **File Size Limit**: 52,428,800 bytes (50 MB)
- **Allowed MIME Types**: 
  - Images: image/jpeg, image/jpg, image/png, image/gif, image/webp
  - Videos: video/mp4, video/quicktime, video/webm, video/x-msvideo

**Storage Policies:**
All policies allow **public** (unauthenticated) access:
1. ✅ **SELECT** (view) - Public can view rated media
2. ✅ **INSERT** (upload) - Public can insert rated media
3. ✅ **UPDATE** - Public can update rated media
4. ✅ **DELETE** - Public can delete rated media

### Web Dashboard - Display Ratings

**Location**: `webdashboards/staff.js` (lines 13380-13461)

**Features:**
✅ Displays "Customer Feedback" section when order is rated
✅ Shows order rating with star icons (1-5 stars)
✅ Displays order comment if provided
✅ Shows uploaded media (images and videos)
  - Images: Clickable thumbnails with enlarge functionality
  - Videos: Embedded video player with controls
✅ Shows rider rating with star icons (1-5 stars)
✅ Displays rider comment if provided

**Visual Design:**
- Orange/amber theme for feedback section
- Card-based layout with icons
- Responsive image/video gallery
- Clear separation between order and rider feedback

## Implementation Flow

### 1. Customer Rates Order

```
Customer App (Flutter)
  ↓
1. Order Status: 'delivered' or 'picked_up'
  ↓
2. "To Rate" tab shows the order
  ↓
3. Customer clicks "Rate Order!" button
  ↓
4. OrderRatingScreen opens with:
   - Order feedback form
   - Rider feedback form
   - Media upload interface
  ↓
5. Customer submits rating
  ↓
6. CustomerProvider.submitOrderRating() called
```

### 2. Rating Data Processing

```
Customer Provider
  ↓
1. Upload media files to Supabase Storage (rated_media bucket)
  ↓
2. Get public URLs for uploaded files
  ↓
3. Update orders table in Supabase:
   - order_rating
   - order_comment
   - order_media (JSON array of URLs)
   - order_rated_at
   - rider_rating
   - rider_comment
   - rider_rated_at
   - is_rated = true
  ↓
4. Refresh local order data
  ↓
5. Show success message
```

### 3. Display on Web Dashboard

```
Web Dashboard (staff.js)
  ↓
1. Fetch order from Supabase
  ↓
2. Check if is_rated = true
  ↓
3. Render "Customer Feedback" section:
   - Parse rating fields
   - Parse order_media JSON
   - Display stars, comments, media
   - Show rider feedback if available
```

## SQL Setup Instructions

**File**: `webdashboards/setup_order_rating_system.sql`

Run this complete SQL script in the Supabase SQL Editor to set up:
1. All rating columns in the orders table
2. Indexes for performance
3. Constraints for data validation
4. rated_media storage bucket
5. Public access policies for the bucket

```bash
# In Supabase Dashboard:
1. Go to SQL Editor
2. Create New Query
3. Copy contents of setup_order_rating_system.sql
4. Click "Run" to execute
5. Verify success with verification queries (at end of script)
```

## File Locations

### Customer App (Flutter)
- **Rating Screen**: `customer_app/lib/screens/orders/order_rating_screen.dart`
- **Order Phases Screen**: `customer_app/lib/screens/orders/order_phases_screen.dart`
- **Customer Provider**: `customer_app/lib/providers/customer_provider.dart` (submitOrderRating method at line 1535)
- **Order Model**: `customer_app/lib/models/order.dart`

### Web Dashboard
- **Staff Dashboard**: `webdashboards/staff-dashboard.html`
- **Staff Manager**: `webdashboards/staff.js` (rating display at line 13380)

### SQL Scripts
- **Complete Setup**: `webdashboards/setup_order_rating_system.sql` (NEW - comprehensive setup)
- **Original Rating Columns**: `webdashboards/add_order_rating_columns.sql` (basic columns only)

## Testing Checklist

### Customer App Testing
- [ ] Order with status 'delivered' appears in "To Rate" tab
- [ ] Order with status 'picked_up' appears in "To Rate" tab
- [ ] "Rate Order!" button appears for unrated orders
- [ ] "Rate Order!" button does NOT appear for already-rated orders
- [ ] Rating screen opens when button is clicked
- [ ] Can select 1-5 stars for order rating
- [ ] Can enter comment for order
- [ ] Can upload images (up to 5 files, 50 MB total)
- [ ] Can upload videos (up to 5 files, 50 MB total)
- [ ] Can select 1-5 stars for rider rating
- [ ] Can enter comment for rider
- [ ] Shows error if file size exceeds 50 MB
- [ ] Shows error if more than 5 files selected
- [ ] Successfully submits rating to Supabase
- [ ] Shows success message after submission
- [ ] Order moves out of "To Rate" tab after rating

### Web Dashboard Testing
- [ ] Rated orders show "Customer Feedback" section
- [ ] Order rating displays correct number of stars
- [ ] Order comment displays if provided
- [ ] Uploaded images display as clickable thumbnails
- [ ] Uploaded videos display with video player
- [ ] Click on image enlarges it
- [ ] Rider rating displays correct number of stars
- [ ] Rider comment displays if provided
- [ ] Unrated orders do NOT show feedback section

### Database Testing
- [ ] orders table has all rating columns
- [ ] Indexes are created successfully
- [ ] Constraints prevent ratings outside 1-5 range
- [ ] rated_media bucket exists
- [ ] Public can view files in rated_media bucket
- [ ] Public can upload files to rated_media bucket
- [ ] File size limit is enforced (50 MB)

## API Endpoints Used

### Supabase Storage
- **Upload**: `supabase.storage.from('rated_media').uploadBinary()`
- **Get URL**: `supabase.storage.from('rated_media').getPublicUrl()`

### Supabase Database
- **Update Order**: `supabase.from('orders').update({...}).eq('id', orderId)`
- **Fetch Orders**: `supabase.from('orders').select().eq('customer_id', customerId)`

## Data Format Examples

### Order Media JSON (stored in order_media column)
```json
[
  "https://[supabase-url]/storage/v1/object/public/rated_media/order_12345_1234567890_0.jpg",
  "https://[supabase-url]/storage/v1/object/public/rated_media/order_12345_1234567890_1.mp4",
  "https://[supabase-url]/storage/v1/object/public/rated_media/order_12345_1234567890_2.png"
]
```

### Rating Update Payload
```javascript
{
  order_rating: 5,
  order_comment: "Great products, fresh vegetables!",
  order_media: "[\"url1\", \"url2\"]",  // JSON string
  order_rated_at: 1640000000000,        // Unix timestamp in ms
  rider_rating: 5,
  rider_comment: "Very polite and professional rider!",
  rider_rated_at: 1640000000000,        // Unix timestamp in ms
  is_rated: true,
  updated_at: 1640000000000
}
```

## Notes

### Important Considerations
1. **Order Status**: Only orders with status `delivered` or `picked_up` show the rate button
2. **One-Time Rating**: Once an order is rated (`is_rated = true`), the rate button disappears
3. **Media Storage**: Files are uploaded to Supabase Storage, URLs stored in database
4. **Public Access**: rated_media bucket is public to allow viewing without authentication
5. **File Validation**: Client-side validation for file size and count (50 MB, 5 files max)
6. **Optional Comments**: Comments are optional, ratings are required
7. **Rider Information**: Shows rider name in feedback section if rider was assigned

### Security Considerations
1. Storage policies allow public access for ease of use
2. File size limits enforced at bucket level (50 MB)
3. MIME type restrictions prevent malicious file uploads
4. Rating constraints ensure valid star ratings (1-5)
5. Consider adding RLS policies if authentication is required in future

### Performance Optimizations
1. Indexes created for common queries (is_rated, customer_id, rider_id)
2. Composite indexes for multi-column queries
3. JSONB used for media array (efficient storage and querying)
4. Timestamps stored as BIGINT (milliseconds) for consistency

## Future Enhancements (Optional)

- [ ] Add ability to edit ratings within a time window
- [ ] Add rating analytics dashboard for staff
- [ ] Send notification to staff when order is rated
- [ ] Add rider performance metrics based on ratings
- [ ] Add product-level ratings (in addition to order rating)
- [ ] Implement rating moderation system
- [ ] Add "helpful" votes on ratings
- [ ] Export ratings data for analysis

## Support

For issues or questions about the rating system:
1. Check the SQL script output for any errors
2. Verify Supabase bucket exists and has correct policies
3. Check browser console for JavaScript errors
4. Review Flutter debug console for app errors
5. Verify order status is 'delivered' or 'picked_up'

## Version History

- **v1.0** (Initial Implementation)
  - Order and rider rating functionality
  - Media upload support (images and videos)
  - Web dashboard display
  - Complete SQL setup script
  - Public storage policies

---

**Last Updated**: November 26, 2025  
**Implementation Status**: ✅ Complete and Ready for Testing

