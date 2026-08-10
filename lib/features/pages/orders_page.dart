import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:manchi_app/features/data/cart_provider.dart';
import 'package:manchi_app/features/pages/payment_review_page.dart';
import 'package:manchi_app/features/auth/auth_page.dart';
import 'package:manchi_app/features/pages/addresses_page.dart';
import 'package:intl/intl.dart';
import 'package:manchi_app/features/domain/models.dart';
import 'package:manchi_app/features/components/food_detail_modal.dart';
import 'package:manchi_app/features/data/food_repository.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/features/services/checkout_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

String _cartSelectionsSummary(List<CartSelection> selections) {
  if (selections.isEmpty) return '';
  final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
  final grouped = <String, List<String>>{};
  for (final sel in selections) {
    final group = sel.groupName ?? 'Extras';
    var label = sel.quantity > 1 ? '${sel.name} x${sel.quantity}' : sel.name;
    if (sel.priceDelta > 0) {
      label += ' (+${currencyFormat.format(sel.priceDelta)})';
    } else if (sel.priceDelta < 0) {
      label += ' (-${currencyFormat.format(sel.priceDelta.abs())})';
    }
    grouped.putIfAbsent(group, () => []).add(label);
  }
  return grouped.entries
      .map((e) => '${e.key}: ${e.value.join(', ')}')
      .join(' · ');
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool _isPlacingOrder = false;
  /// 'delivery' or 'pickup'
  String _deliveryMethod = 'delivery';
  double _deliveryFee = 0.0;
  CartProvider? _cartRef;
  String? _lastDeliveryLga;

  final List<StoreLocation> _branches = supportedStores;

  String? _selectedBranchName;
  final TextEditingController _orderNoteController = TextEditingController();
  final FoodRepository _foodRepository = FoodRepository();
  final CheckoutService _checkoutService = const CheckoutService();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cart = Provider.of<CartProvider>(context, listen: false);
      _cartRef = cart;
      _lastDeliveryLga = cart.deliveryLga;
      final initialStore = cart.selectedStore ?? (_branches.isNotEmpty ? _branches.first : null);
      if (initialStore != null) {
        _selectedBranchName = initialStore.name;
      }
      cart.addListener(_onCartChanged);
      _recalculateDeliveryFee(cart);
    });
  }

  void _onCartChanged() {
    if (!mounted) return;
    if (_deliveryMethod != 'delivery') return;
    final cart = _cartRef;
    if (cart == null) return;

    final currentLga = cart.deliveryLga;
    if (currentLga == _lastDeliveryLga) return;
    _lastDeliveryLga = currentLga;
    _recalculateDeliveryFee(cart);
  }

  @override
  void dispose() {
    _cartRef?.removeListener(_onCartChanged);
    _orderNoteController.dispose();
    super.dispose();
  }

  Future<void> _recalculateDeliveryFee(CartProvider cart) async {
    if (_deliveryMethod == 'pickup' ||
        cart.deliveryAddress.isEmpty) {
      if (!mounted) return;
      setState(() => _deliveryFee = 0.0);
      return;
    }

    try {
      final transport =
          await BackendService.getTransportPriceForLga(cart.deliveryLga);
      if (!mounted) return;

      if (transport == null) {
        setState(() => _deliveryFee = 0.0);
        return;
      }

      setState(() => _deliveryFee = transport.toDouble());
    } catch (_) {
      if (!mounted) return;
      setState(() => _deliveryFee = 0.0);
    }
  }

  Future<void> _handleCheckout(CartProvider cart) async {
    if (_selectedBranchName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a restaurant location'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    if (_deliveryMethod == 'delivery' && cart.deliveryAddress.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a delivery address'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() => _isPlacingOrder = true);
    
    // Check authentication via BackendService
    final user = await BackendService.getCurrentUser();
    final userId = user?['id'];
    final userEmail = user?['email'];
    
    if (userId == null) {
      if (mounted) setState(() => _isPlacingOrder = false);
      if (!mounted) return;
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const AuthPage()),
      );
      if (result == true) {
        if (mounted) _handleCheckout(cart);
      }
      return;
    }

    try {
      // Check if profile exists (Name/Phone)
      final profile = await BackendService.getProfile(userId);
      
      if (profile == null || profile['full_name'] == null || profile['phone_number'] == null) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please add your name and phone number in Profile before checkout'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
         setState(() => _isPlacingOrder = false);
         return;
      }

      final branchCode = _selectedBranchCode;
      if (branchCode == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a restaurant location'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final store = cart.selectedStore;
      if (store == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a restaurant location'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Refresh delivery fee from live API before totals.
      if (_deliveryMethod == 'delivery' && cart.deliveryLga.isNotEmpty) {
        final transport =
            await BackendService.getTransportPriceForLga(cart.deliveryLga);
        if (mounted) {
          setState(() => _deliveryFee = transport?.toDouble() ?? 0.0);
        }
      }

      late final CheckoutTotals totals;
      try {
        totals = await _checkoutService.refreshCartAndTotals(
          cart: cart,
          repository: _foodRepository,
          storeCode: store.code,
          stateName: store.state,
          deliveryMethod: _deliveryMethod,
          deliveryFee: _deliveryFee,
        );
      } on CheckoutValidationException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final grandTotal = totals.grandTotal;
      final vat = totals.vat;

      if (!mounted) return;

      final String safeEmail = userEmail ?? 'customer_$userId@tryspce.com';

      final orderId = await _createOrderInBackend(
        cart,
        grandTotal,
        vat,
        _deliveryMethod,
      );
      if (orderId == null || !mounted) return;

      final paymentSuccess = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentReviewPage(
            email: safeEmail,
            amount: grandTotal,
            location: branchCode,
            orderId: orderId,
          ),
        ),
      );

      if (paymentSuccess == true && mounted) {
        cart.clearCart();
        _orderNoteController.clear();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Column(
              children: [
                Icon(LucideIcons.circleCheckBig, color: Colors.green, size: 60),
                SizedBox(height: 16),
                Text('Order Placed!'),
              ],
            ),
            content: const Text(
              'Your order has been successfully placed. You can track it in your Order History.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Back to Home'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (e is CheckoutValidationException) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (BackendService.isSessionExpiredError(e)) {
        await _promptReauth();
        return;
      }
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'Checkout failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  String? get _selectedBranchCode {
    if (_selectedBranchName == null) return null;
    for (final branch in _branches) {
      if (branch.name == _selectedBranchName) return branch.code;
    }
    return null;
  }

  Future<String?> _createOrderInBackend(
    CartProvider cart,
    double grandTotal,
    double vat,
    String deliveryMethod,
  ) async {
    try {
      final items = cart.items.map((item) {
        final food = item.food as Food;
        return {
          'food_id': food.id,
          'quantity': item.quantity,
          'price_at_time': item.lineUnitPrice,
          'selections': item.selections.map((s) => s.toOrderPayload()).toList(),
        };
      }).toList();

      final branchCode = _selectedBranchCode;
      if (branchCode == null) return null;

      final deliveryAddress = deliveryMethod == 'pickup'
          ? 'Pickup at $_selectedBranchName'
          : cart.deliveryAddress;

      final response = await BackendService.createOrder(
        totalAmount: grandTotal,
        vat: vat,
        deliveryAddress: deliveryAddress,
        location: branchCode,
        deliveryLga: deliveryMethod == 'delivery' ? cart.deliveryLga : null,
        items: items,
        deliveryMethod: deliveryMethod,
        orderNote: _orderNoteController.text,
      );

      final orderId = BackendService.orderIdFromResponse(response);
      if (orderId == null) {
        throw Exception('Order was created but no order ID was returned.');
      }
      return orderId.toString();
    } catch (e) {
      if (BackendService.isSessionExpiredError(e)) {
        await _promptReauth();
        return null;
      }
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(
          context,
          e,
          contextMessage: 'We couldn\'t place your order. Please try again.',
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        actions: [
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.trash2),
              onPressed: () => cart.clearCart(),
            ),
        ],
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shoppingCart, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Your cart is empty', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delivery / Pickup segment (tab modal style)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: _deliveryMethod == 'delivery'
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                setState(() => _deliveryMethod = 'delivery');
                                _recalculateDeliveryFee(cart);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Center(
                                  child: Text(
                                    'Delivery',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: _deliveryMethod == 'delivery'
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Material(
                            color: _deliveryMethod == 'pickup'
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                setState(() {
                                  _deliveryMethod = 'pickup';
                                  _deliveryFee = 0.0;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Center(
                                  child: Text(
                                    'Pickup',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: _deliveryMethod == 'pickup'
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Cart items
                  Text(
                    'Order summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cart.items.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      final imageUrl = item.food.imageUrl;
                      return Dismissible(
                        key: ValueKey('${item.food.id}_${index}_${item.hashCode}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => cart.removeFromCart(index),
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(LucideIcons.trash2, color: Colors.white),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[200],
                              image: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? DecorationImage(
                                      image: NetworkImage(imageUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: (imageUrl == null || imageUrl.isEmpty)
                                ? const Icon(LucideIcons.utensilsCrossed, color: Colors.grey)
                                : null,
                          ),
                          title: Text(item.food.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.selections.isNotEmpty)
                                Text(
                                  _cartSelectionsSummary(item.selections),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                              Text(
                                currencyFormat.format(item.totalPrice),
                                style: TextStyle(
                                  color: isDark
                                      ? theme.colorScheme.onSurface
                                      : theme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.food is Food)
                                IconButton(
                                  icon: const Icon(LucideIcons.pencil, size: 18),
                                  tooltip: 'Edit',
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => FoodDetailModal(
                                        food: item.food as Food,
                                        initialSelections: item.selections,
                                        cartIndex: index,
                                      ),
                                    );
                                  },
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'x${item.quantity}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Branch
                  if (_branches.isNotEmpty) ...[
                    Text(
                      _deliveryMethod == 'pickup' ? 'Pick up from' : 'Delivering from',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedBranchName),
                      initialValue: _selectedBranchName,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        labelText: 'Select restaurant location',
                        filled: true,
                        fillColor: Theme.of(context).scaffoldBackgroundColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                      items: _branches.map((branch) {
                        return DropdownMenuItem<String>(
                          value: branch.name,
                          child: Text(branch.address, overflow: TextOverflow.ellipsis, maxLines: 2, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final branch = _branches.firstWhere(
                          (b) => b.name == value,
                          orElse: () => _branches.first,
                        );
                        setState(() {
                          _selectedBranchName = value;
                        });
                        cart.setSelectedStore(branch);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Delivery address (only for delivery)
                  if (_deliveryMethod == 'delivery') ...[
                    const Text(
                      'Delivering to',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (cart.savedAddresses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text('No saved addresses found', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AddressesPage(popAfterSave: true)),
                                );
                              },
                              icon: const Icon(LucideIcons.mapPinned),
                              label: const Text('Add Address'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: cart.savedAddresses.any((a) => a.fullAddress == cart.deliveryAddress)
                                ? cart.deliveryAddress
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              labelText: 'Select Delivery Address',
                              filled: true,
                              fillColor: Theme.of(context).scaffoldBackgroundColor,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                              ),
                            ),
                            items: cart.savedAddresses.map((addr) {
                              return DropdownMenuItem(
                                value: addr.fullAddress,
                                child: Text('${addr.area}, ${addr.street}', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              final matches = cart.savedAddresses
                                  .where((a) => a.fullAddress == val)
                                  .toList();
                              if (matches.isNotEmpty) {
                                cart.setDeliveryAddressModel(matches.first);
                              } else {
                                // Fallback: preserve old behavior if something unexpected happens.
                                cart.setDeliveryAddress(val);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AddressesPage(popAfterSave: true)),
                                );
                              },
                              icon: const Icon(LucideIcons.mapPinPlusInside, size: 16),
                              label: const Text('Manage Addresses'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                  ],

                  // Pickup note
                  if (_deliveryMethod == 'pickup') ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.store, color: Theme.of(context).colorScheme.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You will pick up your order at $_selectedBranchName',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  const Text(
                    'Order note',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _orderNoteController,
                    maxLength: 500,
                    maxLines: 3,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Special instructions, allergies, etc. (optional)',
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Cost summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal', style: TextStyle(fontSize: 16)),
                            Text(
                              currencyFormat.format(cart.totalAmount),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('VAT (7.5%)', style: TextStyle(fontSize: 16)),
                            Text(
                              currencyFormat.format(cart.totalAmount * 0.075),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Delivery fee row (only for delivery)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Delivery fee', style: TextStyle(fontSize: 16)),
                            Text(
                              _deliveryMethod == 'delivery'
                                  ? currencyFormat.format(_deliveryFee)
                                  : currencyFormat.format(0),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            Text(
                              currencyFormat.format(
                                cart.totalAmount * 1.075 +
                                    (_deliveryMethod == 'delivery' ? _deliveryFee : 0),
                              ),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? theme.colorScheme.onSurface
                                    : theme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isPlacingOrder ? null : () => _handleCheckout(cart),
                      child: _isPlacingOrder
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text('Place order'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
