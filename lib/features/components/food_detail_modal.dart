import 'package:flutter/material.dart';
import 'package:manchi_app/features/domain/models.dart';
import 'package:manchi_app/features/data/food_repository.dart';
import 'package:manchi_app/features/data/cart_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

Side? _findSide(List<Side> sides, int id) {
  for (final side in sides) {
    if (side.id == id) return side;
  }
  return null;
}

class FoodDetailModal extends StatefulWidget {
  final Food food;
  final List<CartSelection>? initialSelections;
  final int? cartIndex;

  const FoodDetailModal({
    super.key,
    required this.food,
    this.initialSelections,
    this.cartIndex,
  });

  @override
  State<FoodDetailModal> createState() => _FoodDetailModalState();
}

class _FoodDetailModalState extends State<FoodDetailModal> {
  final FoodRepository _repository = FoodRepository();
  late Food _food;
  bool _isLoading = true;
  int _quantity = 1;

  /// groupId -> sideId -> quantity (multi-select groups)
  final Map<int, Map<int, int>> _multiSelections = {};

  /// groupId -> sideId (single-select groups)
  final Map<int, int?> _singleSelections = {};

  List<OptionGroup> get _sortedGroups => _food.sortedOptionGroups;

  @override
  void initState() {
    super.initState();
    _food = widget.food;
    if (widget.initialSelections != null) {
      _applyInitialSelections(widget.initialSelections);
    } else if (_food.optionGroups.isNotEmpty) {
      _applyPricingDefaults();
      _isLoading = false;
    }
    _loadFoodDetails();
  }

  void _applyInitialSelections(List<CartSelection>? selections) {
    if (selections == null || selections.isEmpty) return;
    for (final sel in selections) {
      if (sel.groupId == null) continue;
      final group = _food.optionGroups
          .where((g) => g.id == sel.groupId)
          .cast<OptionGroup?>()
          .firstWhere((g) => g != null, orElse: () => null);
      if (group == null) continue;
      if (group.maxSelections == 1) {
        _singleSelections[group.id] = sel.itemId;
      } else {
        _multiSelections.putIfAbsent(group.id, () => {});
        _multiSelections[group.id]![sel.itemId] = sel.quantity;
      }
    }
  }

  Future<void> _loadFoodDetails() async {
    try {
      final store = context.read<CartProvider>().selectedStore;
      final freshFood = await _repository.getFoodDetail(
        widget.food.id,
        storeCode: store?.code,
        stateName: store?.state,
      );

      if (mounted) {
        setState(() {
          if (freshFood.optionGroups.isNotEmpty) {
            _food = freshFood;
          }
          if (widget.initialSelections != null) {
            _applyInitialSelections(widget.initialSelections);
          } else if (_food.optionGroups.isNotEmpty) {
            _applyPricingDefaults();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_food.optionGroups.isEmpty) {
            _food = widget.food;
            if (widget.initialSelections == null && _food.optionGroups.isNotEmpty) {
              _applyPricingDefaults();
            }
          }
          _isLoading = false;
        });
      }
    }
  }

  void _applyPricingDefaults() {
    for (final group in _sortedGroups) {
      Side? defaultSide;
      final defaultId = group.pricingDefaultSideId;
      if (defaultId != null) {
        defaultSide = _findSide(group.sides, defaultId);
      }
      if (defaultSide == null) {
        for (final side in group.sides) {
          if (side.isPricingDefault) {
            defaultSide = side;
            break;
          }
        }
      }
      if (defaultSide == null || !defaultSide.canOrder) continue;
      if (group.maxSelections == 1) {
        _singleSelections[group.id] = defaultSide.id;
      } else {
        _multiSelections.putIfAbsent(group.id, () => {})[defaultSide.id] = 1;
      }
    }
  }

