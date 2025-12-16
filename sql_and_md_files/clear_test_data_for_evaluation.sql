-- ============================================================================
-- CLEAR TEST DATA FOR EVALUATION/TESTING
-- ============================================================================
-- This script removes test data (orders, sales, user accounts) while
-- preserving permanent system data (admin accounts, products, system tables)
--
-- ⚠️ WARNING: This will permanently delete data. Make a backup first!
--
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- DATABASE TABLES OVERVIEW
-- ============================================================================
--
-- TABLES TO BE CLEARED (Test Data):
-- ✗ orders                  - All customer orders and transactions
-- ✗ delivery_orders         - Orders assigned to riders for delivery
-- ✗ customers               - Customer accounts (with total_orders, total_spent stats)
-- ✗ staff                   - Staff employee accounts
-- ✗ riders                  - Delivery rider accounts (with total_deliveries stats)
-- ✗ farmers                 - Farmer/supplier accounts
-- ✗ products                - Product listings/catalog and inventory
-- ✗ delivery_fees           - Delivery fee configuration for all barangays
-- ✗ pickup_area             - Pickup location settings
--
-- TABLES TO BE PRESERVED (Permanent Data):
-- ✓ admins                  - Administrator accounts (CRITICAL - DO NOT DELETE)
-- ✓ system_data             - System settings and cooperative time
--
-- OPTIONAL TABLES (Can be cleared manually if needed):
-- ? delivery_addresses      - Customer saved addresses (auto-deleted with customers)
-- ? chat_messages           - Customer-staff chat conversations
-- ? conversations           - Chat conversation metadata
--
-- ============================================================================

-- ============================================================================
-- STEP 1: DELETE ALL ORDERS AND RELATED DATA
-- ============================================================================

-- Delete all orders (includes order ratings, sales amounts, etc.)
DELETE FROM orders;

-- Delete all delivery orders (separate table for rider app)
DELETE FROM delivery_orders;

-- Note: These tables store all order information including:
-- - Order details (items, amounts, status)
-- - Customer information
-- - Payment information
-- - Delivery/pickup details
-- - Order ratings and feedback
-- - Rider assignments
-- - All sales/transaction amounts

COMMENT ON TABLE orders IS 'Orders table - All test orders cleared for evaluation';
COMMENT ON TABLE delivery_orders IS 'Delivery orders table - All test orders cleared for evaluation';

-- ============================================================================
-- STEP 2: DELETE ALL USER ACCOUNTS (EXCEPT ADMINS)
-- ============================================================================

-- Delete all customer accounts
-- Customers are users who place orders through the customer app
-- NOTE: This also removes customer statistics like:
--   - total_orders (count of orders placed)
--   - total_spent (total amount spent)
--   - favorite_products (list of favorited items)
DELETE FROM customers;

COMMENT ON TABLE customers IS 'Customers table - All test customer accounts cleared';

-- Delete all staff accounts
-- Staff are employees who manage orders and verify users
DELETE FROM staff;

COMMENT ON TABLE staff IS 'Staff table - All test staff accounts cleared';

-- Delete all rider accounts
-- Riders are delivery personnel who fulfill delivery orders
-- NOTE: This also removes rider statistics like:
--   - total_deliveries (count of completed deliveries)
DELETE FROM riders;

COMMENT ON TABLE riders IS 'Riders table - All test rider accounts cleared';

-- Delete all farmer accounts
-- Farmers are suppliers who provide products
DELETE FROM farmers;

COMMENT ON TABLE farmers IS 'Farmers table - All test farmer accounts cleared';

-- Delete all products
-- Products are the items/inventory that customers can order
-- This includes product names, descriptions, prices, stock quantities, images
DELETE FROM products;

COMMENT ON TABLE products IS 'Products table - All product listings and inventory cleared';

-- Delete all delivery fee configurations
-- This removes the delivery fee settings for all Ormoc barangays
DELETE FROM delivery_fees;

COMMENT ON TABLE delivery_fees IS 'Delivery fees table - All delivery fee configurations cleared';

-- Delete all pickup area locations
-- This removes all pickup location settings
DELETE FROM pickup_area;

COMMENT ON TABLE pickup_area IS 'Pickup area table - All pickup location settings cleared';

-- ============================================================================
-- STEP 3: RESET AUTO-INCREMENT SEQUENCES
-- ============================================================================

-- Reset the farmers table auto-increment ID sequence back to 1
-- This ensures the next farmer will have id = 1
ALTER SEQUENCE farmers_id_seq RESTART WITH 1;

-- Reset the delivery_fees table auto-increment ID sequence back to 1
-- This ensures the next delivery fee entry will have id = 1
ALTER SEQUENCE delivery_fees_id_seq RESTART WITH 1;

