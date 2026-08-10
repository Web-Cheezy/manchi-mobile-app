import 'package:intl/intl.dart';

abstract class MenuItem {
  int get id;
  String get name;
  String? get description;
  double get price;
  String? get imageUrl;
  bool get isSide;
  bool get isVisible;
  bool get isOutOfStock;
  bool get canOrder => isVisible && !isOutOfStock;
}

class StoreLocation {
  final String code;
  final String name;
  final String state;
  final String city;
  final String address;

  const StoreLocation({
    required this.code,
    required this.name,
    required this.state,
    required this.city,
    required this.address,
  });
}

const supportedStores = <StoreLocation>[
  StoreLocation(
    code: 'Chasemall',
    name: 'Chasemall, Enugu',
    state: 'Enugu State',
    city: 'Enugu',
    address:
        'Chasemall 33, Abakaliki Road by 38 Bus Stop, GRA, Enugu, Enugu State.',
  ),
  StoreLocation(
    code: 'Eromo',
    name: 'Eromo, Port Harcourt',
    state: 'Rivers State',
    city: 'Port Harcourt',
    address:
        'Opposite Eromo Filling Station, New Road Eneka Atali Road Port Harcourt Rivers State.',
  ),
];

StoreLocation? findStoreByCode(String? code) {
  if (code == null || code.isEmpty) return null;
  for (final store in supportedStores) {
    if (store.code.toLowerCase() == code.toLowerCase()) {
      return store;
    }
  }
  return null;
}

StoreLocation? findStoreByState(String? state) {
  if (state == null || state.isEmpty) return null;
  for (final store in supportedStores) {
    if (store.state.toLowerCase() == state.toLowerCase() ||
        store.state.toLowerCase().contains(state.toLowerCase()) ||
        state.toLowerCase().contains(store.state.toLowerCase().replaceAll(' state', ''))) {
      return store;
    }
  }
  return null;
}

int _parseInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _parseDouble(dynamic value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _parseBool(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

String? _normalizeAvailabilityStatus(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized == 'available' ||
      normalized == 'out_of_stock' ||
      normalized == 'unavailable') {
    return normalized;
  }
  if (normalized == 'outofstock' || normalized == 'sold_out') {
    return 'out_of_stock';
  }
  if (normalized == 'disabled' || normalized == 'hidden') {
    return 'unavailable';
  }
  return null;
}

String? _extractAvailabilityStatus(dynamic raw) {
  final directStatus = _normalizeAvailabilityStatus(raw);
  if (directStatus != null) return directStatus;

  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    final candidates = [
      map['status'],
      map['availability_status'],
      map['availabilityStatus'],
      map['availability'],
    ];
    for (final candidate in candidates) {
      final status = _normalizeAvailabilityStatus(candidate);
      if (status != null) return status;
    }
  }

  if (raw is List) {
    for (final item in raw) {
      final status = _extractAvailabilityStatus(item);
      if (status != null) return status;
    }
  }

  return null;
}

String? _resolveAvailabilityStatus(Map<String, dynamic> json) {
  final topLevelCandidates = [
    json['status'],
    json['availability_status'],
    json['availabilityStatus'],
    json['availability'],
  ];
  for (final candidate in topLevelCandidates) {
    final status = _normalizeAvailabilityStatus(candidate);
    if (status != null) return status;
  }

  final nestedCandidates = [
    json['food_availability'],
    json['foodAvailability'],
    json['side_availability'],
    json['sideAvailability'],
  ];
  for (final candidate in nestedCandidates) {
    final status = _extractAvailabilityStatus(candidate);
    if (status != null) return status;
  }

  return null;
}

bool _parseIsVisible(Map<String, dynamic> json) {
  final status = _resolveAvailabilityStatus(json);
  if (status != null) {
    return status != 'unavailable';
  }
  final raw = json['is_available'] ?? json['isAvailable'] ?? json['available'];
  if (raw != null) {
    return _parseBool(raw, fallback: true);
  }
  final legacyStatus = json['status']?.toString().toLowerCase();
  if (legacyStatus == 'unavailable' || legacyStatus == 'hidden') {
    return false;
  }
  return true;
}

