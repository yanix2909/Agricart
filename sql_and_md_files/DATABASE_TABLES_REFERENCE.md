# Database Tables Reference - AgriCart System

This document provides a comprehensive overview of all database tables in the AgriCart system, their purpose, and what should be preserved vs cleared during testing.

---

## 📊 **TABLES OVERVIEW**

### **Tables to CLEAR for Testing** (Test/Transaction Data)
| Table | Purpose | Contains | Clear? |
|-------|---------|----------|--------|
| `orders` | Customer orders | Order details, sales amounts, transactions, ratings | ✗ YES |
| `delivery_orders` | Rider delivery assignments | Orders assigned to riders for delivery | ✗ YES |
| `customers` | Customer accounts | User profiles, statistics (total_orders, total_spent) | ✗ YES |
| `staff` | Staff employee accounts | Staff profiles, credentials | ✗ YES |
| `riders` | Delivery rider accounts | Rider profiles, statistics (total_deliveries) | ✗ YES |
| `farmers` | Farmer/supplier accounts | Farmer profiles, farm details | ✗ YES |

### **Tables to PRESERVE** (Permanent/System Data)
| Table | Purpose | Contains | Clear? |
|-------|---------|----------|--------|
| `admins` | Administrator accounts | Admin credentials, system access | ✓ **NEVER** |
| `products` | Product catalog | Inventory, prices, descriptions | ✓ Preserve |
| `delivery_fees` | Delivery fee configuration | Fees for all Ormoc barangays | ✓ Preserve |
| `pickup_area` | Pickup location settings | Pickup addresses and details | ✓ Preserve |
| `system_data` | System configuration | Cooperative time, support contacts | ✓ Preserve |

### **Optional Tables** (Can be cleared if needed)
| Table | Purpose | Auto-Deleted? |
|-------|---------|---------------|
| `delivery_addresses` | Customer saved addresses | Yes (CASCADE with customers) |
| `chat_messages` | Customer-staff conversations | No (manual clear) |
| `conversations` | Chat conversation metadata | No (manual clear) |

---

## 📋 **DETAILED TABLE STRUCTURES**

### **1. ADMIN ACCOUNTS** (`admins` table) - ⚠️ CRITICAL - NEVER DELETE

**Purpose:** Administrator accounts that control the entire system

**Columns:**
- `uuid` (TEXT, PRIMARY KEY) - Unique identifier
- `email` (TEXT) - Login email
- `password` (TEXT) - Login password (plain text)
- `fullname` (TEXT) - Full name
- `username` (TEXT) - Username
- `phone` (TEXT) - Contact number
- `status` (TEXT) - Account status (active/inactive)
- `role` (TEXT) - Admin role
- `last_login` (TIMESTAMP) - Last login time
- `last_seen` (TIMESTAMP) - Last activity
- `created_at` (TIMESTAMP) - Account creation date
- `updated_at` (TIMESTAMP) - Last update date

**Why Preserve:** Required for system access and management. Without admin accounts, the system cannot be managed.

---

### **2. ORDERS** (`orders` table) - CLEAR FOR TESTING

**Purpose:** Stores all customer orders and transactions

**Key Columns:**
- `id` / `order_id` (TEXT, PRIMARY KEY) - Timestamp-based unique order ID
- `customer_id` (TEXT) - Customer who placed the order
- `customer_name`, `customer_phone`, `customer_address`
- `subtotal`, `delivery_fee`, `total` (NUMERIC) - **Sales amounts**
- `status` (TEXT) - Order status (pending, confirmed, delivered, etc.)
- `payment_method`, `payment_status` (TEXT)
- `delivery_option` (TEXT) - delivery or pickup
- `items` (JSONB) - Order items array
- `order_date`, `created_at`, `updated_at` (BIGINT)
- `rider_id`, `rider_name`, `rider_phone` (TEXT) - Assigned rider info
- `assigned_at`, `out_for_delivery_at` (BIGINT)
- `order_rating`, `order_comment`, `order_media` (JSONB) - Customer feedback
- `rider_rating`, `rider_comment` - Rider feedback
- `pickup_experience_comment` - Pickup feedback
- Cancellation, refund, reschedule metadata

**Why Clear:** Contains all test transaction data and sales amounts

---

### **3. DELIVERY ORDERS** (`delivery_orders` table) - CLEAR FOR TESTING

**Purpose:** Optimized table for rider app to query assigned deliveries

**Key Columns:**
- `id` (TEXT, PRIMARY KEY) - Order ID
- `rider_id`, `rider_name`, `rider_phone` (TEXT, NOT NULL)
- `assigned_at`, `out_for_delivery_at` (BIGINT)
- `status` (TEXT)
- Customer and delivery information (mirrors orders table)
- `delivery_proof` (JSONB) - Proof of delivery images
- `delivered_at`, `delivered_by`, `delivered_by_name`
- `failed_at`, `failure_reason`

**Why Clear:** Contains test delivery assignments and transactions

---

