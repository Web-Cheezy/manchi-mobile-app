import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:manchi_app/features/auth/auth_page.dart';
import 'package:manchi_app/features/data/food_repository.dart';
import 'package:manchi_app/features/domain/models.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';
import 'package:intl/intl.dart';

final class _OrderMenuImageFallback {
  _OrderMenuImageFallback._();
  static final _OrderMenuImageFallback instance = _OrderMenuImageFallback._();

  bool _loaded = false;
  final Map<dynamic, String> _imageByFoodId = {};
  final Map<dynamic, String> _imageBySideId = {};

  Future<void> _ensureLoaded(String? storeCode, String? stateName) async {
    if (_loaded) return;
    try {
      final menu = await FoodRepository().getMenu(
        storeCode: storeCode,
        stateName: stateName,
      );
      if (menu != null) {
        for (final f in menu.foods) {
          final img = f.imageUrl;
          if (img != null && img.isNotEmpty) {
            _imageByFoodId[f.id] = img;
          }
          for (final g in f.optionGroups) {
            for (final s in g.sides) {
              final img = s.imageUrl;
              if (img != null && img.isNotEmpty) {
                _imageBySideId[s.id] = img;
              }
            }
          }
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  static Future<void> prime({String? storeCode, String? stateName}) {
    return instance._ensureLoaded(storeCode, stateName);
  }

  static String? imageForFoodId(dynamic foodId) {
    if (foodId == null) return null;
    return instance._imageByFoodId[foodId];
  }

  static String? imageForSideId(dynamic sideId) {
    if (sideId == null) return null;
    return instance._imageBySideId[sideId];
  }
}

List<dynamic> _parseOrderList(dynamic raw) {
  if (raw is List) return raw;
  if (raw is String && raw.isNotEmpty) {
    try {
      return _parseOrderList(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }
  if (raw is Map) {
    final nested = raw['items'] ?? raw['order_items'] ?? raw['data'] ?? raw['results'];
    if (nested != null) return _parseOrderList(nested);
  }
  return [];
}

List<Map<String, dynamic>> _parseOrderLineOptions(dynamic raw) {
  if (raw == null) return [];
  if (raw is Map) {
    final selections = raw['selections'];
    if (selections is List) {
      return selections
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw['food_name'] != null || raw['food_id'] != null) {
      return [Map<String, dynamic>.from(raw)];
    }
  }
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return [];
}

Map<String, dynamic> _asStringKeyMap(dynamic raw) {
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

String? _firstNonEmptyString(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

Map<String, dynamic> _normalizeOrderItem(dynamic raw) {
  final item = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final optionsRaw = item['options'];
  final snapshot = _asStringKeyMap(optionsRaw);
  final nestedFood = _asStringKeyMap(item['food']);
  final nestedSide = _asStringKeyMap(item['side']);
  final snapshotFood = _asStringKeyMap(snapshot['food']);
  final snapshotSide = _asStringKeyMap(snapshot['side']);
  final parsedOptions = _parseOrderLineOptions(optionsRaw);
  final foodName = _firstNonEmptyString([
    item['food_name'],
    snapshot['food_name'],
    nestedFood['name'],
    nestedSide['name'],
    snapshotFood['name'],
    snapshotSide['name'],
    item['name'],
    item['title'],
  ]);
  final itemTotal = item['item_total'] ??
      snapshot['item_total'] ??
      item['price_at_time'] ??
      item['price'];
  final displayPrice =
      snapshot['display_price'] ?? item['display_price'] ?? snapshot['base_price'];
  final priceAdjustment =
      snapshot['price_adjustment'] ?? item['price_adjustment'] ?? 0;
  final basePrice =
      snapshot['base_price'] ?? item['base_price'] ?? item['price_at_time'];
  final imageUrl = _firstNonEmptyString([
    item['image_url'],
    item['imageUrl'],
    nestedFood['image_url'],
    nestedFood['imageUrl'],
    nestedSide['image_url'],
    nestedSide['imageUrl'],
    snapshot['image_url'],
    snapshot['imageUrl'],
    snapshotFood['image_url'],
    snapshotFood['imageUrl'],
    snapshotSide['image_url'],
    snapshotSide['imageUrl'],
    _OrderMenuImageFallback.imageForFoodId(item['food_id'] ?? nestedFood['id']),
    _OrderMenuImageFallback.imageForSideId(item['side_id'] ?? nestedSide['id']),
  ]);

  return {
    'food_id': item['food_id'] ?? nestedFood['id'] ?? item['id'],
    'side_id': item['side_id'] ?? nestedSide['id'],
    'food_name': foodName ?? 'Item',
    'name': foodName ?? item['name']?.toString() ?? 'Item',
    'quantity': item['quantity'] ?? item['qty'] ?? 1,
    'base_price': basePrice ?? 0,
    'display_price': displayPrice,
    'price_adjustment': priceAdjustment,
    'price_at_time': itemTotal ?? basePrice ?? 0,
    'item_total': itemTotal,
    'image_url': imageUrl,
    'options': parsedOptions,
    'selections': parsedOptions,
  };
}

List<Map<String, dynamic>> _orderItemsFromOrder(Map order) {
  final normalizedOrder = Map<String, dynamic>.from(order);
  final orderItems = normalizedOrder['order_items'];
  if (orderItems is List && orderItems.isNotEmpty) {
    return orderItems
        .whereType<Map>()
        .map((e) => _normalizeOrderItem(Map<String, dynamic>.from(e)))
        .toList();
  }
  return _parseOrderList(
    normalizedOrder['items'] ?? normalizedOrder['order_items'],
  ).map(_normalizeOrderItem).toList();
}

String _formatSelectionsSummary(List<Map<String, dynamic>> options) {
  if (options.isEmpty) return '';
  final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
  final grouped = <String, List<String>>{};
  for (final opt in options) {
    final group =
        opt['group']?.toString() ?? opt['group_name']?.toString() ?? 'Extras';
    final name = opt['name']?.toString() ?? 'Item';
    final qty = opt['quantity'] ?? opt['qty'] ?? 1;
    final qtyNum = qty is num ? qty.toInt() : int.tryParse('$qty') ?? 1;
    var label = qtyNum > 1 ? '$name x$qtyNum' : name;
    final deltaRaw = opt['price_delta'] ?? opt['priceDelta'];
    if (deltaRaw is num && deltaRaw != 0) {
      final delta = deltaRaw.toDouble();
      if (delta > 0) {
        label += ' (+${currencyFormat.format(delta)})';
      } else {
        label += ' (-${currencyFormat.format(delta.abs())})';
      }
    }
    grouped.putIfAbsent(group, () => []).add(label);
  }
  return grouped.entries
      .map((e) => '${e.key}: ${e.value.join(', ')}')
      .join(' · ');
}

int _orderStatusIndex(String? status) {
  const flow = [
    'pending',
    'confirmed',
    'preparing',
    'delivering',
    'delivered',
  ];
  final normalized = status?.toLowerCase().trim() ?? '';
  if (normalized == 'delivery') return flow.indexOf('delivering');
  if (normalized == 'processing' || normalized == 'paid') {
    return flow.indexOf('pending');
  }
  final idx = flow.indexOf(normalized);
  return idx >= 0 ? idx : 0;
}

String _displayStoreAddress(String? code) {
  final store = findStoreByCode(code);
  return store?.address ?? code ?? 'Unknown Location';
}

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);
  List<dynamic> _orders = [];
  bool _isLoading = true;
  bool _isSignedIn = false;

  Future<void> _promptReauth() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your session expired. Please sign in again.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    final user = await BackendService.getCurrentUser();
    if (user == null || user['id'] == null) {
      if (mounted) {
        setState(() {
          _orders = [];
          _isLoading = false;
          _isSignedIn = false;
        });
      }
      return;
    }
    try {
      final orders = await BackendService.getOrders();
      String? location;
      String? stateName;
      for (final o in orders) {
        if (o is Map) {
          final loc = o['location']?.toString();
          final st = o['state']?.toString() ?? o['delivery_lga']?.toString();
          if (loc != null && loc.isNotEmpty && location == null) location = loc;
          if (st != null && st.isNotEmpty && stateName == null) stateName = st;
        }
      }
      try {
        await _OrderMenuImageFallback.prime(storeCode: location, stateName: stateName);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
          _isSignedIn = true;
        });
      }
    } catch (e) {
      if (BackendService.isSessionExpiredError(e)) {
        await _promptReauth();
      }
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t load your orders. Pull down to try again.');
        setState(() {
          _orders = [];
          _isLoading = false;
          _isSignedIn = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_orders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: RefreshIndicator(
          onRefresh: _fetchOrders,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isSignedIn ? 'No orders yet' : 'Sign in to see your orders',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignedIn
                          ? 'Orders you place will appear here.\nPull down to refresh.'
                          : 'Open the menu and sign in to view order history.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    // Sort orders by date (newest first)
    final sortedOrders = List.from(_orders);
    sortedOrders.sort((a, b) {
      final aStr = a['created_at']?.toString() ?? '';
      final bStr = b['created_at']?.toString() ?? '';
      final dateA = DateTime.tryParse(aStr) ?? DateTime(0);
      final dateB = DateTime.tryParse(bStr) ?? DateTime(0);
      return dateB.compareTo(dateA);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: RefreshIndicator(
        onRefresh: _fetchOrders,
        child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: sortedOrders.length,
        itemBuilder: (context, index) {
          final order = sortedOrders[index];
          // Calculate order number based on total count and current index
          // Oldest order is #1, Newest is #Total
          final orderNumber = sortedOrders.length - index;
          
          final status = order['status'] ?? 'pending';
          final total = (order['total_amount'] ?? 0) as num;
          final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now();
          final deliveryAddress = order['delivery_address'] ?? 'Not specified';
          final items = _orderItemsFromOrder(order as Map);

          Color statusColor;
          switch (status.toString().toLowerCase()) {
            case 'confirmed':
              statusColor = Colors.blue;
              break;
            case 'preparing':
              statusColor = Colors.amber;
              break;
            case 'delivery':
            case 'delivering':
              statusColor = Colors.purple;
              break;
            case 'delivered':
              statusColor = Colors.green;
              break;
            case 'pending':
            case 'processing':
            case 'paid':
              statusColor = Colors.orange;
              break;
            case 'cancelled':
              statusColor = Colors.red;
              break;
            default:
              statusColor = Colors.grey;
          }

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _showOrderDetails(context, order, orderNumber);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #$orderNumber',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMMM d, y HH:mm')
                                  .format(createdAt.toLocal()),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        Chip(
                          label: Text(
                            status.toString().toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                          backgroundColor: statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Delivery',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deliveryAddress,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    if (items.isNotEmpty)
                      SizedBox(
                        height: 56,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          itemBuilder: (context, itemIndex) {
                            final item = items[itemIndex];
                            final imageUrl = item['image_url'] as String?;
                            final quantity = item['quantity'] ?? 1;

                            return Container(
                              width: 56,
                              height: 56,
                              margin: EdgeInsets.only(
                                right: itemIndex == items.length - 1 ? 0 : 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey[200],
                                image: imageUrl != null && imageUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(
                                          imageUrl,
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: imageUrl == null
                                  ? const Icon(Icons.fastfood,
                                      color: Colors.grey)
                                  : Align(
                                      alignment: Alignment.bottomRight,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'x$quantity',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          currencyFormat.format(total),
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white 
                                : Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Map order, int orderNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          order: Map<String, dynamic>.from(order),
          orderNumber: orderNumber,
        ),
      ),
    );
  }
}

class OrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> order;
  final int orderNumber;

  const OrderDetailPage({super.key, required this.order, required this.orderNumber});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late Map<String, dynamic> _order;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    () async {
      try {
        await _OrderMenuImageFallback.prime(
          storeCode: _order['location']?.toString(),
          stateName: _order['state']?.toString() ?? _order['delivery_lga']?.toString(),
        );
        if (mounted) setState(() {});
      } catch (_) {}
    }();
    _refreshOrder();
  }

  Future<void> _refreshOrder() async {
    final id = _order['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final fresh = await BackendService.getOrderById(id);
      if (mounted) {
        setState(() {
          _order = fresh;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(symbol: '₦', decimalDigits: 2);
    final items = _orderItemsFromOrder(_order);
    final createdAt = DateTime.tryParse(_order['created_at']?.toString() ?? '') ??
        DateTime.now();
    final total = _order['total_amount'] ?? 0;
    final locationValue = _order['location']?.toString();
    final displayLocation = _displayStoreAddress(locationValue);
    final status = _order['status']?.toString() ?? 'pending';
    final deliveryAddress = _order['delivery_address'] ?? 'Not specified';

    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${widget.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshOrder,
          ),
        ],
      ),
      body: _isLoading && items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshOrder,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OrderStatusTimeline(status: status),
                    const SizedBox(height: 16),
                    Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMMM d, y HH:mm')
                            .format(createdAt.toLocal()),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        currencyFormat.format(total),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white 
                              : Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Delivering from',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayLocation,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey.withValues(alpha: 0.3),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Delivering to',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              deliveryAddress,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
                    const SizedBox(height: 24),
                    const Text(
                      'Items',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const Text('No items information available')
                    else
                      ...items.map((item) {
                        final name = item['name']?.toString() ?? 'Item';
                        final quantity = item['quantity'] ?? 1;
                        final price = item['item_total'] ??
                            item['price_at_time'] ??
                            0;
                        final priceAdjustment = item['price_adjustment'];
                        final displayPrice = item['display_price'];
                        final imageUrl = item['image_url'] as String?;
                        final options = (item['options'] as List?)
                                ?.whereType<Map<String, dynamic>>()
                                .toList() ??
                            <Map<String, dynamic>>[];
                        final selectionSummary = _formatSelectionsSummary(options);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Colors.grey[200],
                                  image: (imageUrl != null &&
                                          imageUrl.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage(imageUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: (imageUrl == null || imageUrl.isEmpty)
                                    ? const Icon(
                                        Icons.fastfood,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (selectionSummary.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        selectionSummary,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                    if (priceAdjustment is num &&
                                        priceAdjustment > 0 &&
                                        displayPrice is num) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Meal ${NumberFormat.currency(symbol: '₦', decimalDigits: 0).format(displayPrice)} + ${NumberFormat.currency(symbol: '₦', decimalDigits: 0).format(priceAdjustment)} extras',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      'Qty: $quantity',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                currencyFormat.format(price),
                                style: TextStyle(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OrderStatusTimeline extends StatelessWidget {
  final String status;

  const _OrderStatusTimeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    if (normalized == 'cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Order cancelled',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
      );
    }

    final currentIndex = _orderStatusIndex(status);
    const labels = [
      'Pending',
      'Confirmed',
      'Preparing',
      'Delivering',
      'Delivered',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isComplete = index <= currentIndex;
          final isActive = index == currentIndex;
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isComplete
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
                        : null,
                  ),
                  child: isComplete
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isComplete
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
