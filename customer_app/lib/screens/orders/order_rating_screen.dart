import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../providers/customer_provider.dart';
import '../../utils/responsive.dart';

class OrderRatingScreen extends StatefulWidget {
  final String orderId;
  final Order order;

  const OrderRatingScreen({super.key, required this.orderId, required this.order});

  @override
  State<OrderRatingScreen> createState() => _OrderRatingScreenState();
}

class _OrderRatingScreenState extends State<OrderRatingScreen> {
  // Order feedback
  double _orderRating = 5.0;
  final _orderCommentController = TextEditingController();
  final List<XFile> _selectedMedia = [];
  bool _isSubmitting = false;

  // Rider feedback (for delivery orders)
  double _riderRating = 5.0;
  final _riderCommentController = TextEditingController();

  // Pickup experience feedback (for pickup orders)
  final _pickupExperienceController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  // Check if this is a pickup order
  bool get _isPickupOrder => widget.order.deliveryOption.toLowerCase() == 'pickup';

  @override
  void dispose() {
    _orderCommentController.dispose();
    _riderCommentController.dispose();
    _pickupExperienceController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    if (_selectedMedia.length >= 5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 files allowed')),
      );
      return;
    }

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Media'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final mediaType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Image'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );

    if (mediaType == null) return;

    try {
      XFile? file;
      if (mediaType == 'image') {
        file = await _picker.pickImage(source: source);
      } else {
        file = await _picker.pickVideo(source: source);
      }

      if (file != null) {
        // Check file size (max 50MB total)
        final fileSize = await file.length();
        int totalSize = fileSize;
        for (var media in _selectedMedia) {
          totalSize += await media.length();
        }

        if (totalSize > 52428800) { // 50 MB
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Total file size exceeds 50 MB')),
          );
          return;
        }

        setState(() {
          _selectedMedia.add(file!);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking media: $e')),
      );
    }
  }

  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      
      // Submit different data based on order type
      final success = await provider.submitOrderRating(
        orderId: widget.orderId,
        orderRating: _orderRating.round(),
        orderComment: _orderCommentController.text.trim(),
        riderRating: _isPickupOrder ? null : _riderRating.round(),
        riderComment: _isPickupOrder ? null : _riderCommentController.text.trim(),
        pickupExperienceComment: _isPickupOrder ? _pickupExperienceController.text.trim() : null,
        mediaFiles: _selectedMedia,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your feedback!')),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit rating. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Order'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: _isSubmitting
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
              children: [
                // Order Feedback Section
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shopping_bag, color: Colors.green[700]),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Order Feedback',
                              style: TextStyle(
                                fontSize: Responsive.getFontSize(context, mobile: 20),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        
                        // Order Rating
                        const Text('Overall Rating', style: TextStyle(fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                min: 1,
                                max: 5,
                                divisions: 4,
                                label: _orderRating.round().toString(),
                                value: _orderRating,
                                onChanged: (v) => setState(() => _orderRating = v),
                                activeColor: Colors.amber,
                              ),
                            ),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Row(
                              children: List.generate(
                                5,
                                (index) => Icon(
                                  index < _orderRating.round()
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber,
                                  size: Responsive.getIconSize(context, mobile: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        
                        // Order Comment
                        TextField(
                          controller: _orderCommentController,
                          decoration: const InputDecoration(
                            labelText: 'Comment (Optional)',
                            hintText: 'Share your experience with this order...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        
                        // Media Upload
                        const Text(
                          'Upload Images/Videos (Max 5 files, 50 MB total)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._selectedMedia.asMap().entries.map((entry) {
                              final index = entry.key;
                              final media = entry.value;
                              final isVideo = media.path.toLowerCase().endsWith('.mp4') ||
                                  media.path.toLowerCase().endsWith('.mov') ||
                                  media.path.toLowerCase().endsWith('.webm');
                              
                              return Stack(
                                children: [
                                  Container(
                                    width: Responsive.getWidth(context, mobile: 80),
                                    height: Responsive.getHeight(context, mobile: 80),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                                      child: isVideo
                                          ? Center(
                                              child: Icon(Icons.videocam, size: Responsive.getIconSize(context, mobile: 40)),
                                            )
                                          : Image.file(
                                              File(media.path),
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -8,
                                    right: -8,
                                    child: IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.red),
                                      onPressed: () => _removeMedia(index),
                                    ),
                                  ),
                                ],
                              );
                            }),
                            if (_selectedMedia.length < 5)
                              GestureDetector(
                                onTap: _pickMedia,
                                child: Container(
                                  width: Responsive.getWidth(context, mobile: 80),
                                  height: Responsive.getHeight(context, mobile: 80),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey, width: 2),
                                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                                  ),
                                  child: Icon(Icons.add, size: Responsive.getIconSize(context, mobile: 40), color: Colors.grey),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                
                // Conditional Section: Delivery Rider Feedback OR Pickup Experience
                if (_isPickupOrder)
                  // Pickup Experience Section (for pickup orders)
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.store, color: Colors.orange[700]),
                              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                              Text(
                                'Pickup Experience',
                                style: TextStyle(
                                  fontSize: Responsive.getFontSize(context, mobile: 20),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                          
                          // Pickup Experience Comment
                          TextField(
                            controller: _pickupExperienceController,
                            decoration: const InputDecoration(
                              labelText: 'Comment (Optional)',
                              hintText: 'How was your pickup experience?',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // Delivery Rider Feedback Section (for delivery orders)
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.delivery_dining, color: Colors.blue[700]),
                              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                              Text(
                                'Delivery Rider Feedback',
                                style: TextStyle(
                                  fontSize: Responsive.getFontSize(context, mobile: 20),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (widget.order.riderName != null) ...[
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            Text(
                              'Rider: ${widget.order.riderName}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                          
                          // Rider Rating
                          const Text('Overall Rating', style: TextStyle(fontWeight: FontWeight.w600)),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  min: 1,
                                  max: 5,
                                  divisions: 4,
                                  label: _riderRating.round().toString(),
                                  value: _riderRating,
                                  onChanged: (v) => setState(() => _riderRating = v),
                                  activeColor: Colors.amber,
                                ),
                              ),
                              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                              Row(
                                children: List.generate(
                                  5,
                                  (index) => Icon(
                                    index < _riderRating.round()
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: Responsive.getIconSize(context, mobile: 20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                          
                          // Rider Comment
                          TextField(
                            controller: _riderCommentController,
                            decoration: const InputDecoration(
                              labelText: 'Comment (Optional)',
                              hintText: 'Share your experience with the rider...',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                
                // Submit Button
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitRating,
                  icon: const Icon(Icons.send),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit Rating'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
                    textStyle: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
    );
  }
}