### **4. CUSTOMERS** (`customers` table) - CLEAR FOR TESTING

**Purpose:** Customer accounts who order through the mobile app

**Key Columns:**
- `uid` (TEXT, PRIMARY KEY) - Firebase Auth UID / UUID
- `email` (TEXT, NOT NULL)
- `full_name`, `first_name`, `last_name`, `middle_initial`, `suffix`
- `username`, `age`, `gender`
- `phone_number`, `address`, `street`, `sitio`, `barangay`, `city`
- `profile_image_url`
- `status`, `account_status`, `verification_status`
- `id_type`, `id_front_photo`, `id_back_photo`
- `is_online`, `last_seen`, `has_logged_in_before`
- **Statistics:**
  - `total_orders` (INTEGER) - Count of orders placed
  - `total_spent` (NUMERIC) - Total amount spent
  - `favorite_products` (TEXT[]) - Favorited product IDs
- `created_at`, `updated_at`, `registration_date` (BIGINT)

**Why Clear:** Test user accounts with embedded order statistics

---

### **5. STAFF** (`staff` table) - CLEAR FOR TESTING

**Purpose:** Staff employee accounts who manage orders and verify users

**Key Columns:**
- `uuid` (TEXT, PRIMARY KEY) - Unique identifier
- `full_name` (TEXT, NOT NULL)
- `email` (TEXT, NOT NULL)
- `phone` (TEXT)
- `employee_id` (TEXT) - Employee ID number
- `valid_id_type`, `valid_id_number`
- `address` - Full address
- `id_front_photo_url`, `id_back_photo_url`
- `password` (TEXT) - Login password (plain text)
- `role` (TEXT) - 'staff'
- `status` (TEXT) - active/inactive
- `created_at`, `updated_at` (BIGINT)
- `created_by` (TEXT) - Admin who created the account

**Why Clear:** Test employee accounts

---

### **6. RIDERS** (`riders` table) - CLEAR FOR TESTING

**Purpose:** Delivery rider accounts who fulfill delivery orders

**Key Columns:**
- `uid` (TEXT, PRIMARY KEY)
- `first_name`, `middle_name`, `last_name`, `suffix`, `full_name`
- `email` (TEXT, NOT NULL UNIQUE)
- `phone_number` (TEXT, NOT NULL)
- `gender`, `birth_date` (BIGINT)
- `street`, `sitio`, `barangay`, `city`, `province`, `postal_code`, `address`
- `id_type`, `id_number`, `id_front_photo`, `id_back_photo`
- `vehicle_type`, `vehicle_number`, `license_number`
- `login_password_hash` (TEXT) - SHA256 hashed password
- `status` (TEXT) - pending/active
- `is_active`, `is_online` (BOOLEAN)
- **Statistics:**
  - `total_deliveries` (INTEGER) - Count of completed deliveries
- `created_at` (BIGINT)
- `created_by` (TEXT)

**Why Clear:** Test rider accounts with embedded delivery statistics

---

### **7. FARMERS** (`farmers` table) - CLEAR FOR TESTING

**Purpose:** Farmer/supplier accounts who provide products

**Key Columns:**
- `id` (BIGSERIAL, PRIMARY KEY) - **Auto-incrementing ID**
- `uid` (TEXT, UNIQUE NOT NULL) - Unique identifier
- `full_name` (TEXT, NOT NULL)
- `age`, `birth_date` (DATE), `gender`
- `phone_number`
- `farm_location`, `home_location`
- `farm_size` (NUMERIC)
- `id_type`, `id_front_photo`, `id_back_photo`
- `created_at`, `updated_at` (BIGINT)
- `created_by`, `created_by_name`, `created_by_role`
- `verified_by`, `verified_by_name`, `verified_by_role`

**Why Clear:** Test farmer accounts
**Note:** Auto-increment sequence resets to 1 with clear script

---

### **8. PRODUCTS** (`products` table) - PRESERVE (with optional stat reset)

**Purpose:** Product catalog and inventory

**Key Columns:**
- `uid` (TEXT, PRIMARY KEY) - Unique product ID
- `name`, `description`, `category` (TEXT, NOT NULL)
- `price` (NUMERIC, NOT NULL)
- `unit` (TEXT) - kg, piece, bundle, etc.
- `harvest_date` (TEXT)
- **Stock Management:**
  - `available_quantity` (INTEGER) - Current stock
  - `current_reserved` (INTEGER) - Reserved for pending orders
  - `sold_quantity` (INTEGER) - Total sold count
- `image_url`, `image_urls` (TEXT[])
- `status` (TEXT) - active/inactive
- `is_available` (BOOLEAN)
- `farmer_id`, `farmer_name` (TEXT)
- `created_by`, `staff_id`, `managed_by`, `updated_by`
- `rating` (NUMERIC), `review_count` (INTEGER)
- `tags` (TEXT[]), `location`
- `created_at`, `updated_at` (BIGINT)

