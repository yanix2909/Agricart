# Rider Assignment - Supabase Migration Guide

## Overview
This document explains the Supabase database structure for assigning orders to riders, replacing the Firebase Realtime Database implementation.

## Tables and Columns

### 1. **orders** Table (Updated)
The main orders table gets these new columns for rider assignment:

| Column Name | Type | Description |
|------------|------|-------------|
| `rider_id` | TEXT | UID of the assigned rider (references `riders.uid`) |
| `rider_name` | TEXT | Full name of the assigned rider (denormalized) |
| `rider_phone` | TEXT | Phone number of the assigned rider (denormalized) |
| `assigned_at` | BIGINT | Unix timestamp (milliseconds) when rider was assigned |
| `out_for_delivery_at` | BIGINT | Unix timestamp when order was marked as out for delivery |

**Indexes Created:**
- `idx_orders_rider_id` - For querying orders by rider
- `idx_orders_assigned_at` - For sorting by assignment time
- `idx_orders_out_for_delivery_at` - For delivery scheduling
- `idx_orders_rider_status` - Composite index for rider + status queries

### 2. **delivery_orders** Table (New)
Separate table optimized for the delivery app to query orders assigned to riders.

**Key Fields:**
- `id` (TEXT, PRIMARY KEY) - Order ID
- `rider_id` (TEXT, NOT NULL) - Assigned rider UID
- `rider_name` (TEXT, NOT NULL) - Rider's full name
- `rider_phone` (TEXT) - Rider's phone number
- `assigned_at` (BIGINT, NOT NULL) - Assignment timestamp
- `out_for_delivery_at` (BIGINT) - Out for delivery timestamp
- `status` (TEXT) - Order status (default: 'pending')
- `delivery_proof` (JSONB) - Array of proof of delivery image URLs (null initially)
- `proof_delivery_images` (JSONB) - Legacy field for proof images
- Full order details (customer info, items, addresses, etc.)

**Indexes Created:**
- `idx_delivery_orders_rider_id` - Primary query index
- `idx_delivery_orders_status` - Status filtering
- `idx_delivery_orders_rider_status` - Composite for rider + status
- `idx_delivery_orders_assigned_at` - Time-based sorting
- `idx_delivery_orders_created_at` - Creation time sorting

**Query Pattern:**
```sql
-- Get all orders assigned to a specific rider
SELECT * FROM delivery_orders 
WHERE rider_id = 'rider_uid_here' 
ORDER BY assigned_at DESC;

-- Get pending orders for a rider
SELECT * FROM delivery_orders 
WHERE rider_id = 'rider_uid_here' 
AND status = 'pending';
```

### 3. **order_assignments** Table (Optional - Fallback)
Backup table for rider assignments, used to recover missing assignment data.

**Fields:**
- `order_id` (TEXT, PRIMARY KEY) - Order ID
- `rider_id` (TEXT, NOT NULL) - Assigned rider UID
- `rider_name` (TEXT, NOT NULL) - Rider's full name
- `rider_phone` (TEXT) - Rider's phone number
- `assigned_at` (BIGINT, NOT NULL) - Assignment timestamp
- `created_at` (BIGINT) - Record creation timestamp
- `updated_at` (BIGINT) - Last update timestamp

**Purpose:** 
- Fallback mechanism if `orders` table loses rider assignment data
- Can be used for data recovery/migration
- Optional - can be removed if not needed

## Workflow

### When Assigning a Rider to Orders:

1. **Update `orders` table:**
   ```sql
   UPDATE orders 
   SET 
     rider_id = 'rider_uid',
     rider_name = 'Rider Full Name',
     rider_phone = 'rider_phone',
     assigned_at = EXTRACT(EPOCH FROM NOW()) * 1000,
     out_for_delivery_at = EXTRACT(EPOCH FROM NOW()) * 1000,
     status = 'out_for_delivery',
     updated_at = EXTRACT(EPOCH FROM NOW()) * 1000
   WHERE uid = 'order_id';
   ```