-- Note: pickup_area uses UUID (gen_random_uuid()), not auto-increment
-- Note: Other tables (orders, customers, riders, staff) use TEXT-based UIDs
-- (timestamps or UUIDs) which do not auto-increment and cannot be reset

-- ============================================================================
-- STEP 4: PRESERVE ADMIN ACCOUNTS (NO DELETION)
-- ============================================================================

-- ⚠️ ADMIN ACCOUNTS ARE NOT DELETED
-- Admin accounts are permanent and essential for system operation
-- Table: admins
-- These accounts control the entire system and should never be cleared

-- You can verify admin accounts are still present with:
-- SELECT * FROM admins;

-- ============================================================================
-- STEP 5: VERIFY DATA CLEARING AND SEQUENCE RESET
-- ============================================================================

-- Check row counts to confirm deletion:
-- SELECT 'orders' as table_name, COUNT(*) as row_count FROM orders
-- UNION ALL
-- SELECT 'delivery_orders', COUNT(*) FROM delivery_orders
-- UNION ALL
-- SELECT 'customers', COUNT(*) FROM customers
-- UNION ALL
-- SELECT 'staff', COUNT(*) FROM staff
-- UNION ALL
-- SELECT 'riders', COUNT(*) FROM riders
-- UNION ALL
-- SELECT 'farmers', COUNT(*) FROM farmers
-- UNION ALL
-- SELECT 'admins', COUNT(*) FROM admins;

-- ============================================================================
-- ADDITIONAL NOTES
-- ============================================================================

-- ✅ CLEARED (Deleted):
-- - All orders (sales amounts, transactions)
-- - All order ratings and feedback
-- - All customer accounts (including their total_orders, total_spent statistics)
-- - All staff accounts
-- - All rider accounts (including their total_deliveries statistics)
-- - All farmer accounts
-- - All products (product listings, inventory, stock levels, sales statistics)
-- - All delivery fee configurations (barangay delivery fees)
-- - All pickup area locations (pickup settings)

-- ✅ PRESERVED (NOT Deleted):
-- 
-- 1. Admin Accounts (admins table)
--    - uuid, email, password, fullname, username, phone
--    - status, role, last_login, last_seen, created_at, updated_at
--    ⚠️ CRITICAL: These accounts control the entire system
--
-- 2. System Configuration Tables:
--    a) system_data - System settings and cooperative time
--       - id, epoch_ms, iso, weekday, source, server_ts, updated_at
--       - support_email, support_phone (contact support settings)
--
-- 3. Storage Buckets (Supabase Storage):
--    ⚠️ Files in buckets are NOT deleted by this script (must be cleared manually)
--    
--    Product-related buckets (may want to clear manually):
--    - product-images (product photos)
--    - featured-display (featured product images)
--    - product-videos (product video files)
--    
--    User-related buckets (may want to clear manually):
--    - id-photos (user ID verification photos)
--    - profile-pictures (user profile photos)
--    
--    Order-related buckets (may want to clear manually):
--    - delivery-proof (proof of delivery images)
--    - rated_media (order rating images/videos)
--    - gcash-receipts (payment receipts)
--    - refund-receipts (refund proof receipts)
--    
--    Other buckets:
--    - customerconvo-uploads (chat message attachments)
--    
--    To clear buckets manually:
--    1. Go to Supabase Dashboard → Storage
--    2. Select each bucket
--    3. Delete all files or entire folders

-- 📊 STATISTICS AFTER RUNNING THIS SCRIPT:
-- - Total Orders Count: 0
-- - Total Sales Amount: 0
-- - Total Products: 0 (all product listings deleted)
-- - Total Delivery Fees: 0 (all fee configurations deleted)
-- - Total Pickup Areas: 0 (all pickup locations deleted)
-- - Customer Order Count: 0 (accounts deleted)
-- - Rider Delivery Count: 0 (accounts deleted)
-- - Product Sales Count: 0 (products deleted)

-- ============================================================================
-- OPTIONAL: ALTERNATIVE APPROACH - KEEP ACCOUNTS BUT RESET STATISTICS
-- ============================================================================

-- ⚠️ USE THIS INSTEAD if you want to KEEP user accounts but RESET their statistics
-- (Comment out the DELETE statements in STEP 2 and use these instead)

-- Reset customer statistics to 0 (keeps accounts, clears stats):
-- UPDATE customers SET 
--   total_orders = 0,
--   total_spent = 0.0,
--   favorite_products = '{}';

-- Reset rider statistics to 0 (keeps accounts, clears stats):
-- UPDATE riders SET 
--   total_deliveries = 0;

-- ============================================================================
-- OPTIONAL: CLEAR ADDITIONAL RELATED DATA
-- ============================================================================

