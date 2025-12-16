import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/customer_provider.dart';
import '../../models/product.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';
import '../orders/order_review_screen.dart';
import '../products/product_detail_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final Set<String> _selected = <String>{};
  bool _selectAll = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Shopping Cart',
          style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 20)),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: Responsive.getAppBarHeight(context),
        actions: [
          Consumer<CustomerProvider>(
            builder: (context, provider, child) {
              if (provider.cartItems.isNotEmpty) {
                return TextButton(
                  onPressed: () {
                    _showClearCartDialog(context, provider);
                  },
                  child: Text(
                    'Clear All',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: Responsive.getFontSize(context, mobile: 14),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<CustomerProvider>(
        builder: (context, provider, child) {
          if (provider.cartItems.isEmpty) {
            return _buildEmptyCart();
          }

          // Keep selected set in sync if cart changes
          _selected.removeWhere((id) => !provider.cartItems.any((it) => it.productId == id));

          return Column(
            children: [
              // Cart Items List
              Expanded(
                child: ListView.builder(
                  padding: Responsive.getPadding(context),
                  itemCount: provider.cartItems.length,
                  itemBuilder: (context, index) {
                    final item = provider.cartItems[index];
                    return _buildCartItem(context, provider, item);
                  },
                ),
              ),
              
              // Checkout Section
              _buildCheckoutSection(context, provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Padding(
        padding: Responsive.getPadding(context).copyWith(
          left: Responsive.getSpacing(context, mobile: 32),
          right: Responsive.getSpacing(context, mobile: 32),
          top: Responsive.getSpacing(context, mobile: 32),
          bottom: Responsive.getSpacing(context, mobile: 32),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 24)),
              decoration: BoxDecoration(
                gradient: AppTheme.creamGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: Responsive.getImageSize(context, mobile: 64),
                color: Colors.grey[400],
              ),
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 24)),
            Text(
              'Your cart is empty',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[800],
                fontWeight: FontWeight.bold,
                fontSize: Responsive.getFontSize(context, mobile: 24),
              ),
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
            Text(
              'Add some products to get started',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
                fontSize: Responsive.getFontSize(context, mobile: 16),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 32)),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to products page (home screen)
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              icon: Icon(
                Icons.shopping_bag_outlined,
                size: Responsive.getIconSize(context, mobile: 20),
              ),
              label: Text(
                'Start Shopping',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.getSpacing(context, mobile: 24),
                  vertical: Responsive.getSpacing(context, mobile: 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
                minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 48)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(BuildContext context, CustomerProvider provider, dynamic item) {
    final product = provider.getProductById(item.productId);
    final remaining = product?.availableQuantity ?? 0;
    final isAvailable = product?.isAvailable ?? false;
    final isSoldOut = remaining <= 0;
    final isInvalid = product == null || !isAvailable || isSoldOut || item.quantity > remaining;

    return Builder(
      builder: (context) => Card(
        margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 12)),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
          side: BorderSide(
            color: Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: () {
            if (product != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(product: product),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
          child: Padding(
            padding: Responsive.getPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Checkbox, Image, and Remove Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selection Checkbox
                  Checkbox(
                    value: _selected.contains(item.productId),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(item.productId);
                        } else {
                          _selected.remove(item.productId);
                        }
                        _selectAll = _selected.length == provider.cartItems.length;
                      });
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
                  
                  // Product Image/Video Carousel
                  _buildProductMediaCarousel(product, Responsive.getImageSize(context, mobile: 80)),
                  
                  SizedBox(width: Responsive.getSpacing(context, mobile: 12)),
                  
                  // Product Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Name
                        Text(
                          item.productName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: Responsive.getFontSize(context, mobile: 16),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                        
                        // Price per unit
                        Text(
                          '\u20B1${(product?.price ?? 0).toStringAsFixed(2)} per ${product?.unit ?? item.unit}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                          ),
                        ),
                        SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                        
                        // Availability Status
                        _buildAvailabilityStatus(isAvailable, isSoldOut, remaining, product?.unit ?? item.unit),
                      ],
                    ),
                  ),
                  
                  // Remove Button
                  IconButton(
                    onPressed: () => _showRemoveItemDialog(context, provider, item),
                    icon: Icon(Icons.delete_outline),
                    color: Colors.red[400],
                    iconSize: Responsive.getIconSize(context, mobile: 20),
                  ),
                ],
              ),
              
              SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
              
              // Bottom Row: Quantity Controls and Total Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Quantity Controls
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: item.quantity > 1 ? () {
                            provider.updateCartItemQuantity(
                              item.productId,
                              item.quantity - 1,
                            );
                          } : null,
                          icon: Icon(Icons.remove),
                          iconSize: Responsive.getIconSize(context, mobile: 18),
                          color: item.quantity > 1 ? AppTheme.primaryColor : Colors.grey,
                          constraints: BoxConstraints(
                            minWidth: Responsive.getButtonHeight(context, mobile: 36),
                            minHeight: Responsive.getButtonHeight(context, mobile: 36),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12)),
                          child: Text(
                            '${item.quantity}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: Responsive.getFontSize(context, mobile: 16),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: item.quantity < remaining ? () {
                            provider.updateCartItemQuantity(
                              item.productId,
                              item.quantity + 1,
                            );
                          } : null,
                          icon: Icon(Icons.add),
                          iconSize: Responsive.getIconSize(context, mobile: 18),
                          color: item.quantity < remaining ? AppTheme.primaryColor : Colors.grey,
                          constraints: BoxConstraints(
                            minWidth: Responsive.getButtonHeight(context, mobile: 36),
                            minHeight: Responsive.getButtonHeight(context, mobile: 36),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Total Price
                  Text(
                    '\u20B1${item.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: Responsive.getFontSize(context, mobile: 18),
                      color: isInvalid ? Colors.red : AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              
              // Warning for invalid items
              if (isInvalid)
                Container(
                  margin: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 8)),
                  padding: Responsive.getPadding(context).copyWith(
                    left: Responsive.getSpacing(context, mobile: 8),
                    right: Responsive.getSpacing(context, mobile: 8),
                    top: Responsive.getSpacing(context, mobile: 8),
                    bottom: Responsive.getSpacing(context, mobile: 8),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_outlined,
                        color: Colors.red[600],
                        size: Responsive.getIconSize(context, mobile: 16),
                      ),
                      SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                      Expanded(
                        child: Text(
                          _getInvalidItemMessage(product, isAvailable, isSoldOut, remaining, item.quantity),
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: Responsive.getFontSize(context, mobile: 12),
                            fontWeight: FontWeight.w500,
                          ),
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
  }

  Widget _buildAvailabilityStatus(bool isAvailable, bool isSoldOut, int remaining, String unit) {
    if (!isAvailable) {
      return Text(
        'Unavailable',
        style: TextStyle(
          color: Colors.red[600],
          fontSize: Responsive.getFontSize(context, mobile: 12),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    
    if (isSoldOut) {
      return Text(
        'Sold Out',
        style: TextStyle(
          color: Colors.red[600],
          fontSize: Responsive.getFontSize(context, mobile: 12),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    
    return Text(
      '$remaining $unit available',
      style: TextStyle(
        color: Colors.green[600],
        fontSize: Responsive.getFontSize(context, mobile: 12),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _getInvalidItemMessage(dynamic product, bool isAvailable, bool isSoldOut, int remaining, int quantity) {
    if (product == null) {
      return 'Product not found';
    }
    if (!isAvailable) {
      return 'Product is unavailable';
    }
    if (isSoldOut) {
      return 'Product is sold out';
    }
    if (quantity > remaining) {
      return 'Quantity exceeds available stock';
    }
    return 'Item has issues';
  }

  Widget _buildCheckoutSection(BuildContext context, CustomerProvider provider) {
    // Calculate subtotal only for selected (checked) items
    final subtotal = provider.cartItems
        .where((item) => _selected.contains(item.productId))
        .fold<double>(
          0,
          (sum, item) => sum + item.total,
        );

    bool hasInvalidItems = false;
    for (final item in provider.cartItems) {
      final product = provider.getProductById(item.productId);
      final remaining = product?.availableQuantity ?? 0;
      final isAvailable = product?.isAvailable ?? false;
      if (product == null || !isAvailable || remaining <= 0 || item.quantity > remaining) {
        hasInvalidItems = true;
        break;
      }
    }

    return Container(
      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Select All Row
          Row(
            children: [
              Checkbox(
                value: _selectAll,
                onChanged: (v) {
                  setState(() {
                    _selectAll = v == true;
                    if (_selectAll) {
                      _selected.clear();
                      _selected.addAll(provider.cartItems.map((it) => it.productId));
                    } else {
                      _selected.clear();
                    }
                  });
                },
                activeColor: AppTheme.primaryColor,
              ),
              const Text(
                'Select all',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (_selected.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showRemoveSelectedDialog(context, provider),
                  icon: Icon(Icons.delete_outline, size: Responsive.getIconSize(context, mobile: 18)),
                  label: const Text('Remove selected'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[600],
                  ),
                ),
            ],
          ),
          
          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
          
          // Subtotal Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal:',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '\u20B1${subtotal.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          
          SizedBox(height: Responsive.getHeight(context, mobile: 20)),
          
          // Checkout Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: hasInvalidItems || _selected.isEmpty ? null : () {
                final selectedItems = provider.cartItems
                    .where((it) => _selected.contains(it.productId))
                    .toList();
                provider.startCheckoutWithSelected(selectedItems);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const OrderReviewScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                ),
                elevation: 2,
              ),
              child: Text(
                _selected.isEmpty 
                    ? 'Select items to checkout'
                    : 'Checkout ${_selected.length} item${_selected.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 16),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          // Warning for invalid items
          if (hasInvalidItems)
            Container(
              margin: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 12)),
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[600], size: Responsive.getIconSize(context, mobile: 20)),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  Expanded(
                    child: Text(
                      'Some items are unavailable or sold out. Please adjust your cart before checkout.',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: Responsive.getFontSize(context, mobile: 13),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showClearCartDialog(BuildContext context, CustomerProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cart'),
        content: const Text('Are you sure you want to remove all items from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.clearCart();
              setState(() {
                _selected.clear();
                _selectAll = false;
              });
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cart cleared')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRemoveItemDialog(BuildContext context, CustomerProvider provider, dynamic item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "${item.productName}" from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removeFromCart(item.productId);
              setState(() {
                _selected.remove(item.productId);
                _selectAll = _selected.length == provider.cartItems.length;
              });
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${item.productName} removed from cart'),
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () {
                      final product = provider.getProductById(item.productId);
                      if (product != null) {
                        provider.addToCart(product, quantity: item.quantity);
                      }
                    },
                  ),
                ),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRemoveSelectedDialog(BuildContext context, CustomerProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Selected Items'),
        content: Text('Remove ${_selected.length} selected item${_selected.length == 1 ? '' : 's'} from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final ids = _selected.toList();
              provider.removeItemsFromCartByProductIds(ids);
              setState(() {
                _selected.clear();
                _selectAll = false;
              });
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${ids.length} items removed from cart')),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
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
            ? Image.network(
                item.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[200],
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: size * 0.4,
                    ),
                  );
                },
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
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 6), vertical: Responsive.getSpacing(context, mobile: 2)),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 4)),
                        ),
                        child: Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Responsive.getFontSize(context, mobile: 10),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// Helper classes for media items
enum _ProductMediaType { image, video }

class _ProductMediaItem {
  final String url;
  final _ProductMediaType type;

  _ProductMediaItem({required this.url, required this.type});
}