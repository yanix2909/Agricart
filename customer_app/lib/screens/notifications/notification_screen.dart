import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../screens/orders/order_detail_screen.dart';
import '../../screens/products/product_detail_screen.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';
import '../../models/notification.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Ensure notification listener is active when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
      
      if (authProvider.currentCustomer != null) {
        // Reload notifications to ensure we have the latest
        notificationProvider.loadNotifications(authProvider.currentCustomer!.uid);
        // Ensure real-time listener is active
        notificationProvider.listenToNotifications(authProvider.currentCustomer!.uid);
        debugPrint('🔔 Notification screen: Ensured listener is active for customer ${authProvider.currentCustomer!.uid}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 20)),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        toolbarHeight: Responsive.getAppBarHeight(context),
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              tooltip: 'Select',
              icon: const Icon(Icons.checklist),
              onPressed: () {
                setState(() {
                  _selectionMode = true;
                });
              },
            ),
            IconButton(
              tooltip: 'Delete All',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final auth = Provider.of<AuthProvider>(context, listen: false);
                if (auth.currentCustomer == null) return;
                final ok = await _confirm(context, 'Delete all notifications?');
                if (!ok) return;
                await Provider.of<NotificationProvider>(context, listen: false)
                    .clearAllNotifications(auth.currentCustomer!.uid);
              },
            ),
          ] else ...[
            IconButton(
              tooltip: 'Select All',
              icon: const Icon(Icons.select_all),
              onPressed: () {
                final provider = Provider.of<NotificationProvider>(context, listen: false);
                setState(() {
                  _selectedIds
                    ..clear()
                    ..addAll(provider.notifications.map((n) => n.id));
                });
              },
            ),
            IconButton(
              tooltip: 'Delete Selected',
              icon: const Icon(Icons.delete),
              onPressed: () async {
                if (_selectedIds.isEmpty) return;
                final auth = Provider.of<AuthProvider>(context, listen: false);
                if (auth.currentCustomer == null) return;
                final ok = await _confirm(context, 'Delete selected notifications?');
                if (!ok) return;
                final notifier = Provider.of<NotificationProvider>(context, listen: false);
                for (final id in _selectedIds) {
                  await notifier.deleteNotification(auth.currentCustomer!.uid, id);
                }
                setState(() {
                  _selectedIds.clear();
                  _selectionMode = false;
                });
              },
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                });
              },
            ),
          ],
        ],
      ),
      body: Consumer2<NotificationProvider, AuthProvider>(
        builder: (context, notificationProvider, authProvider, child) {
          if (notificationProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (notificationProvider.notifications.isEmpty) {
            return Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: Responsive.getImageSize(context, mobile: 64),
                      color: Colors.grey,
                    ),
                    SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 18),
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final customerId = authProvider.currentCustomer?.uid ?? '';

          return ListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.getHorizontalPadding(context).left,
              vertical: Responsive.getSpacing(context, mobile: 8),
            ),
            itemCount: notificationProvider.notifications.length,
            itemBuilder: (context, index) {
              final notification = notificationProvider.notifications[index];
              return Builder(
                builder: (context) => Container(
                  margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 10)),
                  child: Card(
                    margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () async {
                      if (_selectionMode) {
                        setState(() {
                          if (_selectedIds.contains(notification.id)) {
                            _selectedIds.remove(notification.id);
                          } else {
                            _selectedIds.add(notification.id);
                          }
                        });
                        return;
                      }

                      // Show full notification details in dialog
                      await _showNotificationDetails(context, notification, customerId, notificationProvider);
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Responsive.getSpacing(context, mobile: 16),
                        vertical: Responsive.getSpacing(context, mobile: 12),
                      ),
                      child: Row(
                        children: [
                          if (_selectionMode)
                            Checkbox(
                              value: _selectedIds.contains(notification.id),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedIds.add(notification.id);
                                  } else {
                                    _selectedIds.remove(notification.id);
                                  }
                                });
                              },
                            )
                          else
                            Container(
                              width: Responsive.getIconSize(context, mobile: 48),
                              height: Responsive.getIconSize(context, mobile: 48),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getNotificationColor(notification.type),
                              ),
                              child: Icon(
                                _getNotificationIcon(notification.type, title: notification.title),
                                color: Colors.white,
                                size: Responsive.getIconSize(context, mobile: 24),
                              ),
                            ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        notification.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: Responsive.getFontSize(context, mobile: 15),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!notification.isRead)
                                      Container(
                                        width: Responsive.getWidth(context, mobile: 8),
                                        height: Responsive.getHeight(context, mobile: 8),
                                        margin: EdgeInsets.only(left: Responsive.getSpacing(context, mobile: 8)),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                                Text(
                                  _formatDateTime(notification.timestamp),
                                  style: TextStyle(
                                    fontSize: Responsive.getFontSize(context, mobile: 12),
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey[400],
                            size: Responsive.getIconSize(context, mobile: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            },
          );
        },
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('OK')),
            ],
          ),
        ) ??
        false;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  String _formatDateTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notificationDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    final hour = timestamp.hour == 0 ? 12 : (timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour);
    final amPm = timestamp.hour < 12 ? 'AM' : 'PM';
    final timeString = '$hour:${timestamp.minute.toString().padLeft(2, '0')} $amPm';
    
    if (notificationDate == today) {
      return 'Today at $timeString';
    } else if (notificationDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at $timeString';
    } else {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year} at $timeString';
    }
  }

  Future<void> _showNotificationDetails(
    BuildContext context,
    CustomerNotification notification,
    String customerId,
    NotificationProvider notificationProvider,
  ) async {
    // Mark as read when viewing details
    if (customerId.isNotEmpty && !notification.isRead) {
      await notificationProvider.markAsRead(customerId, notification.id);
    }

    // Show dialog with full notification details
    final navigationAction = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
        ),
        title: Row(
          children: [
            Container(
              width: Responsive.getWidth(context, mobile: 40),
              height: Responsive.getHeight(context, mobile: 40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getNotificationColor(notification.type),
              ),
              child: Icon(
                _getNotificationIcon(notification.type, title: notification.title),
                color: Colors.white,
                size: Responsive.getIconSize(context, mobile: 20),
              ),
            ),
            SizedBox(width: Responsive.getWidth(context, mobile: 12)),
            Expanded(
              child: Text(
                notification.title,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 18),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.message,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 14),
                  height: 1.5,
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: Responsive.getIconSize(context, mobile: 16), color: Colors.grey[600]),
                    SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                    Text(
                      _formatDateTime(notification.timestamp),
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 12),
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Close'),
          ),
          if ((notification.orderId ?? '').isNotEmpty)
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('view_order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('View Order'),
            ),
          if ((notification.productId ?? '').isNotEmpty && 
              (notification.type == 'product_restocked' || notification.type == 'product_added'))
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('view_product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('View Product'),
            ),
        ],
      ),
    ) ?? '';

    if (!context.mounted) return;

    // Navigate to order detail if user clicked "View Order"
    if (navigationAction == 'view_order' && (notification.orderId ?? '').isNotEmpty) {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final order = customerProvider.getOrderById(notification.orderId!);
      if (order != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(order: order),
          ),
        );
      }
    }
    // Navigate to product detail if user clicked "View Product"
    else if (navigationAction == 'view_product' && (notification.productId ?? '').isNotEmpty) {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final product = customerProvider.getProductById(notification.productId!);
      if (product != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      } else {
        // Product not found in cache, show error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product not found. Please refresh the products list.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'verification':
        return AppTheme.primaryColor;
      case 'order_placed':
        return Colors.blue;
      case 'order_confirmed':
        return Colors.green;
      case 'order_processing':
        return Colors.orange;
      case 'order_out_for_delivery':
        return AppTheme.primaryColor;
      case 'order_delivered':
        return AppTheme.successColor;
      case 'order_cancelled':
        return AppTheme.errorColor;
      case 'order_packed':
        return Colors.deepOrange;
      case 'order_to_receive':
        return AppTheme.primaryColor;
      case 'order_received':
        return AppTheme.successColor;
      case 'order_picked_up':
        return AppTheme.successColor;
      case 'order_ready_to_pickup':
        return Colors.orange;
      case 'order_rejected':
        return Colors.red;
      case 'order_update':
        return Colors.blueGrey;
      case 'payment':
        return Colors.green;
      case 'promotion':
        return Colors.orange;
      case 'system':
        return Colors.purple;
      case 'product_restocked':
        return Colors.green;
      case 'product_added':
        return Colors.blue;
      case 'product_restocked':
        return Colors.green;
      case 'product_added':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getNotificationIcon(String type, {String? title}) {
    // Special handling for order_to_receive to distinguish between normal and rescheduled
    if (type == 'order_to_receive' && title != null) {
      if (title.toLowerCase().contains('re-scheduled') || title.toLowerCase().contains('rescheduled')) {
        // Rescheduled order - use calendar/repeat icon
        return Icons.event_repeat;
      } else {
        // Normal "Order Ready for Harvesting" - use agriculture/harvest icon
        return Icons.agriculture;
      }
    }
    
    switch (type) {
      case 'verification':
        return Icons.verified_user;
      case 'order_placed':
        return Icons.shopping_cart;
      case 'order_confirmed':
        return Icons.check_circle;
      case 'order_processing':
        return Icons.build;
      case 'order_out_for_delivery':
        return Icons.local_shipping;
      case 'order_delivered':
        return Icons.done_all;
      case 'order_cancelled':
        return Icons.cancel;
      case 'order_packed':
        return Icons.inventory_2;
      case 'order_to_receive':
        // Default for order_to_receive (if title not provided, use harvest icon)
        return Icons.agriculture;
      case 'order_received':
        return Icons.rate_review;
      case 'order_picked_up':
        return Icons.check_circle;
      case 'order_ready_to_pickup':
        return Icons.store;
      case 'order_rejected':
        return Icons.cancel;
      case 'order_update':
        return Icons.notifications_active;
      case 'payment':
        return Icons.payment;
      case 'promotion':
        return Icons.local_offer;
      case 'system':
        return Icons.info;
      case 'product_restocked':
        return Icons.inventory;
      case 'product_added':
        return Icons.add_shopping_cart;
      default:
        return Icons.notifications;
    }
  }
}
