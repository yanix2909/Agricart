import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';

class ChatScreen extends StatefulWidget {
  final String? initialConversationId;
  
  const ChatScreen({super.key, this.initialConversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// Helper class to store media items
class _MediaPreviewItem {
  final File file;
  final String type; // 'image' or 'video'
  VideoPlayerController? videoController;
  
  _MediaPreviewItem({
    required this.file,
    required this.type,
    this.videoController,
  });
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _lastAutoScrollConversationId;
  int _lastAutoScrollMessageCount = 0;
  
  // Media preview state - support multiple files
  final List<_MediaPreviewItem> _selectedMedia = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  void _initializeChat() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    if (authProvider.currentCustomer != null) {
      debugPrint('🚀 ChatScreen: Initializing chat for customer: ${authProvider.currentCustomer!.uid}');
      
      // Store the initial conversation ID if provided
      final conversationIdToRestore = widget.initialConversationId ?? chatProvider.selectedConversationId;
      
      // Initialize chat (this will clear selectedConversationId)
      await chatProvider.initializeChat(authProvider.currentCustomer!.uid);
      
      // Restore the conversation selection if we had one
      if (conversationIdToRestore != null && conversationIdToRestore.isNotEmpty) {
        // Wait for conversations to load and retry if needed
        int retries = 0;
        bool conversationFound = false;
        
        while (retries < 15 && !conversationFound) {
          await Future.delayed(const Duration(milliseconds: 200));
          
          // Check if conversation exists in the list
          final allConversations = [
            ...chatProvider.conversations,
            ...chatProvider.archivedConversations,
          ];
          conversationFound = allConversations.any(
            (conv) => conv.id == conversationIdToRestore,
          );
          
          if (conversationFound) {
            debugPrint('🎯 Restoring conversation selection: $conversationIdToRestore');
            chatProvider.selectConversation(conversationIdToRestore);
            // Wait a bit more to ensure messages are loaded
            await Future.delayed(const Duration(milliseconds: 300));
            break;
          }
          
          retries++;
        }
        
        if (!conversationFound) {
          debugPrint('⚠️ Conversation not found after retries: $conversationIdToRestore');
        }
      }
    } else {
      debugPrint('❌ ChatScreen: No current customer found');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scheduleJumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        try {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } catch (_) {
          // Ignore if controller not ready
        }
      } else {
        Future.delayed(const Duration(milliseconds: 60), _scheduleJumpToBottom);
      }
    });
  }

  void _maybeAutoScroll(String? conversationId, int messageCount) {
    if (conversationId == null || messageCount == 0) return;
    final hasConversationChanged = _lastAutoScrollConversationId != conversationId;
    final hasMessagesChanged = _lastAutoScrollMessageCount != messageCount;
    if (hasConversationChanged || hasMessagesChanged) {
      _lastAutoScrollConversationId = conversationId;
      _lastAutoScrollMessageCount = messageCount;
      _scheduleJumpToBottom();
    }
  }

  bool _shouldShowCalcoaSupportButton(ChatProvider chatProvider) {
    // Don't show button if chat is not initialized
    if (chatProvider.currentCustomerId == null) {
      return false;
    }
    
    // Don't show button if a conversation is selected
    if (chatProvider.selectedConversationId != null) {
      return false;
    }
    
    // Don't show button while loading (prevents glitch on initial load)
    if (chatProvider.isLoading) {
      return false;
    }
    
    // Check if there's already a CALCOA Support conversation (staff chat, not rider)
    final allConversations = [
      ...chatProvider.conversations,
      ...chatProvider.archivedConversations,
    ];
    
    // Return false if there's already a staff conversation (CALCOA Support)
    // Return true only if no staff conversation exists and we're not loading
    return !allConversations.any((conversation) => conversation.chatType == 'staff');
  }

