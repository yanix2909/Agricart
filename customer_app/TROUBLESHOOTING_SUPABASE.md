# Troubleshooting Supabase Image Upload Issues

## Error: "Failed to upload ID photos. Please try again."

If you're encountering this error during customer registration, follow these steps:

### Step 1: Check Console Logs

Look at the Flutter debug console for detailed error messages. The logs will show:
- `=== Supabase Upload Debug ===` - Upload attempt details
- `=== Supabase Upload Error ===` - Specific error information

### Step 2: Verify Supabase Configuration

1. **Check Credentials** (in `lib/services/supabase_service.dart`):
   ```dart
   static const String _supabaseUrl = 'YOUR_SUPABASE_URL';
   static const String _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
   ```
   - Make sure both are replaced with actual values from Supabase Dashboard > Settings > API
   - URL should be: `https://your-project-id.supabase.co`
   - Anon key should be a long string starting with `eyJ...`

2. **Test Credentials**:
   - Open Supabase Dashboard
   - Go to Settings > API
   - Verify the URL and anon key match what's in the code

### Step 3: Verify Bucket Exists

1. In Supabase Dashboard, go to **Storage**
2. Check if bucket `customerid_image` exists
3. If not:
   - Click **New Bucket**
   - Name: `customerid_image`
   - Make it **Public** (uncheck "Private bucket")
   - Click **Create bucket**

### Step 4: Check Storage Policies

1. In Supabase Dashboard, go to **Storage > Policies**
2. Select the `customerid_image` bucket
3. Ensure these policies exist:
   - **SELECT** policy: Allow public access
   - **INSERT** policy: Allow public access
   - **UPDATE** policy: Allow public access
   - **DELETE** policy: Allow public access

4. **OR** run the SQL script:
   - Go to **SQL Editor** in Supabase Dashboard
   - Run the SQL from `supabase_policies.sql`

### Step 5: Test Bucket Permissions

1. In Supabase Dashboard > Storage
2. Try uploading a test file manually to `customerid_image` bucket
3. If manual upload fails, check:
   - Bucket is public
   - Storage policies are correct
   - Your Supabase project is active

### Step 6: Check Network/Connection

- Ensure the device has internet connection
- Verify the Supabase URL is accessible
- Check if there are any firewall/network restrictions

### Step 7: Verify File Access

The logs will show if the file exists:
- `File exists: true` - File is accessible
- `File exists: false` - File path is incorrect

If file doesn't exist:
- Check file permissions on the device
- Verify the image picker is working correctly

## Common Error Messages

### "Supabase credentials not configured"
- **Fix**: Set `_supabaseUrl` and `_supabaseAnonKey` in `supabase_service.dart`

### "Supabase bucket 'customerid_image' not found"
- **Fix**: Create the bucket in Supabase Dashboard > Storage

### "Permission denied" or "policy" error
- **Fix**: Set up storage policies (run `supabase_policies.sql` or configure manually)

### "Network error" or "connection" error
- **Fix**: Check internet connection and Supabase project status

### "File does not exist"
- **Fix**: Check image picker permissions and file handling

## Testing After Fixes

1. Clear the app data/cache
2. Restart the app
3. Try registering a new account
4. Check console logs for detailed error messages
5. If still failing, share the console error logs for further diagnosis

## Additional Debugging

To see even more detailed logs, check:
- Flutter debug console output
- Look for `=== Supabase Upload Debug ===` sections
- Share the complete error stack trace for analysis

