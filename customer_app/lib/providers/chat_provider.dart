import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

import '../models/customer.dart';
import '../services/supabase_service.dart';

class ChatMessage {
  final String id;
  final String conversationId;
  final String sender; // 'customer', 'staff', or 'rider'
  final String text;
  final DateTime timestamp;
  final String customerId;
  final String? staffId;
  final String? staffName;
  final String? staffDisplayName;
  final String? riderId;
  final String? riderName;
  final String chatType; // 'staff' or 'rider'
  final bool isRead;
  final String? imageUrl; // URL for image messages
  final String? videoUrl; // URL for video messages

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.customerId,
    this.staffId,
    this.staffName,
    this.staffDisplayName,
    this.riderId,
    this.riderName,
    this.chatType = 'staff',
    this.isRead = false,
    this.imageUrl,
    this.videoUrl,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> data, String id) {
    // CRITICAL: Normalize timestamp to ensure consistent ordering
    // Handle various timestamp formats: number, string, or null
    int timestampMs = 0;
    if (data['timestamp'] != null) {
      if (data['timestamp'] is int) {
        timestampMs = data['timestamp'] as int;
      } else if (data['timestamp'] is String) {
        timestampMs = int.tryParse(data['timestamp']) ?? 0;
      } else if (data['timestamp'] is double) {
        timestampMs = (data['timestamp'] as double).toInt();
      } else {
        // Try createdAt as fallback
        final createdAt = data['createdAt'];
        if (createdAt is int) {
          timestampMs = createdAt;
        } else if (createdAt is String) {
          timestampMs = int.tryParse(createdAt) ?? 0;
        }
      }
    }
    // If timestamp is still 0 or invalid, use current time
    if (timestampMs <= 0) {
      timestampMs = DateTime.now().millisecondsSinceEpoch;
    }
    
    return ChatMessage(
      id: id,
      conversationId: data['conversationId'] ?? '',
      sender: data['sender'] ?? '',
      text: data['text'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      customerId: data['customerId'] ?? '',
      staffId: data['staffId'],
      staffName: data['staffName'],
      staffDisplayName: data['staffDisplayName'] ?? data['staff_display_name'],
      riderId: data['riderId'],
      riderName: data['riderName'],
      chatType: data['chatType'] ?? 'staff',
      isRead: data['isRead'] ?? false,
      imageUrl: data['imageUrl'],
      videoUrl: data['videoUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'conversationId': conversationId,
      'sender': sender,
      'text': text,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'customerId': customerId,
      'staffId': staffId,
      'staffName': staffName,
      'staffDisplayName': staffDisplayName,
      'riderId': riderId,
      'riderName': riderName,
      'chatType': chatType,
      'isRead': isRead,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
    };
  }
}

class ChatConversation {
  final String id;
  final String customerId;
  final String customerName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageSender;
  final int unreadCount;
  final DateTime updatedAt;
  final String chatType; // 'staff' or 'rider'
  final String? riderId;
  final String? riderName;
  final bool isArchived;
  final String? supabaseConversationUuid;

  ChatConversation({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSender,
    this.unreadCount = 0,
    required this.updatedAt,
    this.chatType = 'staff',
    this.riderId,
    this.riderName,
    this.isArchived = false,
    this.supabaseConversationUuid,
  });
}

class ChatProvider with ChangeNotifier {
  SupabaseClient? _supabase;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _conversationsChannel;
  
  List<ChatMessage> _messages = [];
  List<ChatConversation> _conversations = [];
  List<ChatConversation> _archivedConversations = [];
  List<ChatConversation> _allConversations = [];
  final Set<String> _archivedConversationIds = {};
  final Set<String> _deletedConversationIds = {};
  final Map<String, String> _conversationUuidMap = {};
  String? _currentCustomerId;
  Customer? _currentCustomer;
  String? _selectedConversationId;
  bool _isLoading = false;
  String? _error;

  List<ChatMessage> get messages => _messages;
  List<ChatConversation> get conversations => _conversations;
  List<ChatConversation> get archivedConversations => _archivedConversations;
  String? get currentCustomerId => _currentCustomerId;
  String? get selectedConversationId => _selectedConversationId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get messages for current conversation
  List<ChatMessage> get currentConversationMessages {
    if (_selectedConversationId == null) {
      // If no conversation selected, return empty list (don't auto-show messages)
      return [];
    }
    // Filter messages by conversationId OR customerId (for compatibility)
    // This ensures messages are shown even if conversationId doesn't match exactly
    return _messages.where((msg) {
      // Primary check: message conversationId matches selected conversationId
      if (msg.conversationId == _selectedConversationId) {
        return true;
      }
      // Fallback: For staff conversations, if selected conversation is customer ID,
      // show messages where conversationId OR customerId matches customer ID
      if (_selectedConversationId == _currentCustomerId) {
        return (msg.conversationId == _currentCustomerId || 
                msg.customerId == _currentCustomerId);
      }
      // Additional fallback: if message customerId matches selected conversationId
      if (msg.customerId == _selectedConversationId) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // Get unread message count
  int get unreadMessageCount {
    return _messages.where((msg) => msg.sender == 'staff' && !msg.isRead).length;
  }

  // Get unread count for a specific conversation (staff messages only)
  int getUnreadCountForConversation(String conversationId) {
    return _messages.where((msg) => msg.conversationId == conversationId && msg.sender == 'staff' && !msg.isRead).length;
  }

  void _markLocalStaffMessagesAsRead(String conversationId) {
    bool changed = false;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.conversationId == conversationId && m.sender == 'staff' && !m.isRead) {
        _messages[i] = ChatMessage(
          id: m.id,
          conversationId: m.conversationId,
          sender: m.sender,
          text: m.text,
          timestamp: m.timestamp,
          customerId: m.customerId,
          staffId: m.staffId,
          staffName: m.staffName,
          riderId: m.riderId,
          riderName: m.riderName,
          chatType: m.chatType,
          isRead: true,
          imageUrl: m.imageUrl,
          videoUrl: m.videoUrl,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // Refresh messages manually
  Future<void> refreshMessages() async {
    debugPrint('🔄 Manually refreshing messages...');
    await _loadMessagesFromSupabase();
  }

  // Test function to create a test message (for debugging)
  Future<void> createTestMessage() async {
    if (_currentCustomerId == null) return;
    await sendMessage('Test message from customer app');
  }

  // Initialize chat for customer
  Future<void> initializeChat(String customerId) async {
    _currentCustomerId = customerId;
    _error = null;
    _isLoading = false;
    
    // Clear existing data
    await _ensureSupabaseClient();
    _messages.clear();
    _conversations.clear();
    _archivedConversations.clear();
    _allConversations.clear();
    _archivedConversationIds.clear();
    _deletedConversationIds.clear();
    _selectedConversationId = null;
    
    await _startListeningForMessages();
    await loadConversations();
    await _loadMessagesFromSupabase();
    
    notifyListeners();
  }

  // Manually load messages as a fallback
  Future<void> _loadMessagesFromSupabase() async {
    if (_currentCustomerId == null) return;
    final supabase = await _ensureSupabaseClient();
    final riderPattern = '${_currentCustomerId!}_rider_%';
    final response = await supabase
        .from('chat_messages')
        .select('*')
        .or('customer_id.eq.${_currentCustomerId},customer_id.like.$riderPattern')
        .order('timestamp', ascending: true);
    final rows = (response as List).cast<Map<String, dynamic>>();
    _messages = rows.map(_mapSupabaseMessage).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _isLoading = false;
        notifyListeners();
  }

  Future<void> _startListeningForMessages() async {
    if (_currentCustomerId == null) return;
    _isLoading = true;
    notifyListeners();
    await _loadMessagesFromSupabase();
    final supabase = await _ensureSupabaseClient();
    _messagesChannel?.unsubscribe();
    final pattern = '${_currentCustomerId!}%';
    _messagesChannel = supabase
        .channel('customer-chat-${_currentCustomerId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            try {
              final data = payload.newRecord ?? payload.oldRecord;
              final customerKey = data?['customer_id']?.toString();
              if (customerKey == null ||
                  !(customerKey == _currentCustomerId ||
                      customerKey.startsWith('${_currentCustomerId!}_rider_'))) {
                return;
              }
              
              if (payload.newRecord != null) {
                debugPrint('📨 Real-time message received: ${payload.newRecord!['message_id']} from ${payload.newRecord!['sender']}');
                final message = _mapSupabaseMessage(
                    Map<String, dynamic>.from(payload.newRecord!));
                _upsertLocalMessage(message);
                
                // If message is from staff/rider, reload conversations to update unread count
                if (message.sender == 'staff' || message.sender == 'rider') {
                  // Reload conversations to get updated unread count from database
                  loadConversations();
                  
                  // If conversation is currently selected, mark as read
                  if (_selectedConversationId != null &&
                      (message.conversationId == _selectedConversationId ||
                       message.customerId == _selectedConversationId ||
                       (_selectedConversationId == _currentCustomerId && 
                        (message.conversationId == _currentCustomerId || message.customerId == _currentCustomerId)))) {
                    // Mark as read immediately since conversation is open
                    _markMessagesAsRead(_selectedConversationId!);
                  }
                }
              } else if (payload.oldRecord != null &&
                  payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord!['message_id']?.toString();
                if (id != null) {
                  _messages.removeWhere((m) => m.id == id);
                  notifyListeners();
                }
              }
            } catch (e) {
              debugPrint('❌ Error processing real-time message: $e');
            }
          },
        )
        .subscribe();
  }

  // Load conversations for the customer
  Future<void> loadConversations() async {
    if (_currentCustomerId == null) return;
    final rows = await _fetchConversationsFromSupabase();
    _applyConversationRows(rows);
    final supabase = await _ensureSupabaseClient();
    _conversationsChannel?.unsubscribe();
    final filter = '${_currentCustomerId!}%';
    _conversationsChannel = supabase
        .channel('customer-conversations-${_currentCustomerId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) async {
            final data = payload.newRecord ?? payload.oldRecord;
            final customerKey = data?['customer_id']?.toString();
            if (customerKey == null ||
                !(customerKey == _currentCustomerId ||
                    customerKey.startsWith('${_currentCustomerId!}_rider_'))) {
      return;
    }
            final updated = await _fetchConversationsFromSupabase();
            _applyConversationRows(updated);
          },
        )
        .subscribe();
  }

  // Select a conversation and load its messages
  void selectConversation(String? conversationId) {
    if (conversationId == null || conversationId.isEmpty) {
      debugPrint('🎯 Clearing conversation selection');
      _selectedConversationId = null;
      notifyListeners();
      return;
    }
    debugPrint('🎯 Selecting conversation: $conversationId');
    _selectedConversationId = conversationId;
    // For flat structure, use customerId as conversationId
    final actualConversationId = conversationId.isEmpty ? _currentCustomerId : conversationId;
    debugPrint('🎯 Actual conversation ID: $actualConversationId');
    if (actualConversationId != null) {
      _loadMessages(actualConversationId);
      _markMessagesAsRead(actualConversationId);
      _markLocalStaffMessagesAsRead(actualConversationId);
      // Reload conversations to update unread count from database
      loadConversations();
    }
    notifyListeners();
  }

  // Load messages for a conversation
  void _loadMessages(String conversationId) {
    // Don't cancel the global listener, just filter messages for this conversation
    // The global listener in _startListeningForMessages will handle all messages
    // This method is kept for compatibility but the real work is done by _startListeningForMessages
  }

  // Archive a conversation
  Future<void> archiveConversation(String conversationId) async {
    final supabase = await _ensureSupabaseClient();
    await supabase
        .from('conversations')
        .update({'archived': true, 'updated_at': DateTime.now().toIso8601String()})
        .eq('customer_id', conversationId);
      _archivedConversationIds.add(conversationId);
      _updateConversationLists();
        notifyListeners();
      }

  Future<void> deleteConversation(String conversationId) async {
    final supabase = await _ensureSupabaseClient();
    final now = DateTime.now().toIso8601String();
    
    // Check if admin has already deleted this conversation
    final conversationData = await supabase
        .from('conversations')
        .select('deleted_by_admin')
        .eq('customer_id', conversationId)
        .single() as Map<String, dynamic>?;
    
    final deletedByAdmin = conversationData?['deleted_by_admin'] == true;
    
    // If both admin and customer have deleted, permanently delete from database
    if (deletedByAdmin) {
      // Both deleted - permanently delete
      await supabase.from('chat_messages').delete().eq('customer_id', conversationId);
      await supabase.from('conversations').delete().eq('customer_id', conversationId);
    } else {
      // Only customer deleted - soft delete (set deleted_by_customer flag)
      await supabase
          .from('conversations')
          .update({
            'deleted_by_customer': true,
            'deleted_by_customer_at': now,
            'updated_at': now,
          })
          .eq('customer_id', conversationId);
    }
    
    _archivedConversationIds.remove(conversationId);
    _deletedConversationIds.add(conversationId);
    _allConversations.removeWhere((conv) => conv.id == conversationId);
    _messages.removeWhere((msg) => msg.conversationId == conversationId);
    if (_selectedConversationId == conversationId) {
      _selectedConversationId = null;
    }
    _updateConversationLists();
    notifyListeners();
  }

  Future<void> unarchiveConversation(String conversationId) async {
    final supabase = await _ensureSupabaseClient();
    await supabase
        .from('conversations')
        .update({'archived': false, 'updated_at': DateTime.now().toIso8601String()})
        .eq('customer_id', conversationId);
      _archivedConversationIds.remove(conversationId);
      _updateConversationLists();
      notifyListeners();
  }

  // Send a message
  Future<bool> sendMessage(String text,
      {String? chatType,
      String? riderId,
      String? riderName,
      String? imageUrl,
      String? videoUrl}) async {
    if (_currentCustomerId == null || (text.trim().isEmpty && imageUrl == null && videoUrl == null)) {
      return false;
    }

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final supabase = await _ensureSupabaseClient();
      final actualChatType = chatType ?? 'staff';
      final conversationKey = (actualChatType == 'rider' && riderId != null)
          ? '${_currentCustomerId!}_rider_$riderId'
          : _currentCustomerId!;
      final conversationUuid = await _ensureConversation(conversationKey,
          chatType: actualChatType, riderId: riderId, riderName: riderName);
      if (conversationUuid == null) {
        throw Exception('Unable to create conversation');
      }

      var messageText = text.trim();
      if (messageText.isEmpty && (imageUrl != null || videoUrl != null)) {
        messageText = imageUrl != null ? '📷 Image' : '🎥 Video';
      }
      
      final now = DateTime.now().toIso8601String();
      final messageId = _generateUuid();
      final payload = <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationUuid,
        'customer_id': conversationKey,
        'sender': 'customer',
        'text': messageText,
        'timestamp': now,
        'created_at': now,
        'is_read': false,
      };

      if (imageUrl != null && imageUrl.isNotEmpty) {
        payload['image_url'] = imageUrl;
      }
      if (videoUrl != null && videoUrl.isNotEmpty) {
        payload['video_url'] = videoUrl;
      }
      if (riderId != null && riderId.isNotEmpty) {
        payload['rider_id'] = riderId;
      }
      if (riderName != null && riderName.isNotEmpty) {
        payload['rider_name'] = riderName;
      }

      await supabase.from('chat_messages').insert(payload);

      await supabase
          .from('conversations')
          .update({
            'last_message': messageText,
            'last_message_sender': 'customer',
            'last_message_time': now,
            'updated_at': now,
            'unread_count': 0,
          })
          .eq('customer_id', conversationKey);

      await _loadMessagesFromSupabase();
      await loadConversations();

      return true;
    } catch (e) {
      _error = 'Failed to send message: $e';
      debugPrint('Error sending message: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> createRiderConversation(String riderId, String riderName) async {
    if (_currentCustomerId == null) return null;
      final conversationId = '${_currentCustomerId!}_rider_$riderId';
    await _ensureConversation(conversationId,
        chatType: 'rider', riderId: riderId, riderName: riderName);
      return conversationId;
  }

  // Set current customer
  void setCurrentCustomer(Customer customer) {
    _currentCustomer = customer;
    _currentCustomerId = customer.uid;
    notifyListeners();
  }

  // Get current customer name
  String _getCurrentCustomerName() {
    if (_currentCustomer != null) {
      return _currentCustomer!.fullName.isNotEmpty 
          ? _currentCustomer!.fullName 
          : '${_currentCustomer!.firstName} ${_currentCustomer!.lastName}'.trim();
    }
    return 'Customer';
  }

  Future<void> _markMessagesAsRead(String conversationId) async {
    final supabase = await _ensureSupabaseClient();
    final now = DateTime.now().toIso8601String();
    await supabase
        .from('chat_messages')
        .update({'is_read': true})
        .eq('customer_id', conversationId)
        .or('sender.eq.staff,sender.eq.rider');
    await supabase
        .from('conversations')
        .update({'unread_count': 0, 'updated_at': now})
        .eq('customer_id', conversationId);
    
    // Update local conversation cache to reflect unread count change
    final convIndex = _allConversations.indexWhere((c) => c.id == conversationId);
    if (convIndex >= 0) {
      final conv = _allConversations[convIndex];
      _allConversations[convIndex] = ChatConversation(
        id: conv.id,
        customerId: conv.customerId,
        customerName: conv.customerName,
        lastMessage: conv.lastMessage,
        lastMessageTime: conv.lastMessageTime,
        lastMessageSender: conv.lastMessageSender,
        unreadCount: 0, // Reset unread count
        updatedAt: DateTime.now(), // Update timestamp
        chatType: conv.chatType,
        riderId: conv.riderId,
        riderName: conv.riderName,
        isArchived: conv.isArchived,
      );
      _updateConversationLists();
      notifyListeners();
    }
  }

  // Create a new conversation (if it doesn't exist)
  Future<String?> createConversation() async {
    if (_currentCustomerId == null) return null;
    await _ensureConversation(_currentCustomerId!);
    return _currentCustomerId!;
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Reset chat provider
  void reset() {
    _messages.clear();
    _conversations.clear();
    _archivedConversations.clear();
    _allConversations.clear();
    _archivedConversationIds.clear();
    _deletedConversationIds.clear();
    _selectedConversationId = null;
    _isLoading = false;
    _error = null;
    _messagesChannel?.unsubscribe();
    _conversationsChannel?.unsubscribe();
    _messagesChannel = null;
    _conversationsChannel = null;
    _archivedConversationIds.clear();
    _deletedConversationIds.clear();
    _archivedConversations.clear();
    _allConversations.clear();
    notifyListeners();
  }

  // Dispose
  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _conversationsChannel?.unsubscribe();
    super.dispose();
  }

  void _updateConversationLists({bool shouldNotify = true}) {
    _conversations = _allConversations
        .where((c) => !_archivedConversationIds.contains(c.id) && !_deletedConversationIds.contains(c.id))
        .toList()
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    _archivedConversations = _allConversations
        .where((c) => _archivedConversationIds.contains(c.id) && !_deletedConversationIds.contains(c.id))
        .toList()
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    if (shouldNotify) {
      notifyListeners();
    }
  }

  void _startArchivedConversationsListener() {}

  void _startDeletedConversationsListener() {}

  Future<SupabaseClient> _ensureSupabaseClient() async {
    if (_supabase != null) return _supabase!;
    await SupabaseService.initialize();
    _supabase = SupabaseService.client;
    return _supabase!;
  }

  Future<List<Map<String, dynamic>>> _fetchConversationsFromSupabase() async {
    if (_currentCustomerId == null) return [];
    final supabase = await _ensureSupabaseClient();
    final riderPattern = '${_currentCustomerId!}_rider_%';
    final response = await supabase
        .from('conversations')
        .select('*')
        .or('customer_id.eq.${_currentCustomerId},customer_id.like.$riderPattern')
        .order('updated_at', ascending: false);
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  void _applyConversationRows(List<Map<String, dynamic>> rows) {
    final parsed = rows.map(_mapSupabaseConversation).toList();
    _allConversations = parsed;
    _conversationUuidMap
      ..clear()
      ..addEntries(rows.map((row) {
        final key = row['customer_id']?.toString() ?? '';
        final uuid = row['conversation_id']?.toString() ?? '';
        return MapEntry(key, uuid);
      }).where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty));
    _archivedConversationIds
      ..clear()
      ..addAll(parsed.where((c) => c.isArchived).map((c) => c.id));
      _updateConversationLists();
    notifyListeners();
  }

  ChatConversation _mapSupabaseConversation(Map<String, dynamic> row) {
    final customerKey = row['customer_id']?.toString() ?? '';
    final baseCustomerId = customerKey.contains('_rider_')
        ? customerKey.split('_rider_').first
        : customerKey;
    return ChatConversation(
      id: customerKey,
      customerId: baseCustomerId,
      customerName: row['customer_name']?.toString() ?? '',
      lastMessage: row['last_message']?.toString() ?? '',
      lastMessageTime: _parseSupabaseDate(row['last_message_time']),
      lastMessageSender: row['last_message_sender']?.toString() ?? '',
      unreadCount: _parseInt(row['unread_count']),
      updatedAt: _parseSupabaseDate(row['updated_at']),
      chatType: row['chat_type']?.toString() ?? 'staff',
      riderId: row['rider_id']?.toString(),
      riderName: row['rider_name']?.toString(),
      isArchived: row['archived'] == true,
      supabaseConversationUuid: row['conversation_id']?.toString(),
    );
  }

  ChatMessage _mapSupabaseMessage(Map<String, dynamic> data) {
    final timestamp = _parseSupabaseDate(data['timestamp']);
    final conversationId = data['customer_id']?.toString() ?? '';
    
    // Determine chat type from conversation ID or data
    String chatType = 'staff';
    if (conversationId.contains('_rider_')) {
      chatType = 'rider';
    } else {
      chatType = data['chat_type']?.toString() ?? 'staff';
    }
    
    return ChatMessage(
      id: data['message_id']?.toString() ??
          data['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: conversationId,
      sender: data['sender']?.toString() ?? '',
      text: data['text']?.toString() ?? '',
      timestamp: timestamp,
      customerId: conversationId,
      staffId: data['staff_id']?.toString(),
      staffName: data['staff_name']?.toString() ??
          data['staff_display_name']?.toString(),
      staffDisplayName: data['staff_display_name']?.toString() ??
          data['staffDisplayName']?.toString(),
      riderId: data['rider_id']?.toString(),
      riderName: data['rider_name']?.toString(),
      chatType: chatType,
      isRead: data['is_read'] == true,
      imageUrl: data['image_url']?.toString(),
      videoUrl: data['video_url']?.toString(),
    );
  }

  DateTime _parseSupabaseDate(dynamic value) {
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

  Future<String?> _ensureConversation(String conversationId,
      {String chatType = 'staff', String? riderId, String? riderName}) async {
    try {
      if (_conversationUuidMap.containsKey(conversationId)) {
        final cached = _conversationUuidMap[conversationId];
        if (cached != null && cached.isNotEmpty) return cached;
      }
      final supabase = await _ensureSupabaseClient();
      final existing = await supabase
          .from('conversations')
          .select('*')
          .eq('customer_id', conversationId)
          .maybeSingle();
      if (existing != null) {
        final row = Map<String, dynamic>.from(existing as Map);
        final uuid = row['conversation_id']?.toString();
        if (uuid != null) {
          _conversationUuidMap[conversationId] = uuid;
          return uuid;
        }
      }

      final payload = <String, dynamic>{
        'customer_id': conversationId,
        'customer_name': _getCurrentCustomerName(),
        'chat_type': chatType,
        'last_message': null, // NULL instead of empty string for new conversations
        'last_message_sender': null, // NULL instead of empty string - check constraint requires NULL or valid value
        'last_message_time': DateTime.now().toIso8601String(),
        'unread_count': 0,
        'updated_at': DateTime.now().toIso8601String(),
        'archived': false,
      };

      // Only add rider fields if this is a rider conversation
      if (chatType == 'rider' && riderId != null && riderId.isNotEmpty) {
        payload['rider_id'] = riderId;
      }
      if (chatType == 'rider' && riderName != null && riderName.isNotEmpty) {
        payload['rider_name'] = riderName;
      }

      // For staff conversations, don't set staff_id to avoid foreign key constraint violations
      // The staff_id should be null or set by the staff dashboard when they respond

      final inserted = await supabase
          .from('conversations')
          .upsert(payload, onConflict: 'customer_id')
          .select()
          .maybeSingle();
      if (inserted != null) {
        final uuid = inserted['conversation_id']?.toString();
        if (uuid != null) {
          _conversationUuidMap[conversationId] = uuid;
          return uuid;
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error ensuring conversation: $e');
      // If there's a foreign key constraint error, try to get existing conversation
      if (e.toString().contains('23514') || e.toString().contains('foreign key')) {
        try {
          final supabase = await _ensureSupabaseClient();
          final existing = await supabase
              .from('conversations')
              .select('*')
              .eq('customer_id', conversationId)
              .maybeSingle();
          if (existing != null) {
            final row = Map<String, dynamic>.from(existing as Map);
            final uuid = row['conversation_id']?.toString();
            if (uuid != null) {
              _conversationUuidMap[conversationId] = uuid;
              return uuid;
            }
          }
        } catch (retryError) {
          debugPrint('❌ Error retrying conversation fetch: $retryError');
        }
      }
      rethrow;
    }
  }

  void _upsertLocalMessage(ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    final wasNew = index < 0;
    if (index >= 0) {
      _messages[index] = message;
    } else {
      _messages.add(message);
    }
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    // If this is a new message and matches the currently selected conversation, notify immediately
    if (wasNew && _selectedConversationId != null) {
      final matchesCurrentConversation = message.conversationId == _selectedConversationId ||
          message.customerId == _selectedConversationId ||
          (_selectedConversationId == _currentCustomerId && 
           (message.conversationId == _currentCustomerId || message.customerId == _currentCustomerId));
      
      if (matchesCurrentConversation) {
        debugPrint('📨 New message received for current conversation: ${message.id}');
        notifyListeners();
        return;
      }
    }
    
    notifyListeners();
  }

  String _generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    String _byteToHex(int byte) =>
        byte.toRadixString(16).padLeft(2, '0');
    return '${_byteToHex(bytes[0])}${_byteToHex(bytes[1])}${_byteToHex(bytes[2])}${_byteToHex(bytes[3])}-'
        '${_byteToHex(bytes[4])}${_byteToHex(bytes[5])}-'
        '${_byteToHex(bytes[6])}${_byteToHex(bytes[7])}-'
        '${_byteToHex(bytes[8])}${_byteToHex(bytes[9])}-'
        '${_byteToHex(bytes[10])}${_byteToHex(bytes[11])}${_byteToHex(bytes[12])}${_byteToHex(bytes[13])}${_byteToHex(bytes[14])}${_byteToHex(bytes[15])}';
  }
}