-- Clear customer delivery addresses (automatically deleted via CASCADE foreign key):
-- DELETE FROM delivery_addresses; -- Already handled by customers deletion

-- Clear chat messages (customer-staff and customer-rider conversations):
-- TRUNCATE TABLE chat_messages;
-- TRUNCATE TABLE conversations;

-- Clear chat messages from Firebase Realtime Database (must be done manually):
-- - chatMessages/{messageId}
-- - conversations/{customerId}
-- - customerMessages/{customerId}/{messageId}

-- Clear notifications (if you have a notifications table):
-- DELETE FROM notifications;
-- DELETE FROM customerNotifications; -- If using Firebase

-- Clear Firebase Realtime Database data (must be done manually in Firebase Console):
-- - orders/{orderId}
-- - delivery_orders/{orderId}
-- - orderAssignments/{orderId}
-- - reservations/{productId}/{orderId}
-- - sales/{saleId}
-- - notifications/{notificationId}
-- - customerNotifications/{customerId}/{notificationId}

-- Clear Supabase Storage Buckets (must be done manually in Supabase Dashboard):
-- Since products are now deleted, you may also want to clear product-related files:
-- 1. Go to Supabase Dashboard → Storage
-- 2. Clear these buckets for a fresh start:
--    - product-images (all product photos)
--    - featured-display (featured product images)
--    - product-videos (product video files)
--    - id-photos (user ID verification photos)
--    - profile-pictures (user profile photos)
--    - delivery-proof (proof of delivery images)
--    - rated_media (order rating media)
--    - gcash-receipts (payment receipts)
--    - refund-receipts (refund proof)
--    - customerconvo-uploads (chat attachments)

-- ============================================================================
-- AFTER RUNNING THIS SCRIPT
-- ============================================================================

-- 1. Verify admin accounts still exist:
--    SELECT * FROM admins;

-- 2. Verify all test data is cleared:
--    SELECT COUNT(*) FROM orders;        -- Should be 0
--    SELECT COUNT(*) FROM customers;     -- Should be 0
--    SELECT COUNT(*) FROM staff;         -- Should be 0
--    SELECT COUNT(*) FROM riders;        -- Should be 0
--    SELECT COUNT(*) FROM farmers;       -- Should be 0
--    SELECT COUNT(*) FROM products;      -- Should be 0
--    SELECT COUNT(*) FROM delivery_fees; -- Should be 0
--    SELECT COUNT(*) FROM pickup_area;   -- Should be 0

-- 3. Verify sequence reset:
--    SELECT nextval('farmers_id_seq');       -- Should return 1
--    SELECT nextval('delivery_fees_id_seq'); -- Should return 1

-- 4. You can now create new test data for evaluation
--    - Next farmer will have id = 1
--    - Next delivery fee entry will have id = 1
--    - Pickup areas will use new UUIDs
--    - Orders, customers, riders, staff will use new timestamp/UUID-based IDs

-- ============================================================================
-- STATISTICS & COUNTERS BEHAVIOR SUMMARY
-- ============================================================================

-- ✅ RESET TO 0 (Automatically when accounts are deleted):
-- 
-- Customer Account Statistics (deleted with customers table):
--   - total_orders           → 0 (account deleted)
--   - total_spent            → 0.00 (account deleted)
--   - favorite_products      → [] (account deleted)
--
-- Rider Account Statistics (deleted with riders table):
--   - total_deliveries       → 0 (account deleted)
--
-- Product Statistics (deleted with products table):
--   - current_reserved       → 0 (product deleted)
--   - sold_quantity          → 0 (product deleted)
--   - available_quantity     → 0 (product deleted)
--
-- Global Metrics (calculated from orders table):
--   - Total Orders Count     → 0 (no orders)
--   - Total Sales Amount     → 0 (no orders)
--   - Total Revenue          → 0 (no orders)

-- ============================================================================
-- ID BEHAVIOR SUMMARY
-- ============================================================================

-- TEXT-based IDs (DO NOT reset, continue with new unique values):
-- - orders.id / order_id         → Timestamp-based (e.g., 1732633845123456789)
-- - customers.uid                → Firebase Auth UID / UUID
-- - riders.uid                   → UUID / TEXT
-- - staff.uuid                   → UUID / TEXT
-- - delivery_orders.id           → TEXT-based

-- UUID-based IDs (Randomly generated, do not reset):
-- - pickup_area.id               → UUID (gen_random_uuid())

-- Auto-increment IDs (RESET to 1):
-- - farmers.id                   → BIGSERIAL (reset to 1 with this script)
-- - delivery_fees.id             → SERIAL (reset to 1 with this script)

-- ============================================================================

