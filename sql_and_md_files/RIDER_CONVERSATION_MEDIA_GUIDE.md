# Rider Conversation Media Sharing Guide

This guide explains how to implement image and video sharing between riders and customers in the chat system.

## Overview

The system uses Supabase Storage bucket `rider_conversation` to store images and videos shared in chat conversations. The `chat_messages` table has been extended with columns to support media files.

## Database Setup

### 1. Storage Bucket

- **Bucket Name**: `rider_conversation`
- **Public Access**: Yes (no authentication required)
- **File Size Limit**: 50MB
- **Allowed MIME Types**:
  - Images: `image/jpeg`, `image/jpg`, `image/png`, `image/gif`, `image/webp`
  - Videos: `video/mp4`, `video/quicktime`, `video/x-msvideo`, `video/webm`

### 2. Storage Policies

All policies are set to **public** (no authentication required):
- **View**: Anyone can view files
- **Insert**: Anyone can upload files
- **Update**: Anyone can update files
- **Delete**: Anyone can delete files

### 3. Database Columns Added

The `chat_messages` table now includes:

| Column | Type | Description |
|--------|------|-------------|
| `image_url` | TEXT | URL to image file in storage |
| `video_url` | TEXT | URL to video file in storage |
| `thumbnail_url` | TEXT | URL to video thumbnail (optional) |
| `message_type` | TEXT | Type: 'text', 'image', 'video', or 'mixed' |
| `file_name` | TEXT | Original filename |
| `file_size` | BIGINT | File size in bytes |
| `mime_type` | TEXT | MIME type (e.g., 'image/jpeg', 'video/mp4') |

## File Path Structure

Recommended file path structure in the bucket:
```
rider_conversation/
  ├── {conversation_id}/
  │   ├── images/
  │   │   └── {message_id}_{timestamp}.{ext}
  │   └── videos/
  │       └── {message_id}_{timestamp}.{ext}
```

Example:
```
rider_conversation/
  ├── customer123_rider_rider456/
  │   ├── images/
  │   │   └── msg_abc123_1734567890.jpg
  │   └── videos/
  │       └── msg_def456_1734567900.mp4
```

## Implementation Steps

### 1. Run SQL Setup

Execute `rider_conversation_storage_setup.sql` in Supabase SQL Editor to:
- Create the storage bucket
- Set up storage policies
- Add required columns to `chat_messages` table

### 2. Update Flutter Models

#### RiderChatMessage (delivery_app)

Add fields to support media:
```dart
class RiderChatMessage {
  // ... existing fields ...
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? messageType; // 'text', 'image', 'video', 'mixed'
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
}
```

### 3. Upload Files

#### Example: Upload Image

```dart
Future<String?> uploadImage(File imageFile, String conversationId, String messageId) async {
  try {
    final supabase = SupabaseService.client;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = imageFile.path.split('.').last;
    final fileName = '${messageId}_$timestamp.$extension';
    final filePath = '$conversationId/images/$fileName';
    
    // Upload file
    await supabase.storage
        .from('rider_conversation')
        .upload(filePath, imageFile);
    
    // Get public URL
    final url = supabase.storage
        .from('rider_conversation')
        .getPublicUrl(filePath);
    
    return url;
  } catch (e) {
    debugPrint('Error uploading image: $e');
    return null;
  }
}
```

#### Example: Upload Video

```dart
Future<Map<String, String>?> uploadVideo(
  File videoFile, 
  String conversationId, 
  String messageId
) async {
  try {
    final supabase = SupabaseService.client;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = videoFile.path.split('.').last;
    final fileName = '${messageId}_$timestamp.$extension';
    final filePath = '$conversationId/videos/$fileName';
    
    // Upload video
    await supabase.storage
        .from('rider_conversation')
        .upload(filePath, videoFile);
    
    // Get public URL
    final videoUrl = supabase.storage
        .from('rider_conversation')
        .getPublicUrl(filePath);
    
    // Generate thumbnail (you'll need to implement this)
    // For now, return null for thumbnail
    final thumbnailUrl = null; // TODO: Generate thumbnail
    
    return {
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl ?? '',
    };
  } catch (e) {
    debugPrint('Error uploading video: $e');
    return null;
  }
}
```