bool _parseIsOutOfStock(Map<String, dynamic> json) {
  final status = _resolveAvailabilityStatus(json);
  if (status != null) {
    return status == 'out_of_stock';
  }
  final stockKeys = [
    json['is_in_stock'],
    json['isInStock'],
    json['in_stock'],
    json['inStock'],
  ];
  for (final value in stockKeys) {
    if (value != null) {
      return !_parseBool(value, fallback: true);
    }
  }
  final stockStatus =
      json['stock_status']?.toString().toLowerCase() ??
      json['stockStatus']?.toString().toLowerCase() ??
      json['availability']?.toString().toLowerCase();
  return stockStatus == 'out_of_stock' ||
      stockStatus == 'sold_out' ||
      stockStatus == 'outofstock';
}

class CartSelection {
  final int? groupId;
  final int itemId;
  final String name;
  final double priceDelta;
  final int quantity;
  final String? groupName;

  const CartSelection({
    this.groupId,
    required this.itemId,
    required this.name,
    this.priceDelta = 0,
    this.quantity = 1,
    this.groupName,
  });

  Map<String, dynamic> toOrderPayload() {
    return {
      if (groupId != null) 'group_id': groupId,
      'item_id': itemId,
      'quantity': quantity,
    };
  }

  CartSelection withLiveSide(Side side, {String? groupName}) {
    return CartSelection(
      groupId: groupId,
      itemId: itemId,
      name: side.name,
      priceDelta: side.priceDelta,
      quantity: quantity,
      groupName: groupName ?? this.groupName,
    );
  }
}

Side? findSideInFood(Food food, int? groupId, int itemId) {
  final groups = food.sortedOptionGroups;
  if (groupId != null) {
    for (final group in groups) {
      if (group.id != groupId) continue;
      for (final side in group.sides) {
        if (side.id == itemId) return side;
      }
      return null;
    }
  }
  for (final group in groups) {
    for (final side in group.sides) {
      if (side.id == itemId) return side;
    }
  }
  return null;
}

String? groupNameForSide(Food food, int? groupId) {
  if (groupId == null) return null;
  for (final group in food.sortedOptionGroups) {
    if (group.id == groupId) return group.name;
  }
  return null;
}

String? formatPriceDeltaLabel(double delta, NumberFormat currencyFormat) {
  if (delta == 0) return 'Included';
  if (delta > 0) return '+${currencyFormat.format(delta)}';
  return '-${currencyFormat.format(delta.abs())}';
}

double lineTotalFromMenuPrice(double menuPrice, List<CartSelection> selections) {
  var total = menuPrice;
  for (final sel in selections) {
    total += sel.priceDelta * sel.quantity;
  }
  return total;
}

int? _parseDefaultSideId(Map<String, dynamic> json) {
  final raw = json['pricing_default_side_id'] ??
      json['default_side_id'] ??
      json['defaultSideId'] ??
      json['pricingDefaultSideId'];
  if (raw == null) return null;
  return _parseInt(raw, 0);
}

List<Side> _parseSidesList(Map<String, dynamic> json) {
  final sidesRaw = json['sides'] ?? json['items'] ?? json['options'];
  if (sidesRaw is! List) return [];
  return sidesRaw
      .whereType<Map>()
      .map((e) => Side.fromJson(Map<String, dynamic>.from(e)))
      .where((s) => s.isVisible)
      .toList();
}