  int _selectionCountForGroup(OptionGroup group) {
    if (group.maxSelections == 1) {
      return _singleSelections[group.id] != null ? 1 : 0;
    }
    final map = _multiSelections[group.id];
    if (map == null) return 0;
    return map.values.fold<int>(0, (sum, qty) => sum + qty);
  }

  bool _isGroupSatisfied(OptionGroup group) {
    final count = _selectionCountForGroup(group);
    return count >= group.effectiveMin && count <= group.maxSelections;
  }

  String? get _blockedAddMessage {
    for (final group in _sortedGroups) {
      if (_isGroupSatisfied(group)) continue;
      final count = _selectionCountForGroup(group);
      if (count < group.effectiveMin) {
        return 'Choose ${group.name}';
      }
      return 'Too many options for ${group.name}';
    }
    return null;
  }

  bool get _canAddToCart {
    if (!_food.canOrder) return false;
    for (final group in _sortedGroups) {
      if (!_isGroupSatisfied(group)) return false;
    }
    return true;
  }

  double get _unitPrice {
    final selections = _buildSelections();
    return lineTotalFromMenuPrice(_food.menuPrice, selections);
  }

  double get _totalPrice => _unitPrice * _quantity;

  List<CartSelection> _buildSelections() {
    final selections = <CartSelection>[];
    for (final group in _sortedGroups) {
      if (group.maxSelections == 1) {
        final sideId = _singleSelections[group.id];
        if (sideId == null) continue;
        final side = _findSide(group.sides, sideId);
        if (side == null) continue;
        selections.add(CartSelection(
          groupId: group.id,
          itemId: side.id,
          name: side.name,
          priceDelta: side.priceDelta,
          groupName: group.name,
        ));
      } else {
        final map = _multiSelections[group.id] ?? {};
        for (final entry in map.entries) {
          if (entry.value <= 0) continue;
          final side = _findSide(group.sides, entry.key);
          if (side == null) continue;
          selections.add(CartSelection(
            groupId: group.id,
            itemId: side.id,
            name: side.name,
            priceDelta: side.priceDelta,
            quantity: entry.value,
            groupName: group.name,
          ));
        }
      }
    }
    return selections;
  }

  void _selectSingle(OptionGroup group, Side side) {
    if (!side.canOrder) return;
    setState(() => _singleSelections[group.id] = side.id);
  }

  void _toggleMulti(OptionGroup group, Side side) {
    if (!side.canOrder) return;
    setState(() {
      final map = _multiSelections.putIfAbsent(group.id, () => {});
      final current = map[side.id] ?? 0;
      if (current > 0) {
        map.remove(side.id);
      } else if (_selectionCountForGroup(group) < group.maxSelections) {
        map[side.id] = 1;
      }
    });
  }

  void _incrementMulti(OptionGroup group, Side side) {
    if (!side.canOrder) return;
    setState(() {
      final map = _multiSelections.putIfAbsent(group.id, () => {});
      final current = map[side.id] ?? 0;
      if (current == 0 && _selectionCountForGroup(group) >= group.maxSelections) {
        return;
      }
      map[side.id] = current + 1;
    });
  }

  void _decrementMulti(OptionGroup group, Side side) {
    setState(() {
      final map = _multiSelections[group.id];
      if (map == null) return;
      final current = map[side.id] ?? 0;
      if (current <= 1) {
        map.remove(side.id);
      } else {
        map[side.id] = current - 1;
      }
    });
  }

