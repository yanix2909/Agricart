import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../providers/chat_provider.dart';
import '../utils/rider_session.dart';
import '../utils/theme.dart';
import '../utils/responsive.dart';

class RiderChatScreen extends StatefulWidget {
  final String? initialCustomerId;
  final String? initialCustomerName;
  const RiderChatScreen({super.key, this.initialCustomerId, this.initialCustomerName});

  @override
  State<RiderChatScreen> createState() => _RiderChatScreenState();
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

class _RiderChatScreenState extends State<RiderChatScreen> {
  final RiderChatProvider _chat = RiderChatProvider();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _expectedConversationId;
  VideoPlayerController? _videoPlayerController;
  
  // Media preview state - support multiple files
  final List<_MediaPreviewItem> _selectedMedia = [];

  @override
  void initState() {
    super.initState();
    _initializeChat();
    
    // Listen to provider changes to update UI when conversation is selected
    _chat.addListener(_onChatProviderChanged);
  }

  void _onChatProviderChanged() {
    if (mounted) {
      final previousMessageCount = _chat.currentMessages.length;
      setState(() {});
      
      // If we have an expected conversation and it's now selected, scroll to bottom
      if (_expectedConversationId != null && 
          _chat.selectedConversationId == _expectedConversationId) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
      
      // If new messages were added (count increased), scroll to bottom
      final currentMessageCount = _chat.currentMessages.length;
      if (currentMessageCount > previousMessageCount && _chat.selectedConversationId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && _scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            });
          }
        });
      }
    }
  }

  Future<void> _initializeChat() async {
    if (widget.initialCustomerId != null && widget.initialCustomerName != null) {
      // Start initialization without blocking - this allows UI to render immediately
      _initializeChatForCustomer();
    } else {
      // No initial customer - just initialize normally
      await _chat.initialize();
    }
  }

  Future<void> _initializeChatForCustomer() async {
    // Get rider ID first (fast - from SharedPreferences)
    final riderId = await RiderSession.getId();
    final riderName = await RiderSession.getName();
    if (riderId == null || riderId.isEmpty) {
      return;
    }
    
    // Construct conversation ID immediately (no waiting)
    final conversationId = '${widget.initialCustomerId!}_rider_$riderId';
    _expectedConversationId = conversationId;
    
    // Set rider info in provider first (before initialize)
    // This allows us to preserve the selected conversation
    _chat.setRiderInfo(riderId, riderName);
    
    // Initialize chat provider (starts listeners) - this won't clear selectedConversationId now
    _chat.initialize().then((_) {
      if (mounted) {
        // Open/create conversation (fast - checks if exists first)
        _chat.openConversationForCustomer(
          customerId: widget.initialCustomerId!,
          customerName: widget.initialCustomerName!,
        ).then((convId) {
          if (convId != null && mounted) {
            // Ensure conversation is selected (in case it wasn't preserved)
            if (_chat.selectedConversationId != convId) {
              _chat.selectConversation(convId);
            }
            
            // Scroll to bottom after messages load
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted && _chat.selectedConversationId == convId) {
                _scrollToBottom();
              }
            });
          }
        });
      }
    });
    
    // Select conversation immediately with the ID we constructed
    // This makes the UI show the chat view right away, before initialization completes
    _chat.selectConversation(conversationId);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatProviderChanged);
    _input.dispose();
    _searchController.dispose();
    _scroll.dispose();
    _videoPlayerController?.dispose();
    _chat.dispose();
    super.dispose();
  }

  void _clearMediaPreview() {
    setState(() {
      // Dispose all video controllers
      for (var item in _selectedMedia) {
        item.videoController?.dispose();
      }
      _selectedMedia.clear();
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
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

  List<RiderChatConversation> _getFilteredConversations(List<RiderChatConversation> conversations) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return conversations;
    }

    return conversations.where((conversation) {
      final customerName = conversation.customerName.toLowerCase();
      final customerId = conversation.customerId.toLowerCase();
      return customerName.contains(query) || customerId.contains(query);
    }).toList();
  }

  static const double _conversationTitleSize = 18.0;
  static const double _conversationSubtitleSize = 16.0;
  static const double _conversationMetaSize = 14.0;
  static const double _messageBodySize = 17.0;
  static const double _messageMetaSize = 14.0;
  static const double _inputFontSize = 17.0;
  static const double _searchFontSize = 16.0;

  Widget _buildSearchField({bool isInGreenHeader = false}) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: isInGreenHeader 
            ? Colors.white
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
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
            size: 18,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.clear, 
                    color: isInGreenHeader 
                        ? Colors.grey[600]
                        : Colors.grey[600],
                    size: 16,
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final ok = await _chat.sendMessage(text);
    if (ok) {
      _input.clear();
      setState(() {});
      // Wait for provider to notify listeners and UI to rebuild before scrolling
      // Use multiple post-frame callbacks to ensure ListView has updated with new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Wait a bit more to ensure the message is fully added and sorted
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && _scroll.hasClients) {
              // Scroll to the absolute bottom
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
              // Then animate smoothly if needed
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted && _scroll.hasClients) {
                  _scroll.animateTo(
                    _scroll.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          });
        }
      });
    } else {
      if (!mounted) return;
      final errorMsg = _chat.error ?? 'Failed to send message';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show error message if provider has one
    if (_chat.error != null && _chat.error!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chat.error != null && _chat.error!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_chat.error!),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
          // Clear error after showing
          _chat.clearError();
        }
      });
    }
    final isMobile = Responsive.isMobile(context);
    final hasSelectedConversation = _chat.selectedConversationId != null || 
        (widget.initialCustomerId != null && widget.initialCustomerName != null);
    
    return Scaffold(
      appBar: (isMobile && !hasSelectedConversation)
          ? null
          : AppBar(
              title: Text(
                hasSelectedConversation ? 'CHAT' : 'Chats',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              leading: hasSelectedConversation
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    )
                  : null,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await _chat.initialize();
                    setState(() {});
                  },
                ),
              ],
            ),
      body: isMobile
          ? _buildMobileLayout()
          : _buildDesktopLayout(),
    );
  }

  Widget _buildMobileLayout() {
    // If we have an initial customer ID, show chat view directly
    // This ensures that when clicking chat icon from orders, we go directly to the conversation
    if (widget.initialCustomerId != null && widget.initialCustomerName != null) {
      // Always show chat view when we have initial customer - no loading state to avoid glitch
      // The chat view will handle showing messages once they load
      return _buildChatView();
    }
    
    // Otherwise, show conversation list if no conversation selected
    if (_chat.selectedConversationId == null) {
      // Show conversations list with green header
      final mediaQuery = MediaQuery.of(context);
      final screenHeight = mediaQuery.size.height;
      final safeAreaTop = mediaQuery.padding.top;
      final totalHeaderHeight = safeAreaTop + 140.0;
      
      return Column(
        children: [
          // Green header section (1/8 of screen) with title and tabs
          Container(
            height: totalHeaderHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withOpacity(0.85),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button and Chat title row
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 18,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _conversationTitleSize,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Search bar inside green space
                    _buildSearchField(isInGreenHeader: true),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
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
              child: _buildConversationListContent(),
            ),
          ),
        ],
      );
    } else {
      // Show chat view
      return _buildChatView();
    }
  }

  Widget _buildDesktopLayout() {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final safeAreaTop = mediaQuery.padding.top;
    final totalHeaderHeight = safeAreaTop + 140.0;
    
    return Row(
      children: [
        // Left panel - Conversations list
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Column(
            children: [
              // Green header section (1/8 of screen) with title and tabs
              Container(
                height: totalHeaderHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.85),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button and Chat title row
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.of(context).maybePop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 20,
                            ),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'Chat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Search bar inside green space
                        _buildSearchField(isInGreenHeader: true),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildConversationListContent(),
              ),
            ],
          ),
        ),
        // Chat area
        Expanded(
          child: Container(
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
            child: _buildChatView(),
          ),
        ),
      ],
    );
  }

  Widget _buildConversationListContent() {
    // Combine active and archived conversations; all should be visible to rider.
    final all = <RiderChatConversation>[
      ..._chat.conversations,
      ..._chat.archivedConversations,
    ];
    // De-duplicate by id (in case of overlap)
    final Map<String, RiderChatConversation> byId = {
      for (final c in all) c.id: c,
    };
    final conversations = byId.values.toList()
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    final filteredConversations = _getFilteredConversations(conversations);
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    
    if (_chat.isLoading && conversations.isEmpty && !hasSearchQuery) {
      // Proper loading state while initial conversations are fetched
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading conversations...'),
          ],
        ),
      );
    }

    if (filteredConversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasSearchQuery ? Icons.search_off : Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              hasSearchQuery
                  ? 'No conversations matched your search'
                  : 'No conversations',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
                  itemCount: filteredConversations.length,
                  itemBuilder: (context, index) {
                    final conv = filteredConversations[index];
                    final selected = _chat.selectedConversationId == conv.id;
                    return Material(
                      color: selected ? AppTheme.primaryColor.withOpacity(0.1) : Colors.transparent,
                      child: ListTile(
                        dense: true,
                        leading: const CircleAvatar(child: Icon(Icons.person, size: 24)),
                        title: Text(
                          conv.customerName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: _conversationTitleSize,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                conv.lastMessage.isEmpty 
                                    ? 'No messages yet' 
                                    : _formatLastMessage(conv.lastMessage, conv.lastMessageSender),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: _conversationSubtitleSize,
                                  fontWeight: conv.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                  color: conv.unreadCount > 0 ? Colors.black87 : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTime(conv.lastMessageTime),
                                  style: TextStyle(fontSize: _conversationMetaSize, color: Colors.grey[700]),
                                ),
                                if (conv.unreadCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    child: Center(
                                      child: Text(
                                        conv.unreadCount > 99 ? '99+' : conv.unreadCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            // Keep deletion from overflow menu, but hide archive/unarchive
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  await _confirmDelete(context, conv.id);
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          _chat.selectConversation(conv.id);
                          setState(() {});
                          _scrollToBottom();
                        },
                      ),
                    );
                  },
                );
  }

  Future<void> _confirmArchive(BuildContext context, String conversationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive conversation?'),
        content: const Text('This conversation will be archived and hidden from your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed == true) {
      await _chat.archiveConversation(conversationId);
      setState(() {});
    }
  }

  Future<void> _confirmDelete(BuildContext context, String conversationId) async {
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
      await _chat.deleteConversation(conversationId);
      setState(() {});
    }
  }

  Widget _buildChatView() {
    // Always show chat view if we have initial customer (for smooth transition)
    if (widget.initialCustomerId != null && widget.initialCustomerName != null) {
      final customerName = _chat.selectedConversationId != null 
          ? _currentHeaderTitle() 
          : widget.initialCustomerName!;
      // Show chat view structure immediately - messages will load asynchronously
      return _buildChatViewStructure(customerName, isLoading: _chat.selectedConversationId == null);
    }
    
    // If conversation not selected yet, show select state
    if (_chat.selectedConversationId == null) {
      return const Center(child: Text('Select a conversation'));
    }

    // Get customer name from conversation
    final customerName = _currentHeaderTitle();
    return _buildChatViewStructure(customerName, isLoading: false);
  }

  Widget _buildChatViewStructure(String customerName, {required bool isLoading}) {
    return Column(
      children: [
        // Chat header (always visible for smooth transition)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person, size: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  customerName,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: _conversationTitleSize),
                ),
              ),
            ],
          ),
        ),
        // Messages area
        Expanded(
          child: isLoading && _chat.currentMessages.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : _chat.currentMessages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
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
                          SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
                          Text(
                            'No messages yet',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
                          Text(
                            'Start the conversation!',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _chat.currentMessages.length,
                      itemBuilder: (context, index) {
                        final messages = _chat.currentMessages;
                        final m = messages[index];
                        final isRider = m.sender == 'rider';
                        
                        // Group consecutive media messages from the same sender within 2 seconds
                        final groupedMessages = <RiderChatMessage>[m];
                        if ((m.imageUrl != null && m.imageUrl!.isNotEmpty) || 
                            (m.videoUrl != null && m.videoUrl!.isNotEmpty)) {
                          // Check if next messages should be grouped
                          for (int i = index + 1; i < messages.length; i++) {
                            final nextMsg = messages[i];
                            if (nextMsg.sender != m.sender) break;
                            if (nextMsg.text.isNotEmpty && 
                                (nextMsg.imageUrl == null || nextMsg.imageUrl!.isEmpty) &&
                                (nextMsg.videoUrl == null || nextMsg.videoUrl!.isEmpty)) break;
                            
                            final timeDiff = nextMsg.timestamp.difference(m.timestamp);
                            if (timeDiff.inSeconds > 2) break;
                            
                            // Only group if it's a media message (image or video)
                            if ((nextMsg.imageUrl != null && nextMsg.imageUrl!.isNotEmpty) ||
                                (nextMsg.videoUrl != null && nextMsg.videoUrl!.isNotEmpty)) {
                              groupedMessages.add(nextMsg);
                            } else {
                              break;
                            }
                          }
                        }
                        
                        // Skip rendering if this message is already part of a previous group
                        if (index > 0) {
                          final prevMsg = messages[index - 1];
                          if (prevMsg.sender == m.sender) {
                            final timeDiff = m.timestamp.difference(prevMsg.timestamp);
                            if (timeDiff.inSeconds <= 2 &&
                                ((prevMsg.imageUrl != null && prevMsg.imageUrl!.isNotEmpty) ||
                                 (prevMsg.videoUrl != null && prevMsg.videoUrl!.isNotEmpty)) &&
                                ((m.imageUrl != null && m.imageUrl!.isNotEmpty) ||
                                 (m.videoUrl != null && m.videoUrl!.isNotEmpty))) {
                              return const SizedBox.shrink();
                            }
                          }
                        }
                        
                        final hasMultipleMedia = groupedMessages.length > 1;
                        final firstMessage = groupedMessages.first;
                        final lastMessage = groupedMessages.last;
                        
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: Responsive.getSpacing(context, mobile: 4),
                            horizontal: Responsive.getHorizontalPadding(context).horizontal / 2,
                          ),
                          child: Align(
                            alignment: isRider ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: Responsive.getMaxContentWidth(context, mobile: MediaQuery.of(context).size.width * 0.75) ?? MediaQuery.of(context).size.width * 0.75,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: Responsive.getSpacing(context, mobile: 16),
                                vertical: Responsive.getSpacing(context, mobile: 12),
                              ),
                              decoration: BoxDecoration(
                                color: isRider 
                                    ? AppTheme.primaryColor 
                                    : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                                  topRight: Radius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                                  bottomLeft: isRider 
                                      ? Radius.circular(Responsive.getBorderRadius(context, mobile: 20)) 
                                      : Radius.circular(Responsive.getBorderRadius(context, mobile: 4)),
                                  bottomRight: isRider 
                                      ? Radius.circular(Responsive.getBorderRadius(context, mobile: 4)) 
                                      : Radius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                                ),
                                border: isRider 
                                    ? null 
                                    : Border.all(
                                        color: Colors.grey[300]!,
                                        width: 1,
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isRider)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
                                      child: Text(
                                        _currentHeaderTitle(),
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  // Display grouped media in grid if multiple
                                  if (hasMultipleMedia)
                                    _buildGroupedMedia(groupedMessages, isRider)
                                  else ...[
                                    // Display single image if present
                                    if (firstMessage.imageUrl != null && firstMessage.imageUrl!.isNotEmpty) ...[
                                      _buildImageMessage(firstMessage.imageUrl!, isRider),
                                      if (firstMessage.text.isNotEmpty) SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
                                    ],
                                    // Display single video if present
                                    if (firstMessage.videoUrl != null && firstMessage.videoUrl!.isNotEmpty) ...[
                                      _buildVideoMessage(firstMessage.videoUrl!, firstMessage.thumbnailUrl, isRider),
                                      if (firstMessage.text.isNotEmpty) SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
                                    ],
                                  ],
                                  // Display text if present (only from first message)
                                  if (firstMessage.text.isNotEmpty)
                                    Text(
                                      firstMessage.text,
                                      style: TextStyle(
                                        color: isRider ? Colors.white : Colors.black87,
                                        fontSize: Responsive.getFontSize(context, mobile: 17),
                                      ),
                                    ),
                                  SizedBox(height: Responsive.getSpacing(context, mobile: 2)),
                                  Text(
                                    _formatTime(lastMessage.timestamp),
                                    style: TextStyle(
                                      color: isRider ? Colors.white70 : Colors.grey[600],
                                      fontSize: Responsive.getFontSize(context, mobile: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        // Input area - Modern Messenger style
        Container(
          padding: EdgeInsets.only(
            left: Responsive.getSpacing(context, mobile: 12),
            right: Responsive.getSpacing(context, mobile: 12),
            top: Responsive.getSpacing(context, mobile: 8),
            bottom: MediaQuery.of(context).padding.bottom + Responsive.getSpacing(context, mobile: 8),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Media preview
              if (_selectedMedia.isNotEmpty)
                _buildMediaPreview(),
              // Upload progress indicator
              if (_chat.isUploading)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _chat.uploadProgress,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uploading... ${(_chat.uploadProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  // Image/Video picker button
                  IconButton(
                    onPressed: isLoading || _chat.isUploading ? null : _showMediaPicker,
                    icon: Icon(
                      Icons.add_photo_alternate,
                      color: isLoading || _chat.isUploading ? Colors.grey : AppTheme.primaryColor,
                      size: 24,
                    ),
                    tooltip: 'Add photo or video',
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 24)),
                      ),
                      child: TextField(
                        controller: _input,
                        enabled: !isLoading && !_chat.isUploading,
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 17),
                        ),
                        decoration: InputDecoration(
                          hintText: isLoading ? 'Loading...' : _chat.isUploading ? 'Uploading...' : 'Type a message...',
                          hintStyle: TextStyle(
                            color: isLoading || _chat.isUploading ? Colors.grey : Colors.grey[600],
                            fontSize: Responsive.getFontSize(context, mobile: 17),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: Responsive.getSpacing(context, mobile: 16),
                            vertical: Responsive.getSpacing(context, mobile: 12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: isLoading || _chat.isUploading ? null : (_) => _send(),
                      ),
                    ),
                  ),
                  SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: (isLoading || _chat.isUploading || (_input.text.trim().isEmpty && _selectedMedia.isEmpty)) ? null : (_selectedMedia.isNotEmpty ? _sendSelectedMedia : _send),
                      icon: const Icon(Icons.send, size: 20, color: Colors.white),
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _currentHeaderTitle() {
    final id = _chat.selectedConversationId;
    if (id == null) {
      // If we have initial customer name, use it as fallback
      return widget.initialCustomerName ?? 'No conversation selected';
    }
    
    // Check all conversations (including archived) to find the customer name
    final allConvs = _chat.allConversations;
    final conv = allConvs.where((c) => c.id == id).toList();
    if (conv.isNotEmpty && conv.first.customerName.isNotEmpty && conv.first.customerName.toLowerCase() != 'customer') {
      return conv.first.customerName;
    }
    
    // Fallback to initial customer name if available
    if (widget.initialCustomerName != null && widget.initialCustomerName!.isNotEmpty) {
      return widget.initialCustomerName!;
    }
    
    return 'Conversation';
  }

  String _formatLastMessage(String lastMessage, String lastMessageSender) {
    // Add sender indicator if message is from customer
    if (lastMessageSender == 'customer') {
      // Check if it's an image or video message
      if (lastMessage.contains('📷') || lastMessage.toLowerCase().contains('image')) {
        return '📷 Image';
      } else if (lastMessage.contains('🎥') || lastMessage.toLowerCase().contains('video')) {
        return '🎥 Video';
      }
      return lastMessage;
    } else {
      // Rider's own messages - show "You: " prefix or just the message
      if (lastMessage.contains('📷') || lastMessage.toLowerCase().contains('image')) {
        return 'You: 📷 Image';
      } else if (lastMessage.contains('🎥') || lastMessage.toLowerCase().contains('video')) {
        return 'You: 🎥 Video';
      }
      return 'You: $lastMessage';
    }
  }

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.purple),
              title: const Text('Choose Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.red),
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

  Future<void> _sendSelectedMedia() async {
    if (_selectedMedia.isEmpty) return;

    final caption = _input.text.trim();
    _input.clear();

    bool allSuccess = true;
    String? lastError;

    // Use the same timestamp for all media items so they can be grouped
    final baseTimestamp = DateTime.now();

    // Send all media items with the same timestamp (or very close)
    for (int i = 0; i < _selectedMedia.length; i++) {
      final item = _selectedMedia[i];
      bool success = false;
      
      // Only add caption to the first message
      final shouldAddCaption = i == 0 && caption.isNotEmpty;
      
      // Use the same timestamp for all items (add milliseconds to keep order)
      final itemTimestamp = baseTimestamp.add(Duration(milliseconds: i));
      
      if (item.type == 'image') {
        success = await _chat.sendImageMessage(
          item.file,
          caption: shouldAddCaption ? caption : null,
          timestamp: itemTimestamp,
        );
      } else if (item.type == 'video') {
        success = await _chat.sendVideoMessage(
          item.file,
          caption: shouldAddCaption ? caption : null,
          timestamp: itemTimestamp,
        );
      }

      if (!success) {
        allSuccess = false;
        lastError = _chat.error;
        // Continue sending other items even if one fails
      }

      // Small delay between sends to avoid overwhelming the server
      if (i < _selectedMedia.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
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

    if (mounted) {
      _clearMediaPreview();
      setState(() {});
      _scrollToBottom();
    }
  }

  Widget _buildMediaPreview() {
    if (_selectedMedia.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _FullScreenImageViewer(imageUrl: item.file.path, isFile: true),
                              ),
                            );
                          } else if (item.type == 'video') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _VideoPlayerScreen(videoUrl: item.file.path, isFile: true),
                              ),
                            );
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

  Widget _buildGroupedMedia(List<RiderChatMessage> messages, bool isRider) {
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
    
    return GridView.builder(
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullScreenImageViewer(imageUrl: msg.imageUrl!, isFile: false),
                  ),
                );
              } else if (hasVideo) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _VideoPlayerScreen(videoUrl: msg.videoUrl!, isFile: false),
                  ),
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage)
                  Image.network(
                    msg.imageUrl!,
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
                      msg.thumbnailUrl != null && msg.thumbnailUrl!.isNotEmpty
                          ? Image.network(
                              msg.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(color: Colors.grey[900]);
                              },
                            )
                          : Container(color: Colors.grey[900]),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
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
    );
  }

  Widget _buildImageMessage(String imageUrl, bool isRider) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullScreenImageViewer(imageUrl: imageUrl, isFile: false),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 250,
            maxHeight: 300,
          ),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 250,
                height: 300,
                color: Colors.grey[200],
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
                width: 250,
                height: 200,
                color: Colors.grey[300],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.grey[600]),
                    const SizedBox(height: 8),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVideoMessage(String videoUrl, String? thumbnailUrl, bool isRider) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _VideoPlayerScreen(videoUrl: videoUrl, isFile: false),
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 250,
          maxHeight: 300,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  thumbnailUrl,
                  width: 250,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 250,
                      height: 300,
                      color: Colors.grey[900],
                    );
                  },
                ),
              )
            else
              Container(
                width: 250,
                height: 300,
                color: Colors.grey[900],
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
                    dt.month == now.month &&
                    dt.day == now.day;
    
    if (isToday) {
      // Show just time for today's messages (e.g., "3:47 PM")
      final hour = dt.hour == 0 
          ? 12 
          : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$hour:$minute $ampm';
    } else {
      // Show date and time for older messages
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year;
      final hour = dt.hour == 0 
          ? 12 
          : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      
      // Show short format for recent dates, full for older
      final diff = now.difference(dt);
      if (diff.inDays < 7) {
        return '$day/$month, $hour:$minute $ampm';
      } else {
        return '$day/$month/$year, $hour:$minute $ampm';
      }
    }
  }
}

// Full-screen image viewer
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final bool isFile;

  const _FullScreenImageViewer({required this.imageUrl, this.isFile = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: isFile
              ? Image.file(
                  File(imageUrl),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(Icons.error, color: Colors.white, size: 48),
                    );
                  },
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(Icons.error, color: Colors.white, size: 48),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// Video player screen
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final bool isFile;

  const _VideoPlayerScreen({required this.videoUrl, this.isFile = false});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      if (widget.isFile) {
        _controller = VideoPlayerController.file(File(widget.videoUrl));
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      }
      await _controller!.initialize();
      setState(() {
        _isInitialized = true;
      });
      _controller!.play();
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _hasError
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.white, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Failed to load video',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : _isInitialized && _controller != null
                ? AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  )
                : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

