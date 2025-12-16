import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../../models/product.dart';
import '../../providers/customer_provider.dart';
import '../orders/order_review_screen.dart';
import '../../utils/order_schedule.dart';
import '../../utils/harvest_date_helper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int quantity = 1;
  final PageController _pageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void initState() {
    super.initState();
    // Add listener for order schedule changes
    OrderSchedule.addListener(_onOrderScheduleChanged);
  }

  @override
  void dispose() {
    OrderSchedule.removeListener(_onOrderScheduleChanged);
    _pageController.dispose();
    super.dispose();
  }

  // Handle order schedule changes
  void _onOrderScheduleChanged() {
    if (mounted) {
      print('🔄 Order schedule changed, refreshing product detail...');
      setState(() {
        // Force rebuild to update ordering status
      });
    }
  }

  // Build combined media list for carousel
  List<_ProductMediaItem> _getProductMedia(Product product) {
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CustomerProvider>(context);
    final product = provider.getProductById(widget.product.id) ?? widget.product;
    final canBuy = product.isAvailable && product.availableQuantity > 0;
    final canOrderNow = OrderSchedule.canPlaceOrder();
    final mediaItems = _getProductMedia(product);
    final soldQuantity = provider.getSoldQuantity(product.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          product.name,
          style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 20)),
        ),
      ),
      body: SingleChildScrollView(
        padding: Responsive.getPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product media carousel (images + videos)
            _buildProductMediaCarousel(mediaItems),
            SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: Responsive.getFontSize(context, mobile: 24),
                    ),
                  ),
                ),
                if (!product.isAvailable)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.getSpacing(context, mobile: 8),
                      vertical: Responsive.getSpacing(context, mobile: 4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Text(
                      'Unavailable',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: Responsive.getFontSize(context, mobile: 12),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
            Text(
              product.description,
              style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
            Wrap(
              spacing: Responsive.getSpacing(context, mobile: 8),
              runSpacing: Responsive.getSpacing(context, mobile: 8),
              children: [
                Chip(
                  label: Text(
                    product.category,
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12)),
                  ),
                ),
                Chip(
                  label: Text(
                    '${product.availableQuantity} ${product.unit} available',
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12)),
                  ),
                ),
                if (soldQuantity > 0)
                  Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_bag,
                          size: Responsive.getIconSize(context, mobile: 14),
                          color: Colors.green[700],
                        ),
                        SizedBox(width: Responsive.getSpacing(context, mobile: 4)),
                        Text(
                          '$soldQuantity kg sold',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                            fontSize: Responsive.getFontSize(context, mobile: 12),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green.shade50,
                  ),
              ],
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: Responsive.getIconSize(context, mobile: 16),
                  color: Colors.grey[600],
                ),
                SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                Expanded(
                  child: Text(
                    'Estimated Harvest Date: ${HarvestDateHelper.getHarvestDateRangeSimple()}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: Responsive.getFontSize(context, mobile: 14),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Price per Kilo: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: Responsive.getFontSize(context, mobile: 18),
                      color: Colors.black87,
                    ),
                  ),
                  TextSpan(
                    text: '\u20B1',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontFamilyFallback: ['Arial', 'sans-serif'],
                      fontWeight: FontWeight.bold,
                      fontSize: Responsive.getFontSize(context, mobile: 18),
                      color: Colors.black87,
                    ),
                  ),
                  TextSpan(
                    text: product.price.toStringAsFixed(2),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: Responsive.getFontSize(context, mobile: 18),
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
            Row(
              children: [
                Text(
                  'Quantity/Kilo:',
                  style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
                ),
                SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                IconButton(
                  onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
                  icon: Icon(
                    Icons.remove_circle_outline,
                    size: Responsive.getIconSize(context, mobile: 24),
                  ),
                ),
                Text(
                  '$quantity',
                  style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 18)),
                ),
                IconButton(
                  onPressed: canBuy && quantity < product.availableQuantity
                      ? () => setState(() => quantity++)
                      : null,
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: Responsive.getIconSize(context, mobile: 24),
                  ),
                ),
              ],
            ),
            SizedBox(height: Responsive.getSpacing(context, mobile: 24)),
            if (!product.isAvailable)
              Padding(
                padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 12)),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red,
                      size: Responsive.getIconSize(context, mobile: 20),
                    ),
                    SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                    Expanded(
                      child: Text(
                        'This product is currently unavailable. Purchasing is disabled.',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canBuy && quantity <= product.availableQuantity
                        ? () {
                            Provider.of<CustomerProvider>(context, listen: false).addToCart(product, quantity: quantity);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
                          }
                        : null,
                    icon: Icon(
                      Icons.add_shopping_cart,
                      size: Responsive.getIconSize(context, mobile: 18),
                    ),
                    label: Text(
                      'Add to Cart',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: Responsive.getSpacing(context, mobile: 8),
                        vertical: Responsive.getSpacing(context, mobile: 12),
                      ),
                      minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 48)),
                    ),
                  ),
                ),
                SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (canBuy && quantity <= product.availableQuantity && canOrderNow)
                        ? () {
                            final provider = Provider.of<CustomerProvider>(context, listen: false);
                            // Build a one-off order review with ONLY this product, not the entire cart
                            provider.startBuyNow(product, quantity: quantity);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const OrderReviewScreen(),
                              ),
                            );
                          }
                        : null,
                    icon: Icon(
                      Icons.flash_on,
                      size: Responsive.getIconSize(context, mobile: 18),
                    ),
                    label: Text(
                      'Buy Now',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: Responsive.getSpacing(context, mobile: 8),
                        vertical: Responsive.getSpacing(context, mobile: 12),
                      ),
                      minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 48)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductMediaCarousel(List<_ProductMediaItem> mediaItems) {
    if (mediaItems.isEmpty) {
      return Container(
        height: Responsive.getImageSize(context, mobile: 300),
        width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppTheme.creamGradient,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        child: Icon(
          Icons.image,
          size: Responsive.getImageSize(context, mobile: 72),
          color: Colors.grey,
        ),
      );
    }

    return Builder(
      builder: (context) => Container(
        height: Responsive.getImageSize(context, mobile: 300),
        width: double.infinity,
        margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
          decoration: BoxDecoration(
            color: AppTheme.creamLight,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
      child: Builder(
        builder: (context) => Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentMediaIndex = index;
              });
            },
            itemCount: mediaItems.length,
            itemBuilder: (context, index) {
              final media = mediaItems[index];
              return Builder(
                builder: (context) => ClipRRect(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: media.type == _ProductMediaType.image
                            ? CachedNetworkImage(
                                imageUrl: media.url,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[200],
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: Responsive.getImageSize(context, mobile: 48),
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
                                      Text(
                                        'Failed to load image',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : _ProductVideoPlayer(videoUrl: media.url),
                      ),
                      if (media.type == _ProductMediaType.video)
                        Positioned(
                          top: Responsive.getSpacing(context, mobile: 12),
                          left: Responsive.getSpacing(context, mobile: 12),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: Responsive.getSpacing(context, mobile: 10),
                              vertical: Responsive.getSpacing(context, mobile: 4),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: Responsive.getIconSize(context, mobile: 14),
                                ),
                                SizedBox(width: Responsive.getSpacing(context, mobile: 4)),
                                Text(
                                  'Video',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: Responsive.getFontSize(context, mobile: 12),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Navigation Arrows (only show if multiple media items)
          if (mediaItems.length > 1) ...[
            // Previous Button
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: const Color.fromRGBO(0, 0, 0, 0.4),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                  child: InkWell(
                    onTap: () {
                      if (_currentMediaIndex > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _pageController.jumpToPage(mediaItems.length - 1);
                      }
                    },
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                    child: Container(
                      width: Responsive.getWidth(context, mobile: 40),
                      height: Responsive.getHeight(context, mobile: 40),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: Responsive.getIconSize(context, mobile: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Next Button
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: const Color.fromRGBO(0, 0, 0, 0.4),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                  child: InkWell(
                    onTap: () {
                      if (_currentMediaIndex < mediaItems.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _pageController.jumpToPage(0);
                      }
                    },
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                    child: Container(
                      width: Responsive.getWidth(context, mobile: 40),
                      height: Responsive.getHeight(context, mobile: 40),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: Responsive.getIconSize(context, mobile: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Dots Indicator
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  mediaItems.length,
                  (index) => Container(
                    width: Responsive.getWidth(context, mobile: 8),
                    height: Responsive.getHeight(context, mobile: 8),
                    margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 4)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentMediaIndex == index
                          ? Colors.white
                          : const Color.fromRGBO(255, 255, 255, 0.4),
                    ),
                  ),
                ),
              ),
            ),
          ],
          
          // Media Counter
          if (mediaItems.length > 1)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 4)),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(0, 0, 0, 0.6),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                ),
                child: Text(
                  '${_currentMediaIndex + 1} / ${mediaItems.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: Responsive.getFontSize(context, mobile: 12),
                    fontWeight: FontWeight.w500,
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

enum _ProductMediaType { image, video }

class _ProductMediaItem {
  final String url;
  final _ProductMediaType type;

  _ProductMediaItem({required this.url, required this.type});
}

class _ProductVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const _ProductVideoPlayer({required this.videoUrl});

  @override
  State<_ProductVideoPlayer> createState() => _ProductVideoPlayerState();
}

class _ProductVideoPlayerState extends State<_ProductVideoPlayer> {
  late VideoPlayerController _controller;
  Future<void>? _initializeFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _initializeFuture = _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
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
    if (!_controller.value.isInitialized) return;
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
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: Responsive.getHeight(context, mobile: 220),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!_controller.value.isInitialized) {
          return Container(
            height: Responsive.getHeight(context, mobile: 220),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            ),
            child: const Center(
              child: Text('Failed to load video'),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio == 0
                    ? 16 / 9
                    : _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.fromARGB(120, 0, 0, 0),
                        Color.fromARGB(60, 0, 0, 0),
                        Color.fromARGB(120, 0, 0, 0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
              IconButton(
                iconSize: Responsive.getIconSize(context, mobile: 56),
                onPressed: _togglePlayback,
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: Colors.white,
                  size: Responsive.getIconSize(context, mobile: 56),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 4)),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                  ),
                  child: Text(
                    _controller.value.isPlaying ? 'Playing' : 'Paused',
                    style: TextStyle(color: Colors.white, fontSize: Responsive.getFontSize(context, mobile: 12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