### 4. Save Message with Media

```dart
Future<bool> sendImageMessage(String conversationKey, File imageFile) async {
  try {
    final messageId = _generateUuid();
    final conversationUuid = await _ensureConversationForCustomer(
      conversationKey: conversationKey,
      customerName: customerName,
    );
    
    // Upload image
    final imageUrl = await uploadImage(imageFile, conversationKey, messageId);
    if (imageUrl == null) {
      throw Exception('Failed to upload image');
    }
    
    // Get file info
    final fileSize = await imageFile.length();
    final mimeType = 'image/${imageFile.path.split('.').last}';
    
    // Save message to database
    final nowIso = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'message_id': messageId,
      'conversation_id': conversationUuid,
      'customer_id': conversationKey,
      'sender': 'rider',
      'text': '', // Empty for image-only messages
      'image_url': imageUrl,
      'message_type': 'image',
      'file_name': imageFile.path.split('/').last,
      'file_size': fileSize,
      'mime_type': mimeType,
      'timestamp': nowIso,
      'created_at': nowIso,
      'is_read': false,
      'rider_id': _riderId,
      'rider_name': _riderName ?? 'Rider',
    };
    
    await supabase.from('chat_messages').insert(payload);
    
    // Update conversation last message
    await supabase
        .from('conversations')
        .update({
          'last_message': '📷 Image',
          'last_message_sender': 'rider',
          'last_message_time': nowIso,
          'updated_at': nowIso,
        })
        .eq('customer_id', conversationKey);
    
    return true;
  } catch (e) {
    debugPrint('Error sending image message: $e');
    return false;
  }
}
```

### 5. Display Media in UI

#### Display Image

```dart
Widget _buildImageMessage(String imageUrl) {
  return GestureDetector(
    onTap: () {
      // Show full-screen image viewer
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FullScreenImageViewer(imageUrl: imageUrl),
        ),
      );
    },
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: 200,
            height: 200,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 200,
            color: Colors.grey[300],
            child: Icon(Icons.error),
          );
        },
      ),
    ),
  );
}
```

#### Display Video

```dart
Widget _buildVideoMessage(String videoUrl, String? thumbnailUrl) {
  return GestureDetector(
    onTap: () {
      // Show video player
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(videoUrl: videoUrl),
        ),
      );
    },
    child: Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (thumbnailUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                thumbnailUrl,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          Icon(
            Icons.play_circle_filled,
            color: Colors.white,
            size: 64,
          ),
        ],
      ),
    ),
  );
}
```

## Security Considerations

⚠️ **Note**: The current setup uses **public access** (no authentication). This means:
- Anyone with the URL can access files
- Files are not protected by user authentication
- Consider implementing authentication if sensitive data is shared

### Alternative: Authenticated Access

If you want to restrict access, modify the policies:

```sql
-- Allow authenticated users only
CREATE POLICY "Authenticated view rider_conversation"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'rider_conversation');
```

## File Cleanup

Consider implementing automatic cleanup for old files:
- Delete files older than X days
- Delete files when conversation is deleted
- Implement storage quota limits per user

## Testing

1. Upload a test image from rider app
2. Verify it appears in customer app
3. Upload a test video from customer app
4. Verify it appears in rider app
5. Test file size limits (try uploading >50MB file)
6. Test invalid file types

## Troubleshooting

### Files not uploading
- Check bucket exists: `SELECT * FROM storage.buckets WHERE id = 'rider_conversation';`
- Verify policies: `SELECT * FROM pg_policies WHERE tablename = 'objects' AND policyname LIKE '%rider_conversation%';`
- Check file size is under 50MB
- Verify MIME type is allowed

### Files not displaying
- Verify URLs are correct
- Check if bucket is public
- Test URL in browser directly
- Check CORS settings if needed

### Database errors
- Verify columns exist: `SELECT column_name FROM information_schema.columns WHERE table_name = 'chat_messages';`
- Check data types match

