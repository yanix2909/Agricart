import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/customer_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
// Removed dynamic pickup fallback: display only the pickup details saved on the order
import '../../utils/order_schedule.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/supabase_service.dart';
import '../chat/chat_screen.dart';
import '../../utils/responsive.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  // Read-only fallback: if order lacks landmark/instructions/map, try to resolve by pickupName from systemData/pickupLocations
  String? _fallbackPickupLandmark;
  String? _fallbackPickupInstructions;
  String? _fallbackPickupMapLink;
  bool _hasSyncedOrder = false;
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    // Sync order status from Supabase when screen opens to ensure we have the latest status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOrderStatus();
      // Set up periodic refresh to keep order status up to date
      _startPeriodicRefresh();
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    // Refresh order status every 10 seconds to ensure we have the latest status
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _syncOrderStatus();
      } else {
        timer.cancel();
      }
    });
  }
  
  Future<void> _syncOrderStatus() async {
    try {
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      // Sync order status from Supabase to ensure we have the latest status
      await provider.syncOrderStatus(widget.order.id);
      if (mounted) {
        setState(() {}); // Trigger rebuild to show updated status
      }
    } catch (e) {
      debugPrint('⚠️ Error syncing order status: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<CustomerProvider>(
      builder: (context, provider, child) {
        // Always get the latest order from the provider
        final currentOrder = provider.getOrderById(widget.order.id) ?? widget.order;
        
        // Sync order status if not already synced (in case provider doesn't have it)
        if (!_hasSyncedOrder) {
          _syncOrderStatus();
        }
        
        print('🔍 Order Detail - Order ID: ${currentOrder.id}, Status: ${currentOrder.status}');
        
        // Attempt a read-only lookup by pickupName to fill missing display-only details
        _maybeResolvePickupDetails(currentOrder);

        return Scaffold(
          appBar: AppBar(
            title: Text('Order #${_shortId(currentOrder.id)}'),
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                  children: [
                    _buildStatusCard(context, currentOrder),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    // Customer Info for pickup orders (both GCash and Cash) and delivery orders (both GCash and Cash)
                    if (currentOrder.deliveryOption.toLowerCase() == 'pickup' ||
                        currentOrder.deliveryOption.toLowerCase() == 'delivery') ...[
                      _buildCustomerInfoCard(context, currentOrder),
                      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    ],
                    _buildAddressesCard(context, currentOrder),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    _buildItemsAndSummaryCard(context, currentOrder),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    _buildPaymentCard(context, currentOrder),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    _buildDatesCard(context, currentOrder),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    _buildUpdatesAndNotesCard(context, currentOrder),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    _buildSupportChatButton(context, currentOrder),
                  ],
                ),
              ),
              // Footer actions
              _buildFooterActions(context, currentOrder),
            ],
          ),
        );
      },
    );
  }

  String _shortId(String id) => id.length > 8 ? id.substring(id.length - 8).toUpperCase() : id.toUpperCase();

  // Get Supabase GCash receipt URL - handles both full URLs and file paths
  String _getGcashReceiptUrl(String? receiptUrl, String orderId) {
    if (receiptUrl == null || receiptUrl.isEmpty) return '';
    if (receiptUrl.startsWith('pending:')) return '';
    
    // If it's already a full URL, return as is
    if (receiptUrl.startsWith('http://') || receiptUrl.startsWith('https://')) {
      // Fix duplicate bucket names if present
      if (receiptUrl.contains('/gcash_receipt/gcash_receipt/')) {
        return receiptUrl.replaceAll('/gcash_receipt/gcash_receipt/', '/gcash_receipt/');
      }
      return receiptUrl;
    }
    
    // If it's a file path, construct Supabase public URL
    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'gcash_receipt';
    
    // Remove bucket name if already present
    String filePath = receiptUrl;
    if (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1);
    }
    // Remove leading slashes
    filePath = filePath.replaceAll(RegExp(r'^/+'), '');
    
    // If it doesn't contain order ID, add it (optional - depends on storage structure)
    // For now, use the path as-is
    if (!filePath.startsWith('$orderId/') && !filePath.contains('/')) {
      filePath = '$orderId/$filePath';
    }
    
    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  // Get Supabase refund receipt URL - handles both full URLs and file paths
  String _getRefundReceiptUrl(String? receiptUrl, String orderId) {
    if (receiptUrl == null || receiptUrl.isEmpty) return '';
    if (receiptUrl.startsWith('pending:')) return '';
    
    // If it's already a full URL, return as is
    if (receiptUrl.startsWith('http://') || receiptUrl.startsWith('https://')) {
      // Fix duplicate bucket names if present (handle both refund_receipt and gcash_receipt for backward compatibility)
      if (receiptUrl.contains('/refund_receipt/refund_receipt/')) {
        return receiptUrl.replaceAll('/refund_receipt/refund_receipt/', '/refund_receipt/');
      }
      if (receiptUrl.contains('/gcash_receipt/refund_receipt/')) {
        return receiptUrl.replaceAll('/gcash_receipt/refund_receipt/', '/refund_receipt/');
      }
      return receiptUrl;
    }
    
    // If it's a file path, construct Supabase public URL
    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'refund_receipt';
    
    // Remove bucket name if already present (handle both refund_receipt and gcash_receipt for backward compatibility)
    String filePath = receiptUrl;
    if (filePath.startsWith('refund_receipt/')) {
      filePath = filePath.substring('refund_receipt/'.length);
    } else if (filePath.startsWith('gcash_receipt/')) {
      filePath = filePath.substring('gcash_receipt/'.length);
    }
    // Remove leading slashes
    filePath = filePath.replaceAll(RegExp(r'^/+'), '');
    
    // If it doesn't contain order ID, add it (optional - depends on storage structure)
    // For now, use the path as-is
    if (!filePath.startsWith('$orderId/') && !filePath.contains('/')) {
      filePath = '$orderId/$filePath';
    }
    
    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  Widget _buildStatusCard(BuildContext context, Order o) {
    // Determine display status with cancellation/refund handling
    // Check if order is cancelled by status OR cancellation flags (cancellationConfirmed, refundConfirmedAt, refundReceiptUrl, etc.)
    final isCancelled = o.status.toLowerCase() == 'cancelled' ||
                        o.cancellationConfirmed == true ||
                        o.refundConfirmedAt != null ||
                        o.refundReceiptUrl != null ||
                        o.refundDenied == true;
    final isCancellationRequested = o.cancellationRequested == true;
    final initiatedByStaff = (o.cancellationInitiatedBy ?? 'customer') == 'staff';
    final orderStatus = o.status.toLowerCase();
    
    // CRITICAL: Check timestamps to ensure we never show "Ready to Pickup" for completed orders
    // This is a defensive check in case database has inconsistent data
    final hasPickedUpTimestamp = o.pickedUpAt != null;
    final hasFailedPickupTimestamp = o.failedPickupAt != null;
    
    // CRITICAL: Prioritize final pickup states - never override with "Ready to Pickup"
    // If order is picked_up or failed_pickup (by status OR timestamp), always use the actual status
    final isFinalPickupState = orderStatus == 'picked_up' || 
                               orderStatus == 'failed_pickup' ||
                               hasPickedUpTimestamp || 
                               hasFailedPickupTimestamp;
    
    // Determine final status: use timestamp as authoritative source if available
    String finalStatus = o.status;
    if (hasPickedUpTimestamp && orderStatus != 'picked_up') {
      finalStatus = 'picked_up';
    } else if (hasFailedPickupTimestamp && orderStatus != 'failed_pickup') {
      finalStatus = 'failed_pickup';
    }
    
    // If cancelled, show cancellation confirmed regardless of request flag
    // If request exists but was staff-initiated, suppress the request indicator
    // CRITICAL: Never override final pickup states with cancellation or request status
    final displayStatus = isFinalPickupState
        ? finalStatus // Always use actual status for final pickup states
        : (isCancelled
            ? 'cancellation_confirmed'
            : ((isCancellationRequested && !initiatedByStaff) ? 'request_cancellation_sent' : o.status));
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _statusColor(displayStatus),
              child: Icon(_statusIcon(displayStatus), color: Colors.white),
            ),
            SizedBox(width: Responsive.getWidth(context, mobile: 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusLabel(() {
                      // CRITICAL: Ensure we use the actual order status, not displayStatus if order is in final state
                      // Check timestamps first to determine real status
                      final hasPickedUpTimestamp = o.pickedUpAt != null;
                      final hasFailedTimestamp = o.failedPickupAt != null;
                      final actualStatus = o.status.toLowerCase();
                      
                      // If timestamps indicate final state but displayStatus doesn't, use actual status
                      if (hasPickedUpTimestamp && actualStatus == 'picked_up') {
                        return 'picked_up';
                      } else if (hasFailedTimestamp && actualStatus == 'failed_pickup') {
                        return 'failed_pickup';
                      }
                      // Otherwise use displayStatus (handles cancellation states)
                      return displayStatus;
                    }(), o),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: Responsive.getFontSize(context, mobile: 16)),
                    maxLines: null,
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                  Text('Total: \u20B1${o.total.toStringAsFixed(2)}'),
                  
                  // Show rider information if available (only for delivery orders)
                  if (o.riderName != null && o.riderName!.isNotEmpty && o.deliveryOption.toLowerCase() == 'delivery') ...[
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    Container(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.delivery_dining, color: Colors.blue[600], size: Responsive.getIconSize(context, mobile: 20)),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivery Rider',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: Responsive.getFontSize(context, mobile: 12),
                                  ),
                                ),
                                SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                                Text(
                                  o.riderName!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: Responsive.getFontSize(context, mobile: 16),
                                  ),
                                ),
                                if (o.riderPhone != null && o.riderPhone!.isNotEmpty) ...[
                                  SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                                  Text(
                                    o.riderPhone!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: Responsive.getFontSize(context, mobile: 14),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Chat button icon for delivery orders
                          IconButton(
                            onPressed: () => _openRiderChat(context, o),
                            icon: Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.blue[600],
                              size: Responsive.getIconSize(context, mobile: 24),
                            ),
                            tooltip: 'Chat with ${o.riderName}',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundInfo(BuildContext context, Order o) {
    // Check if order is cancelled by status OR cancellation flags
    final isCancelled = o.status.toLowerCase() == 'cancelled' ||
                        o.cancellationConfirmed == true ||
                        o.refundConfirmedAt != null ||
                        o.refundReceiptUrl != null ||
                        o.refundDenied == true;
    if (!isCancelled) return const SizedBox.shrink();
    final confirmedAt = o.refundConfirmedAt;
    final confirmedAtText = confirmedAt != null
        ? '${confirmedAt.toLocal()}'
        : 'Not available';
    final hasRefundReceipt = (o.refundReceiptUrl ?? '').isNotEmpty;
    return Card(
      margin: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 12)),
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Refund Details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Text('Cancelled and Refunded at: $confirmedAtText'),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            if (hasRefundReceipt) ...[
              const Text('Refund Receipt (placeholder):'),
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              Container(
                height: Responsive.getHeight(context, mobile: 160),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
                alignment: Alignment.center,
                child: const Text('Refund receipt uploaded (placeholder)'),
              ),
            ] else ...[
              const Text('No refund receipt available'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddressesCard(BuildContext context, Order o) {
    final isDelivery = o.deliveryOption.toLowerCase() == 'delivery';
    
    if (isDelivery) {
      // Delivery address card with table style
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, color: AppTheme.primaryColor),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  Text('Delivery Address', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                        child: Text(
                          'Address:',
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                        child: Text(
                          o.deliveryAddress ?? o.customerAddress,
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      // Pickup address card with comprehensive details
      return _buildPickupDetailsCard(context, o);
    }
  }

  Widget _buildPickupDetailsCard(BuildContext context, Order o) {
    // Debug: Print order pickup data
    print('🔍 Order Detail - Pickup Data Debug:');
    print('  - pickupName: ${o.pickupName}');
    print('  - pickupLandmark: ${o.pickupLandmark}');
    print('  - pickupInstructions: ${o.pickupInstructions}');
    print('  - pickupMapLink: ${o.pickupMapLink}');
    print('  - fallbackLandmark: $_fallbackPickupLandmark');
    print('  - fallbackInstructions: $_fallbackPickupInstructions');
    print('  - fallbackMapLink: $_fallbackPickupMapLink');
    
    // Always use the order's stored pickup fields; do not fallback to the current active pickup
    final effectiveName = (o.pickupName != null && o.pickupName!.isNotEmpty) ? o.pickupName! : '';
    final effectiveLandmark = (o.pickupLandmark != null && o.pickupLandmark!.isNotEmpty)
        ? o.pickupLandmark!
        : (_fallbackPickupLandmark ?? '');
    final effectiveInstructions = (o.pickupInstructions != null && o.pickupInstructions!.isNotEmpty)
        ? o.pickupInstructions!
        : (_fallbackPickupInstructions ?? '');
    final effectiveMapLink = (o.pickupMapLink != null && o.pickupMapLink!.isNotEmpty)
        ? o.pickupMapLink!
        : (_fallbackPickupMapLink ?? '');
    final hasAddress = (
      (o.pickupStreet != null && o.pickupStreet!.isNotEmpty) ||
      (o.pickupSitio != null && o.pickupSitio!.isNotEmpty) ||
      (o.pickupBarangay != null && o.pickupBarangay!.isNotEmpty) ||
      (o.pickupCity != null && o.pickupCity!.isNotEmpty) ||
      (o.pickupProvince != null && o.pickupProvince!.isNotEmpty) ||
      ((o.pickupAddress ?? '').isNotEmpty)
    );
    // Build address from structured components
    final addressParts = <String>[];
    if (o.pickupStreet != null && o.pickupStreet!.isNotEmpty) {
      addressParts.add(o.pickupStreet!);
    }
    if (o.pickupSitio != null && o.pickupSitio!.isNotEmpty) {
      addressParts.add(o.pickupSitio!);
    }
    if (o.pickupBarangay != null && o.pickupBarangay!.isNotEmpty) {
      addressParts.add(o.pickupBarangay!);
    }
    if (o.pickupCity != null && o.pickupCity!.isNotEmpty) {
      addressParts.add(o.pickupCity!);
    }
    if (o.pickupProvince != null && o.pickupProvince!.isNotEmpty) {
      addressParts.add(o.pickupProvince!);
    }
    final fullAddress = addressParts.isNotEmpty 
        ? addressParts.join(', ')
        : (o.pickupAddress ?? 'Address not available');
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with navigation button
            Row(
              children: [
                Icon(Icons.store_mall_directory, color: AppTheme.primaryColor),
                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                Expanded(
                  child: Text('Pickup Details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            
            // Table style details without visible lines
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
              },
              children: [
                if (effectiveName.isNotEmpty)
                  TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                        child: Text(
                          'Location:',
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                        child: Text(
                          effectiveName,
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        'Address:',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        fullAddress,
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        'Landmark:',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        effectiveLandmark.isNotEmpty ? effectiveLandmark : 'No landmark provided',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        'Instructions:',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        effectiveInstructions.isNotEmpty ? effectiveInstructions : 'No pickup instructions provided',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            // Navigate button placed below table
            if (effectiveMapLink.isNotEmpty) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () => _launchGoogleMaps(effectiveMapLink),
                  icon: Icon(Icons.navigation, size: Responsive.getIconSize(context, mobile: 16)),
                  label: const Text('Navigate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12), vertical: Responsive.getSpacing(context, mobile: 8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
            
            // If order lacks pickup details and address, show an informative placeholder
            if (effectiveName.isEmpty && effectiveLandmark.isEmpty && effectiveInstructions.isEmpty && effectiveMapLink.isEmpty && !hasAddress) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[600], size: Responsive.getIconSize(context, mobile: 16)),
                        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                        Text(
                          'Complete pickup information not available',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[700],
                            fontSize: Responsive.getFontSize(context, mobile: 12),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                    Text(
                      'Please contact staff for detailed pickup instructions and location information.',
                      style: TextStyle(
                        color: Colors.orange[600],
                        fontSize: Responsive.getFontSize(context, mobile: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _maybeResolvePickupDetails(Order o) async {
    try {
      if (o.deliveryOption.toLowerCase() != 'pickup') return;
      
      print('🔍 Attempting to resolve pickup details for order: ${o.id}');
      print('🔍 Pickup name: ${o.pickupName}');
      
      final needsLandmark = (o.pickupLandmark == null || o.pickupLandmark!.isEmpty) && (_fallbackPickupLandmark == null);
      final needsInstructions = (o.pickupInstructions == null || o.pickupInstructions!.isEmpty) && (_fallbackPickupInstructions == null);
      final needsMap = (o.pickupMapLink == null || o.pickupMapLink!.isEmpty) && (_fallbackPickupMapLink == null);
      
      print('🔍 Needs landmark: $needsLandmark, instructions: $needsInstructions, map: $needsMap');
      
      if (!(needsLandmark || needsInstructions || needsMap)) {
        print('🔍 No pickup details needed, returning');
        return;
      }
      
      final pickupName = (o.pickupName ?? '').trim();
      if (pickupName.isEmpty) {
        print('🔍 No pickup name found, returning');
        return;
      }

      // Using Firebase Realtime Database directly (read-only)
      // Query Supabase for pickup area matching the name
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        
        // Search for pickup area by name (case-insensitive)
        // Get all pickup areas and filter by name match
        final areas = await supabase
            .from('pickup_area')
            .select('*') as List;
        
        if (areas.isNotEmpty) {
          // Find exact match (case-insensitive)
          final matchingArea = areas.firstWhere(
            (area) {
              final areaMap = area as Map<String, dynamic>;
              final areaName = (areaMap['name']?.toString().trim().toLowerCase() ?? '');
              return areaName == pickupName.toLowerCase();
            },
            orElse: () => areas.first,
          ) as Map<String, dynamic>;
          
          final lm = (matchingArea['landmark'] ?? '').toString();
          final ins = (matchingArea['instructions'] ?? '').toString();
          final ml = (matchingArea['map_link'] ?? '').toString();
          print('🔍 Found matching pickup in Supabase: ${matchingArea['name']}');
          print('🔍 Landmark: $lm, Instructions: $ins, MapLink: $ml');
          
          if (mounted) {
            setState(() {
              if (needsLandmark && lm.isNotEmpty) {
                _fallbackPickupLandmark = lm;
                print('🔍 Set fallback landmark: $lm');
              }
              if (needsInstructions && ins.isNotEmpty) {
                _fallbackPickupInstructions = ins;
                print('🔍 Set fallback instructions: $ins');
              }
              if (needsMap && ml.isNotEmpty) {
                _fallbackPickupMapLink = ml;
                print('🔍 Set fallback map link: $ml');
              }
            });
          }
          return;
        }
      } catch (e) {
        print('🔍 Error fetching pickup area from Supabase: $e');
      }
      
      // No matching pickup area found
      print('🔍 No matching pickup area found for: $pickupName');
    } catch (e) {
      print('🔍 Error in pickup area lookup: $e');
      // best-effort; ignore errors
    }
  }

  Widget _buildCustomerInfoCard(BuildContext context, Order o) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: AppTheme.primaryColor),
                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                Text('Customer Info', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        'Name:',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        o.customerName,
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        'Phone:',
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
                      child: Text(
                        o.customerPhone,
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: Responsive.getIconSize(context, mobile: 16), color: Colors.grey[600]),
        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 12),
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 2)),
              Text(
                value,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 14),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressSection(Order o) {
    // Build address from structured components
    final addressParts = <String>[];
    
    if (o.pickupStreet != null && o.pickupStreet!.isNotEmpty) {
      addressParts.add(o.pickupStreet!);
    }
    if (o.pickupSitio != null && o.pickupSitio!.isNotEmpty) {
      addressParts.add(o.pickupSitio!);
    }
    if (o.pickupBarangay != null && o.pickupBarangay!.isNotEmpty) {
      addressParts.add(o.pickupBarangay!);
    }
    if (o.pickupCity != null && o.pickupCity!.isNotEmpty) {
      addressParts.add(o.pickupCity!);
    }
    if (o.pickupProvince != null && o.pickupProvince!.isNotEmpty) {
      addressParts.add(o.pickupProvince!);
    }
    
    final fullAddress = addressParts.isNotEmpty 
        ? addressParts.join(', ')
        : (o.pickupAddress ?? 'Address not available');
    
    return _buildInfoRow(Icons.location_on, 'Address', fullAddress);
  }

  Widget _buildItemsAndSummaryCard(BuildContext context, Order o) {
    return Consumer<CustomerProvider>(
      builder: (context, provider, child) {
        return Card(
          child: Padding(
            padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Items section
                Text('Items (${o.items.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                ...o.items.map((it) {
                  final product = provider.getProductById(it.productId);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _buildProductMediaCarousel(product, 48),
                    title: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${it.quantity} ${it.unit} × \u20B1${it.price.toStringAsFixed(2)}'),
                    trailing: Text(
                      '\u20B1${it.total.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
                
                // Summary section
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                const Divider(height: 1),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                Text('Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                _row('Subtotal', '\u20B1${o.subtotal.toStringAsFixed(2)}'),
                _row('Delivery Fee', '\u20B1${o.deliveryFee.toStringAsFixed(2)}'),
                const Divider(height: 20),
                _row('Total', '\u20B1${o.total.toStringAsFixed(2)}', emphasize: true),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentCard(BuildContext context, Order o) {
    final isGcash = o.paymentMethod.toLowerCase() == 'gcash';
    return Card(
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isGcash ? Icons.account_balance_wallet : Icons.payments, color: AppTheme.primaryColor),
                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                Text('Payment', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  label: Text(o.paymentMethod.toUpperCase()),
                  backgroundColor: Colors.grey.shade100,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            const Divider(height: 1),
            if (isGcash) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              Center(
                child: Text('Official GCash Receipt (amount paid)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              Center(
                child: Builder(
                builder: (context) {
                  final receiptUrl = _getGcashReceiptUrl(o.gcashReceiptUrl, o.id);
                  if (o.gcashReceiptUrl != null && o.gcashReceiptUrl!.startsWith('pending:')) {
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long, color: Colors.grey),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Text('(placeholder)'),
                        ],
                      ),
                    );
                  } else if (receiptUrl.isNotEmpty) {
                    return GestureDetector(
                      onTap: () => _showReceiptLightbox(context, receiptUrl, 'GCash Receipt'),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          child: Stack(
                            children: [
                              CachedNetworkImage(
                                imageUrl: receiptUrl,
                                height: Responsive.getHeight(context, mobile: 160),
                                fit: BoxFit.contain,
                                placeholder: (c, _) => Container(
                                  height: Responsive.getHeight(context, mobile: 160),
                                  color: Colors.transparent,
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(),
                                ),
                                errorWidget: (c, _, __) => Container(
                                  height: Responsive.getHeight(context, mobile: 160),
                                  color: Colors.transparent,
                                  alignment: Alignment.center,
                                  child: const Text('Failed to load receipt'),
                                ),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 6)),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                                ),
                                child: Icon(
                                  Icons.fullscreen,
                                  color: Colors.white,
                                  size: Responsive.getIconSize(context, mobile: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    );
                  } else {
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long, color: Colors.grey),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Text('(placeholder)'),
                        ],
                      ),
                    );
                  }
                },
                ),
              ),
              
              // Refund Details (only for refunded GCASH orders; exclude cash/no-refund)
              // Check if order is cancelled by status OR cancellation flags
              if ((o.status.toLowerCase() == 'cancelled' ||
                   o.cancellationConfirmed == true ||
                   o.refundConfirmedAt != null ||
                   o.refundReceiptUrl != null ||
                   o.refundDenied == true) && 
                  isGcash && 
                  (o.refundDenied != true)) ...[
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                // Refund Details and Cancelled date outside receipt container
                Text('Refund Details', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                Text('Cancelled and Refunded at: ${_formatDate(o.refundConfirmedAt ?? o.updatedAt)}'),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                // Receipt title and container
                Center(
                  child: Text('Official GCash Receipt (amount refunded)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                Center(
                  child: Builder(
                  builder: (context) {
                    final receiptUrl = _getRefundReceiptUrl(o.refundReceiptUrl, o.id);
                    if (o.refundReceiptUrl != null && o.refundReceiptUrl!.startsWith('pending:')) {
                      return Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, color: Colors.grey),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text('(placeholder) refund receipt'),
                          ],
                        ),
                      );
                    } else if (receiptUrl.isNotEmpty) {
                      return GestureDetector(
                        onTap: () => _showReceiptLightbox(context, receiptUrl, 'Refund Receipt'),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                            child: Stack(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: receiptUrl,
                                  height: Responsive.getHeight(context, mobile: 160),
                                  fit: BoxFit.contain,
                                  placeholder: (c, _) => Container(
                                    height: Responsive.getHeight(context, mobile: 160),
                                    color: Colors.transparent,
                                    alignment: Alignment.center,
                                    child: const CircularProgressIndicator(),
                                  ),
                                  errorWidget: (c, _, __) => Container(
                                    height: Responsive.getHeight(context, mobile: 160),
                                    color: Colors.transparent,
                                    alignment: Alignment.center,
                                    child: const Text('Failed to load refund receipt'),
                                  ),
                                ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 6)),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                                  ),
                                  child: Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                    size: Responsive.getIconSize(context, mobile: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long, color: Colors.grey),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Text('No refund receipt available'),
                        ],
                      ),
                    );
                  }
                },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context, Order order) {
    final status = order.status.toLowerCase();
    final canCancel = _canCancelOrder(order);
    // Remove 'out_for_delivery' from canMarkReceived - delivery rider confirms delivery, not customer
    // CRITICAL: Don't allow marking as received if already picked_up or failed_pickup
    // Check both status and timestamps for defensive programming
    final hasPickedUpTimestamp = order.pickedUpAt != null;
    final hasFailedPickupTimestamp = order.failedPickupAt != null;
    final isPickupFinal = status == 'picked_up' || 
                         status == 'failed_pickup' ||
                         hasPickedUpTimestamp || 
                         hasFailedPickupTimestamp;
    // REMOVED: canMarkReceived - Order Received button is now only on order preview card, not in detail screen
    // This prevents duplicate buttons for pickup orders
    final isGcash = order.paymentMethod.toLowerCase() == 'gcash';
    final initiatedByStaff = (order.cancellationInitiatedBy ?? 'customer') == 'staff';
    final requestSent = order.cancellationRequested == true && !initiatedByStaff;
    final cancellationConfirmed = order.status.toLowerCase() == 'cancelled';

    if (!canCancel) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (canCancel)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: requestSent
                          ? null
                          : () async {
                              String? reason = '';
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => StatefulBuilder(
                                  builder: (context, setState) => AlertDialog(
                                  title: const Text('Cancel Order'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('Are you sure you want to cancel this order? This action cannot be undone'),
                                      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                                      TextField(
                                        decoration: const InputDecoration(
                                          labelText: 'Reason for cancellation',
                                          hintText: 'Please provide a reason',
                                          border: OutlineInputBorder(),
                                        ),
                                        maxLines: 3,
                                        onChanged: (v) {
                                          setState(() {
                                            reason = v;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      child: const Text('No'),
                                    ),
                                    ElevatedButton(
                                      onPressed: (reason != null && reason!.trim().isNotEmpty) ? () => Navigator.of(context).pop(true) : null,
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Yes, Cancel'),
                                    ),
                                  ],
                                )),
                              );

                              if (confirm == true) {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => const Center(child: CircularProgressIndicator()),
                                );

                                final provider = Provider.of<CustomerProvider>(context, listen: false);
                                final ok = await provider.cancelOrder(order.id, reason: reason);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  if (ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(isGcash ? 'Cancellation request sent' : 'Order cancelled'),
                                        backgroundColor: isGcash ? Colors.orange : Colors.red,
                                      ),
                                    );
                                    setState(() {});
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to cancel order'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                      icon: const Icon(Icons.cancel),
                      label: Text(
                        requestSent
                            ? 'Request Sent'
                            : (isGcash ? 'Request to Cancel' : 'Cancel Order'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: requestSent ? Colors.grey : Colors.red,
                        side: BorderSide(color: requestSent ? Colors.grey : Colors.red),
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
                      ),
                    ),
                  ),
                // REMOVED: Order Received button - now only shown on order preview card
              ],
            ),
            if (isGcash && requestSent && !cancellationConfirmed) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
                child: const Text(
                  'Please wait for the cooperative to refund your paid amount and confirm the cancellation.',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDatesCard(BuildContext context, Order o) {
    final dateEntries = <Map<String, dynamic>>[];
    final isGcash = o.paymentMethod.toLowerCase() == 'gcash';
    final isCash = o.paymentMethod.toLowerCase() == 'cash';
    
    // Order date (always shown)
    dateEntries.add({
      'label': 'Order Date',
      'value': _formatDate(o.orderDate),
      'icon': Icons.shopping_cart_outlined,
    });
    
    // Delivery date
    if (o.deliveryDate != null) {
      dateEntries.add({
        'label': 'Delivery Date',
        'value': _formatDate(o.deliveryDate!),
        'icon': Icons.local_shipping_outlined,
      });
    }
    
    // Estimated delivery range
    if (o.estimatedDeliveryStart != null && o.estimatedDeliveryEnd != null) {
      dateEntries.add({
        'label': o.deliveryOption.toLowerCase() == 'pickup' ? 'Estimated Pickup' : 'Estimated Delivery',
        'value': _formatDateRange(o.estimatedDeliveryStart!, o.estimatedDeliveryEnd!),
        'icon': Icons.calendar_today_outlined,
      });
    }
    
    // Confirmed at (for GCash orders that have been confirmed)
    if (isGcash && o.status.toLowerCase() == 'confirmed') {
      dateEntries.add({
        'label': 'Confirmed at',
        'value': _formatDate(o.updatedAt),
        'icon': Icons.check_circle_outline,
      });
    }
    
    // Rejected at (for GCash orders that have been rejected)
    if (isGcash && o.status.toLowerCase() == 'rejected') {
      dateEntries.add({
        'label': 'Rejected at',
        'value': _formatDate(o.updatedAt),
        'icon': Icons.cancel_outlined,
      });
    }
    
    // Cancelled at (for GCash orders that have been confirmed cancellation by staff/admin)
    if (isGcash && o.cancellationConfirmedAt != null) {
      dateEntries.add({
        'label': 'Cancelled at',
        'value': _formatDate(o.cancellationConfirmedAt!),
        'icon': Icons.cancel_outlined,
      });
    }
    
    // Cancelled at (for cash orders cancelled immediately by customer)
    if (isCash && o.cancellationRequestedAt != null) {
      dateEntries.add({
        'label': 'Cancelled at',
        'value': _formatDate(o.cancellationRequestedAt!),
        'icon': Icons.cancel_outlined,
      });
    }
    
    // Delivered at (for both GCash and cash orders that have been delivered)
    if (o.status.toLowerCase() == 'delivered') {
      dateEntries.add({
        'label': 'Delivered at',
        'value': _formatDate(o.updatedAt),
        'icon': Icons.local_shipping_outlined,
      });
    }
    
    // Refund confirmed at
    if (o.refundConfirmedAt != null) {
      dateEntries.add({
        'label': 'Refund Confirmed',
        'value': _formatDate(o.refundConfirmedAt!),
        'icon': Icons.account_balance_wallet_outlined,
      });
    }
    
    // Refund denied at
    if (o.refundDeniedAt != null) {
      dateEntries.add({
        'label': 'Refund Denied',
        'value': _formatDate(o.refundDeniedAt!),
        'icon': Icons.block_outlined,
      });
    }
    
    
    // Out for delivery at
    if (o.outForDeliveryAt != null) {
      dateEntries.add({
        'label': 'Out for Delivery',
        'value': _formatDateOnly(o.outForDeliveryAt!),
        'icon': Icons.local_shipping_outlined,
      });
    }

    // Failed at (delivery) – show immediately after Out for Delivery
    // Don't show "Failed At" for failed pickup orders
    final isFailedPickup = o.status.toLowerCase() == 'failed_pickup' || 
                           o.status.toLowerCase().contains('pickup_failed');
    if (!isFailedPickup) {
      final failedDeliveryTs = o.failedAt ??
          ((o.status.toLowerCase().contains('failed') ||
                  o.status.toLowerCase() == 'delivery_failed') &&
                  o.updatedAt != null
              ? o.updatedAt
              : null);
      if (failedDeliveryTs != null) {
        dateEntries.add({
          'label': 'Failed At',
          'value': _formatDate(failedDeliveryTs),
          'icon': Icons.error_outline,
        });
      }
    }

    // Failed pickup at – show immediately after Out for Delivery/failed delivery
    final failedPickupTs = o.failedPickupAt ??
        ((o.status.toLowerCase() == 'failed_pickup' ||
                o.status.toLowerCase().contains('pickup_failed')) &&
                o.updatedAt != null
            ? o.updatedAt
            : null);
    if (failedPickupTs != null) {
      dateEntries.add({
        'label': 'Failed Pickup',
        'value': _formatDate(failedPickupTs),
        'icon': Icons.error_outline,
      });
    }
    
    // Pickup Schedule (for pickup orders that have been marked as ready)
    // CRITICAL: Always show Pickup Schedule if readyForPickupAt exists, regardless of current status
    // This ensures it displays for ready to pick, picked_up, and failed_pickup orders
    if (o.deliveryOption.toLowerCase() == 'pickup' && o.readyForPickupAt != null) {
      dateEntries.add({
        'label': 'Pickup Schedule',
        'value': _formatDateOnly(o.readyForPickupAt!),
        'icon': Icons.store_outlined,
      });
    }
    
    // Picked up at
    if (o.pickedUpAt != null) {
      dateEntries.add({
        'label': 'Picked Up',
        'value': _formatDate(o.pickedUpAt!),
        'icon': Icons.check_circle_outline,
      });
    }
    
    if (dateEntries.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: AppTheme.primaryColor),
                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                Text(
                  'Timeline',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            const Divider(height: 1),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            ...dateEntries.map((entry) => Padding(
              padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(entry['icon'] as IconData, size: Responsive.getIconSize(context, mobile: 18), color: Colors.grey[600]),
                  SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['label'] as String,
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 12),
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                        Text(
                          entry['value'] as String,
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
  
  Widget _buildUpdatesAndNotesCard(BuildContext context, Order o) {
    final updateEntries = <Widget>[];
    
    // Determine display status
    final isCancelled = o.status.toLowerCase() == 'cancelled' ||
                        o.cancellationConfirmed == true ||
                        o.refundConfirmedAt != null ||
                        o.refundReceiptUrl != null ||
                        o.refundDenied == true;
    final isCancellationRequested = o.cancellationRequested == true;
    final initiatedByStaff = (o.cancellationInitiatedBy ?? 'customer') == 'staff';
    
    // Cancellation reason
    if (o.status.toLowerCase() == 'cancelled' && (o.cancellationReason ?? '').isNotEmpty) {
      updateEntries.add(_buildUpdateEntry(
        icon: Icons.cancel_outlined,
        iconColor: Colors.red,
        title: 'Cancellation Reason',
        content: o.cancellationReason!,
        timestamp: o.cancellationRequestedAt,
        backgroundColor: Colors.red.shade50,
        borderColor: Colors.red.shade200,
      ));
    }
    
    // Rejection reason
    if (o.status.toLowerCase() == 'rejected' && (o.rejectionReason ?? '').isNotEmpty) {
      updateEntries.add(_buildUpdateEntry(
        icon: Icons.info_outline,
        iconColor: Colors.red,
        title: 'Rejection Reason',
        content: o.rejectionReason!,
        backgroundColor: Colors.red.shade50,
        borderColor: Colors.red.shade200,
      ));
    }
    
    // Refund confirmed
    if ((o.paymentMethod.toLowerCase() == 'gcash') && isCancelled && (o.refundDenied != true) && (o.refundConfirmedAt != null)) {
      updateEntries.add(_buildUpdateEntry(
        icon: Icons.check_circle_outline,
        iconColor: Colors.green,
        title: 'Refund Status',
        content: 'Cancellation confirmed and refunded to your GCash account.',
        timestamp: o.refundConfirmedAt,
        backgroundColor: Colors.green.shade50,
        borderColor: Colors.green.shade200,
      ));
    }
    
    // Refund denied
    if (o.status.toLowerCase() == 'cancelled' && (o.refundDenied == true) && (o.refundDeniedReason ?? '').isNotEmpty) {
      updateEntries.add(_buildUpdateEntry(
        icon: Icons.info_outline,
        iconColor: Colors.orange,
        title: 'Cancellation confirmed (No refund)',
        content: o.refundDeniedReason!,
        timestamp: o.refundDeniedAt,
        backgroundColor: Colors.orange.shade50,
        borderColor: Colors.orange.shade200,
      ));
    }
    
    // To Receive status updates
    // CRITICAL: Only show "Pickup Ready" if status is actually 'to_receive'
    // Status check ensures we don't show "Ready to Pickup" when already picked_up or failed_pickup
    final orderStatus = o.status.toLowerCase();
    if (orderStatus == 'to_receive') {
      // Pickup ready notification
      if (o.deliveryOption.toLowerCase() == 'pickup' && o.readyForPickup == true) {
        updateEntries.add(_buildUpdateEntry(
          icon: Icons.store_outlined,
          iconColor: Colors.orange,
          title: 'Pickup Ready',
          content: 'Your order is ready to pickup. Please get your order within this day since this is a one-time pickup schedule. No reschedule and refund.',
          backgroundColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
        ));
      }
      
      // Delivery schedule notification
      if (((o.estimatedDeliveryStart != null && o.estimatedDeliveryEnd != null) || (o.deliveryNotes).isNotEmpty) && 
          !(o.deliveryOption.toLowerCase() == 'pickup' && o.readyForPickup == true)) {
        final scheduleNote = o.deliveryOption.toLowerCase() == 'pickup'
            ? 'Pickup of orders can be done for the next one-day pickup schedule.'
            : 'Your order will be delivered for the next one-day delivery schedule.';
        
        String fullContent = scheduleNote;
        if (o.estimatedDeliveryStart != null && o.estimatedDeliveryEnd != null) {
          final scheduleLabel = o.deliveryOption.toLowerCase() == 'pickup'
              ? 'Estimated Pickup Schedule'
              : 'Estimated Delivery Schedule';
          fullContent += '\n\n$scheduleLabel: ${_formatDateRange(o.estimatedDeliveryStart!, o.estimatedDeliveryEnd!)}';
        }
        
        updateEntries.add(_buildUpdateEntry(
          icon: Icons.event_note_outlined,
          iconColor: Colors.blue,
          title: 'Schedule Information',
          content: fullContent,
          backgroundColor: Colors.blue.shade50,
          borderColor: Colors.blue.shade200,
        ));
      }
      
      // Cancellation no longer applicable
      updateEntries.add(_buildUpdateEntry(
        icon: Icons.info_outline,
        iconColor: Colors.red[700]!,
        title: 'Important Notice',
        content: 'Cancellation is no longer applicable',
        backgroundColor: Colors.red.shade50,
        borderColor: Colors.red.shade200,
      ));
    }
    
    // Order notes - always display regardless of order status
    // Check all possible field names for order notes
    final orderNotes = o.deliveryNotes ?? '';
    if (orderNotes.isNotEmpty && orderNotes.trim().isNotEmpty) {
      // Determine title based on delivery option
      final notesTitle = o.deliveryOption.toLowerCase() == 'pickup'
          ? 'Order/Pickup Notes'
          : 'Order/Delivery Notes';
      
      updateEntries.add(_buildUpdateEntry(
        icon: Icons.note_outlined,
        iconColor: Colors.grey[700]!,
        title: notesTitle,
        content: orderNotes,
        backgroundColor: Colors.grey.shade50,
        borderColor: Colors.grey.shade200,
      ));
    }
    
    if (updateEntries.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.update_outlined, color: AppTheme.primaryColor),
                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                Text(
                  'Updates & Notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            const Divider(height: 1),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            ...updateEntries,
          ],
        ),
      ),
    );
  }
  
  Widget _buildUpdateEntry({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    DateTime? timestamp,
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 12)),
      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: Responsive.getIconSize(context, mobile: 20)),
              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.bold,
                        fontSize: Responsive.getFontSize(context, mobile: 14),
                      ),
                    ),
                    if (timestamp != null) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                      Text(
                        _formatDate(timestamp),
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 11),
                          color: iconColor.withOpacity(0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
          Padding(
            padding: EdgeInsets.only(left: Responsive.getSpacing(context, mobile: 28)),
            child: Text(
              content,
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 13),
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 4)),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(fontWeight: emphasize ? FontWeight.bold : FontWeight.normal, color: emphasize ? AppTheme.primaryColor : null)),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final amPm = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day}/${d.month}/${d.year} at $hour:${d.minute.toString().padLeft(2, '0')} $amPm';
  }

  String _formatDateOnly(DateTime d) {
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _markOrderAsReceived(Order order) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Order Received'),
          content: const Text('Are you sure you have received your order? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Update order status to picked up
        await FirebaseDatabase.instance
            .ref('orders/${order.id}')
            .update({
          'status': 'picked_up',
          'pickedUpAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order marked as received successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Navigate back to orders list
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final s = '${start.month}/${start.day}/${start.year}';
    final e = '${end.month}/${end.day}/${end.year}';
    return '$s - $e';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppTheme.warningColor;
      case 'confirmed':
        return AppTheme.infoColor;
      case 'out_for_delivery':
        return AppTheme.primaryColor;
      case 'pickup_ready':
        return Colors.orange;
      case 'picked_up':
        return Colors.green;
      case 'delivered':
        return AppTheme.successColor;
      case 'cancelled':
        return AppTheme.errorColor;
      case 'request_cancellation_sent':
        return Colors.orange;
      case 'cancellation_confirmed':
        return AppTheme.successColor;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.schedule;
      case 'confirmed':
        return Icons.check_circle;
      case 'out_for_delivery':
        return Icons.local_shipping;
      case 'pickup_ready':
        return Icons.store;
      case 'picked_up':
        return Icons.check_circle;
      case 'delivered':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel;
      case 'request_cancellation_sent':
        return Icons.hourglass_empty;
      case 'cancellation_confirmed':
        return Icons.check_circle;
      default:
        return Icons.receipt;
    }
  }

  String _statusLabel(String status, [Order? order]) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'to_receive':
        // CRITICAL: Don't show "Ready to Pickup" if order is already picked_up or failed_pickup
        // Check status first to prevent glitching back to "Ready to Pickup"
        final orderStatus = order?.status.toLowerCase() ?? status.toLowerCase();
        if (orderStatus == 'picked_up' || orderStatus == 'failed_pickup') {
          // Order is in final state, don't check readyForPickup flag
          if (orderStatus == 'picked_up') {
            return 'Order pickedup successfully!';
          } else {
            return 'Failed to Pickup';
          }
        }
        // Check if pickup order is ready for pickup
        if (order?.deliveryOption.toLowerCase() == 'pickup' && order?.readyForPickup == true) {
          return 'Ready to Pickup';
        }
        return 'To Receive';
      case 'pickup_ready':
        return 'Pickup Ready';
      case 'picked_up':
        return 'Order pickedup successfully!';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'request_cancellation_sent':
        return 'Request Cancellation Sent';
      case 'cancellation_confirmed':
        return 'Ordered Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  Widget _buildSupportChatButton(BuildContext context, Order order) {
    final status = order.status.toLowerCase();
    final isReadyForPickup = order.deliveryOption.toLowerCase() == 'pickup' && 
        order.readyForPickup == true && 
        status == 'to_receive';
    
    // Determine text and button label based on status
    String supportText;
    if (status == 'out_for_delivery') {
      supportText = 'Did not receive your order?';
    } else if (isReadyForPickup) {
      supportText = 'Have a problem to pickup or failed to get your order?';
    } else {
      // For: pending, confirmed, to_receive, failed (pickup or delivery), delivered, picked_up, cancelled, cancellation_confirmed
      supportText = 'Order concerns and questions?';
    }
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            supportText,
            style: TextStyle(
              fontSize: Responsive.getFontSize(context, mobile: 14),
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openSupportChat(context),
              icon: Icon(Icons.support_agent, size: Responsive.getIconSize(context, mobile: 18)),
              label: Text(
                'CALCOA Support',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14), fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRiderChat(BuildContext context, Order order) async {
    if (order.riderId == null || order.riderName == null || order.riderName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider information not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    if (authProvider.currentCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to chat'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final customerId = authProvider.currentCustomer!.uid;

    // Initialize chat if not already initialized - wait for it to complete
    if (chatProvider.currentCustomerId != customerId) {
      await chatProvider.initializeChat(customerId);
    }

    // Create or get rider conversation (will create new one if deleted)
    final conversationId = await chatProvider.createRiderConversation(
      order.riderId!,
      order.riderName!,
    );

    if (conversationId != null) {
      // Reload conversations to ensure the new/updated conversation is in the list
      await chatProvider.loadConversations();
      
      // Wait for conversations to be loaded and find the rider conversation
      int retries = 0;
      bool conversationFound = false;
      while (retries < 10 && !conversationFound) {
        await Future.delayed(const Duration(milliseconds: 200));
        final allConversations = [
          ...chatProvider.conversations,
          ...chatProvider.archivedConversations,
        ];
        conversationFound = allConversations.any(
          (conv) => conv.id == conversationId && conv.chatType == 'rider',
        );
        retries++;
      }
      
      // Select the conversation immediately
      chatProvider.selectConversation(conversationId);
      
      // Wait a bit more to ensure selection is processed and messages are loaded
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Navigate to chat screen - it will show the conversation directly
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(initialConversationId: conversationId),
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open chat. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openSupportChat(BuildContext context) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      
      if (authProvider.currentCustomer == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in to chat'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final customerId = authProvider.currentCustomer!.uid;

      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening support chat...'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // Initialize chat if not already initialized - wait for it to complete
      if (chatProvider.currentCustomerId != customerId) {
        await chatProvider.initializeChat(customerId);
      }

      // Create or get support conversation (staff chat)
      String? conversationId;
      try {
        conversationId = await chatProvider.createConversation();
      } catch (e) {
        debugPrint('❌ Error creating conversation: $e');
        // If creation fails, try to load existing conversations and find staff conversation
        await chatProvider.loadConversations();
        final allConversations = [
          ...chatProvider.conversations,
          ...chatProvider.archivedConversations,
        ];
        final staffConversation = allConversations.firstWhere(
          (conv) => conv.chatType == 'staff' && conv.customerId == customerId,
          orElse: () => allConversations.firstWhere(
            (conv) => conv.chatType == 'staff',
            orElse: () => allConversations.isNotEmpty ? allConversations.first : throw Exception('No conversations found'),
          ),
        );
        conversationId = staffConversation.id;
      }
      
      if (conversationId != null && conversationId.isNotEmpty) {
        // Reload conversations to ensure the new/updated conversation is in the list
        await chatProvider.loadConversations();
        
        // Wait for conversations to be loaded and find the staff conversation
        int retries = 0;
        bool conversationFound = false;
        while (retries < 10 && !conversationFound) {
          await Future.delayed(const Duration(milliseconds: 200));
          final allConversations = [
            ...chatProvider.conversations,
            ...chatProvider.archivedConversations,
          ];
          conversationFound = allConversations.any(
            (conv) => conv.id == conversationId && conv.chatType == 'staff',
          );
          retries++;
        }
        
        // Select the conversation - use customerId for staff conversations
        chatProvider.selectConversation(conversationId);
        
        // Wait a bit more to ensure selection is processed and messages are loaded
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Navigate to chat screen - it will show the conversation directly
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(initialConversationId: conversationId),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open chat. Please try again later.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error opening support chat: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to open support chat. Please try again later.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _openSupportChat(context),
            ),
          ),
        );
      }
    }
  }

  Widget _buildMarkAsReceivedButton(BuildContext context, Order order) {
    return Container(
      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              // Show loading dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );

              try {
                final provider = Provider.of<CustomerProvider>(context, listen: false);
                final success = await provider.markOrderReceived(order.id);
                
                if (context.mounted) {
                  Navigator.of(context).pop(); // Close loading dialog
                  
                  if (success) {
                    // Show success message
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Order marked as received! You can now rate your order.'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    
                    // Navigate back to orders screen and go to "To Rate" tab
                    Navigator.of(context).pop();
                    
                    // Navigate to the "To Rate" tab (delivered status)
                    // This will be handled by the OrderPhasesScreen when it detects the status change
                  } else {
                    // Show error message
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('❌ Failed to update order status'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop(); // Close loading dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark as Received'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _canCancelOrder(Order order) {
    final status = order.status.toLowerCase();
    if (status == 'to_receive' || status == 'out_for_delivery' || status == 'delivered') return false;
    if (status == 'pending' || status == 'confirmed') {
      return OrderSchedule.canCancelOrder();
    }
    return false;
  }

  void _showReceiptLightbox(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Full-screen image viewer with zoom capability
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black,
                    child: Center(
                      child: Icon(Icons.error, color: Colors.white, size: Responsive.getIconSize(context, mobile: 48)),
                    ),
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 24)),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Title
            Positioned(
              top: 40,
              left: 20,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12), vertical: Responsive.getSpacing(context, mobile: 8)),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: Responsive.getFontSize(context, mobile: 16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Hint text at bottom
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                  ),
                  child: Text(
                    'Pinch to zoom • Tap outside to close',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: Responsive.getFontSize(context, mobile: 12),
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

  Future<void> _launchGoogleMaps(String mapLink) async {
    try {
      final Uri url = Uri.parse(mapLink);
      
      // Check if the URL can be launched
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication, // This will open in the default app (Google Maps)
        );
      } else {
        // Fallback: try to open in browser
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Get Supabase image URL
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
    // Remove leading slashes
    filePath = filePath.replaceAll(RegExp(r'^/+'), '');
    
    // If it doesn't contain product ID, add it
    if (!filePath.startsWith('$productId/') && !filePath.contains('/')) {
      filePath = '$productId/$filePath';
    }
    
    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  // Get Supabase video URL
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

  // Build combined media list for carousel
  List<_ProductMediaItem> _getProductMedia(Product? product) {
    if (product == null) return [];
    
    final List<_ProductMediaItem> media = [];
    
    final imageUrls = <String>[];
    if (product.imageUrls.isNotEmpty) {
      imageUrls.addAll(product.imageUrls);
    }
    if (product.imageUrl.isNotEmpty && !imageUrls.contains(product.imageUrl)) {
      imageUrls.add(product.imageUrl);
    }
    media.addAll(
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
    media.addAll(
      videoUrls
          .map((url) => _getSupabaseVideoUrl(url, product.id))
          .where((url) => url.isNotEmpty)
          .map((url) => _ProductMediaItem(url: url, type: _ProductMediaType.video)),
    );
    
    return media;
  }

  Widget _buildProductMediaCarousel(Product? product, double size) {
    final mediaItems = _getProductMedia(product);
    
    if (mediaItems.isEmpty) {
      // Show placeholder if no media
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
          child: Icon(
            Icons.image_outlined,
            color: Colors.grey,
            size: size * 0.4,
          ),
        ),
      );
    }

    // Single media item - no carousel needed
    if (mediaItems.length == 1) {
      return _buildMediaItem(mediaItems[0], size);
    }

    // Multiple media items - carousel
    return SizedBox(
      width: size,
      height: size,
      child: PageView.builder(
        itemCount: mediaItems.length,
        itemBuilder: (context, index) {
          return _buildMediaItem(mediaItems[index], size);
        },
      ),
    );
  }

  Widget _buildMediaItem(_ProductMediaItem item, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        child: item.type == _ProductMediaType.image
            ? CachedNetworkImage(
                imageUrl: item.url,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: size * 0.4,
                  ),
                ),
              )
            : Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Icon(
                        Icons.play_circle_filled,
                        color: Colors.white70,
                        size: size * 0.5,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

enum _ProductMediaType { image, video }

class _ProductMediaItem {
  final String url;
  final _ProductMediaType type;

  _ProductMediaItem({required this.url, required this.type});
}


