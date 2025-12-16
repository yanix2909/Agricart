import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/featured_media_provider.dart';
import '../../utils/theme.dart';
import '../../utils/order_schedule.dart';
import '../../utils/responsive.dart';
import '../profile/profile_screen.dart';
import '../products/product_detail_screen.dart';
import '../orders/order_review_screen.dart';
import '../cart/cart_screen.dart';
import '../orders/order_rating_screen.dart';
import '../orders/order_phases_screen.dart';
import '../orders/order_detail_screen.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/customer.dart';
import 'dart:async';
import '../../services/notification_service.dart';
import '../../models/notification.dart';
import '../notifications/notification_screen.dart';
import '../qr/qr_scanner_screen.dart';
import '../chat/chat_screen.dart';
import '../../providers/featured_media_provider.dart' show FeaturedMediaItem, FeaturedMediaType;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  StreamSubscription<CustomerNotification?>? _verificationSub;
  bool _isPolicyDropdownExpanded = false;
  final TextEditingController _productSearchController = TextEditingController();
  String _productSearchQuery = '';
  String _selectedSortOption = 'Featured';
  final List<String> _sortOptions = const [
    'Featured',
    'Price: Low to High',
    'Price: High to Low',
    'Alphabetical',
  ];
  static const String _productFilterBackground = '';
  static const String _homeHeroBackground = 'assets/images/mewkmewk.jpg';

  @override
  void initState() {
    super.initState();
    _loadData();
    // Add listener for order schedule changes
    OrderSchedule.addListener(_onOrderScheduleChanged);
  }

  Widget _buildHeroSection({
    required BuildContext context,
  }) {
    return Consumer<FeaturedMediaProvider>(
      builder: (context, featuredProvider, child) {
        final mediaItems = featuredProvider.featuredMedia;
        
        if (mediaItems.isEmpty) {
          // Fallback to default image if no featured media
          return Container(
            height: Responsive.getHeroHeight(context),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 28)),
              image: const DecorationImage(
                image: AssetImage(_homeHeroBackground),
                fit: BoxFit.cover,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Logos at the upper right (always visible)
                Positioned(
                  top: Responsive.getSpacing(context, mobile: 16),
                  right: Responsive.getSpacing(context, mobile: 16),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.getSpacing(context, mobile: 8),
                      vertical: Responsive.getSpacing(context, mobile: 6),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/calcoa-logo.png',
                          height: Responsive.getImageSize(context, mobile: 24),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                        SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                        Image.asset(
                          'assets/images/ormoc_logo.png',
                          height: Responsive.getImageSize(context, mobile: 24),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                        SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                        Image.asset(
                          'assets/images/evsu_logo.png',
                          height: Responsive.getImageSize(context, mobile: 24),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        
        return Container(
          height: Responsive.getHeroHeight(context),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 28)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 28)),
            child: _FeaturedMediaCarousel(mediaItems: mediaItems),
          ),
        );
      },
    );
  }

  Widget _buildQuickStatsRow(Customer? customer, CustomerProvider customerProvider) {
    final isLoading = customerProvider.isLoading;
    
    final stats = [
      _HomeStat(
        label: 'Total Orders',
        value: isLoading ? '...' : '${customerProvider.cumulativeTotalOrders}',
        icon: Icons.receipt_long,
        isLoading: isLoading,
      ),
      _HomeStat(
        label: 'Total Spent',
        value: isLoading ? '...' : '\u20B1${customerProvider.cumulativeTotalSpent.toStringAsFixed(2)}',
        icon: Icons.payments,
        isLoading: isLoading,
      ),
    ];

    return Row(
      children: stats.asMap().entries.map((entry) {
        final index = entry.key;
        final stat = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 12),
            child: _buildStatChip(stat),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatChip(_HomeStat stat) {
    return Builder(
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.getHorizontalPadding(context).left,
          vertical: Responsive.getSpacing(context, mobile: 20),
        ),
        decoration: BoxDecoration(
          color: AppTheme.creamLight,
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 14)),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2), width: 1),
              ),
              child: stat.isLoading
                  ? SizedBox(
                      width: Responsive.getIconSize(context, mobile: 24),
                      height: Responsive.getIconSize(context, mobile: 24),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                    )
                  : Icon(stat.icon, color: AppTheme.primaryColor, size: Responsive.getIconSize(context, mobile: 24)),
            ),
            SizedBox(width: Responsive.getSpacing(context, mobile: 14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  stat.isLoading
                      ? SizedBox(
                          height: Responsive.getFontSize(context, mobile: 20, tablet: 22) * 1.2,
                          child: Center(
                            child: SizedBox(
                              width: Responsive.getFontSize(context, mobile: 20, tablet: 22),
                              height: Responsive.getFontSize(context, mobile: 20, tablet: 22),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                              ),
                            ),
                          ),
                        )
                      : RichText(
                          text: TextSpan(
                            children: [
                              if (stat.value.startsWith('\u20B1'))
                                TextSpan(
                                  text: '\u20B1',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontFamilyFallback: ['Arial', 'sans-serif'],
                                    fontSize: Responsive.getFontSize(context, mobile: 20, tablet: 22),
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryColor,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              TextSpan(
                                text: stat.value.startsWith('\u20B1') 
                                    ? stat.value.substring(1) 
                                    : stat.value,
                                style: TextStyle(
                                  fontSize: Responsive.getFontSize(context, mobile: 20, tablet: 22),
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryColor,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                  Text(
                    stat.label,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: Responsive.getFontSize(context, mobile: 12, tablet: 13),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 24)),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.creamLight, AppTheme.creamColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 24)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withOpacity(0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: Responsive.getIconSize(context, mobile: 28),
                ),
              ),
              SizedBox(width: Responsive.getSpacing(context, mobile: 18)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: Responsive.getFontSize(context, mobile: 17, tablet: 19),
                            color: AppTheme.primaryColor,
                            letterSpacing: -0.3,
                          ),
                    ),
                    SizedBox(height: Responsive.getSpacing(context, mobile: 6)),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                            height: 1.5,
                            fontSize: Responsive.getFontSize(context, mobile: 13, tablet: 14),
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: Responsive.getIconSize(context, mobile: 16),
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
    required String title,
    required VoidCallback onViewAll,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.getSpacing(context, mobile: 12),
            vertical: Responsive.getSpacing(context, mobile: 6),
          ),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2), width: 1),
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: Responsive.getFontSize(context, mobile: 20, tablet: 22),
              color: AppTheme.primaryColor,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.creamColor,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2), width: 1),
          ),
          child: TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.getSpacing(context, mobile: 12),
                vertical: Responsive.getSpacing(context, mobile: 6),
              ),
              minimumSize: Size(
                64,
                Responsive.getButtonHeight(context, mobile: 36),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View all',
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 14),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: Responsive.getSpacing(context, mobile: 4)),
                Icon(
                  Icons.arrow_forward,
                  size: Responsive.getIconSize(context, mobile: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    if (authProvider.currentCustomer != null) {
      // CRITICAL: Clear all data first to prevent cross-account contamination
      customerProvider.clearAllData();
      
      // Set current customer ID for persistence
      customerProvider.setCurrentCustomerId(authProvider.currentCustomer!.uid);
      
      // Initialize chat for this customer
      chatProvider.initializeChat(authProvider.currentCustomer!.uid);
      
      // Load orders from local storage first (customer-specific)
      await customerProvider.loadOrdersFromStorage(authProvider.currentCustomer!.uid);
      
      await customerProvider.loadProducts();
      await customerProvider.loadOrders(authProvider.currentCustomer!.uid);
      
      // Load weekly top products (resets every Monday 12:00 AM)
      await customerProvider.loadTopProducts();
      
      // Clear notifications before loading new user's notifications
      notificationProvider.clearNotificationsBeforeLoading();
      await notificationProvider.loadNotifications(authProvider.currentCustomer!.uid);
      // Start realtime listening for new notifications
      notificationProvider.listenToNotifications(authProvider.currentCustomer!.uid);

      // Note: hasLoggedInBefore flag will be updated when user interacts with the app
      // This ensures new users see "Welcome" message first

      // Show "Account Verified" notification only on first login after verification
      // This notification should only be created once, not every time the dashboard loads
      if (!authProvider.currentCustomer!.hasLoggedInBefore && 
          authProvider.currentCustomer!.verificationStatus == 'approved') {
        
        // Check if notification already exists to prevent duplicates
        final existingNotifications = notificationProvider.notifications;
        final hasVerificationNotification = existingNotifications.any(
          (n) => n.type == 'verification' && n.title == 'Account Verified'
        );
        
        if (!hasVerificationNotification) {
          final now = DateTime.now();
          debugPrint('=== CREATING ACCOUNT VERIFIED NOTIFICATION (FIRST LOGIN) ===');
          debugPrint('Current time: $now');
          debugPrint('Timestamp: ${now.millisecondsSinceEpoch}');
          
          final notification = CustomerNotification(
            id: 'verification_approved_${now.millisecondsSinceEpoch}',
            title: 'Account Verified',
            message: 'Account verified successfully. Enjoy shopping!',
            type: 'verification',
            timestamp: now,
            isRead: false,
          );
          
          debugPrint('Notification created with timestamp: ${notification.timestamp}');
          
          await NotificationService.sendNotification(
            authProvider.currentCustomer!.uid,
            notification,
          );
          
          debugPrint('Notification sent to database');
          debugPrint('===============================================');
          
          // Immediately mark user as having logged in to prevent notification from showing again
          await authProvider.markUserAsLoggedInBefore();
        }
      }
    }
    
    // Load cart items from storage (customer-specific)
    if (authProvider.currentCustomer != null) {
      await customerProvider.loadCartFromStorage(authProvider.currentCustomer!.uid);
    }
  }

  @override
  void dispose() {
    _verificationSub?.cancel();
    OrderSchedule.removeListener(_onOrderScheduleChanged);
    _productSearchController.dispose();
    super.dispose();
  }

  // Handle order schedule changes
  void _onOrderScheduleChanged() {
    if (mounted) {
      print('🔄 Order schedule changed, refreshing dashboard...');
      setState(() {
        // Force rebuild to update ordering status
      });
    }
  }

  List<_ProductMediaItem> _getProductMediaItems(Product product) {
    final mediaItems = <_ProductMediaItem>[];

    final imageUrls = <String>[];
    if (product.imageUrls.isNotEmpty) {
      imageUrls.addAll(product.imageUrls);
    }
    if (product.imageUrl.isNotEmpty && !imageUrls.contains(product.imageUrl)) {
      imageUrls.add(product.imageUrl);
    }
    mediaItems.addAll(
      imageUrls
          .map((url) => _getSupabaseImageUrl(url, product.id))
          .where((url) => url.isNotEmpty)
          .map((url) => _ProductMediaItem(url: url, type: _ProductMediaType.image)),
    );

    final videoUrls = <String>[];
    if (product.videoUrls.isNotEmpty) {
      videoUrls.addAll(product.videoUrls);
    }
    if (product.videoUrl.isNotEmpty && !videoUrls.contains(product.videoUrl)) {
      videoUrls.add(product.videoUrl);
    }
    mediaItems.addAll(
      videoUrls
          .map((url) => _getSupabaseVideoUrl(url, product.id))
          .where((url) => url.isNotEmpty)
          .map((url) => _ProductMediaItem(url: url, type: _ProductMediaType.video)),
    );

    return mediaItems;
  }

  // Get Supabase image URL - handles both full URLs and file paths
  String _getSupabaseImageUrl(String imageUrl, String productId) {
    if (imageUrl.isEmpty) return '';
    
    // If it's already a full URL, return as is
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      // Fix duplicate bucket names if present
      if (imageUrl.contains('/product_image/product_image/')) {
        return imageUrl.replaceAll('/product_image/product_image/', '/product_image/');
      }
      return imageUrl;
    }
    
    // If it's a file path, construct Supabase public URL
    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'product_image';
    
    // Remove bucket name if already present
    String filePath = imageUrl;
    if (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1);
    }
    
    // If it doesn't contain product ID, add it
    if (!filePath.startsWith('$productId/') && !filePath.contains('/')) {
      filePath = '$productId/$filePath';
    }
    
    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  String _getSupabaseVideoUrl(String videoUrl, String productId) {
    if (videoUrl.isEmpty) return '';

    if (videoUrl.startsWith('http://') || videoUrl.startsWith('https://')) {
      if (videoUrl.contains('/product_video/product_video/')) {
        return videoUrl.replaceAll('/product_video/product_video/', '/product_video/');
      }
      return videoUrl;
    }

    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'product_video';

    String filePath = videoUrl;
    if (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1);
    }

    if (!filePath.startsWith('$productId/')) {
      filePath = '$productId/$filePath';
    }

    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  void _handleScannedQRData(String data) {
    // Show dialog with scanned data and options
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('QR Code Scanned'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Data: $data'),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              const Text(
                'What would you like to do with this data?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              const Text('• Search for products'),
              const Text('• View order details'),
              const Text('• Navigate to location'),
              const Text('• Copy to clipboard'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: Implement specific actions based on QR data
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Processing QR data: $data'),
                    backgroundColor: AppTheme.primaryColor,
                  ),
                );
              },
              child: const Text('Process'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: _currentIndex == 3,
      appBar: _currentIndex == 3
          ? null
          : AppBar(
              toolbarHeight: Responsive.getAppBarHeight(context),
              centerTitle: false,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/agricart_logo.png',
                    height: Responsive.getHeight(context, mobile: 32),
                    width: Responsive.getWidth(context, mobile: 32),
                    fit: BoxFit.contain,
                  ),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  Text(
                    'AgriCart',
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 20)),
                  ),
                ],
              ),
              actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NotificationScreen(),
                    ),
                  );
                },
              ),
              // Notification badge
              Consumer<NotificationProvider>(
                builder: (context, notificationProvider, child) {
                  if (notificationProvider.unreadCount == 0) return const SizedBox.shrink();
                  return Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 2)),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        notificationProvider.unreadCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Responsive.getFontSize(context, mobile: 10),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          // Chat Button
          Consumer2<AuthProvider, ChatProvider>(
            builder: (context, authProvider, chatProvider, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat),
                    tooltip: 'Chat with Staff',
                    onPressed: () {
                      // Ensure chat is initialized before navigating
                      if (authProvider.currentCustomer != null) {
                        chatProvider.initializeChat(authProvider.currentCustomer!.uid);
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ChatScreen(),
                        ),
                      );
                    },
                  ),
                  // Chat badge
                  if (chatProvider.unreadMessageCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 2)),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          chatProvider.unreadMessageCount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Responsive.getFontSize(context, mobile: 10),
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // QR Scanner Button
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR Code',
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const QRScannerScreen(),
                ),
              );
              if (result != null) {
                // Handle the scanned QR data
                _handleScannedQRData(result);
              }
            },
          ),
          Stack(
            children: [
                             IconButton(
                 icon: const Icon(Icons.shopping_cart),
                 onPressed: () {
                   Navigator.of(context).push(
                     MaterialPageRoute(
                       builder: (context) => const CartScreen(),
                     ),
                   );
                 },
               ),
              // Cart badge
              Consumer<CustomerProvider>(
                builder: (context, provider, child) {
                  if (provider.cartItems.isEmpty) return const SizedBox.shrink();
                  return Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 2)),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        provider.cartItems.length.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Responsive.getFontSize(context, mobile: 10),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          height: Responsive.getBottomNavHeight(context),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
              // Mark user as having logged in when they interact with the app
              Provider.of<AuthProvider>(context, listen: false).markUserAsLoggedInBefore();
            },
            backgroundColor: AppTheme.primaryColor,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white.withOpacity(0.7),
            type: BottomNavigationBarType.fixed,
            selectedFontSize: Responsive.getFontSize(context, mobile: 12),
            unselectedFontSize: Responsive.getFontSize(context, mobile: 12),
            iconSize: Responsive.getIconSize(context, mobile: 24),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.shopping_bag),
                label: 'Products',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt),
                label: 'Orders',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildProductsTab();
      case 2:
        return _buildOrdersTab();
      case 3:
        return const ProfileScreen(showAppBar: false);
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return Consumer2<AuthProvider, CustomerProvider>(
      builder: (context, authProvider, customerProvider, child) {
        final customer = authProvider.currentCustomer;
        
        return DecoratedBox(
          decoration: const BoxDecoration(color: AppTheme.backgroundColor),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              Responsive.getHorizontalPadding(context).left,
              Responsive.getSpacing(context, mobile: 20),
              Responsive.getHorizontalPadding(context).right,
              Responsive.getSpacing(context, mobile: 24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroSection(
                  context: context,
                ),
                SizedBox(height: Responsive.getSpacing(context, mobile: 20)),
                _buildOrderingPolicyDropdown(),
                SizedBox(height: Responsive.getSpacing(context, mobile: 20)),
                _buildQuickStatsRow(customer, customerProvider),
                SizedBox(height: Responsive.getSpacing(context, mobile: 24)),
                _buildQuickActionCard(
                  context: context,
                  title: 'QR Scanner',
                  description: 'Scan product, order, or pickup QR codes in one tap.',
                  icon: Icons.qr_code_scanner,
                  onTap: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const QRScannerScreen(),
                      ),
                    );
                    if (result != null) {
                      _handleScannedQRData(result);
                    }
                  },
                ),
                SizedBox(height: Responsive.getSpacing(context, mobile: 28)),
                _buildSectionHeader(
                  context: context,
                  title: 'Top Products',
                  onViewAll: () {
                    setState(() {
                      _currentIndex = 1;
                    });
                  },
                ),
                SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                
                if (customerProvider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (customerProvider.topProducts.isEmpty)
                  const Center(child: Text('No top products yet'))
                else
                  SizedBox(
                    height: Responsive.getHorizontalCardHeight(context),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: customerProvider.topProducts.take(5).length,
                      itemBuilder: (context, index) {
                        final product = customerProvider.topProducts[index];
                        final mediaItems = _getProductMediaItems(product);
                        final soldQuantity = customerProvider.getSoldQuantity(product.id);
                        return Container(
                          width: Responsive.getHorizontalCardWidth(context),
                          margin: EdgeInsets.only(right: Responsive.getSpacing(context, mobile: 14)),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                Provider.of<AuthProvider>(context, listen: false).markUserAsLoggedInBefore();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProductDetailScreen(product: product),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.creamLight,
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 22)),
                                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.1), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withOpacity(0.08),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                        ),
                                        child: _buildCompactProductMediaCarousel(mediaItems, product.id),
                                      ),
                                    ),
                                    Padding(
                                      padding: Responsive.getPadding(context).copyWith(
                                        left: Responsive.getSpacing(context, mobile: 12),
                                        right: Responsive.getSpacing(context, mobile: 12),
                                        top: Responsive.getSpacing(context, mobile: 12),
                                        bottom: Responsive.getSpacing(context, mobile: 10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: Responsive.getFontSize(context, mobile: 14),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: true,
                                          ),
                                          SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            flex: 3,
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '\u20B1',
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontFamilyFallback: ['Arial', 'sans-serif'],
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: Responsive.getFontSize(context, mobile: 15),
                                    ),
                                  ),
                                  TextSpan(
                                    text: product.price.toStringAsFixed(2),
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: Responsive.getFontSize(context, mobile: 15),
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: Responsive.getSpacing(context, mobile: 4)),
                          Flexible(
                            flex: 2,
                            fit: FlexFit.loose,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: Responsive.getSpacing(context, mobile: 4),
                                vertical: Responsive.getSpacing(context, mobile: 2),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${product.availableQuantity} ${product.unit}',
                                  style: TextStyle(
                                    fontSize: Responsive.getFontSize(context, mobile: 9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                                          if (soldQuantity > 0)
                                            Padding(
                                              padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 6)),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.shopping_bag,
                                                    size: Responsive.getIconSize(context, mobile: 12),
                                                    color: Colors.green[700],
                                                  ),
                                                  SizedBox(width: Responsive.getSpacing(context, mobile: 4)),
                                                  Flexible(
                                                    child: Text(
                                                      '${soldQuantity.toDouble().toStringAsFixed(1)} kg sold',
                                                      style: TextStyle(
                                                        color: Colors.green[700],
                                                        fontSize: Responsive.getFontSize(context, mobile: 10),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
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
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Product> _sortProducts(List<Product> products) {
    final sorted = List<Product>.from(products);
    switch (_selectedSortOption) {
      case 'Price: Low to High':
        sorted.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'Price: High to Low':
        sorted.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'Alphabetical':
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      default:
        break;
    }
    return sorted;
  }

  Widget _buildProductsTab() {
    return Consumer<CustomerProvider>(
      builder: (context, customerProvider, child) {
        if (customerProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final allProducts = customerProvider.products;
        if (allProducts.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              await customerProvider.refreshProducts();
            },
            child: const Center(
              child: Text('No products available'),
            ),
          );
        }

        final query = _productSearchQuery.trim().toLowerCase();
        var visibleProducts = allProducts.where((product) {
          if (query.isEmpty) return true;
          return product.name.toLowerCase().contains(query);
        }).toList();
        visibleProducts = _sortProducts(visibleProducts);

        final Map<String, List<Product>> grouped = {};
        for (final p in visibleProducts) {
          grouped.putIfAbsent(p.category, () => []).add(p);
        }
        final categories = grouped.keys.toList()..sort();
        final orderingOpen = OrderSchedule.canPlaceOrder();
        final nextMonday = OrderSchedule.getNextOrderingPeriodStart();
        final nextThursday = DateTime(nextMonday.year, nextMonday.month, nextMonday.day + 3, 20, 0);
          return DecoratedBox(
           decoration: BoxDecoration(
             color: AppTheme.backgroundColor,
           ),
          child: RefreshIndicator(
            onRefresh: () async {
              await customerProvider.refreshProducts();
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Responsive.getHorizontalPadding(context).left,
                Responsive.getSpacing(context, mobile: 20),
                Responsive.getHorizontalPadding(context).right,
                Responsive.getBottomNavHeight(context) + Responsive.getSpacing(context, mobile: 16),
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildProductFiltersSection(),
                SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
                if (!orderingOpen)
                  _buildOrderingClosedNotice(
                    context: context,
                    nextMonday: nextMonday,
                    nextThursday: nextThursday,
                  ),
                if (categories.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 4)),
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: Responsive.getIconSize(context, mobile: 48), color: Colors.grey),
                        SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                        Text(
                          'No products match “$_productSearchQuery”.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...categories.map(
                    (cat) {
                      final items = grouped[cat]!;
                      final showCategoryTitle = cat.trim().toLowerCase() != 'vegetables';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showCategoryTitle)
                            Text(
                              cat,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                          if (showCategoryTitle) SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: Responsive.getProductGridColumns(context),
                              crossAxisSpacing: Responsive.getSpacing(context, mobile: 14),
                              mainAxisSpacing: Responsive.getSpacing(context, mobile: 14),
                              childAspectRatio: Responsive.getProductAspectRatio(context),
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final product = items[index];
                              final mediaItems = _getProductMediaItems(product);
                              final soldQuantity = customerProvider.getSoldQuantity(product.id);
                              return _buildProductGridItem(
                                context: context,
                                product: product,
                                mediaItems: mediaItems,
                                soldQuantity: soldQuantity,
                              );
                            },
                          ),
                          SizedBox(height: Responsive.getSpacing(context, mobile: 28)),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductFiltersSection() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _productSearchController,
            onChanged: (value) {
              setState(() {
                _productSearchQuery = value;
              });
            },
            style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search products',
              hintStyle: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
              prefixIcon: Icon(Icons.search, size: Responsive.getIconSize(context, mobile: 20)),
              suffixIcon: _productSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, size: Responsive.getIconSize(context, mobile: 18)),
                      onPressed: () {
                        setState(() {
                          _productSearchQuery = '';
                          _productSearchController.clear();
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),
        SizedBox(width: Responsive.getSpacing(context, mobile: 12)),
        SizedBox(
          height: Responsive.getButtonHeight(context, mobile: 44),
          width: Responsive.getButtonHeight(context, mobile: 44),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 14))),
            ),
            onPressed: () {
              _showSortOptions(context);
            },
            child: Icon(Icons.tune, size: Responsive.getIconSize(context, mobile: 20)),
          ),
        ),
      ],
    );
  }

  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Responsive.getBorderRadius(context, mobile: 20)),
        ),
      ),
      constraints: BoxConstraints(
        maxWidth: Responsive.getDialogWidth(context) ?? double.infinity,
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _sortOptions.map((option) {
              final isSelected = option == _selectedSortOption;
              return ListTile(
                title: Text(
                  option,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? AppTheme.primaryColor : null,
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
                onTap: () {
                  setState(() {
                    _selectedSortOption = option;
                  });
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildOrderingClosedNotice({
    required BuildContext context,
    required DateTime nextMonday,
    required DateTime nextThursday,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 20)),
      padding: Responsive.getPadding(context),
      decoration: BoxDecoration(
        color: AppTheme.creamLight,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange, size: Responsive.getIconSize(context, mobile: 20)),
              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
              Text(
                'Ordering is currently closed',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange),
              ),
            ],
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 10)),
          Text(
            'Order window reopens\nMon ${_formatDateShort(nextMonday)} · 12:00 AM  —  Thu ${_formatDateShort(nextThursday)} · 8:00 PM',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[d.month - 1];
    return '$month ${d.day}, ${d.year}';
  }

  Widget _buildProductGridItem({
    required BuildContext context,
    required Product product,
    required List<_ProductMediaItem> mediaItems,
    required int soldQuantity,
  }) {
    // Product is unavailable if isAvailable is false
    // Note: isAvailable already considers both is_available and status fields from database
    final isUnavailable = !product.isAvailable;
    // Product is sold out if availableQuantity is 0 but product is still available
    final isSoldOut = product.availableQuantity <= 0 && product.isAvailable;
    // Product is non-interactive if unavailable or sold out
    final isNonInteractive = isUnavailable || isSoldOut;
    
    return Material(
      color: Colors.transparent,
      child: AbsorbPointer(
        absorbing: isNonInteractive,
        child: InkWell(
          onTap: isNonInteractive ? null : () {
            Provider.of<AuthProvider>(context, listen: false).markUserAsLoggedInBefore();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: product),
              ),
            );
          },
          // Disable splash and highlight when unavailable or sold out
          splashColor: isNonInteractive ? Colors.transparent : null,
          highlightColor: isNonInteractive ? Colors.transparent : null,
          child: Container(
            decoration: BoxDecoration(
              color: isUnavailable 
                  ? Colors.red.shade50 
                  : isSoldOut
                      ? Colors.orange.shade50
                      : AppTheme.creamLight,
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
              border: Border.all(
                color: isUnavailable 
                    ? Colors.red.shade300 
                    : isSoldOut
                        ? Colors.orange.shade300
                        : AppTheme.primaryColor.withOpacity(0.12), 
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isUnavailable 
                      ? Colors.red.withOpacity(0.2)
                      : isSoldOut
                          ? Colors.orange.withOpacity(0.2)
                          : AppTheme.primaryColor.withOpacity(0.1),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                    ),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        children: [
                          _buildGridProductMediaCarousel(mediaItems, product.id),
                          if (isUnavailable)
                            Container(
                              color: Colors.red.withOpacity(0.3),
                              child: Center(
                                child: Icon(
                                  Icons.block,
                                  color: Colors.red.shade700,
                                  size: Responsive.getIconSize(context, mobile: 48),
                                ),
                              ),
                            ),
                          if (isSoldOut)
                            Container(
                              color: Colors.orange.withOpacity(0.3),
                              child: Center(
                                child: Icon(
                                  Icons.remove_shopping_cart,
                                  color: Colors.orange.shade700,
                                  size: Responsive.getIconSize(context, mobile: 48),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (isUnavailable)
                    Positioned(
                      top: Responsive.getSpacing(context, mobile: 8),
                      right: Responsive.getSpacing(context, mobile: 8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: Responsive.getSpacing(context, mobile: 8),
                          vertical: Responsive.getSpacing(context, mobile: 4),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'Unavailable',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: Responsive.getFontSize(context, mobile: 11),
                          ),
                        ),
                      ),
                    ),
                  if (isSoldOut)
                    Positioned(
                      top: Responsive.getSpacing(context, mobile: 8),
                      right: Responsive.getSpacing(context, mobile: 8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: Responsive.getSpacing(context, mobile: 8),
                          vertical: Responsive.getSpacing(context, mobile: 4),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'Sold Out',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: Responsive.getFontSize(context, mobile: 11),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.getSpacing(context, mobile: 10),
                    Responsive.getSpacing(context, mobile: 10),
                    Responsive.getSpacing(context, mobile: 10),
                    Responsive.getSpacing(context, mobile: 8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: Responsive.getFontSize(context, mobile: 13),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                      SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            flex: 3,
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '\u20B1',
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontFamilyFallback: ['Arial', 'sans-serif'],
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: Responsive.getFontSize(context, mobile: 15),
                                    ),
                                  ),
                                  TextSpan(
                                    text: product.price.toStringAsFixed(2),
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: Responsive.getFontSize(context, mobile: 15),
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: Responsive.getSpacing(context, mobile: 4)),
                          Flexible(
                            flex: 2,
                            fit: FlexFit.loose,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: Responsive.getSpacing(context, mobile: 4),
                                vertical: Responsive.getSpacing(context, mobile: 2),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${product.availableQuantity} ${product.unit}',
                                  style: TextStyle(
                                    fontSize: Responsive.getFontSize(context, mobile: 9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                      if (soldQuantity > 0)
                        Text(
                          '$soldQuantity kg sold',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: Responsive.getFontSize(context, mobile: 10),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      // Sold out text removed - now shown as badge and overlay
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildOrdersTab() {
    // Return the OrderPhasesScreen content directly instead of the old order list
    return const OrderPhasesScreen();
  }

  // Favorites tab removed; replaced with Profile tab

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return _buildStatChip(_HomeStat(label: title, value: value, icon: icon));
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppTheme.warningColor;
      case 'confirmed':
        return AppTheme.infoColor;
      case 'packed':
      case 'out_for_delivery':
        return AppTheme.primaryColor;
      case 'shipped':
        return AppTheme.primaryColor;
      case 'delivered':
        return AppTheme.successColor;
      case 'cancelled':
        return AppTheme.errorColor;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.schedule;
      case 'confirmed':
        return Icons.check_circle;
      case 'packed':
      case 'out_for_delivery':
        return Icons.local_shipping;
      case 'shipped':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.receipt;
    }
  }

  String _phaseLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'packed':
      case 'out_for_delivery':
        return 'To Receive';
      case 'delivered':
        return 'To Rate';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  bool _canCancelOrder(Order order) {
    final status = order.status.toLowerCase();
    if (status == 'packed' || status == 'out_for_delivery' || status == 'delivered') return false;
    if (status == 'pending' || status == 'confirmed') {
      return OrderSchedule.canCancelOrder();
    }
    return false;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _nextSaturdayDate() {
    final now = DateTime.now();
    int daysUntilSaturday = (DateTime.saturday - now.weekday) % 7;
    if (daysUntilSaturday == 0) daysUntilSaturday = 7;
    final deliveryDate = now.add(Duration(days: daysUntilSaturday));
    return '${deliveryDate.day}/${deliveryDate.month}/${deliveryDate.year}';
  }

  Widget _buildOrderingPolicyDropdown() {
    // Get current week's Monday (not next week)
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    final daysFromMonday = weekday - 1; // 0 if Monday, 1 if Tuesday, etc.
    final currentMonday = DateTime(now.year, now.month, now.day - daysFromMonday, 0, 0);
    final currentThursday = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + 3, 20, 0);
    final currentSunday = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + 6, 23, 59);
    
    String _formatDateShort(DateTime d) {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final month = months[d.month - 1];
      return '$month ${d.day}, ${d.year}';
    }
    return Container(
        decoration: BoxDecoration(
          color: AppTheme.creamLight,
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 24)),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: Responsive.getHorizontalPadding(context).left,
              vertical: Responsive.getSpacing(context, mobile: 6),
            ),
            onTap: () {
              setState(() {
                _isPolicyDropdownExpanded = !_isPolicyDropdownExpanded;
              });
            },
            leading: CircleAvatar(
              radius: Responsive.getImageSize(context, mobile: 22),
              backgroundColor: AppTheme.warningColor.withOpacity(0.12),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.warningColor,
                size: Responsive.getIconSize(context, mobile: 24),
              ),
            ),
            title: Text(
              'Ordering & Cancellation Schedule',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: Responsive.getFontSize(context, mobile: 16),
              ),
            ),
            trailing: Icon(
              _isPolicyDropdownExpanded ? Icons.keyboard_arrow_up_outlined : Icons.keyboard_arrow_down_outlined,
              color: Colors.grey[600],
            ),
          ),
          if (_isPolicyDropdownExpanded) Divider(color: Colors.grey.shade100, height: 1),
          if (_isPolicyDropdownExpanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                Responsive.getHorizontalPadding(context).left,
                Responsive.getSpacing(context, mobile: 16),
                Responsive.getHorizontalPadding(context).right,
                Responsive.getSpacing(context, mobile: 20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PolicyTableRow(
                    label: 'Order window',
                    value:
                        'Mon ${_formatDateShort(currentMonday)} · 12:00 AM  —  Thu ${_formatDateShort(currentThursday)} · 8:00 PM',
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                  _PolicyTableRow(
                    label: 'Cut-off',
                    value:
                        'Thu ${_formatDateShort(currentThursday)} · 8:00 PM  —  Sun ${_formatDateShort(currentSunday)} · 11:59 PM',
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                  _PolicyTableRow(
                    label: 'Delivery & pickup',
                    value: 'One-day schedule on weekends (estimate: Saturday or Sunday)',
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 18)),
                  Text(
                    'Policy',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: Responsive.getFontSize(context, mobile: 14),
                    ),
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
                  Text(
                    '• Missed pickups/deliveries are cancelled automatically.\n'
                    '• No rescheduling; GCash payments cannot be refunded once processed.\n'
                    '• Help our farmers reduce waste by receiving orders on time.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                          color: Colors.grey[700],
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactProductMediaCarousel(List<_ProductMediaItem> mediaItems, String productId) {
    if (mediaItems.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(12),
          ),
        ),
        child: Icon(Icons.image, size: Responsive.getIconSize(context, mobile: 50), color: Colors.grey),
      );
    }

    return _CompactProductCarousel(
      mediaItems: mediaItems,
      productId: productId,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
    );
  }

  Widget _buildListProductMediaCarousel(List<_ProductMediaItem> mediaItems, String productId) {
    if (mediaItems.isEmpty) {
      final size = Responsive.getImageSize(context, mobile: 60);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        ),
        child: Icon(Icons.image, size: Responsive.getIconSize(context, mobile: 30), color: Colors.grey),
      );
    }

    return _ListProductCarousel(
      mediaItems: mediaItems,
      productId: productId,
    );
  }

  Widget _buildGridProductMediaCarousel(List<_ProductMediaItem> mediaItems, String productId) {
    if (mediaItems.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.grey,
        ),
        child: Icon(Icons.image, size: Responsive.getIconSize(context, mobile: 50), color: Colors.grey),
      );
    }

    return _CompactProductCarousel(
      mediaItems: mediaItems,
      productId: productId,
      borderRadius: const BorderRadius.all(Radius.zero),
    );
  }

}

class _HomeStat {
  final String label;
  final String value;
  final IconData icon;
  final bool isLoading;

  _HomeStat({
    required this.label,
    required this.value,
    required this.icon,
    this.isLoading = false,
  });
}

class _PolicyLine extends StatelessWidget {
  final String label;
  final String value;

  const _PolicyLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: Responsive.getWidth(context, mobile: 120),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[800],
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }
}

class _PolicyTableRow extends StatelessWidget {
  final String label;
  final String value;

  const _PolicyTableRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.3),
        1: FlexColumnWidth(0.7),
      },
      children: [
        TableRow(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[800],
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _ProductMediaType { image, video }

class _ProductMediaItem {
  final String url;
  final _ProductMediaType type;

  const _ProductMediaItem({
    required this.url,
    required this.type,
  });
}

// Separate StatefulWidget for compact product carousel (Top Products section)
class _CompactProductCarousel extends StatefulWidget {
  final List<_ProductMediaItem> mediaItems;
  final String productId;
  final BorderRadius borderRadius;

  const _CompactProductCarousel({
    required this.mediaItems,
    required this.productId,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(12)),
  });

  @override
  State<_CompactProductCarousel> createState() => _CompactProductCarouselState();
}

class _CompactProductCarouselState extends State<_CompactProductCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          // Media carousel
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemCount: widget.mediaItems.length,
            itemBuilder: (context, index) {
              final media = widget.mediaItems[index];
              return Stack(
                children: [
                  Positioned.fill(
                    child: media.type == _ProductMediaType.image
                        ? CachedNetworkImage(
                            imageUrl: media.url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[200],
                              child: Icon(Icons.error_outline, size: Responsive.getIconSize(context, mobile: 40), color: Colors.grey),
                            ),
                          )
                        : _DashboardVideoPlayer(videoUrl: media.url),
                  ),
                  if (media.type == _ProductMediaType.video)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 2)),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        ),
                        child: Text(
                          'Video',
                          style: TextStyle(color: Colors.white, fontSize: Responsive.getFontSize(context, mobile: 10), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
          // Dots indicator (only if multiple media items)
          if (widget.mediaItems.length > 1)
            Positioned(
              bottom: 4,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.mediaItems.length,
                  (index) => GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      width: Responsive.getWidth(context, mobile: 6),
                      height: Responsive.getHeight(context, mobile: 6),
                      margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 2)),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentIndex == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          // Media counter (only if multiple media items)
          if (widget.mediaItems.length > 1)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 6), vertical: Responsive.getSpacing(context, mobile: 2)),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(0, 0, 0, 0.6),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                ),
                child: Text(
                  '${_currentIndex + 1}/${widget.mediaItems.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: Responsive.getFontSize(context, mobile: 10),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Separate StatefulWidget for list product carousel
class _ListProductCarousel extends StatefulWidget {
  final List<_ProductMediaItem> mediaItems;
  final String productId;

  const _ListProductCarousel({
    required this.mediaItems,
    required this.productId,
  });

  @override
  State<_ListProductCarousel> createState() => _ListProductCarouselState();
}

class _ListProductCarouselState extends State<_ListProductCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Responsive.getWidth(context, mobile: 60),
      height: Responsive.getHeight(context, mobile: 60),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        child: Stack(
          children: [
            // Media carousel
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: widget.mediaItems.length,
              itemBuilder: (context, index) {
                final media = widget.mediaItems[index];
                return Stack(
                  children: [
                    Positioned.fill(
                      child: media.type == _ProductMediaType.image
                          ? CachedNetworkImage(
                              imageUrl: media.url,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: Center(
                                  child: SizedBox(
                                    width: Responsive.getWidth(context, mobile: 16),
                                    height: Responsive.getHeight(context, mobile: 16),
                                    child: const CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: Icon(Icons.error_outline, size: Responsive.getIconSize(context, mobile: 24), color: Colors.grey),
                              ),
                            )
                          : _DashboardVideoPlayer(
                              videoUrl: media.url,
                              isMini: true,
                            ),
                    ),
                    if (media.type == _ProductMediaType.video)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 4), vertical: Responsive.getSpacing(context, mobile: 1)),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                          ),
                          child: Text(
                            'Vid',
                            style: TextStyle(color: Colors.white, fontSize: Responsive.getFontSize(context, mobile: 8), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            
            // Dots indicator (only if multiple media items, smaller for list items)
            if (widget.mediaItems.length > 1)
              Positioned(
                bottom: 2,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.mediaItems.length,
                    (index) => GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        width: Responsive.getWidth(context, mobile: 4),
                        height: Responsive.getHeight(context, mobile: 4),
                        margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 1)),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentIndex == index
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isMini;

  const _DashboardVideoPlayer({required this.videoUrl, this.isMini = false});

  @override
  State<_DashboardVideoPlayer> createState() => _DashboardVideoPlayerState();
}

class _DashboardVideoPlayerState extends State<_DashboardVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    });
    _controller.setLooping(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_isInitialized || _hasError) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.error_outline, color: Colors.white70),
      );
    }

    return GestureDetector(
      onTap: _togglePlayback,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: _isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller.value.size.width,
                      height: _controller.value.size.height,
                      child: VideoPlayer(_controller),
                    ),
                  )
                : Container(
                    color: Colors.black12,
                    child: Center(
                      child: SizedBox(
                        width: widget.isMini ? 16 : 28,
                        height: widget.isMini ? 16 : 28,
                        child: CircularProgressIndicator(
                          strokeWidth: widget.isMini ? 2 : 3,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            padding: EdgeInsets.all(widget.isMini ? 4 : 8),
            child: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: widget.isMini ? 14 : 24,
            ),
          ),
        ],
      ),
    );
  }
}

