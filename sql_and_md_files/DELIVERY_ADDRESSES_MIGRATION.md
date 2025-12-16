# Delivery Addresses Migration to Supabase

## Overview
This document describes the migration of delivery addresses from Firebase to Supabase. All delivery address operations now use Supabase exclusively.

## Changes Made

### 1. Database Schema
- **Updated**: `sql_and_md_files/create_delivery_addresses_table.sql`
  - Added `phone_number` column (TEXT, nullable)

- **Migration Script**: `sql_and_md_files/add_phone_number_to_delivery_addresses.sql`
  - Run this SQL script in Supabase SQL Editor to add the `phone_number` column to existing tables

### 2. Supabase Service (`customer_app/lib/services/supabase_service.dart`)
- **Added**: `loadDeliveryAddresses(String customerId)` - Loads all addresses for a customer
- **Updated**: `saveDeliveryAddress()` - Now includes `phone_number` field support
- **Added**: `updateDeliveryAddress()` - Updates an existing address
- **Added**: `deleteDeliveryAddress(String addressId)` - Deletes an address

### 3. Customer Provider (`customer_app/lib/providers/customer_provider.dart`)
- **Migrated**: `loadDeliveryAddresses()` - Now loads from Supabase instead of Firebase
- **Migrated**: `saveDeliveryAddress()` - Now saves to Supabase only (Firebase code removed)
- **Migrated**: `updateDeliveryAddress()` - Now updates in Supabase instead of Firebase
- **Migrated**: `deleteDeliveryAddress()` - Now deletes from Supabase instead of Firebase

## Key Features

### 1. Address Persistence
- ✅ When a customer adds a new address, existing addresses are preserved
- ✅ All addresses are reloaded after save/update/delete operations
- ✅ No addresses disappear when adding new ones

### 2. Multiple Address Selection
- ✅ Customers can add multiple saved addresses
- ✅ Customers can select different addresses for different orders
- ✅ Default address is automatically selected, but can be changed

### 3. Data Storage
- ✅ All addresses are stored in Supabase `delivery_addresses` table
- ✅ No Firebase storage for delivery addresses
- ✅ Phone number support included for each address

## Database Table Structure

```sql
CREATE TABLE delivery_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    address TEXT NOT NULL,
    label TEXT NOT NULL DEFAULT 'Address',
    phone_number TEXT,  -- NEW: Added for phone number support
    is_default BOOLEAN DEFAULT FALSE,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);
```

## Migration Steps

1. **Run the SQL migration** (if phone_number column doesn't exist):
   ```sql
   -- Run: sql_and_md_files/add_phone_number_to_delivery_addresses.sql
   ```

2. **Deploy the updated code** to the customer app

3. **Existing addresses** will be automatically loaded from Supabase on next app launch

## Testing Checklist

- [ ] Load existing addresses from Supabase
- [ ] Add new delivery address - should save to Supabase only
- [ ] Update existing address - should update in Supabase
- [ ] Delete address - should delete from Supabase
- [ ] Verify addresses persist when adding new ones
- [ ] Verify customers can select different addresses for different orders
- [ ] Verify default address selection works correctly

## Notes

- Old Firebase migration functions remain in the code but are no longer used
- The `phone_number` field is optional and can be null
- All timestamps are stored as Unix timestamps in milliseconds