**Why Preserve:** Product catalog should remain for evaluation
**Optional:** Reset `current_reserved` and `sold_quantity` to 0

---

### **9. DELIVERY FEES** (`delivery_fees` table) - PRESERVE

**Purpose:** Delivery fee configuration for all Ormoc barangays

**Structure:**
- `id` (SERIAL, PRIMARY KEY) - Always 1 (single row)
- `updated_at` (TIMESTAMP)
- **110+ Barangay Columns:** Each as `DECIMAL(10,2)`
  - `airport`, `alta_vista`, `bantigue`, `bagong_buhay`, etc.
  - All Ormoc City barangays

**Why Preserve:** System configuration needed for order calculations

---

### **10. PICKUP AREA** (`pickup_area` table) - PRESERVE

**Purpose:** Pickup locations where customers collect orders

**Key Columns:**
- `id` (UUID, PRIMARY KEY)
- `name` (VARCHAR, NOT NULL) - Location name
- `address`, `street`, `sitio`, `barangay`, `city`, `province`
- `map_link`, `landmark`, `instructions`
- `active` (BOOLEAN) - Only one should be active
- `created_at`, `updated_at` (TIMESTAMP)

**Why Preserve:** System configuration for pickup orders

---

### **11. SYSTEM DATA** (`system_data` table) - PRESERVE

**Purpose:** System settings and cooperative time synchronization

**Key Columns:**
- `id` (TEXT, PRIMARY KEY) - Row identifier (e.g., 'coopTime', 'contactSupport')
- `epoch_ms` (BIGINT) - Timestamp in milliseconds
- `iso` (TEXT) - ISO 8601 formatted timestamp
- `weekday` (INTEGER) - Day of week (1=Mon..7=Sun)
- `source` (TEXT) - Source identifier
- `server_ts` (BIGINT) - Server timestamp
- `support_email` (TEXT) - Support email address
- `support_phone` (TEXT) - Support phone number
- `updated_at` (BIGINT)

**Why Preserve:** Critical system settings and time synchronization

---

### **12. DELIVERY ADDRESSES** (`delivery_addresses` table) - AUTO-CLEARED

**Purpose:** Customer saved delivery addresses

**Key Columns:**
- `id` (UUID, PRIMARY KEY)
- `customer_id` (TEXT, FOREIGN KEY) - References customers(uid) ON DELETE CASCADE
- `address`, `label`
- `is_default` (BOOLEAN)
- `created_at`, `updated_at` (BIGINT)

**Why Auto-Clear:** Automatically deleted when customers are deleted (CASCADE)

---

### **13. CHAT MESSAGES** (`chat_messages` table) - OPTIONAL CLEAR

**Purpose:** Customer-staff and customer-rider chat conversations

**Stored in:** Supabase + Firebase Realtime Database

**Why Optional:** Can be cleared to remove test conversations

---

## 🔑 **ID BEHAVIOR AFTER CLEARING**

### **Auto-Incrementing IDs (RESET to 1):**
- `farmers.id` (BIGSERIAL) - Resets to 1 with script

### **Text-Based IDs (Continue with new unique values):**
- `orders.id` - Timestamp-based (e.g., 1732633845123456789)
- `customers.uid` - Firebase Auth UID / UUID
- `riders.uid` - UUID
- `staff.uuid` - UUID
- `delivery_orders.id` - TEXT-based

---

## 📊 **STATISTICS BEHAVIOR**

### **Reset to 0 (accounts deleted):**
- Customer `total_orders` and `total_spent`
- Rider `total_deliveries`
- Global order count and sales amount

### **Preserved (can reset manually):**
- Product `sold_quantity` and `current_reserved`

---

## 💾 **SUPABASE STORAGE BUCKETS** (NOT deleted by script)

Files in these buckets are preserved unless manually deleted:
- `product-images` - Product photos
- `id-photos` - User ID verification photos
- `profile-pictures` - User profile photos
- `delivery-proof` - Proof of delivery images
- `rated_media` - Order rating media
- `gcash-receipts` - Payment receipts
- `refund-receipts` - Refund proof
- `featured-display` - Featured product images
- `product-videos` - Product videos
- `customerconvo-uploads` - Chat attachments

---

## 🎯 **USAGE FOR EVALUATION TESTING**

1. **Run the clear script** (`clear_test_data_for_evaluation.sql`)
2. **Result:**
   - ✅ All orders, sales, and transactions removed
   - ✅ All test user accounts removed
   - ✅ Admin accounts preserved
   - ✅ Product catalog preserved
   - ✅ System configuration preserved
3. **Ready for:** Fresh evaluation data entry

---

## ⚠️ **CRITICAL REMINDERS**

1. **ALWAYS** backup before running clear scripts
2. **NEVER** delete the `admins` table
3. **VERIFY** admin accounts exist after clearing: `SELECT * FROM admins;`
4. **OPTIONAL:** Reset product statistics if needed
5. **MANUAL:** Clear Firebase Realtime Database data separately (chat, notifications)