/// Legacy fallback when the API only returns [food_sides] without [option_groups].
List<Side> _finalizeLegacySidesPricing({
  required List<Side> sides,
  required int? defaultSideId,
  required bool isRequired,
  required int minSelections,
  required int maxSelections,
}) {
  if (sides.isEmpty) return sides;

  Side? baseline;
  if (defaultSideId != null) {
    for (final side in sides) {
      if (side.id == defaultSideId) {
        baseline = side;
        break;
      }
    }
  }
  if (baseline == null) {
    for (final side in sides) {
      if (side.isPricingDefault) {
        baseline = side;
        break;
      }
    }
  }

  if (baseline != null) {
    final defaultSide = baseline;
    return sides
        .map(
          (side) => Side(
            id: side.id,
            name: side.name,
            price: side.price,
            priceDelta:
                side.id == defaultSide.id ? 0 : side.price - defaultSide.price,
            isPricingDefault: side.id == defaultSide.id,
            type: side.type,
            imageUrl: side.imageUrl,
            isVisible: side.isVisible,
            isOutOfStock: side.isOutOfStock,
          ),
        )
        .toList();
  }

  final isOptionalAddOn =
      !isRequired && minSelections == 0 && defaultSideId == null;
  if (isOptionalAddOn) {
    return sides
        .map(
          (side) => Side(
            id: side.id,
            name: side.name,
            price: side.price,
            priceDelta: side.price,
            isPricingDefault: false,
            type: side.type,
            imageUrl: side.imageUrl,
            isVisible: side.isVisible,
            isOutOfStock: side.isOutOfStock,
          ),
        )
        .toList();
  }

  if (maxSelections == 1 && sides.length > 1) {
    final cheapest = sides.reduce((a, b) => a.price <= b.price ? a : b);
    return sides
        .map(
          (side) => Side(
            id: side.id,
            name: side.name,
            price: side.price,
            priceDelta:
                side.id == cheapest.id ? 0 : side.price - cheapest.price,
            isPricingDefault: side.id == cheapest.id,
            type: side.type,
            imageUrl: side.imageUrl,
            isVisible: side.isVisible,
            isOutOfStock: side.isOutOfStock,
          ),
        )
        .toList();
  }

  return sides;
}

int _scoreBundledAssignment(
  List<_OptionGroupBuilder> eligible,
  Map<int, int> pick,
) {
  var score = pick.length * 1000;
  for (final group in eligible) {
    if (!pick.containsKey(group.id)) continue;
    if (group.isRequired) score += 10000;
    score -= group.displayOrder;
  }
  return score;
}

void _inferBundledDefaults(
  Map<int, _OptionGroupBuilder> builders,
  double basePrice,
  double menuPrice,
) {
  if (builders.values.any((b) => b.defaultSideId != null)) return;

  final target = (menuPrice - basePrice).round();
  if (target <= 0) return;

  final eligible = builders.values
      .where(
        (b) =>
            b.id > 0 &&
            b.defaultSideId == null &&
            b.maxSelections == 1 &&
            b.sides.isNotEmpty,
      )
      .toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  if (eligible.isEmpty) return;

  Map<int, int>? best;
  var bestScore = -1;

  void search(int index, int sum, Map<int, int> pick) {
    if (sum > target) return;
    if (index == eligible.length) {
      if (sum != target) return;
      final score = _scoreBundledAssignment(eligible, pick);
      if (score > bestScore) {
        bestScore = score;
        best = Map<int, int>.from(pick);
      }
      return;
    }

    final group = eligible[index];
    search(index + 1, sum, pick);

    for (final side in group.sides) {
      pick[group.id] = side.id;
      search(index + 1, sum + side.price.round(), pick);
      pick.remove(group.id);
    }
  }

  search(0, 0, {});

  if (best == null) return;
  for (final entry in best!.entries) {
    builders[entry.key]?.defaultSideId = entry.value;
  }
}

class _OptionGroupBuilder {
  final int id;
  String name;
  int minSelections = 0;
  int maxSelections = 1;
  bool isRequired = false;
  int displayOrder = 0;
  int? defaultSideId;
  final List<Side> sides = [];
  final Set<int> _sideIds = {};

  _OptionGroupBuilder({
    required this.id,
    this.name = 'Options',
  });

  void absorbMeta(Map<String, dynamic> json) {
    final parsedName = json['name']?.toString().trim();
    if (parsedName != null && parsedName.isNotEmpty) {
      name = parsedName;
    }
    if (json.containsKey('min_selections') || json.containsKey('minSelections')) {
      minSelections = _parseInt(json['min_selections'] ?? json['minSelections'], 0);
    }
    if (json.containsKey('max_selections') || json.containsKey('maxSelections')) {
      maxSelections = _parseInt(json['max_selections'] ?? json['maxSelections'], 1);
    }
    if (json.containsKey('is_required') || json.containsKey('isRequired')) {
      isRequired = _parseBool(
        json['is_required'] ?? json['isRequired'],
        fallback: isRequired,
      );
      if (isRequired && minSelections < 1) minSelections = 1;
    }
    if (json.containsKey('display_order') || json.containsKey('displayOrder')) {
      displayOrder = _parseInt(json['display_order'] ?? json['displayOrder'], 0);
    }
    final parsedDefault = _parseDefaultSideId(json);
    if (parsedDefault != null) {
      defaultSideId = parsedDefault;
    }
  }

