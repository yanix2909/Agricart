# Order Notes Debug Guide

## Issue
Order notes are not displaying in the web dashboard even though they are saved in the `order_notes` column in Supabase.

## Root Cause
There's a mismatch between:
1. **Saving**: Data is saved as `order_notes` (snake_case) in Supabase
2. **Fetching**: The normalization converts `order_notes` → `orderNotes` (camelCase)
3. **Display**: Code checks for multiple field names but may not be getting the data properly

## Solution Applied

### 1. Database Column
Make sure the `order_notes` column exists in the `orders` table:
```sql
-- Run this in Supabase SQL Editor if not already done
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_notes TEXT;
```

### 2. Normalization Fix
Updated `normalizeRow()` function in `staff.js` to:
- Check raw `row` data FIRST before normalized values
- Handle both `order_notes` and `delivery_notes` fields
- Set both camelCase and snake_case versions for compatibility

### 3. Display Fix
Added order notes display in:
- `viewOrderDetails()` modal (simple modal)
- Card-based order details view (confirmed orders)
- Original layout (non-confirmed orders)

## Debug Steps

1. **Check Console Logs** when viewing an order:
   - Look for "🔍 Raw order data from Supabase:" - should show `order_notes` value
   - Look for "📝 Order Notes Normalization:" - shows normalization process
   - Look for "🔍 Normalized order data:" - shows final normalized values
   - Look for "🔍 Order Notes Debug:" - shows what's available in the modal

2. **Verify Database**:
   - Check if `order_notes` column exists in Supabase
   - Check if the order actually has data in `order_notes` column
   - Run: `SELECT id, order_notes FROM orders WHERE order_notes IS NOT NULL LIMIT 5;`

3. **Check Data Flow**:
   - Customer app saves: `order_notes` (snake_case) ✅
   - Supabase stores: `order_notes` (snake_case) ✅
   - Normalization converts: `order_notes` → `orderNotes` ✅
   - Display checks: `orderNotes || order_notes || deliveryNotes || delivery_notes` ✅

## Expected Console Output

When viewing an order WITH order notes:
```javascript
🔍 Raw order data from Supabase: {
  has_order_notes: true,
  order_notes_value: "Customer's note here",
  order_notes_type: "string",
  ...
}

📝 Order Notes Normalization: {
  raw_order_notes: "Customer's note here",
  normalized_orderNotes: "Customer's note here",
  ...
}

🔍 Normalized order data: {
  has_orderNotes: true,
  orderNotes_value: "Customer's note here",
  ...
}
```

## If Still Not Working

1. **Check if column exists**: Run the SQL migration
2. **Check if data exists**: Query Supabase directly
3. **Check browser console**: Look for the debug logs
4. **Verify normalization**: Check if `normalizeRow` is being called
5. **Check field names**: Verify the exact field names in the database

## Files Modified

1. `webdashboards/staff.js`:
   - `normalizeRow()` - Enhanced normalization for order notes
   - `fetchOrderById()` - Added debug logging
   - `viewOrderDetails()` - Added order notes display
   - Card-based order details - Added order notes card

2. `customer_app/lib/providers/customer_provider.dart`:
   - `placeOrder()` - Saves `order_notes` to Supabase

3. `sql_and_md_files/add_order_notes_column.sql`:
   - SQL migration to add `order_notes` column