2. **Insert/Update `delivery_orders` table:**
   ```sql
   INSERT INTO delivery_orders (
     id, rider_id, rider_name, rider_phone, 
     assigned_at, out_for_delivery_at, status,
     customer_id, customer_name, items, ...
   ) VALUES (
     'order_id', 'rider_uid', 'Rider Name', 'rider_phone',
     EXTRACT(EPOCH FROM NOW()) * 1000,
     EXTRACT(EPOCH FROM NOW()) * 1000,
     'pending',
     'customer_id', 'Customer Name', '[...]'::jsonb, ...
   )
   ON CONFLICT (id) DO UPDATE SET
     rider_id = EXCLUDED.rider_id,
     rider_name = EXCLUDED.rider_name,
     rider_phone = EXCLUDED.rider_phone,
     assigned_at = EXCLUDED.assigned_at,
     out_for_delivery_at = EXCLUDED.out_for_delivery_at,
     updated_at = EXTRACT(EPOCH FROM NOW()) * 1000;
   ```

3. **Optionally update `order_assignments` (for backup):**
   ```sql
   INSERT INTO order_assignments (
     order_id, rider_id, rider_name, rider_phone, assigned_at
   ) VALUES (
     'order_id', 'rider_uid', 'Rider Name', 'rider_phone',
     EXTRACT(EPOCH FROM NOW()) * 1000
   )
   ON CONFLICT (order_id) DO UPDATE SET
     rider_id = EXCLUDED.rider_id,
     rider_name = EXCLUDED.rider_name,
     updated_at = EXTRACT(EPOCH FROM NOW()) * 1000;
   ```

### When Delivery App Queries Orders:

```sql
-- Get all pending orders for a rider
SELECT * FROM delivery_orders 
WHERE rider_id = 'current_rider_uid' 
AND status IN ('pending', 'out_for_delivery', 'to_receive')
ORDER BY assigned_at DESC;
```

### When Updating Delivery Status:

```sql
-- Mark as delivered
UPDATE delivery_orders 
SET 
  status = 'delivered',
  delivered_at = EXTRACT(EPOCH FROM NOW()) * 1000,
  delivered_by = 'rider_uid',
  delivered_by_name = 'Rider Name',
  delivery_proof = '["url1", "url2"]'::jsonb,
  updated_at = EXTRACT(EPOCH FROM NOW()) * 1000
WHERE id = 'order_id';

-- Also update main orders table
UPDATE orders 
SET 
  status = 'delivered',
  updated_at = EXTRACT(EPOCH FROM NOW()) * 1000
WHERE uid = 'order_id';
```

## Migration Notes

1. **Column Naming:** Uses snake_case (PostgreSQL convention) instead of camelCase
   - Firebase: `riderId` → Supabase: `rider_id`
   - Firebase: `riderName` → Supabase: `rider_name`
   - Firebase: `assignedAt` → Supabase: `assigned_at`

2. **Timestamps:** Uses BIGINT (Unix milliseconds) to match Firebase format

3. **JSON Fields:** Uses JSONB for arrays/objects (items, delivery_proof)

4. **Indexes:** All critical query paths are indexed for performance

5. **Foreign Keys:** Optional - commented out in SQL file. Uncomment if you want referential integrity.

## Testing Checklist

- [ ] Run SQL script in Supabase SQL Editor
- [ ] Verify `orders` table has new rider columns
- [ ] Verify `delivery_orders` table exists
- [ ] Verify `order_assignments` table exists (if using)
- [ ] Test inserting a rider assignment
- [ ] Test querying orders by rider_id
- [ ] Test updating delivery status
- [ ] Verify indexes are being used (EXPLAIN queries)

## Rollback Plan

If you need to rollback:
1. Remove rider columns from `orders` table:
   ```sql
   ALTER TABLE orders DROP COLUMN IF EXISTS rider_id;
   ALTER TABLE orders DROP COLUMN IF EXISTS rider_name;
   ALTER TABLE orders DROP COLUMN IF EXISTS rider_phone;
   ALTER TABLE orders DROP COLUMN IF EXISTS assigned_at;
   ALTER TABLE orders DROP COLUMN IF EXISTS out_for_delivery_at;
   ```

2. Drop `delivery_orders` table:
   ```sql
   DROP TABLE IF EXISTS delivery_orders;
   ```

3. Drop `order_assignments` table:
   ```sql
   DROP TABLE IF EXISTS order_assignments;
   ```