  List<ChatConversation> _getFilteredConversations(List<ChatConversation> conversations) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      // Show all conversations (both active and archived) in one display
      return conversations;
    }

    return conversations.where((conversation) {
      final names = <String?>[
        conversation.customerName,
        conversation.customerId,
        conversation.chatType == 'rider' ? conversation.riderName : 'CALCOA Support',
      ];

      for (final name in names) {
        if (name == null) continue;
        if (name.toLowerCase().contains(query)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Widget _buildSearchField({bool isInGreenHeader = false}) {
    return Container(
      height: Responsive.getHeight(context, mobile: 34),
      decoration: BoxDecoration(
        color: isInGreenHeader 
            ? Colors.white
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        boxShadow: isInGreenHeader
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: isInGreenHeader ? Colors.black87 : Colors.black87,
          fontSize: Responsive.getFontSize(context, mobile: 13),
        ),
        decoration: InputDecoration(
          hintText: 'Search conversations',
          hintStyle: TextStyle(
            color: isInGreenHeader 
                ? Colors.grey[600]
                : Colors.grey[600],
            fontSize: Responsive.getFontSize(context, mobile: 13),
          ),
          prefixIcon: Icon(
            Icons.search, 
            color: isInGreenHeader 
                ? AppTheme.primaryColor
                : Colors.grey[600],
            size: Responsive.getIconSize(context, mobile: 18),
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.clear, 
                    color: isInGreenHeader 
                        ? Colors.grey[600]
                        : Colors.grey[600],
                    size: Responsive.getIconSize(context, mobile: 16),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: Responsive.getSpacing(context, mobile: 10),
            vertical: Responsive.getSpacing(context, mobile: 6),
          ),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }



  Future<void> _confirmDelete(BuildContext context, ChatProvider chatProvider, String conversationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This will permanently delete this conversation and all its messages. '
          'This action cannot be undone. The conversation will be completely removed from the database.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await chatProvider.deleteConversation(conversationId);
    }
  }

  Future<bool> _sendMessage({String? text, String? imageUrl, String? videoUrl}) async {
    final messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty && imageUrl == null && videoUrl == null) return false;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    // Check if chat is properly initialized
    if (chatProvider.currentCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat not initialized. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Get current conversation to determine chat type
    final currentConversation = chatProvider.conversations.firstWhere(
      (conv) => conv.id == chatProvider.selectedConversationId,
      orElse: () => chatProvider.conversations.isNotEmpty ? chatProvider.conversations.first : ChatConversation(
        id: '',
        customerId: '',
        customerName: '',
        lastMessage: '',
        lastMessageTime: DateTime.now(),
        lastMessageSender: '',
        updatedAt: DateTime.now(),
      ),
    );
    
    final success = await chatProvider.sendMessage(
      messageText,
      chatType: currentConversation.chatType,
      riderId: currentConversation.riderId,
      riderName: currentConversation.riderName,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
    );
    
    if (success) {
      if (text == null) {
        _messageController.clear();
      }
      _scrollToBottom();
      return true;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<String?> _uploadToSupabase(File file, bool isVideo) async {
    try {
      // Initialize Supabase if not already initialized
      await SupabaseService.initialize();
      
      // Generate unique filename with timestamp and random string
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = DateTime.now().microsecondsSinceEpoch % 10000;
      final extension = path.extension(file.path);
      final fileName = '${timestamp}_$random$extension';
      
      // Upload to Supabase
      final url = await SupabaseService.uploadChatMedia(file, fileName);
      
      return url;
    } catch (e) {
      debugPrint('Error uploading to Supabase: $e');
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        setState(() {
          _selectedMedia.add(_MediaPreviewItem(file: file, type: 'image'));
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        
        // Initialize video player for preview
        final videoController = VideoPlayerController.file(file);
        await videoController.initialize();
        
        // Add listener to update UI when video state changes
        videoController.addListener(() {
          if (mounted) {
            setState(() {});
          }
        });
        
        setState(() {
          _selectedMedia.add(_MediaPreviewItem(
            file: file,
            type: 'video',
            videoController: videoController,
          ));
        });
      }
    } catch (e) {
      debugPrint('Error picking video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _takePicture() async {
    await _pickImage(ImageSource.camera);
  }
  
  Future<void> _sendPreviewedMedia() async {
    if (_isUploading || _selectedMedia.isEmpty) return;
    
    setState(() {
      _isUploading = true;
    });
    
    try {
      final caption = _messageController.text.trim();
      _messageController.clear();
      
      bool allSuccess = true;
      String? lastError;
      
      // Use the same timestamp for all media items so they can be grouped
      final baseTimestamp = DateTime.now();
      
      // Send all media items with the same timestamp (or very close)
      for (int i = 0; i < _selectedMedia.length; i++) {
        final item = _selectedMedia[i];
        String? imageUrl;
        String? videoUrl;
        
        // Only add caption to the first message
        final shouldAddCaption = i == 0 && caption.isNotEmpty;
        
        if (item.type == 'image') {
          // Upload image
          imageUrl = await _uploadToSupabase(item.file, false);
          if (imageUrl == null) {
            allSuccess = false;
            lastError = 'Failed to upload image';
            continue;
          }
        } else if (item.type == 'video') {
          // Upload video
          videoUrl = await _uploadToSupabase(item.file, true);
          if (videoUrl == null) {
            allSuccess = false;
            lastError = 'Failed to upload video';
            continue;
          }
        }
        
        // Send message with media
        final success = await _sendMessage(
          text: shouldAddCaption ? caption : '',
          imageUrl: imageUrl,
          videoUrl: videoUrl,
        );
        
        if (!success) {
          allSuccess = false;
          lastError = 'Failed to send ${item.type}';
        }
        
        // Small delay between sends to avoid overwhelming the server
        if (i < _selectedMedia.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      
      if (!allSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lastError ?? 'Some items failed to send'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      // Clear preview
      _clearMediaPreview();
      setState(() {
        _isUploading = false;
      });
    } catch (e) {
      debugPrint('Error sending previewed media: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending media: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isUploading = false;
      });
    }
  }
  
  void _clearMediaPreview() {
    setState(() {
      // Dispose all video controllers
      for (var item in _selectedMedia) {
        item.videoController?.dispose();
      }
      _selectedMedia.clear();
    });
  }
  
  void _removeMediaItem(int index) {
    if (index >= 0 && index < _selectedMedia.length) {
      setState(() {
        _selectedMedia[index].videoController?.dispose();
        _selectedMedia.removeAt(index);
      });
    }
  }
  
  void _cancelPreview() {
    _clearMediaPreview();
  }

  void _showMediaOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _takePicture();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Choose Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Record Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
  

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        final selectedId = chatProvider.selectedConversationId;
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;
        
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: selectedId == null
                ? const Text('Messages')
                : Builder(
                    builder: (context) {
                      final conversation = chatProvider.conversations.firstWhere(
                        (c) => c.id == selectedId,
                        orElse: () => chatProvider.conversations.isNotEmpty 
                            ? chatProvider.conversations.first 
                            : ChatConversation(
                                id: '',
                                customerId: '',
                                customerName: '',
                                lastMessage: '',
                                lastMessageTime: DateTime.now(),
                                lastMessageSender: '',
                                updatedAt: DateTime.now(),
                              ),
                      );
                      return Row(
                        children: [
                          Container(
                            width: Responsive.getWidth(context, mobile: 40),
                            height: Responsive.getHeight(context, mobile: 40),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: conversation.chatType == 'rider'
                                    ? [Colors.orange.shade400, Colors.orange.shade600]
                                    : [AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.8)],
                              ),
                            ),
                            child: Icon(
                              conversation.chatType == 'rider'
                                  ? Icons.delivery_dining
                                  : Icons.support_agent,
                              color: Colors.white,
                              size: Responsive.getIconSize(context, mobile: 20),
                            ),
                          ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                          Expanded(
                            child: Text(
                              conversation.chatType == 'rider' 
                                  ? (conversation.riderName ?? 'Rider')
                                  : 'CALCOA Support',
                              style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 18), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(selectedId == null ? Icons.arrow_back : Icons.arrow_back),
              onPressed: () {
                if (selectedId != null) {
                  // Go back to conversation list
                  chatProvider.selectConversation(null);
                } else {
                  // Navigate away from chat screen
                  Navigator.of(context).maybePop();
                }
              },
            ),
            actions: [
              if (selectedId != null)
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    // Future: Add more options menu
                  },
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  if (authProvider.currentCustomer != null) {
                    chatProvider.initializeChat(authProvider.currentCustomer!.uid);
                  }
                },
                tooltip: 'Refresh Messages',
              ),
            ],
          ),
          body: _buildBody(chatProvider),
        );
      },
    );
  }

  Widget _buildBody(ChatProvider chatProvider) {
    // Check if chat is initialized
    if (chatProvider.currentCustomerId == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: Responsive.getIconSize(context, mobile: 64),
                    color: Colors.grey,
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
                  Text(
                    'Chat not initialized',
                    style: TextStyle(
                      fontSize: Responsive.getFontSize(context, mobile: 18),
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
                  const Text(
                    'Please try refreshing or restarting the app',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  ElevatedButton(
                    onPressed: () {
                      _initializeChat();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Show loading state
          if (chatProvider.isLoading && chatProvider.conversations.isEmpty && chatProvider.currentConversationMessages.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Show error state
          if (chatProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error,
                    size: Responsive.getIconSize(context, mobile: 64),
                    color: Colors.red,
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
                  Text(
                    'Error: ${chatProvider.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  ElevatedButton(
                    onPressed: () {
                      _initializeChat();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

    // Show modern Messenger-style interface
    debugPrint('📱 Showing Messenger-style chat interface');
    return _buildMessengerStyleView(chatProvider);
  }

  Widget _buildNoConversationsView(ChatProvider chatProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: Responsive.getIconSize(context, mobile: 64),
            color: Colors.grey[400],
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
          Text(
            'No conversations yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
          Text(
            'Start a conversation with our staff',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 24)),
          ElevatedButton.icon(
            onPressed: () async {
              debugPrint('🚀 Creating new conversation...');
              final conversationId = await chatProvider.createConversation();
              if (conversationId != null) {
                debugPrint('✅ Conversation created: $conversationId');
                chatProvider.selectConversation(conversationId);
              } else {
                debugPrint('❌ Failed to create conversation');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to create conversation. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.chat),
            label: const Text('Start Conversation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessengerStyleView(ChatProvider chatProvider) {
    // Show conversation list or chat view in the same container
    if (chatProvider.selectedConversationId == null) {
      // Show conversation list directly
      return _buildConversationListView(chatProvider);
    } else {
      // Show full-screen chat view
      return _buildChatView(chatProvider);
    }
  }

  Widget _buildConversationListView(ChatProvider chatProvider) {
    final allConversations = [
      ...chatProvider.conversations,
      ...chatProvider.archivedConversations,
    ];
    final filteredConversations = _getFilteredConversations(allConversations);
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[50]!,
            Colors.white,
          ],
        ),
      ),
      child: Column(
        children: [
          // Search bar
          Container(
            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 12)),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildSearchField(isInGreenHeader: false),
          ),
          // Conversations list with loading state
          Expanded(
            child: chatProvider.isLoading && allConversations.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading conversations...'),
                      ],
                    ),
                  )
                : _buildMobileConversationList(
                    chatProvider: chatProvider,
                    conversations: allConversations,
                    filteredConversations: filteredConversations,
                    hasSearchQuery: hasSearchQuery,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationDrawer(ChatProvider chatProvider) {
    final allConversations = [
      ...chatProvider.conversations,
      ...chatProvider.archivedConversations,
    ];
    final filteredConversations = _getFilteredConversations(allConversations);
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Column(
        children: [
          // Drawer header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Conversations',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                _buildSearchField(isInGreenHeader: true),
              ],
            ),
          ),
          // Conversations list
          Expanded(
            child: _buildMobileConversationList(
              chatProvider: chatProvider,
              conversations: allConversations,
              filteredConversations: filteredConversations,
              hasSearchQuery: hasSearchQuery,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationsList(ChatProvider chatProvider) {
    final conversations = chatProvider.conversations;
    final filteredConversations = _getFilteredConversations(conversations);
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
          child: _buildSearchField(),
        ),
        Expanded(
          child: _buildDesktopConversationList(
            chatProvider: chatProvider,
            conversations: conversations,
            filteredConversations: filteredConversations,
            hasSearchQuery: hasSearchQuery,
          ),
        ),
      ],
    );
  }

  Widget _buildChatView(ChatProvider chatProvider) {
    final messages = chatProvider.currentConversationMessages;
    // Ensure newest messages are shown immediately (no animated auto-scroll)
    _maybeAutoScroll(chatProvider.selectedConversationId, messages.length);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[50]!,
            Colors.white,
          ],
        ),
      ),
      child: Column(
        children: [
          // Messages list
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryColor.withOpacity(0.1),
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            size: Responsive.getIconSize(context, mobile: 48),
                            color: AppTheme.primaryColor.withOpacity(0.6),
                          ),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                        Text(
                          'Start the conversation!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 12)),
                    children: _buildMessageListWithHeaders(messages),
                  ),
          ),
          // Message input - Modern Messenger style
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Media preview
              if (_selectedMedia.isNotEmpty)
                _buildMediaPreview(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attach button
                  Container(
                    margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 4)),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isUploading ? null : _showMediaOptions,
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                        child: Container(
                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 10)),
                          child: Icon(
                            Icons.add_circle_outline,
                            color: _isUploading ? Colors.grey : AppTheme.primaryColor,
                            size: Responsive.getIconSize(context, mobile: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  // Message input field
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 25)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        enabled: !_isUploading,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: _isUploading ? 'Uploading...' : 'Type a message...',
                          hintStyle: TextStyle(
                            color: Colors.grey[600],
                            fontSize: Responsive.getFontSize(context, mobile: 15),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 15),
                          color: Colors.black87,
                        ),
                        onSubmitted: (_) {
                          if (_selectedMedia.isNotEmpty) {
                            _sendPreviewedMedia();
                          } else {
                            _sendMessage();
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  // Send button
                  Container(
                    margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 4)),
                    decoration: BoxDecoration(
                      color: _isUploading ? Colors.grey[400] : AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: _isUploading
                          ? null
                          : [
                              BoxShadow(
                                color: AppTheme.primaryColor.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isUploading
                            ? null
                            : () {
                                if (_selectedMedia.isNotEmpty) {
                                  _sendPreviewedMedia();
                                } else {
                                  _sendMessage();
                                }
                              },
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 25)),
                        child: Container(
                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                          child: _isUploading
                              ? SizedBox(
                                  width: Responsive.getWidth(context, mobile: 20),
                                  height: Responsive.getHeight(context, mobile: 20),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: Responsive.getIconSize(context, mobile: 20),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isCustomer = message.sender == 'customer';
    
    String? senderLabel;
    if (!isCustomer) {
      // Check if message is from rider by checking chatType or conversationId
      final isRiderMessage = message.chatType == 'rider' || 
                            (message.conversationId.contains('_rider_') && message.sender == 'rider');
      
      if (isRiderMessage) {
        senderLabel = message.riderName != null && message.riderName!.isNotEmpty
            ? '${message.riderName} - (Role: Delivery Rider)'
            : 'Delivery Rider';
      } else {
        // Get the display name, and fix any incorrect role labels
        String? displayName = message.staffDisplayName;
        if (displayName != null && displayName.isNotEmpty) {
          // Fix old messages that have "System Administrator - (Role: Staff)" 
          // to show "System Administrator - (Role: Admin)" instead
          if (displayName.contains('System Administrator') && displayName.contains('(Role: Staff)')) {
            displayName = displayName.replaceAll('(Role: Staff)', '(Role: Admin)');
          }
          senderLabel = displayName;
        } else {
          // Fallback to staffName with default role
          senderLabel = message.staffName != null && message.staffName!.isNotEmpty
              ? '${message.staffName} - (Role: Staff)'
              : 'CALCOA Support';
        }
      }
    }

    return Align(
      alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderLabel != null)
              Padding(
                padding: EdgeInsets.only(
                  left: isCustomer ? 0 : 12,
                  right: isCustomer ? 12 : 0,
                  bottom: 4,
                ),
                child: Text(
                  senderLabel,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: Responsive.getFontSize(context, mobile: 11),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 10)),
              decoration: BoxDecoration(
                color: isCustomer 
                    ? AppTheme.primaryColor 
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isCustomer ? const Radius.circular(18) : const Radius.circular(4),
                  bottomRight: isCustomer ? const Radius.circular(4) : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isCustomer
                        ? AppTheme.primaryColor.withOpacity(0.2)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Display image if present
            if (message.imageUrl != null)
              GestureDetector(
                onTap: () {
                  // Show image in full screen
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: EdgeInsets.zero,
                      child: Stack(
                        children: [
                          Center(
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Image.network(
                                _fixImageUrl(message.imageUrl!),
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(Icons.broken_image, color: Colors.white, size: Responsive.getIconSize(context, mobile: 64)),
                                  );
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            top: 40,
                            right: 20,
                            child: IconButton(
                              icon: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 30)),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
                  constraints: const BoxConstraints(
                    maxWidth: 250,
                    maxHeight: 250,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                    border: Border.all(
                      color: isCustomer ? Colors.white24 : Colors.grey[300]!,
                      width: Responsive.getWidth(context, mobile: 1),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                    child: Image.network(
                      _fixImageUrl(message.imageUrl!),
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: Center(
                            child: Icon(Icons.broken_image, size: Responsive.getIconSize(context, mobile: 48), color: Colors.grey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            // Display video if present
            if (message.videoUrl != null)
              GestureDetector(
                onTap: () {
                  // Show video in full-screen dialog with inline player
                  final videoUrl = _fixImageUrl(message.videoUrl!);
                  _showVideoPlayer(context, videoUrl);
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
                  constraints: const BoxConstraints(
                    maxWidth: 250,
                    maxHeight: 250,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                    border: Border.all(
                      color: isCustomer ? Colors.white24 : Colors.grey[300]!,
                      width: Responsive.getWidth(context, mobile: 1),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Video thumbnail or placeholder
                        Container(
                          color: Colors.black,
                          child: Center(
                            child: Icon(Icons.play_circle_filled, size: Responsive.getIconSize(context, mobile: 64), color: Colors.white70),
                          ),
                        ),
                        // Video label
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 4)),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                            ),
                            child: Text(
                              'Video',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: Responsive.getFontSize(context, mobile: 12),
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                  // Display text if present
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        color: isCustomer ? Colors.white : Colors.black87,
                        fontSize: Responsive.getFontSize(context, mobile: 15),
                        height: 1.4,
                      ),
                    ),
                  if (message.text.isNotEmpty) SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: isCustomer ? Colors.white.withOpacity(0.7) : Colors.grey[500],
                          fontSize: Responsive.getFontSize(context, mobile: 11),
                        ),
                      ),
                      if (isCustomer) ...[
                        SizedBox(width: Responsive.getWidth(context, mobile: 4)),
                        Icon(
                          Icons.done_all,
                          size: Responsive.getIconSize(context, mobile: 14),
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedMediaBubble(List<ChatMessage> messages) {
    if (messages.isEmpty) return const SizedBox.shrink();
    
    final firstMessage = messages.first;
    final lastMessage = messages.last;
    final isCustomer = firstMessage.sender == 'customer';
    
    String? senderLabel;
    if (!isCustomer) {
      // Check if message is from rider by checking chatType or conversationId
      final isRiderMessage = firstMessage.chatType == 'rider' || 
                            (firstMessage.conversationId.contains('_rider_') && firstMessage.sender == 'rider');
      
      if (isRiderMessage) {
        senderLabel = firstMessage.riderName != null && firstMessage.riderName!.isNotEmpty
            ? '${firstMessage.riderName} - (Role: Delivery Rider)'
            : 'Delivery Rider';
      } else {
        String? displayName = firstMessage.staffDisplayName;
        if (displayName != null && displayName.isNotEmpty) {
          if (displayName.contains('System Administrator') && displayName.contains('(Role: Staff)')) {
            displayName = displayName.replaceAll('(Role: Staff)', '(Role: Admin)');
          }
          senderLabel = displayName;
        } else {
          senderLabel = firstMessage.staffName != null && firstMessage.staffName!.isNotEmpty
              ? '${firstMessage.staffName} - (Role: Staff)'
              : 'CALCOA Support';
        }
      }
    }
    
    // Calculate grid dimensions based on number of items
    final itemCount = messages.length;
    int crossAxisCount = 2;
    if (itemCount == 1) {
      crossAxisCount = 1;
    } else if (itemCount <= 4) {
      crossAxisCount = 2;
    } else if (itemCount <= 9) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 3;
    }
    
    final itemSize = (MediaQuery.of(context).size.width * 0.75 - 32 - (crossAxisCount - 1) * 4) / crossAxisCount;
    
    return Align(
      alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderLabel != null)
              Padding(
                padding: EdgeInsets.only(
                  left: isCustomer ? 0 : 12,
                  right: isCustomer ? 12 : 0,
                  bottom: 4,
                ),
                child: Text(
                  senderLabel,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: Responsive.getFontSize(context, mobile: 11),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 10)),
              decoration: BoxDecoration(
                color: isCustomer 
                    ? AppTheme.primaryColor 
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isCustomer ? const Radius.circular(18) : const Radius.circular(4),
                  bottomRight: isCustomer ? const Radius.circular(4) : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isCustomer
                        ? AppTheme.primaryColor.withOpacity(0.2)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Display grouped media in grid
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth = constraints.maxWidth;
                      final itemSize = (availableWidth - (crossAxisCount - 1) * 4) / crossAxisCount;
                      final rowCount = (itemCount / crossAxisCount).ceil();
                      final gridHeight = (rowCount * itemSize) + ((rowCount - 1) * 4);
                      
                      return SizedBox(
                        height: gridHeight,
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                            childAspectRatio: 1,
                          ),
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                      final msg = messages[index];
                      final hasImage = msg.imageUrl != null && msg.imageUrl!.isNotEmpty;
                      final hasVideo = msg.videoUrl != null && msg.videoUrl!.isNotEmpty;
                      
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GestureDetector(
                          onTap: () {
                            if (hasImage) {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: EdgeInsets.zero,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: InteractiveViewer(
                                          minScale: 0.5,
                                          maxScale: 4.0,
                                          child: Image.network(
                                            _fixImageUrl(msg.imageUrl!),
                                            fit: BoxFit.contain,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                                            },
                                            errorBuilder: (context, error, stackTrace) {
                                              return Center(
                                                child: Icon(Icons.broken_image, color: Colors.white, size: Responsive.getIconSize(context, mobile: 64)),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 40,
                                        right: 20,
                                        child: IconButton(
                                          icon: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 30)),
                                          onPressed: () => Navigator.of(context).pop(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else if (hasVideo) {
                              _showVideoPlayer(context, _fixImageUrl(msg.videoUrl!));
                            }
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (hasImage)
                                Image.network(
                                  _fixImageUrl(msg.imageUrl!),
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey[300],
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
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.error_outline, color: Colors.grey),
                                    );
                                  },
                                )
                              else if (hasVideo)
                                Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(color: Colors.grey[900]),
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Video indicator
                              if (hasVideo)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '🎥',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                          },
                        ),
                      );
                    },
                  ),
                  // Display text if present (only from first message)
                  if (firstMessage.text.isNotEmpty) ...[
                    SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                    Text(
                      firstMessage.text,
                      style: TextStyle(
                        color: isCustomer ? Colors.white : Colors.black87,
                        fontSize: Responsive.getFontSize(context, mobile: 15),
                        height: 1.4,
                      ),
                    ),
                  ],
                  SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(lastMessage.timestamp),
                        style: TextStyle(
                          color: isCustomer ? Colors.white.withOpacity(0.7) : Colors.grey[500],
                          fontSize: Responsive.getFontSize(context, mobile: 11),
                        ),
                      ),
                      if (isCustomer) ...[
                        SizedBox(width: Responsive.getWidth(context, mobile: 4)),
                        Icon(
                          Icons.done_all,
                          size: Responsive.getIconSize(context, mobile: 14),
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoPlayer(BuildContext context, String videoUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Video player container
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                  child: Column(
                    children: [
                      // Video player area
                      Expanded(
                        child: Center(
                          child: _buildVideoPlayer(videoUrl),
                        ),
                      ),
                      // Video controls/info
                      Container(
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                        color: Colors.black54,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Video',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: Responsive.getFontSize(context, mobile: 16),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_new, color: Colors.white),
                              onPressed: () async {
                                final uri = Uri.parse(videoUrl);
                                try {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } catch (e) {
                                  debugPrint('Failed to open in external app: $e');
                                }
                              },
                              tooltip: 'Open in external player',
                            ),
                            IconButton(
                              icon: const Icon(Icons.download, color: Colors.white),
                              onPressed: () async {
                                // Copy URL for download
                                await Clipboard.setData(ClipboardData(text: videoUrl));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Video URL copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              tooltip: 'Copy video URL',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 30)),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    return _VideoPlayerWidget(videoUrl: videoUrl);
  }

  String _fixImageUrl(String url) {
    // Fix duplicate bucket names in URL (same fix as staff dashboard)
    // Works for both images and videos
    String fixedUrl = url.trim();
    
    // Remove duplicate bucket names
    fixedUrl = fixedUrl.replaceAll('/customerconvo_uploads/customerconvo_uploads/', '/customerconvo_uploads/');
    
    // If URL doesn't start with http, it might be a path - construct full URL
    if (!fixedUrl.startsWith('http://') && !fixedUrl.startsWith('https://')) {
      // It's a file path, construct Supabase URL
      String cleanPath = fixedUrl.replaceFirst(RegExp(r'^/+'), '');
      // Remove bucket name if present (handle multiple occurrences)
      while (cleanPath.startsWith('customerconvo_uploads/')) {
        cleanPath = cleanPath.substring('customerconvo_uploads/'.length).replaceFirst(RegExp(r'^/+'), '');
      }
      fixedUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co/storage/v1/object/public/customerconvo_uploads/$cleanPath';
    }
    
    return fixedUrl;
  }

  Widget _buildMediaPreview() {
    if (_selectedMedia.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 12)),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Media Preview (${_selectedMedia.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: Colors.grey[600],
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearMediaPreview,
                tooltip: 'Clear all',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedMedia.length,
              itemBuilder: (context, index) {
                final item = _selectedMedia[index];
                return Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (item.type == 'image') {
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: EdgeInsets.zero,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: InteractiveViewer(
                                        minScale: 0.5,
                                        maxScale: 4.0,
                                        child: Image.file(
                                          item.file,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 40,
                                      right: 20,
                                      child: IconButton(
                                        icon: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 30)),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          } else if (item.type == 'video' && item.videoController != null) {
                            _showVideoPlayer(context, item.file.path);
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.type == 'image'
                              ? Image.file(
                                  item.file,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                )
                              : item.videoController != null
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SizedBox(
                                          width: 120,
                                          height: 120,
                                          child: VideoPlayer(item.videoController!),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            item.videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Container(
                                      width: 120,
                                      height: 120,
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                        ),
                      ),
                      // Remove button
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeMediaItem(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      // Type indicator
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.type == 'image' ? '📷' : '🎥',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastMessage(String lastMessage, String lastMessageSender, {String? senderName, String? chatType}) {
    // Add sender indicator if message is from customer
    if (lastMessageSender.toLowerCase() == 'customer') {
      // Check if it's an image or video message
      if (lastMessage.contains('📷') || lastMessage.toLowerCase().contains('image')) {
        return 'You: 📷 Image';
      } else if (lastMessage.contains('🎥') || lastMessage.toLowerCase().contains('video')) {
        return 'You: 🎥 Video';
      }
      return 'You: $lastMessage';
    } else {
      // Staff/Rider messages - show sender name and message or media indicator
      String senderPrefix = '';
      if (chatType == 'rider' && senderName != null && senderName.isNotEmpty) {
        senderPrefix = '$senderName: ';
      } else if (chatType != 'rider') {
        senderPrefix = 'CALCOA Support: ';
      }
      
      // Check if it's an image or video message
      if (lastMessage.contains('📷') || lastMessage.toLowerCase().contains('image')) {
        return senderPrefix.isNotEmpty ? '$senderPrefix📷 Image' : '📷 Image';
      } else if (lastMessage.contains('🎥') || lastMessage.toLowerCase().contains('video')) {
        return senderPrefix.isNotEmpty ? '$senderPrefix🎥 Video' : '🎥 Video';
      }
      return senderPrefix.isNotEmpty ? '$senderPrefix$lastMessage' : lastMessage;
    }
  }

  String _formatTime(DateTime dateTime) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    final year = dateTime.year;
    final hour = dateTime.hour == 0 
        ? 12 
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = dateTime.hour < 12 ? 'AM' : 'PM';
    final timeString = '$hour:$minute $ampm';
    return '$month $day, $year • $timeString';
  }

  List<Widget> _buildMessageListWithHeaders(List<ChatMessage> messages) {
    final widgets = <Widget>[];
    String? lastHeader;
    int i = 0;
    while (i < messages.length) {
      final message = messages[i];
      final header = _formatHeader(message.timestamp);
      if (header != lastHeader) {
        widgets.add(
              Padding(
            padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 8)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  header,
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 12),
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
        lastHeader = header;
      }
      
      // Group consecutive media messages from the same sender within 5 seconds
      final groupedMessages = <ChatMessage>[message];
      // Check if current message is a media message (even if it has text like "📷 Image")
      final currentHasMedia = (message.imageUrl != null && message.imageUrl!.isNotEmpty) || 
                              (message.videoUrl != null && message.videoUrl!.isNotEmpty);
      if (currentHasMedia) {
        // Check if next messages should be grouped
        for (int j = i + 1; j < messages.length; j++) {
          final nextMsg = messages[j];
          if (nextMsg.sender != message.sender) break;
          
          // If next message has text and no media, don't group it
          if (nextMsg.text.isNotEmpty && 
              (nextMsg.imageUrl == null || nextMsg.imageUrl!.isEmpty) &&
              (nextMsg.videoUrl == null || nextMsg.videoUrl!.isEmpty)) break;
          
          final timeDiff = nextMsg.timestamp.difference(message.timestamp);
          // Increase time window to 5 seconds for better grouping
          if (timeDiff.inSeconds > 5) break;
          
          // Only group if it's a media message (image or video)
          if ((nextMsg.imageUrl != null && nextMsg.imageUrl!.isNotEmpty) ||
              (nextMsg.videoUrl != null && nextMsg.videoUrl!.isNotEmpty)) {
            // Group media messages even if they have text (like "📷 Image" or "🎥 Video")
            // Also group if the first message has a caption - we'll display caption with the group
            final text = nextMsg.text.trim();
            final isMediaIndicatorOnly = text.isEmpty || 
                                        text == '📷 Image' || 
                                        text == '🎥 Video' ||
                                        text.toLowerCase().contains('image') ||
                                        text.toLowerCase().contains('video');
            
            // Always group consecutive media messages from the same sender within time window
            // The caption (if any) will be displayed with the first message in the group
            groupedMessages.add(nextMsg);
          } else {
            break;
          }
        }
      }
      
      // Skip rendering if this message is already part of a previous group
      if (i > 0) {
        final prevMsg = messages[i - 1];
        if (prevMsg.sender == message.sender) {
          final timeDiff = message.timestamp.difference(prevMsg.timestamp);
          // Use same 5 second window for checking previous group
          if (timeDiff.inSeconds <= 5 &&
              ((prevMsg.imageUrl != null && prevMsg.imageUrl!.isNotEmpty) ||
               (prevMsg.videoUrl != null && prevMsg.videoUrl!.isNotEmpty)) &&
              ((message.imageUrl != null && message.imageUrl!.isNotEmpty) ||
               (message.videoUrl != null && message.videoUrl!.isNotEmpty))) {
            i++;
            continue;
          }
        }
      }
      
      final hasMultipleMedia = groupedMessages.length > 1;
      if (hasMultipleMedia) {
        widgets.add(_buildGroupedMediaBubble(groupedMessages));
        i += groupedMessages.length;
      } else {
        widgets.add(_buildMessageBubble(message));
        i++;
      }
    }
    return widgets;
  }

  String _formatHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(dDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (_isSameWeek(dt, now)) {
      final weekday = _weekdayName(dt.weekday);
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$weekday, $hour:$minute $ampm';
    }
    // Full date e.g., November 3, 2025
    final months = [
      'January','February','March','April','May','June','July','August','September','October','November','December'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  bool _isSameWeek(DateTime a, DateTime b) {
    final aMonday = a.subtract(Duration(days: a.weekday - 1));
    final bMonday = b.subtract(Duration(days: b.weekday - 1));
    return aMonday.year == bMonday.year && aMonday.month == bMonday.month && aMonday.day == bMonday.day;
  }
  
  String _weekdayName(int w) {
    switch (w) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return '';
    }
  }

  Widget _buildMobileConversationList({
    required ChatProvider chatProvider,
    required List<ChatConversation> conversations,
    required List<ChatConversation> filteredConversations,
    required bool hasSearchQuery,
  }) {
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: Responsive.getIconSize(context, mobile: 64), color: Colors.grey[400]),
            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            Text(
              'No conversations yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Text(
              'Start a conversation to see it here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

            if (filteredConversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: Responsive.getIconSize(context, mobile: 48), color: Colors.grey),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            Text(
              hasSearchQuery
                  ? 'No conversations matched your search'
                  : 'No conversations found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
      itemCount: filteredConversations.length,
      itemBuilder: (context, index) {
        final conversation = filteredConversations[index];
        final isSelected = chatProvider.selectedConversationId == conversation.id;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 2)),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                debugPrint('🎯 Tapping conversation: ${conversation.id}');
                chatProvider.selectConversation(conversation.id);
              },
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
              child: Padding(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: Responsive.getWidth(context, mobile: 56),
                          height: Responsive.getHeight(context, mobile: 56),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: conversation.chatType == 'rider'
                                  ? [Colors.orange.shade400, Colors.orange.shade600]
                                  : [AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.8)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (conversation.chatType == 'rider' ? Colors.orange : AppTheme.primaryColor)
                                    .withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            conversation.chatType == 'rider'
                                ? Icons.delivery_dining
                                : Icons.support_agent,
                            color: Colors.white,
                            size: Responsive.getIconSize(context, mobile: 26),
                          ),
                        ),
                        // Unread indicator dot on avatar
                        if (conversation.unreadCount > 0)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.5),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        conversation.chatType == 'rider'
                                            ? (conversation.riderName ?? 'Rider')
                                            : 'CALCOA Support',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: Responsive.getFontSize(context, mobile: 16),
                                          color: isSelected
                                              ? AppTheme.primaryColor
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (conversation.chatType == 'rider')
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Rider',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  conversation.lastMessage.isEmpty
                                      ? 'No messages yet'
                                      : _formatLastMessage(
                                          conversation.lastMessage, 
                                          conversation.lastMessageSender,
                                          senderName: conversation.chatType == 'rider' ? conversation.riderName : null,
                                          chatType: conversation.chatType,
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: conversation.unreadCount > 0 ? Colors.black87 : Colors.grey[600],
                                    fontSize: Responsive.getFontSize(context, mobile: 14),
                                    fontWeight: conversation.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Unread count badge - make it more prominent
                                  if (conversation.unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red.withOpacity(0.3),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                      child: Center(
                                        child: Text(
                                          conversation.unreadCount > 99 ? '99+' : conversation.unreadCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatTime(conversation.lastMessageTime),
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 12),
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopConversationList({
    required ChatProvider chatProvider,
    required List<ChatConversation> conversations,
    required List<ChatConversation> filteredConversations,
    required bool hasSearchQuery,
  }) {
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: Responsive.getIconSize(context, mobile: 64), color: Colors.grey[400]),
            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            Text(
              'No conversations yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Text(
              'Start a conversation to see it here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    if (filteredConversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: Responsive.getIconSize(context, mobile: 48), color: Colors.grey),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            Text(
              hasSearchQuery
                  ? 'No conversations matched your search'
                  : 'No conversations found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredConversations.length,
      itemBuilder: (context, index) {
        final conversation = filteredConversations[index];
        final isSelected = chatProvider.selectedConversationId == conversation.id;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 4)),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            border: isSelected
                ? Border.all(color: AppTheme.primaryColor.withOpacity(0.3), width: 1.5)
                : Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                debugPrint('🎯 Tapping conversation: ${conversation.id}');
                chatProvider.selectConversation(conversation.id);
              },
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
              child: Padding(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: Responsive.getWidth(context, mobile: 48),
                          height: Responsive.getHeight(context, mobile: 48),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: conversation.chatType == 'rider'
                                  ? [Colors.orange.shade400, Colors.orange.shade600]
                                  : [AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.8)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (conversation.chatType == 'rider' ? Colors.orange : AppTheme.primaryColor)
                                    .withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            conversation.chatType == 'rider'
                                ? Icons.delivery_dining
                                : Icons.support_agent,
                            color: Colors.white,
                            size: Responsive.getIconSize(context, mobile: 22),
                          ),
                        ),
                        // Unread indicator dot on avatar
                        if (conversation.unreadCount > 0)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.5),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name with role indicator
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  conversation.chatType == 'rider'
                                      ? (conversation.riderName ?? 'Rider')
                                      : 'CALCOA Support',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: Responsive.getFontSize(context, mobile: 14),
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (conversation.chatType == 'rider')
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Rider',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                          // Message preview with timestamp aligned
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  conversation.lastMessage.isEmpty
                                      ? 'No messages yet'
                                      : _formatLastMessage(
                                          conversation.lastMessage, 
                                          conversation.lastMessageSender,
                                          senderName: conversation.chatType == 'rider' ? conversation.riderName : null,
                                          chatType: conversation.chatType,
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: conversation.unreadCount > 0 ? Colors.black87 : Colors.grey[600],
                                    fontSize: Responsive.getFontSize(context, mobile: 12),
                                    fontWeight: conversation.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Unread count badge - make it more prominent
                                  if (conversation.unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red.withOpacity(0.3),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                      child: Center(
                                        child: Text(
                                          conversation.unreadCount > 99 ? '99+' : conversation.unreadCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    _formatTime(conversation.lastMessageTime),
                                    style: TextStyle(
                                      fontSize: Responsive.getFontSize(context, mobile: 11),
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: Responsive.getWidth(context, mobile: 4)),
                    Consumer<ChatProvider>(
                      builder: (context, cp, _) => PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.grey[600], size: Responsive.getIconSize(context, mobile: 18)),
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await _confirmDelete(context, cp, conversation.id);
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Separate widget for video player to manage state
class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerWidget({required this.videoUrl});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // Auto-play the video
        _controller!.play();
      }
    } catch (e) {
      debugPrint('❌ Error initializing video: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: Responsive.getIconSize(context, mobile: 64)),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              Text(
                'Failed to load video',
                style: TextStyle(color: Colors.white, fontSize: Responsive.getFontSize(context, mobile: 16)),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              Text(
                _errorMessage ?? 'Unknown error',
                style: TextStyle(color: Colors.white70, fontSize: Responsive.getFontSize(context, mobile: 12)),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              ElevatedButton.icon(
                onPressed: () async {
                  // Open in external player as fallback
                  final uri = Uri.parse(widget.videoUrl);
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    debugPrint('Failed to open in external app: $e');
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in External Player'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video player
          VideoPlayer(_controller!),
          // Custom controls overlay
          _VideoControlsOverlay(controller: _controller!),
        ],
      ),
    );
  }
}

// Video controls overlay
class _VideoControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoControlsOverlay({required this.controller});

  @override
  State<_VideoControlsOverlay> createState() => _VideoControlsOverlayState();
}

class _VideoControlsOverlayState extends State<_VideoControlsOverlay> {
  bool _showControls = true;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_videoListener);
    _isPlaying = widget.controller.value.isPlaying;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    super.dispose();
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
        // Auto-hide controls after 3 seconds
        if (_showControls) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _showControls = false;
              });
            }
          });
        }
      },
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.black26,
          child: Stack(
            children: [
              // Center play/pause button
              Center(
                child: IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: Responsive.getIconSize(context, mobile: 64),
                  ),
                  onPressed: _togglePlayPause,
                ),
              ),
              // Bottom controls
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black54,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          widget.controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.white,
                            bufferedColor: Colors.white54,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(widget.controller.value.position) +
                            ' / ' +
                            _formatDuration(widget.controller.value.duration),
                        style: TextStyle(color: Colors.white, fontSize: Responsive.getFontSize(context, mobile: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

// Slide button widget for selecting conversations
class _SlideButton extends StatefulWidget {
  final VoidCallback onSlideComplete;
  final String text;

  const _SlideButton({
    required this.onSlideComplete,
    required this.text,
  });

  @override
  State<_SlideButton> createState() => _SlideButtonState();
}

class _SlideButtonState extends State<_SlideButton> {
  double _dragPosition = 0.0;
  bool _isCompleted = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonWidth = screenWidth * 0.75;
    final maxDrag = buttonWidth - 60;

    return Container(
      width: buttonWidth,
      height: Responsive.getHeight(context, mobile: 56),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 28)),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Stack(
        children: [
          // Background text
          Center(
            child: Text(
              widget.text,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: Responsive.getFontSize(context, mobile: 14),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Sliding button
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: _isCompleted ? maxDrag : _dragPosition.clamp(0.0, maxDrag),
            top: 4,
            child: GestureDetector(
              onPanUpdate: (details) {
                if (!_isCompleted) {
                  setState(() {
                    _dragPosition += details.delta.dx;
                    _dragPosition = _dragPosition.clamp(0.0, maxDrag);
                    
                    // Check if slide is complete (dragged more than 80% of the way)
                    if (_dragPosition >= maxDrag * 0.8) {
                      _isCompleted = true;
                      widget.onSlideComplete();
                    }
                  });
                }
              },
              onPanEnd: (details) {
                if (!_isCompleted) {
                  setState(() {
                    _dragPosition = 0.0;
                  });
                }
              },
              child: Container(
                width: Responsive.getWidth(context, mobile: 52),
                height: Responsive.getHeight(context, mobile: 48),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 24)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: Responsive.getIconSize(context, mobile: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