  void addSide(Side side) {
    if (!_sideIds.add(side.id) || !side.isVisible) return;
    sides.add(side);
  }

  OptionGroup build() {
    return OptionGroup(
      id: id,
      name: name,
      minSelections: minSelections,
      maxSelections: maxSelections,
      isRequired: isRequired,
      displayOrder: displayOrder,
      defaultSideId: defaultSideId,
      sides: _finalizeLegacySidesPricing(
        sides: sides,
        defaultSideId: defaultSideId,
        isRequired: isRequired,
        minSelections: minSelections,
        maxSelections: maxSelections,
      ),
    );
  }
}

List<OptionGroup> _parseLegacyFoodSidesGroups(Map<String, dynamic> json) {
  final builders = <int, _OptionGroupBuilder>{};
  final foodSidesRaw = json['food_sides'] ?? json['foodSides'];
  if (foodSidesRaw is! List) return [];

  for (final raw in foodSidesRaw) {
    if (raw is! Map) continue;
    final entry = Map<String, dynamic>.from(raw);
    final groupMeta = entry['option_group'] ?? entry['group'];
    final sideMap = entry['side'] is Map
        ? Map<String, dynamic>.from(entry['side'] as Map)
        : entry;

    var groupId = 0;
    if (groupMeta is Map) {
      groupId = _parseInt(groupMeta['id'], 0);
    }
    if (groupId == 0) {
      groupId = _parseInt(
        sideMap['option_group_id'] ?? entry['option_group_id'],
        0,
      );
    }
    if (groupId == 0) groupId = -1;

    final builder = builders.putIfAbsent(
      groupId,
      () => _OptionGroupBuilder(
        id: groupId,
        name: groupId == -1 ? 'Extras' : 'Options',
      )..displayOrder = groupId > 0 ? groupId : 999,
    );

    if (groupMeta is Map) {
      builder.absorbMeta(Map<String, dynamic>.from(groupMeta));
    }
    if (_parseBool(entry['is_required'], fallback: false)) {
      builder.isRequired = true;
      if (builder.minSelections < 1) builder.minSelections = 1;
    }
    builder.addSide(Side.fromJson(sideMap));
  }

  _inferBundledDefaults(
    builders,
    _parseDouble(json['base_price'] ?? json['price'], 0),
    _parseDouble(
      json['menu_price'] ?? json['display_price'] ?? json['price'],
      0,
    ),
  );

  final groups = builders.values.map((b) => b.build()).toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  return groups.where((g) => g.sides.isNotEmpty).toList();
}

List<OptionGroup> _parseFoodOptionGroups(Map<String, dynamic> json) {
  final groupsRaw = json['option_groups'] ?? json['optionGroups'];
  if (groupsRaw is List && groupsRaw.isNotEmpty) {
    final groups = groupsRaw
        .whereType<Map>()
        .map(
          (e) => OptionGroup.fromApiJson(Map<String, dynamic>.from(e)),
        )
        .where((g) => g.sides.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return groups;
  }

  return _parseLegacyFoodSidesGroups(json);
}

class OptionGroup {
  final int id;
  final String name;
  final int minSelections;
  final int maxSelections;
  final bool isRequired;
  final int displayOrder;
  final int? defaultSideId;
  final List<Side> sides;

  const OptionGroup({
    required this.id,
    required this.name,
    this.minSelections = 0,
    this.maxSelections = 1,
    this.isRequired = false,
    this.displayOrder = 0,
    this.defaultSideId,
    this.sides = const [],
  });

  bool get isRequiredGroup => isRequired || minSelections > 0;

  int? get pricingDefaultSideId => defaultSideId;

  int get effectiveMin {
    if (minSelections > 0) return minSelections;
    if (isRequired) return 1;
    return 0;
  }

  factory OptionGroup.fromApiJson(Map<String, dynamic> json) {
    final defaultSideId = _parseDefaultSideId(json);
    final minSelections =
        _parseInt(json['min_selections'] ?? json['minSelections'], 0);
    final isRequired = _parseBool(
      json['is_required'] ?? json['isRequired'],
      fallback: false,
    );

    return OptionGroup(
      id: _parseInt(json['id'], 0),
      name: json['name']?.toString() ?? 'Options',
      minSelections: minSelections,
      maxSelections: _parseInt(json['max_selections'] ?? json['maxSelections'], 1),
      isRequired: isRequired,
      displayOrder: _parseInt(json['display_order'] ?? json['displayOrder'], 0),
      defaultSideId: defaultSideId,
      sides: _parseSidesList(json),
    );
  }

  factory OptionGroup.fromJson(Map<String, dynamic> json) =>
      OptionGroup.fromApiJson(json);
}

class Category {
  final int id;
  final String name;
  final String? imageUrl;

  Category({required this.id, required this.name, this.imageUrl});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      imageUrl: json['image_url'],
    );
  }
}

