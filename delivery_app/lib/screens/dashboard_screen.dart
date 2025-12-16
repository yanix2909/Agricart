import 'package:flutter/material.dart';
import '../utils/rider_session.dart';
import '../utils/theme.dart';
import '../utils/responsive.dart';
import '../screens/chat_screen.dart';
import '../services/supabase_service.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToOrders;
  
  const DashboardScreen({
    super.key,
    this.onNavigateToOrders,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _riderId;
  Future<Map<String, int>>? _orderCounts;

  @override
  void initState() {
    super.initState();
    _initRider();
  }

  Future<void> _initRider() async {
    final id = await RiderSession.getId();
    if (mounted) {
      setState(() {
        _riderId = id;
        if (id != null) {
          _orderCounts = _fetchOrderCounts(id);
        }
      });
    }
  }
  
  Future<Map<String, int>> _fetchOrderCounts(String riderId) async {
    try {
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }

      final supabase = SupabaseService.client;
      // Fetch basic fields including timestamps so we can filter by current week in Dart
      final response = await supabase
          .from('delivery_orders')
          .select('status, assigned_at, created_at')
          .eq('rider_id', riderId);
      
      int pending = 0, delivered = 0, failed = 0;
      // Calculate current week (Monday 00:00 to next Monday 00:00)
      final nowDt = DateTime.now();
      final weekStart = nowDt.subtract(Duration(days: (nowDt.weekday - DateTime.monday) % 7));
      final weekStartMidnight = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final weekEndMidnight = weekStartMidnight.add(const Duration(days: 7));
      final weekStartMs = weekStartMidnight.millisecondsSinceEpoch;
      final weekEndMs = weekEndMidnight.millisecondsSinceEpoch;
      
      if (response != null) {
        for (final order in response) {
          final status = (order['status'] ?? '').toString().toLowerCase();
          final ts = (order['assigned_at'] ?? order['created_at'] ?? 0) as int? ?? 0;
          if (ts < weekStartMs || ts >= weekEndMs) {
            continue; // skip orders outside the current week
          }
          if (status == 'pending' ||
              status == 'to_receive' ||
              status == 'assigned' ||
              status == 'out_for_delivery') {
            pending++;
          } else if (status == 'delivered' || status == 'completed') {
            delivered++;
          } else if (status == 'failed' || status == 'cancelled') {
            failed++;
          }
        }
      }
      
      return {'pending': pending, 'delivered': delivered, 'failed': failed};
    } catch (e) {
      debugPrint('Error fetching order counts: $e');
      return {'pending': 0, 'delivered': 0, 'failed': 0};
    }
  }
  
  void _refreshCounts() {
    if (_riderId != null) {
      setState(() {
        _orderCounts = _fetchOrderCounts(_riderId!);
      });
    }
  }

  Widget _buildHeroSection(BuildContext context) {
    const String _homeHeroBackground = 'assets/images/mewkmewk.jpg';
    
    return SizedBox(
      height: Responsive.getHeroHeight(context, mobile: AppTheme.heroBannerHeight),
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.heroBannerBorderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _homeHeroBackground,
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.55),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Padding(
              padding: AppTheme.heroBannerPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Welcome to Delivery Dashboard',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                          height: 1.4,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: const Text(
                      '#DeliveryHero',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
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

  Widget _buildQuickStatsRow(int pending, int delivered, int failed) {
    final stats = [
      _HomeStat(
        label: 'Pending',
        value: pending.toString(),
        icon: Icons.local_shipping,
        color: Colors.orange,
      ),
      _HomeStat(
        label: 'Delivered',
        value: delivered.toString(),
        icon: Icons.check_circle,
        color: Colors.green,
      ),
      _HomeStat(
        label: 'Failed',
        value: failed.toString(),
        icon: Icons.cancel,
        color: Colors.red,
      ),
    ];

    // Single "table-style" row: one card with three columns, side-by-side
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _buildStatCell(stats[0])),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCell(stats[1])),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCell(stats[2])),
        ],
      ),
    );
  }

  Widget _buildStatCell(_HomeStat stat) {
    final statColor = stat.color ?? AppTheme.primaryColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: statColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(stat.icon, color: statColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stat.label,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          stat.value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: statColor,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final cardIconColor = iconColor ?? AppTheme.primaryColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
            border: Border.all(color: Colors.grey.shade100),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.getSpacing(context, mobile: 18),
            vertical: Responsive.getSpacing(context, mobile: 18),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardIconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: cardIconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riderId = _riderId;
    if (riderId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('AgriCart'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            tooltip: 'Open Chats',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RiderChatScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshCounts();
        },
        child: FutureBuilder<Map<String, int>>(
          future: _orderCounts,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final counts = snapshot.data ?? {'pending': 0, 'delivered': 0, 'failed': 0};
            final pending = counts['pending'] ?? 0;
            final delivered = counts['delivered'] ?? 0;
            final failed = counts['failed'] ?? 0;
            // Compute current week label for indicator
            final nowDt = DateTime.now();
            final weekStart = nowDt.subtract(Duration(days: (nowDt.weekday - DateTime.monday) % 7));
            final weekStartMidnight = DateTime(weekStart.year, weekStart.month, weekStart.day);
            final weekEnd = weekStartMidnight.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
            final weekLabel =
                'Counts for this week (${weekStartMidnight.month}/${weekStartMidnight.day} - ${weekEnd.month}/${weekEnd.day})';
            
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(context),
                  const SizedBox(height: 20),
                  _buildQuickStatsRow(pending, delivered, failed),
                  const SizedBox(height: 6),
                  Text(
                    weekLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildQuickActionCard(
                    context: context,
                    title: 'View All Orders',
                    description: 'Check your assigned orders and manage deliveries',
                    icon: Icons.list_alt,
                    iconColor: Colors.blue,
                    onTap: () {
                      if (widget.onNavigateToOrders != null) {
                        widget.onNavigateToOrders!();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Helper class for home stats
class _HomeStat {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  _HomeStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
}

