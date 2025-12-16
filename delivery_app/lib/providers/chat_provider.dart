import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../services/supabase_service.dart';
import '../utils/rider_session.dart';

/// Rider ↔ customer chat message (Supabase-backed, no Firebase).
class RiderChatMessage {
  final String id; // message_id
  final String conversationKey; // customer_id in Supabase (e.g. customerId_rider_riderId)
  final String sender; // 'rider' or 'customer'
  final String text;
  final DateTime timestamp;
  final String customerId;
  final String? riderId;
  final String? riderName;
  final bool isRead;
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? messageType; // 'text', 'image', 'video', 'mixed'
  final String? fileName;
  final int? fileSize;
  final String? mimeType;

  RiderChatMessage({
    required this.id,
    required this.conversationKey,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.customerId,
    this.riderId,
    this.riderName,
    this.isRead = false,
    this.imageUrl,
    this.videoUrl,
    this.thumbnailUrl,
    this.messageType,
    this.fileName,
    this.fileSize,
    this.mimeType,
  });

  factory RiderChatMessage.fromSupabaseRow(Map<String, dynamic> row) {
    final customerKey = row['customer_id']?.toString() ?? '';
    final baseCustomerId = customerKey.contains('_rider_')
        ? customerKey.split('_rider_').first
        : customerKey;

    DateTime ts;
    final rawTs = row['timestamp'];
    if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else {
      ts = DateTime.now();
    }

    return RiderChatMessage(
      id: row['message_id']?.toString() ??
          row['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      conversationKey: customerKey,
      sender: row['sender']?.toString() ?? '',
      text: row['text']?.toString() ?? '',
      timestamp: ts,
      customerId: baseCustomerId,
      riderId: row['rider_id']?.toString(),
      riderName: row['rider_name']?.toString(),
      isRead: row['is_read'] == true,
      imageUrl: row['image_url']?.toString(),
      videoUrl: row['video_url']?.toString(),
      thumbnailUrl: row['thumbnail_url']?.toString(),
      messageType: row['message_type']?.toString() ?? 'text',
      fileName: row['file_name']?.toString(),
      fileSize: row['file_size'] != null ? (row['file_size'] is int ? row['file_size'] as int : int.tryParse(row['file_size'].toString())) : null,
      mimeType: row['mime_type']?.toString(),
    );
  }
}

/// Rider ↔ customer conversation (Supabase-backed).
class RiderChatConversation {
  final String id; // customer_id key (e.g. customerId_rider_riderId)
  final String customerId;
  final String customerName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageSender;
  final int unreadCount; // unread messages for rider (from customer)
  final DateTime updatedAt;
  final String? riderId;
  final String? riderName;
  final bool isArchived;

  RiderChatConversation({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSender,
    required this.unreadCount,
    required this.updatedAt,
    required this.riderId,
    required this.riderName,
    required this.isArchived,
  });

  factory RiderChatConversation.fromSupabaseRow(Map<String, dynamic> row) {
    final customerKey = row['customer_id']?.toString() ?? '';
    final baseCustomerId = customerKey.contains('_rider_')
        ? customerKey.split('_rider_').first
        : customerKey;

    DateTime _parseDate(dynamic value) {
      if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
        final maybeInt = int.tryParse(value);
        if (maybeInt != null) {
          return DateTime.fromMillisecondsSinceEpoch(maybeInt);
        }
      }
      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      return DateTime.now();
    }

    int _parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      if (value is double) return value.toInt();
      return 0;
    }

    return RiderChatConversation(
      id: customerKey,
      customerId: baseCustomerId,
      customerName: row['customer_name']?.toString() ?? '',
      lastMessage: row['last_message']?.toString() ?? '',
      lastMessageTime: _parseDate(row['last_message_time']),
      lastMessageSender: row['last_message_sender']?.toString() ?? '',
      unreadCount: _parseInt(row['unread_count']),
      updatedAt: _parseDate(row['updated_at']),
      riderId: row['rider_id']?.toString(),
      riderName: row['rider_name']?.toString(),
      isArchived: row['archived'] == true,
    );
  }
}

class RiderChatProvider with ChangeNotifier {
  SupabaseClient? _supabase;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _conversationsChannel;

  String? _riderId;
  String? _riderName;

