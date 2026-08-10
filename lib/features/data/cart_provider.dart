import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import '../domain/address_model.dart';
import '../services/backend_service.dart';

class CartItem {
  final MenuItem food;
  final int quantity;
  final List<CartSelection> selections;

  CartItem({
    required this.food,
    required this.quantity,
    this.selections = const [],
  });

  double get lineUnitPrice {
    if (food is Food) {
      return lineTotalFromMenuPrice((food as Food).menuPrice, selections);
    }
    return food.price;
  }

  double get totalPrice => lineUnitPrice * quantity;
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  List<UserAddress> _savedAddresses = [];
  String _deliveryAddress = '';
  String _deliveryLga = '';
  bool _isLoadingAddresses = false;
  StoreLocation? _selectedStore;

  List<CartItem> get items => _items;
  List<UserAddress> get savedAddresses => _savedAddresses;
  int get itemCount => _items.length;
  String get deliveryAddress => _deliveryAddress;
  String get deliveryLga => _deliveryLga;
  bool get isLoadingAddresses => _isLoadingAddresses;
  StoreLocation? get selectedStore => _selectedStore;

  double get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);

  bool setSelectedStore(StoreLocation store, {bool clearCartOnChange = false}) {
    final storeChanged = _selectedStore?.code != store.code;
    final cartCleared = storeChanged && clearCartOnChange && _items.isNotEmpty;
    if (cartCleared) {
      _items.clear();
    }
    _selectedStore = store;
    notifyListeners();
    return cartCleared;
  }

  void setDeliveryAddress(String address) {
    _deliveryAddress = address;
    final parts = address.split(',');
    if (parts.length >= 4) {
      _deliveryLga = parts[3].trim();
    } else {
      _deliveryLga = '';
    }
    notifyListeners();
  }

  void setDeliveryAddressModel(UserAddress address) {
    _deliveryAddress = address.fullAddress;
    _deliveryLga = address.lga;
    notifyListeners();
  }

  Future<void> loadAddresses(String userId) async {
    _isLoadingAddresses = true;
    notifyListeners();
    try {
      final data = await BackendService.getAddresses();
      _savedAddresses = data.map((e) => UserAddress.fromMap(e)).toList();

      if (_savedAddresses.isNotEmpty) {
        final defaultAddr = _savedAddresses.firstWhere(
          (a) => a.isDefault,
          orElse: () => _savedAddresses.first,
        );
        _deliveryAddress = defaultAddr.fullAddress;
        _deliveryLga = defaultAddr.lga;
      } else {
        _deliveryAddress = '';
        _deliveryLga = '';
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading addresses: $e');
      }
    } finally {
      _isLoadingAddresses = false;
      notifyListeners();
    }
  }

  Future<void> addAddress(UserAddress address, String userId) async {
    try {
      final savedData = await BackendService.saveAddress(address.toMap(), userId);
      final savedAddress = UserAddress.fromMap(savedData);

      _savedAddresses.add(savedAddress);
      if (savedAddress.isDefault || _savedAddresses.length == 1) {
        _deliveryAddress = savedAddress.fullAddress;
        _deliveryLga = savedAddress.lga;
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error adding address: $e');
      }
      rethrow;
    }
  }

  Future<void> updateAddress(int index, UserAddress newAddress, String userId) async {
    if (index >= 0 && index < _savedAddresses.length) {
      try {
        if (newAddress.id != null) {
          await BackendService.updateAddress(newAddress.id!, newAddress.toMap());
        }

        final oldAddress = _savedAddresses[index];
        final wasSelected = oldAddress.fullAddress == _deliveryAddress;

        _savedAddresses[index] = newAddress;

        if (wasSelected || newAddress.isDefault) {
          _deliveryAddress = newAddress.fullAddress;
          _deliveryLga = newAddress.lga;
        }
        notifyListeners();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error updating address: $e');
        }
        rethrow;
      }
    }
  }

  Future<void> removeAddress(int index) async {
    if (index >= 0 && index < _savedAddresses.length) {
      final addressToRemove = _savedAddresses[index];
      try {
        if (addressToRemove.id != null) {
          await BackendService.deleteAddress(addressToRemove.id!);
        }

        final isSelected = addressToRemove.fullAddress == _deliveryAddress;

        _savedAddresses.removeAt(index);

        if (_savedAddresses.isEmpty) {
          _deliveryAddress = '';
          _deliveryLga = '';
        } else if (isSelected) {
          _deliveryAddress = _savedAddresses.first.fullAddress;
          _deliveryLga = _savedAddresses.first.lga;
        }
        notifyListeners();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error removing address: $e');
        }
        rethrow;
      }
    }
  }

  void addItem(
    MenuItem food, {
    int quantity = 1,
    List<CartSelection> selections = const [],
  }) {
    if (!food.canOrder) return;
    _items.add(CartItem(food: food, quantity: quantity, selections: selections));
    notifyListeners();
  }

  void replaceItem(
    int index,
    MenuItem food, {
    int quantity = 1,
    List<CartSelection> selections = const [],
  }) {
    if (index < 0 || index >= _items.length || !food.canOrder) return;
    _items[index] = CartItem(
      food: food,
      quantity: quantity,
      selections: selections,
    );
    notifyListeners();
  }

  void removeFromCart(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