  void _addToCart() {
    final cart = context.read<CartProvider>();
    final selections = _buildSelections();
    if (widget.cartIndex != null) {
      cart.replaceItem(
        widget.cartIndex!,
        _food,
        quantity: _quantity,
        selections: selections,
      );
    } else {
      cart.addItem(_food, quantity: _quantity, selections: selections);
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.cartIndex != null
              ? 'Updated ${_food.name} in cart'
              : 'Added ${_food.name} to cart',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      Text(
                        _food.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_food.description != null &&
                          _food.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _food.description!,
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            currencyFormat.format(_food.menuPrice),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                      if (_food.isOutOfStock) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'This item is out of stock right now.',
                            style: TextStyle(
                              color: Color(0xFFE53935),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_sortedGroups.isEmpty && _food.hasOptions)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Options for this item could not be loaded. Pull to refresh and try again.',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._sortedGroups.map((group) => _buildOptionGroupCard(
                              group,
                              currencyFormat,
                              isDarkMode,
                            )),
                    ],
                  ),
          ),
          _buildBottomBar(currencyFormat, theme),
        ],
      ),
    );
  }

  Widget _buildOptionGroupCard(
    OptionGroup group,
    NumberFormat currencyFormat,
    bool isDarkMode,
  ) {
    final satisfied = _isGroupSatisfied(group);
    final isRequiredGroup = group.isRequired;
    final selectionSuffix =
        group.maxSelections > 1 ? ' · max ${group.maxSelections}' : '';
    final requiredLabel =
        isRequiredGroup ? 'Required$selectionSuffix' : 'Optional$selectionSuffix';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: !satisfied && isRequiredGroup
            ? Border.all(color: Colors.orange.shade300)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isRequiredGroup
                      ? Colors.orange.shade50
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  requiredLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: isRequiredGroup
                        ? Colors.orange.shade800
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...group.sides.map(
            (side) => group.maxSelections == 1
                ? _buildRadioSide(group, side, currencyFormat)
                : _buildMultiSide(group, side, currencyFormat),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioSide(
    OptionGroup group,
    Side side,
    NumberFormat currencyFormat,
  ) {
    final selected = _singleSelections[group.id] == side.id;
    final priceLabel = formatPriceDeltaLabel(side.priceDelta, currencyFormat);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: side.canOrder,
      title: Text(side.name),
      subtitle: priceLabel == null
          ? null
          : Text(
              priceLabel,
              style: TextStyle(
                fontSize: 13,
                color: side.canOrder ? Colors.grey[600] : Colors.grey,
              ),
            ),
      trailing: side.isOutOfStock
          ? const Text('Out of stock', style: TextStyle(color: Colors.red, fontSize: 12))
          : Radio<int>(
              value: side.id,
              groupValue: _singleSelections[group.id],
              onChanged: side.canOrder ? (_) => _selectSingle(group, side) : null,
            ),
      onTap: side.canOrder ? () => _selectSingle(group, side) : null,
      selected: selected,
    );
  }

  Widget _buildMultiSide(
    OptionGroup group,
    Side side,
    NumberFormat currencyFormat,
  ) {
    final qty = _multiSelections[group.id]?[side.id] ?? 0;
    final atMax =
        qty == 0 && _selectionCountForGroup(group) >= group.maxSelections;
    final priceLabel = formatPriceDeltaLabel(side.priceDelta, currencyFormat);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  side.name,
                  style: TextStyle(
                    fontSize: 16,
                    color: side.canOrder ? null : Colors.grey,
                  ),
                ),
                if (priceLabel != null)
                  Text(
                    priceLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: side.canOrder ? Colors.grey[600] : Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
          if (qty > 0)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () => _decrementMulti(group, side),
                  ),
                  Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: side.canOrder ? () => _incrementMulti(group, side) : null,
                  ),
                ],
              ),
            )
          else
            Checkbox(
              value: false,
              onChanged: side.canOrder && !atMax
                  ? (_) => _toggleMulti(group, side)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(NumberFormat currencyFormat, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Quantity',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed:
                          _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text(
                      '$_quantity',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _canAddToCart ? _addToCart : null,
              child: Text(
                !_food.canOrder
                    ? 'Out of stock'
                    : !_canAddToCart
                        ? (_blockedAddMessage ?? 'Complete your selections')
                        : '${widget.cartIndex != null ? 'Update cart' : 'Add to cart'} • ${currencyFormat.format(_totalPrice)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