// Featured Media Carousel Widget
class _FeaturedMediaCarousel extends StatefulWidget {
  final List<FeaturedMediaItem> mediaItems;

  const _FeaturedMediaCarousel({required this.mediaItems});

  @override
  State<_FeaturedMediaCarousel> createState() => _FeaturedMediaCarouselState();
}

class _FeaturedMediaCarouselState extends State<_FeaturedMediaCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoPlayTimer;
  Timer? _resumeAutoPlayTimer;
  bool _isAutoPlayPaused = false;
  bool _isUserInteracting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoPlay();
  }

  bool _isProgrammaticChange = false;

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _resumeAutoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    if (widget.mediaItems.length <= 1 || _isAutoPlayPaused) return;
    
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients && !_isAutoPlayPaused && !_isUserInteracting) {
        final nextIndex = (_currentIndex + 1) % widget.mediaItems.length;
        _isProgrammaticChange = true;
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        // Reset flag after animation
        Future.delayed(const Duration(milliseconds: 600), () {
          _isProgrammaticChange = false;
        });
      }
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _isAutoPlayPaused = true;
    _isUserInteracting = true;
    
    // Cancel any existing resume timer
    _resumeAutoPlayTimer?.cancel();
    
    // Resume auto-play after 2 minutes
    _resumeAutoPlayTimer = Timer(const Duration(minutes: 2), () {
      if (mounted) {
        setState(() {
          _isAutoPlayPaused = false;
          _isUserInteracting = false;
        });
        _startAutoPlay();
      }
    });
  }

  void _handleManualInteraction() {
    if (!_isUserInteracting) {
      _stopAutoPlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaItems.isEmpty) {
      return Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/mewkmewk.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Logos at the upper right (always visible)
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/calcoa-logo.png',
                  height: Responsive.getHeight(context, mobile: 40),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                Image.asset(
                  'assets/images/ormoc_logo.png',
                  height: Responsive.getHeight(context, mobile: 40),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                Image.asset(
                  'assets/images/evsu_logo.png',
                  height: Responsive.getHeight(context, mobile: 40),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        GestureDetector(
          onPanStart: (_) => _handleManualInteraction(),
          onPanUpdate: (_) => _handleManualInteraction(),
          onTapDown: (_) => _handleManualInteraction(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Detect manual scrolling
              if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
                _handleManualInteraction();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                // If page changed manually (not programmatically), stop auto-play
                if (!_isProgrammaticChange) {
                  _handleManualInteraction();
                }
              },
              itemCount: widget.mediaItems.length,
              itemBuilder: (context, index) {
                final media = widget.mediaItems[index];
                return _buildMediaItem(media);
              },
            ),
          ),
        ),
        // Dots indicator
        if (widget.mediaItems.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.mediaItems.length,
                (index) => GestureDetector(
                  onTap: () {
                    _handleManualInteraction();
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: Responsive.getWidth(context, mobile: 8),
                    height: Responsive.getHeight(context, mobile: 8),
                    margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 4)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Logos at the upper right
        Positioned(
          top: 16,
          right: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/calcoa-logo.png',
                height: Responsive.getHeight(context, mobile: 40),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
              SizedBox(width: Responsive.getWidth(context, mobile: 12)),
              Image.asset(
                'assets/images/ormoc_logo.png',
                height: Responsive.getHeight(context, mobile: 40),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
              SizedBox(width: Responsive.getWidth(context, mobile: 12)),
              Image.asset(
                'assets/images/evsu_logo.png',
                height: Responsive.getHeight(context, mobile: 40),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaItem(FeaturedMediaItem media) {
    if (media.type == FeaturedMediaType.image) {
      return CachedNetworkImage(
        imageUrl: media.url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[200],
          child: Icon(Icons.error_outline, size: Responsive.getIconSize(context, mobile: 40), color: Colors.grey),
        ),
      );
    } else {
      return _FeaturedVideoPlayer(videoUrl: media.url);
    }
  }
}

// Featured Video Player Widget
class _FeaturedVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const _FeaturedVideoPlayer({required this.videoUrl});

  @override
  State<_FeaturedVideoPlayer> createState() => _FeaturedVideoPlayerState();
}

class _FeaturedVideoPlayerState extends State<_FeaturedVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _controller.setLooping(true);
        _controller.play();
      }
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_isInitialized || _hasError) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.error_outline, color: Colors.white70),
      );
    }

    return GestureDetector(
      onTap: _togglePlayback,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: _isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller.value.size.width,
                      height: _controller.value.size.height,
                      child: VideoPlayer(_controller),
                    ),
                  )
                : Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
          ),
          if (!_controller.value.isPlaying && _isInitialized)
            Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
              child: Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: Responsive.getIconSize(context, mobile: 48),
              ),
            ),
        ],
      ),
    );
  }
}