  final Map<String, String> _conversationUuidMap = {}; // customer_key -> conversation_id (uuid)

  List<RiderChatMessage> _messages = [];
  List<RiderChatConversation> _conversations = [];
  List<RiderChatConversation> _archivedConversations = [];
  List<RiderChatConversation> _allConversations = [];

  String? _selectedConversationId; // customer_id key
  bool _isLoading = false;
  String? _error;

  List<RiderChatConversation> get conversations => _conversations;
  List<RiderChatConversation> get archivedConversations => _archivedConversations;
  List<RiderChatConversation> get allConversations => _allConversations;
  List<RiderChatMessage> get currentMessages =>
      _selectedConversationId == null
          ? []
          : (_messages
                .where((m) => m.conversationKey == _selectedConversationId)
                .toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
  String? get selectedConversationId => _selectedConversationId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Upload progress tracking
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  double get uploadProgress => _uploadProgress;
  bool get isUploading => _isUploading;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Set rider info before initialize (allows pre-selection of conversations)
  void setRiderInfo(String riderId, String? riderName) {
    _riderId = riderId;
    _riderName = riderName;
  }

  Future<SupabaseClient> _ensureSupabaseClient() async {
    if (_supabase != null) return _supabase!;
    if (!SupabaseService.isInitialized) {
      await SupabaseService.initialize();
    }
    _supabase = SupabaseService.client;
    return _supabase!;
  }

  Future<void> initialize() async {
    // Only set rider ID if not already set (allows pre-selection from orders screen)
    if (_riderId == null) {
      _riderId = await RiderSession.getId();
      _riderName = await RiderSession.getName();
    }

    if (_riderId == null || _riderId!.isEmpty) {
      _error = 'Rider not logged in';
      notifyListeners();
      return;
    }

    final preservedConversationId = _selectedConversationId;

    _messages.clear();
    _conversations.clear();
    _archivedConversations.clear();
    _allConversations.clear();
    _conversationUuidMap.clear();
    _error = null;
    _isLoading = true;
    notifyListeners();

    if (preservedConversationId != null) {
      _selectedConversationId = preservedConversationId;
    }

    try {
      await _ensureSupabaseClient();
      await _loadConversationsFromSupabase();
      await _loadMessagesFromSupabase();
      _startRealtimeListeners();
    } catch (e) {
      _error = 'Failed to initialize chat: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadConversationsFromSupabase() async {
    final supabase = await _ensureSupabaseClient();
    // At this point initialize() has ensured _riderId is non-null
    final riderId = _riderId!;
    final rows = await supabase
        .from('conversations')
        .select('*')
        .eq('chat_type', 'rider')
        .eq('rider_id', riderId)
        .order('updated_at', ascending: false);

    final list = (rows as List)
        .map((row) =>
            RiderChatConversation.fromSupabaseRow(Map<String, dynamic>.from(row as Map)))
        .toList();

    // Update customer names for conversations that have "Customer" as name
    for (var conv in list) {
      if (conv.customerName.isEmpty || conv.customerName.toLowerCase() == 'customer') {
        final actualName = await _fetchCustomerName(conv.customerId);
        if (actualName.isNotEmpty && actualName.toLowerCase() != 'customer') {
          // Update in database
          try {
            await supabase
                .from('conversations')
                .update({'customer_name': actualName})
                .eq('customer_id', conv.id);
            
            // Update in local list
            final index = list.indexOf(conv);
            if (index >= 0) {
              list[index] = RiderChatConversation(
                id: conv.id,
                customerId: conv.customerId,
                customerName: actualName,
                lastMessage: conv.lastMessage,
                lastMessageTime: conv.lastMessageTime,
                lastMessageSender: conv.lastMessageSender,
                unreadCount: conv.unreadCount,
                updatedAt: conv.updatedAt,
                riderId: conv.riderId,
                riderName: conv.riderName,
                isArchived: conv.isArchived,
              );
            }
          } catch (e) {
            debugPrint('Error updating customer name for conversation ${conv.id}: $e');
          }
        }
      }
    }

    _allConversations = list;

    _conversationUuidMap
      ..clear()
      ..addEntries((rows as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        final key = map['customer_id']?.toString() ?? '';
        final uuid = map['conversation_id']?.toString() ?? '';
        return MapEntry(key, uuid);
      }).where((e) => e.key.isNotEmpty && e.value.isNotEmpty));

    _updateConversationLists();
  }

  Future<void> _loadMessagesFromSupabase() async {
    final supabase = await _ensureSupabaseClient();
    final riderId = _riderId!;
    final rows = await supabase
        .from('chat_messages')
        .select('*')
        .eq('rider_id', riderId)
        .order('timestamp', ascending: true);

    _messages = (rows as List)
        .map((row) =>
            RiderChatMessage.fromSupabaseRow(Map<String, dynamic>.from(row as Map)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void _startRealtimeListeners() async {
    final supabase = await _ensureSupabaseClient();

    _messagesChannel?.unsubscribe();
    _messagesChannel = supabase
        .channel('rider-chat-messages-$_riderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            final data = payload.newRecord ?? payload.oldRecord;
            if (data == null) return;
            final map = Map<String, dynamic>.from(data);
            if (map['rider_id']?.toString() != _riderId) return;

            if (payload.eventType == PostgresChangeEvent.delete) {
              final id = map['message_id']?.toString();
              if (id != null) {
                _messages.removeWhere((m) => m.id == id);
                notifyListeners();
              }
              return;
            }

            final msg = RiderChatMessage.fromSupabaseRow(map);
            final index = _messages.indexWhere((m) => m.id == msg.id);
            if (index >= 0) {
              _messages[index] = msg;
            } else {
              _messages.add(msg);
            }
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            notifyListeners();
          },
        )
        .subscribe();

    _conversationsChannel?.unsubscribe();
    _conversationsChannel = supabase
        .channel('rider-chat-conversations-$_riderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) async {
            final data = payload.newRecord ?? payload.oldRecord;
            if (data == null) return;
            final riderKey = data['rider_id']?.toString();
            final chatType = data['chat_type']?.toString();
            if (riderKey != _riderId || chatType != 'rider') return;

            await _loadConversationsFromSupabase();
            notifyListeners();
          },
        )
        .subscribe();
  }

  void _updateConversationLists() {
    _conversations = _allConversations
        .where((c) => !c.isArchived)
        .toList()
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    _archivedConversations = _allConversations
        .where((c) => c.isArchived)
        .toList()
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
  }

  void selectConversation(String? conversationId) {
    _selectedConversationId = conversationId;
    if (conversationId != null) {
      _markCustomerMessagesAsRead(conversationId);
      
      // Verify customer is active when selecting conversation
      final baseCustomerId = conversationId.contains('_rider_')
          ? conversationId.split('_rider_').first
          : conversationId;
      _isCustomerActive(baseCustomerId).then((isActive) {
        if (!isActive) {
          _error = 'This customer account has been deactivated or removed. Chat is not available.';
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  Future<void> _markCustomerMessagesAsRead(String conversationKey) async {
    try {
      final supabase = await _ensureSupabaseClient();
      
      // Mark customer messages as read
      await supabase
          .from('chat_messages')
          .update({'is_read': true})
          .eq('customer_id', conversationKey)
          .eq('sender', 'customer');
      
      // Update unread_count to 0 in conversations table
      await supabase
          .from('conversations')
          .update({'unread_count': 0})
          .eq('customer_id', conversationKey);
      
      // Update local conversation cache
      final convIndex = _allConversations.indexWhere((c) => c.id == conversationKey);
      if (convIndex >= 0) {
        final conv = _allConversations[convIndex];
        _allConversations[convIndex] = RiderChatConversation(
          id: conv.id,
          customerId: conv.customerId,
          customerName: conv.customerName,
          lastMessage: conv.lastMessage,
          lastMessageTime: conv.lastMessageTime,
          lastMessageSender: conv.lastMessageSender,
          unreadCount: 0, // Reset unread count
          updatedAt: conv.updatedAt,
          riderId: conv.riderId,
          riderName: conv.riderName,
          isArchived: conv.isArchived,
        );
        _updateConversationLists();
        notifyListeners();
      }
    } catch (_) {
      // Best-effort; ignore errors
    }
  }

  /// Fetch customer name from customers table
  Future<String> _fetchCustomerName(String customerId) async {
    try {
      final supabase = await _ensureSupabaseClient();
      final customerRow = await supabase
          .from('customers')
          .select('full_name')
          .eq('uid', customerId)
          .maybeSingle();

      if (customerRow != null && customerRow.isNotEmpty) {
        final fullName = customerRow['full_name']?.toString() ?? '';
        if (fullName.isNotEmpty && fullName.toLowerCase() != 'customer') {
          return fullName;
        }
      }
    } catch (e) {
      debugPrint('Error fetching customer name: $e');
    }
    return 'Customer';
  }

  /// Ensure a Supabase conversation row exists for this rider ↔ customer pair.
  Future<String?> _ensureConversationForCustomer({
    required String conversationKey,
    required String customerName,
  }) async {
    if (_conversationUuidMap.containsKey(conversationKey) &&
        _conversationUuidMap[conversationKey]!.isNotEmpty) {
      return _conversationUuidMap[conversationKey];
    }

    final supabase = await _ensureSupabaseClient();

    final existing = await supabase
        .from('conversations')
        .select('*')
        .eq('customer_id', conversationKey)
        .maybeSingle();

    final now = DateTime.now().toIso8601String();
    
    // Extract base customer ID to fetch actual name if needed
    final baseCustomerId = conversationKey.contains('_rider_')
        ? conversationKey.split('_rider_').first
        : conversationKey;
    
    // If provided customerName is generic or empty, fetch actual name from customers table
    String finalCustomerName = customerName;
    if (customerName.isEmpty || customerName.toLowerCase() == 'customer') {
      finalCustomerName = await _fetchCustomerName(baseCustomerId);
    }
    
    // If conversation exists, update customer_name if provided name is better
    if (existing != null) {
      final row = Map<String, dynamic>.from(existing as Map);
      final uuid = row['conversation_id']?.toString();
      final existingName = row['customer_name']?.toString() ?? '';
      
      // Update customer_name if the provided name is better (not "Customer" and not empty)
      if (uuid != null && uuid.isNotEmpty) {
        _conversationUuidMap[conversationKey] = uuid;
        
        // Update customer_name if current name is generic or empty, and we have a better name
        if ((existingName.isEmpty || existingName.toLowerCase() == 'customer') &&
            finalCustomerName.isNotEmpty && finalCustomerName.toLowerCase() != 'customer') {
          await supabase
              .from('conversations')
              .update({
                'customer_name': finalCustomerName,
                'updated_at': now,
              })
              .eq('customer_id', conversationKey);
          
          // Update local conversation cache if it exists
          final convIndex = _allConversations.indexWhere((c) => c.id == conversationKey);
          if (convIndex >= 0) {
            final conv = _allConversations[convIndex];
            _allConversations[convIndex] = RiderChatConversation(
              id: conv.id,
              customerId: conv.customerId,
              customerName: finalCustomerName,
              lastMessage: conv.lastMessage,
              lastMessageTime: conv.lastMessageTime,
              lastMessageSender: conv.lastMessageSender,
              unreadCount: conv.unreadCount,
              updatedAt: conv.updatedAt,
              riderId: conv.riderId,
              riderName: conv.riderName,
              isArchived: conv.isArchived,
            );
            _updateConversationLists();
            notifyListeners();
          }
        }
        
        return uuid;
      }
    }

    // Create new conversation if it doesn't exist
    final payload = <String, dynamic>{
      'customer_id': conversationKey,
      'customer_name': finalCustomerName,
      'chat_type': 'rider',
      'rider_id': _riderId,
      'rider_name': _riderName ?? 'Rider',
      'last_message': null,
      'last_message_sender': null,
      'last_message_time': now,
      'unread_count': 0,
      'updated_at': now,
      'archived': false,
    };

    final inserted = await supabase
        .from('conversations')
        .upsert(payload, onConflict: 'customer_id')
        .select()
        .maybeSingle();

    if (inserted != null) {
      final uuid = inserted['conversation_id']?.toString();
      if (uuid != null && uuid.isNotEmpty) {
        _conversationUuidMap[conversationKey] = uuid;
        return uuid;
      }
    }

    return null;
  }

  /// Check if customer account is active
  Future<bool> _isCustomerActive(String customerId) async {
    try {
      final supabase = await _ensureSupabaseClient();
      final customerRow = await supabase
          .from('customers')
          .select('uid, status')
          .eq('uid', customerId)
          .maybeSingle();

      if (customerRow == null || customerRow.isEmpty) {
        return false;
      }

      final status = customerRow['status']?.toString().toLowerCase();
      return status == 'active';
    } catch (_) {
      // If check fails, assume inactive to be safe
      return false;
    }
  }

  /// Open (or create) a conversation when rider taps "Chat with customer" from orders.
  Future<String?> openConversationForCustomer({
    required String customerId,
    required String customerName,
  }) async {
    if (_riderId == null || _riderId!.isEmpty) {
      _riderId = await RiderSession.getId();
      _riderName = await RiderSession.getName();
      if (_riderId == null || _riderId!.isEmpty) return null;
    }

    // Verify customer is active before opening conversation
    final isActive = await _isCustomerActive(customerId);
    if (!isActive) {
      _error = 'This customer account has been deactivated or removed. Chat is not available.';
      notifyListeners();
      return null;
    }

    final conversationKey = '${customerId}_rider_${_riderId!}';

    try {
      await _ensureConversationForCustomer(
        conversationKey: conversationKey,
        customerName: customerName,
      );
      return conversationKey;
    } catch (e) {
      _error = 'Failed to open conversation: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (_selectedConversationId == null || trimmed.isEmpty) return false;

    try {
      final conversationKey = _selectedConversationId!;

      // Extract base customer ID from key
      final baseCustomerId = conversationKey.contains('_rider_')
          ? conversationKey.split('_rider_').first
          : conversationKey;

      // Verify customer is still active before sending message
      final isActive = await _isCustomerActive(baseCustomerId);
      if (!isActive) {
        _error = 'Cannot send message: This customer account has been deactivated or removed.';
        notifyListeners();
        return false;
      }

      // Try to preserve any existing friendly customer name from conversations list
      String customerDisplayName = baseCustomerId;
      final existingConv =
          _allConversations.firstWhere((c) => c.id == conversationKey, orElse: () => null as RiderChatConversation);
      if (existingConv != null && existingConv.customerName.isNotEmpty && existingConv.customerName.toLowerCase() != 'customer') {
        customerDisplayName = existingConv.customerName;
      } else {
        // If no good name found, fetch from customers table
        customerDisplayName = await _fetchCustomerName(baseCustomerId);
      }

      final supabase = await _ensureSupabaseClient();
      final conversationUuid = await _ensureConversationForCustomer(
        conversationKey: conversationKey,
        customerName: customerDisplayName,
      );

      if (conversationUuid == null) {
        throw Exception('Unable to create conversation');
      }

      final nowIso = DateTime.now().toIso8601String();
      // Use a proper UUID for message_id to match customer app schema expectations
      final messageId = _generateUuid();

      final payload = <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationUuid,
        'customer_id': conversationKey,
        'sender': 'rider',
        'text': trimmed,
        'timestamp': nowIso,
        'created_at': nowIso,
        'is_read': false,
        'rider_id': _riderId,
        'rider_name': _riderName ?? 'Rider',
      };

      await supabase.from('chat_messages').insert(payload);

      await supabase
          .from('conversations')
          .update({
            'last_message': trimmed,
            'last_message_sender': 'rider',
            'last_message_time': nowIso,
            'updated_at': nowIso,
          })
          .eq('customer_id', conversationKey);

      // Update local cache immediately for snappy UI
      final messageTimestamp = DateTime.parse(nowIso);
      final localMessage = RiderChatMessage(
        id: messageId,
        conversationKey: conversationKey,
        sender: 'rider',
        text: trimmed,
        timestamp: messageTimestamp,
        customerId: baseCustomerId,
        riderId: _riderId,
        riderName: _riderName,
        isRead: false,
      );
      
      // Remove any existing message with same ID (shouldn't happen, but safety check)
      _messages.removeWhere((m) => m.id == messageId);
      
      // Add new message
      _messages.add(localMessage);
      
      // Sort messages by timestamp to ensure proper order (oldest to newest)
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Notify listeners so UI updates
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to send: $e';
      notifyListeners();
      return false;
    }
  }

  /// Compress image before upload
  Future<File?> _compressImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return imageFile;

      // Resize if image is too large (max 1920x1920)
      img.Image resized = image;
      if (image.width > 1920 || image.height > 1920) {
        resized = img.copyResize(image, width: 1920, height: 1920, maintainAspect: true);
      }

      // Compress JPEG quality (85% quality)
      final compressedBytes = img.encodeJpg(resized, quality: 85);
      
      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final compressedFile = File('${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await compressedFile.writeAsBytes(compressedBytes);
      
      return compressedFile;
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return imageFile; // Return original if compression fails
    }
  }

  /// Generate video thumbnail
  Future<String?> _generateVideoThumbnail(String videoPath) async {
    try {
      final thumbnail = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 75,
      );
      return thumbnail;
    } catch (e) {
      debugPrint('Error generating video thumbnail: $e');
      return null;
    }
  }

  /// Upload file to Supabase storage
  Future<String?> _uploadFile(File file, String conversationKey, String messageId, String fileType) async {
    try {
      final supabase = await _ensureSupabaseClient();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = file.path.split('.').last.toLowerCase();
      final fileName = '${messageId}_$timestamp.$extension';
      final folder = fileType == 'image' ? 'images' : 'videos';
      final filePath = '$conversationKey/$folder/$fileName';

      // Upload with progress tracking
      _isUploading = true;
      _uploadProgress = 0.0;
      notifyListeners();

      await supabase.storage
          .from('rider_conversation')
          .upload(filePath, file);

      _uploadProgress = 1.0;
      notifyListeners();

      // Get public URL
      final url = supabase.storage
          .from('rider_conversation')
          .getPublicUrl(filePath);

      _isUploading = false;
      _uploadProgress = 0.0;
      notifyListeners();

      return url;
    } catch (e) {
      _isUploading = false;
      _uploadProgress = 0.0;
      _error = 'Failed to upload file: $e';
      notifyListeners();
      debugPrint('Error uploading file: $e');
      return null;
    }
  }

  /// Upload video thumbnail
  Future<String?> _uploadThumbnail(File thumbnailFile, String conversationKey, String messageId) async {
    try {
      final supabase = await _ensureSupabaseClient();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$conversationKey/thumbnails/${messageId}_thumb_$timestamp.jpg';

      await supabase.storage
          .from('rider_conversation')
          .upload(filePath, thumbnailFile);

      final url = supabase.storage
          .from('rider_conversation')
          .getPublicUrl(filePath);

      return url;
    } catch (e) {
      debugPrint('Error uploading thumbnail: $e');
      return null;
    }
  }

  /// Validate file size (max 50MB)
  bool _validateFileSize(File file, {int maxSizeBytes = 52428800}) {
    final size = file.lengthSync();
    return size <= maxSizeBytes;
  }

  /// Send image message
  Future<bool> sendImageMessage(File imageFile, {String? caption, DateTime? timestamp}) async {
    if (_selectedConversationId == null) return false;

    try {
      final conversationKey = _selectedConversationId!;

      // Extract base customer ID from key
      final baseCustomerId = conversationKey.contains('_rider_')
          ? conversationKey.split('_rider_').first
          : conversationKey;

      // Verify customer is still active
      final isActive = await _isCustomerActive(baseCustomerId);
      if (!isActive) {
        _error = 'Cannot send message: This customer account has been deactivated or removed.';
        notifyListeners();
        return false;
      }

      // Validate file size
      if (!_validateFileSize(imageFile)) {
        _error = 'Image file is too large. Maximum size is 50MB.';
        notifyListeners();
        return false;
      }

      // Compress image
      final compressedFile = await _compressImage(imageFile);
      if (compressedFile == null) {
        _error = 'Failed to process image';
        notifyListeners();
        return false;
      }

      // Get customer name for conversation
      String customerDisplayName = baseCustomerId;
      final existingConv =
          _allConversations.firstWhere((c) => c.id == conversationKey, orElse: () => null as RiderChatConversation);
      if (existingConv != null && existingConv.customerName.isNotEmpty && existingConv.customerName.toLowerCase() != 'customer') {
        customerDisplayName = existingConv.customerName;
      } else {
        customerDisplayName = await _fetchCustomerName(baseCustomerId);
      }

      final supabase = await _ensureSupabaseClient();
      final conversationUuid = await _ensureConversationForCustomer(
        conversationKey: conversationKey,
        customerName: customerDisplayName,
      );

      if (conversationUuid == null) {
        throw Exception('Unable to create conversation');
      }

      final now = timestamp ?? DateTime.now();
      final nowIso = now.toIso8601String();
      final messageId = _generateUuid();

      // Upload image
      final imageUrl = await _uploadFile(compressedFile, conversationKey, messageId, 'image');
      if (imageUrl == null) {
        throw Exception('Failed to upload image');
      }

      // Get file info
      final fileSize = await compressedFile.length();
      final mimeType = 'image/${compressedFile.path.split('.').last}';

      // Save message to database
      final payload = <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationUuid,
        'customer_id': conversationKey,
        'sender': 'rider',
        'text': caption ?? '',
        'image_url': imageUrl,
        'message_type': caption != null && caption.isNotEmpty ? 'mixed' : 'image',
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
            'last_message': caption != null && caption.isNotEmpty ? caption : '📷 Image',
            'last_message_sender': 'rider',
            'last_message_time': nowIso,
            'updated_at': nowIso,
          })
          .eq('customer_id', conversationKey);

      // Update local cache
      final messageTimestamp = DateTime.parse(nowIso);
      final localMessage = RiderChatMessage(
        id: messageId,
        conversationKey: conversationKey,
        sender: 'rider',
        text: caption ?? '',
        timestamp: messageTimestamp,
        customerId: baseCustomerId,
        riderId: _riderId,
        riderName: _riderName,
        isRead: false,
        imageUrl: imageUrl,
        messageType: caption != null && caption.isNotEmpty ? 'mixed' : 'image',
        fileName: imageFile.path.split('/').last,
        fileSize: fileSize,
        mimeType: mimeType,
      );

      _messages.removeWhere((m) => m.id == messageId);
      _messages.add(localMessage);
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to send image: $e';
      notifyListeners();
      return false;
    }
  }

  /// Send video message
  Future<bool> sendVideoMessage(File videoFile, {String? caption, DateTime? timestamp}) async {
    if (_selectedConversationId == null) return false;

    try {
      final conversationKey = _selectedConversationId!;

      // Extract base customer ID from key
      final baseCustomerId = conversationKey.contains('_rider_')
          ? conversationKey.split('_rider_').first
          : conversationKey;

      // Verify customer is still active
      final isActive = await _isCustomerActive(baseCustomerId);
      if (!isActive) {
        _error = 'Cannot send message: This customer account has been deactivated or removed.';
        notifyListeners();
        return false;
      }

      // Validate file size
      if (!_validateFileSize(videoFile)) {
        _error = 'Video file is too large. Maximum size is 50MB.';
        notifyListeners();
        return false;
      }

      // Get customer name for conversation
      String customerDisplayName = baseCustomerId;
      final existingConv =
          _allConversations.firstWhere((c) => c.id == conversationKey, orElse: () => null as RiderChatConversation);
      if (existingConv != null && existingConv.customerName.isNotEmpty && existingConv.customerName.toLowerCase() != 'customer') {
        customerDisplayName = existingConv.customerName;
      } else {
        customerDisplayName = await _fetchCustomerName(baseCustomerId);
      }

      final supabase = await _ensureSupabaseClient();
      final conversationUuid = await _ensureConversationForCustomer(
        conversationKey: conversationKey,
        customerName: customerDisplayName,
      );

      if (conversationUuid == null) {
        throw Exception('Unable to create conversation');
      }

      final now = timestamp ?? DateTime.now();
      final nowIso = now.toIso8601String();
      final messageId = _generateUuid();

      // Generate thumbnail
      String? thumbnailUrl;
      final thumbnailPath = await _generateVideoThumbnail(videoFile.path);
      if (thumbnailPath != null) {
        final thumbnailFile = File(thumbnailPath);
        thumbnailUrl = await _uploadThumbnail(thumbnailFile, conversationKey, messageId);
      }

      // Upload video
      final videoUrl = await _uploadFile(videoFile, conversationKey, messageId, 'video');
      if (videoUrl == null) {
        throw Exception('Failed to upload video');
      }

      // Get file info
      final fileSize = await videoFile.length();
      final mimeType = 'video/${videoFile.path.split('.').last}';

      // Save message to database
      final payload = <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationUuid,
        'customer_id': conversationKey,
        'sender': 'rider',
        'text': caption ?? '',
        'video_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'message_type': caption != null && caption.isNotEmpty ? 'mixed' : 'video',
        'file_name': videoFile.path.split('/').last,
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
            'last_message': caption != null && caption.isNotEmpty ? caption : '🎥 Video',
            'last_message_sender': 'rider',
            'last_message_time': nowIso,
            'updated_at': nowIso,
          })
          .eq('customer_id', conversationKey);

      // Update local cache
      final messageTimestamp = DateTime.parse(nowIso);
      final localMessage = RiderChatMessage(
        id: messageId,
        conversationKey: conversationKey,
        sender: 'rider',
        text: caption ?? '',
        timestamp: messageTimestamp,
        customerId: baseCustomerId,
        riderId: _riderId,
        riderName: _riderName,
        isRead: false,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        messageType: caption != null && caption.isNotEmpty ? 'mixed' : 'video',
        fileName: videoFile.path.split('/').last,
        fileSize: fileSize,
        mimeType: mimeType,
      );

      _messages.removeWhere((m) => m.id == messageId);
      _messages.add(localMessage);
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to send video: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> archiveConversation(String conversationKey) async {
    try {
      final supabase = await _ensureSupabaseClient();
      final now = DateTime.now().toIso8601String();
      await supabase
          .from('conversations')
          .update({'archived': true, 'updated_at': now})
          .eq('customer_id', conversationKey);

      _allConversations = _allConversations
          .map((c) => c.id == conversationKey
              ? RiderChatConversation(
                  id: c.id,
                  customerId: c.customerId,
                  customerName: c.customerName,
                  lastMessage: c.lastMessage,
                  lastMessageTime: c.lastMessageTime,
                  lastMessageSender: c.lastMessageSender,
                  unreadCount: c.unreadCount,
                  updatedAt: DateTime.parse(now),
                  riderId: c.riderId,
                  riderName: c.riderName,
                  isArchived: true,
                )
              : c)
          .toList();

      if (_selectedConversationId == conversationKey) {
        _selectedConversationId = null;
      }

      _updateConversationLists();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to archive conversation: $e';
      notifyListeners();
    }
  }

  Future<void> unarchiveConversation(String conversationKey) async {
    try {
      final supabase = await _ensureSupabaseClient();
      final now = DateTime.now().toIso8601String();
      await supabase
          .from('conversations')
          .update({'archived': false, 'updated_at': now})
          .eq('customer_id', conversationKey);

      _allConversations = _allConversations
          .map((c) => c.id == conversationKey
              ? RiderChatConversation(
                  id: c.id,
                  customerId: c.customerId,
                  customerName: c.customerName,
                  lastMessage: c.lastMessage,
                  lastMessageTime: c.lastMessageTime,
                  lastMessageSender: c.lastMessageSender,
                  unreadCount: c.unreadCount,
                  updatedAt: DateTime.parse(now),
                  riderId: c.riderId,
                  riderName: c.riderName,
                  isArchived: false,
                )
              : c)
          .toList();

      _updateConversationLists();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to unarchive conversation: $e';
      notifyListeners();
    }
  }

  Future<void> deleteConversation(String conversationKey) async {
    try {
      final supabase = await _ensureSupabaseClient();

      await supabase.from('chat_messages').delete().eq('customer_id', conversationKey);
      await supabase.from('conversations').delete().eq('customer_id', conversationKey);

      _allConversations.removeWhere((c) => c.id == conversationKey);
      _messages.removeWhere((m) => m.conversationKey == conversationKey);

      if (_selectedConversationId == conversationKey) {
        _selectedConversationId = null;
      }

      _updateConversationLists();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete conversation: $e';
      notifyListeners();
    }
  }

  // Generate UUID v4 (copied from customer app implementation for compatibility)
  String _generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    String byteToHex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    return '${byteToHex(bytes[0])}${byteToHex(bytes[1])}${byteToHex(bytes[2])}${byteToHex(bytes[3])}-'
        '${byteToHex(bytes[4])}${byteToHex(bytes[5])}-'
        '${byteToHex(bytes[6])}${byteToHex(bytes[7])}-'
        '${byteToHex(bytes[8])}${byteToHex(bytes[9])}-'
        '${byteToHex(bytes[10])}${byteToHex(bytes[11])}${byteToHex(bytes[12])}${byteToHex(bytes[13])}${byteToHex(bytes[14])}${byteToHex(bytes[15])}';
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _conversationsChannel?.unsubscribe();
    super.dispose();
  }
}

