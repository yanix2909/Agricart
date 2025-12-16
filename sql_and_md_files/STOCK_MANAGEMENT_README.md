# Stock Management System Update

## Overview
This update implements a new stock management system that properly handles product restocking and prevents incorrect stock calculations when staff update product quantities.

## Key Changes

### 1. Customer App - Sold Out Indicator
- Added red "Sold Out" indicator when `availableQuantity` is 0 or less
- Indicator appears automatically when products are sold out
- Shows alongside existing "Unavailable" indicator

### 2. New Stock Management Logic
The system now uses three separate quantities:

- **Base Quantity** (`availableQuantity`): What staff sets as the total available stock
- **Current Reserved** (`currentReserved`): Quantity currently reserved by pending orders
- **Sold Quantity** (`soldQuantity`): Quantity from confirmed orders

**Available Quantity = Base Quantity - Current Reserved (Pending Orders)**

**Note**: The displayed available quantity subtracts pending reservations to show accurate availability. When staff restock products, the new base quantity is used, but pending orders still reduce the displayed availability. If pending orders are cancelled/rejected, the reserved quantity gets added back to the available display.

### 3. How It Works

#### Before (Old System):
- Staff uploads product with 10 kg
- Customer orders 10 kg → `availableQuantity` becomes 0
- Staff restocks to 25 kg → `availableQuantity` becomes 25
- **Problem**: Previous order was subtracted from the new base quantity

#### After (New System):
- Staff uploads product with 10 kg
- Customer orders 10 kg → `currentReserved` = 10, display shows 0 kg available (sold out)
- Staff restocks to 25 kg → `availableQuantity` = 25, `currentReserved` remains 10, display shows 15 kg available
- **Result**: Display shows 15 kg available (25 base - 10 reserved), pending orders reduce displayed availability

## Implementation Details

### Database Schema Changes
Products now have these additional fields:
```json
{
  "availableQuantity": 25,        // Base quantity set by staff
  "currentReserved": 5,           // Currently reserved by pending orders
  "soldQuantity": 10              // Confirmed orders
}
```

### Code Changes

#### Customer App (`customer_app/lib/`)
- **Product Model**: Added `soldQuantity` and `currentReserved` fields
- **Customer Provider**: Updated to calculate availability using new formula
- **Dashboard**: Added sold out indicator display

#### Staff Web (`staff.js`)
- **Product Loading**: Updated to use new calculation method
- **Order Confirmation**: Now updates `soldQuantity` instead of decreasing `availableQuantity`
- **Product Updates**: Staff can now update base quantity without affecting previous orders

#### Firebase Functions (`firebase-functions.js`)
- **Stock Reservation**: Updated to use `currentReserved` field
- **Order Cancellation**: Properly restores reserved quantities

## Migration

### Automatic Migration
The system automatically handles existing products by:
- Setting `soldQuantity` to 0 if not present
- Setting `currentReserved` to 0 if not present

### Manual Migration (Optional)
If you want to run a manual migration, use the `migrate-stock-system.js` script:

1. Set up Firebase Admin SDK
2. Update the database URL in the script
3. Run: `node migrate-stock-system.js`

## Benefits

1. **Accurate Stock Display**: Available quantity always reflects actual availability
2. **Proper Restocking**: Staff can update quantities without affecting previous orders
3. **Real-time Updates**: Stock levels update immediately when orders are placed/confirmed
4. **Better UX**: Clear sold out indicators for customers
5. **Data Integrity**: Prevents stock calculation errors

## Testing

### Test Scenarios
1. **Basic Order Flow**:
   - Create product with 10 kg
   - Place order for 5 kg
   - Verify `currentReserved` = 5, display shows 5 kg available

2. **Restocking**:
   - Update product to 25 kg
   - Verify display shows 20 kg available (25 base - 5 reserved)

3. **Order Confirmation**:
   - Confirm the 5 kg order
   - Verify `soldQuantity` = 5, `currentReserved` = 0, display shows 25 kg available

4. **Order Cancellation/Rejection**:
   - Cancel/reject the 5 kg pending order
   - Verify `currentReserved` = 0, display shows 25 kg available (reserved quantity added back)

5. **Sold Out Indicator**:
   - Create product with 0 kg available
   - Verify red "Sold Out" indicator appears

## Rollback Plan

If issues arise, you can rollback by:
1. Reverting the code changes
2. The old reservation system will continue to work
3. Database changes are backward compatible

## Support

For issues or questions about the new stock management system, check:
1. Firebase console for database errors
2. Browser console for JavaScript errors
3. Flutter debug console for app errors
