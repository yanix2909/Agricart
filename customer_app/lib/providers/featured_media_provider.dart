import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

enum FeaturedMediaType { image, video }

class FeaturedMediaItem {
  final String url;
  final FeaturedMediaType type;
  final String? id;

  FeaturedMediaItem({
    required this.url,
    required this.type,
    this.id,
  });
}

class FeaturedMediaProvider with ChangeNotifier {
  List<FeaturedMediaItem> _featuredMedia = [];
  bool _isLoading = false;
  String? _error;

  List<FeaturedMediaItem> get featuredMedia => List.unmodifiable(_featuredMedia);
  bool get isLoading => _isLoading;
  String? get error => _error;

  FeaturedMediaProvider() {
    loadFeaturedMedia();
  }

  Future<void> loadFeaturedMedia() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await SupabaseService.initialize();

      const bucketName = 'featured_display';
      final client = SupabaseService.client;

      // List all files in the bucket
      // Note: list() returns List<FileObject> directly, not a response object
      final List<dynamic> files;
      try {
        files = await client.storage
            .from(bucketName)
            .list();
      } catch (e) {
        throw Exception('Failed to list files: $e');
      }

      if (files.isEmpty) {
        _featuredMedia = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Filter and categorize media
      final List<FeaturedMediaItem> mediaItems = [];
      
      for (final file in files) {
        // Access file properties - file is FileObject from storage_client
        final fileName = (file as dynamic).name?.toString() ?? '';
        final fileId = (file as dynamic).id?.toString();
        
        if (fileName.isEmpty || fileName == '.emptyFolderPlaceholder') continue;
        
        final fileNameLower = fileName.toLowerCase();
        final isImage = fileNameLower.endsWith('.jpg') || 
                       fileNameLower.endsWith('.jpeg') || 
                       fileNameLower.endsWith('.png') || 
                       fileNameLower.endsWith('.gif') || 
                       fileNameLower.endsWith('.webp') ||
                       fileNameLower.endsWith('.bmp') ||
                       fileNameLower.endsWith('.svg');
        
        final isVideo = fileNameLower.endsWith('.mp4') || 
                       fileNameLower.endsWith('.mov') || 
                       fileNameLower.endsWith('.avi') || 
                       fileNameLower.endsWith('.webm') ||
                       fileNameLower.endsWith('.mkv') ||
                       fileNameLower.endsWith('.flv') ||
                       fileNameLower.endsWith('.wmv');

        if (isImage || isVideo) {
          // Get public URL
          final publicUrl = client.storage
              .from(bucketName)
              .getPublicUrl(fileName);

          mediaItems.add(FeaturedMediaItem(
            url: publicUrl,
            type: isImage ? FeaturedMediaType.image : FeaturedMediaType.video,
            id: fileId,
          ));
        }
      }

      // Sort: images first, then videos, and limit to 8 images + 2 videos
      final images = mediaItems.where((m) => m.type == FeaturedMediaType.image).take(8).toList();
      final videos = mediaItems.where((m) => m.type == FeaturedMediaType.video).take(2).toList();
      
      _featuredMedia = [...images, ...videos];
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading featured media: $e');
      _error = e.toString();
      _isLoading = false;
      _featuredMedia = [];
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadFeaturedMedia();
  }
}