class Food implements MenuItem {
  @override
  final int id;
  final int categoryId;
  @override
  final String name;
  @override
  final String? description;
  final double basePrice;
  final double menuPrice;
  @override
  final String? imageUrl;
  final List<OptionGroup> optionGroups;
  final bool hasOptions;
  @override
  final bool isVisible;
  @override
  final bool isOutOfStock;

  Food({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    required this.basePrice,
    required this.menuPrice,
    this.imageUrl,
    this.optionGroups = const [],
    this.hasOptions = false,
    this.isVisible = true,
    this.isOutOfStock = false,
  });

  @override
  double get price => menuPrice;

  @override
  bool get isSide => false;

  @override
  bool get canOrder => isVisible && !isOutOfStock;

  List<OptionGroup> get sortedOptionGroups {
    final groups = List<OptionGroup>.from(optionGroups);
    groups.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return groups;
  }

  factory Food.fromJson(Map<String, dynamic> json) {
    final groups = _parseFoodOptionGroups(json);
    final hasOptions =
        _parseBool(json['has_options'], fallback: false) || groups.isNotEmpty;

    return Food(
      id: _parseInt(json['id'], 0),
      categoryId: _parseInt(json['category_id'], 0),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      basePrice: _parseDouble(json['base_price'] ?? json['price'], 0),
      menuPrice: _parseDouble(
        json['menu_price'] ?? json['display_price'] ?? json['price'],
        0,
      ),
      imageUrl: json['image_url']?.toString(),
      optionGroups: groups,
      hasOptions: hasOptions,
      isVisible: _parseIsVisible(json),
      isOutOfStock: _parseIsOutOfStock(json),
    );
  }
}

class Side implements MenuItem {
  @override
  final int id;
  @override
  final String name;
  @override
  final double price;
  final double priceDelta;
  final bool isPricingDefault;
  final String? type;
  @override
  final String? imageUrl;
  @override
  final bool isVisible;
  @override
  final bool isOutOfStock;

  Side({
    required this.id,
    required this.name,
    required this.price,
    this.priceDelta = 0,
    this.isPricingDefault = false,
    this.type,
    this.imageUrl,
    this.isVisible = true,
    this.isOutOfStock = false,
  });

  @override
  String? get description => type; // Use type as description for list view

  @override
  bool get isSide => true;

  @override
  bool get canOrder => isVisible && !isOutOfStock;

  factory Side.fromJson(Map<String, dynamic> json) {
    final raw = json['side'] is Map
        ? Map<String, dynamic>.from(json['side'] as Map)
        : json;
    final price = _parseDouble(raw['price'], 0);
    return Side(
      id: _parseInt(raw['id'], 0),
      name: raw['name']?.toString() ?? '',
      price: price,
      priceDelta: _parseDouble(raw['price_delta'] ?? raw['priceDelta'], 0),
      isPricingDefault: _parseBool(
        raw['is_pricing_default'] ?? raw['isPricingDefault'],
        fallback: false,
      ),
      type: raw['type']?.toString(),
      imageUrl: raw['image_url']?.toString(),
      isVisible: _parseIsVisible(raw),
      isOutOfStock: _parseIsOutOfStock(raw),
    );
  }
}
