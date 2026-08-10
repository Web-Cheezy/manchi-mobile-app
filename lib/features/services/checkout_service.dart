import '../data/cart_provider.dart';
import '../data/food_repository.dart';
import '../domain/models.dart';

class CheckoutValidationException implements Exception {
  final String message;
  const CheckoutValidationException(this.message);

  @override
  String toString() => message;
}

class CheckoutTotals {
  final double subTotal;
  final double vat;
  final double deliveryFee;
  final double grandTotal;

  const CheckoutTotals({
    required this.subTotal,
    required this.vat,
    required this.deliveryFee,
    required this.grandTotal,
  });
}

/// Re-fetches live menu prices and updates the cart before order submission.
class CheckoutService {
  const CheckoutService();

  Future<CheckoutTotals> refreshCartAndTotals({
    required CartProvider cart,
    required FoodRepository repository,
    required String storeCode,
    required String stateName,
    required String deliveryMethod,
    required double deliveryFee,
    double vatRate = 0.075,
  }) async {
    for (var i = 0; i < cart.items.length; i++) {
      final item = cart.items[i];
      final food = item.food;
      if (food is! Food) {
        throw const CheckoutValidationException(
          'An item in your cart is no longer available. Please remove it and try again.',
        );
      }

      final freshFood = await repository.getFoodDetail(
        food.id,
        storeCode: storeCode,
        stateName: stateName,
      );

      if (!freshFood.canOrder) {
        throw CheckoutValidationException(
          '${freshFood.name} is out of stock. Please remove it from your cart.',
        );
      }

      if (freshFood.hasOptions && item.selections.isEmpty) {
        throw CheckoutValidationException(
          'Please reconfigure ${freshFood.name} before checkout.',
        );
      }

      final refreshedSelections = <CartSelection>[];
      for (final sel in item.selections) {
        final side = findSideInFood(freshFood, sel.groupId, sel.itemId);
        if (side == null || !side.canOrder) {
          throw CheckoutValidationException(
            '${freshFood.name}: ${sel.name} is no longer available. Please update your selections.',
          );
        }
        refreshedSelections.add(
          sel.withLiveSide(
            side,
            groupName: groupNameForSide(freshFood, sel.groupId),
          ),
        );
      }

      cart.replaceItem(
        i,
        freshFood,
        quantity: item.quantity,
        selections: refreshedSelections,
      );
    }

    final subTotal = cart.totalAmount;
    final vat = subTotal * vatRate;
    final appliedDeliveryFee =
        deliveryMethod == 'delivery' ? deliveryFee : 0.0;
    final grandTotal = subTotal + vat + appliedDeliveryFee;

    return CheckoutTotals(
      subTotal: subTotal,
      vat: vat,
      deliveryFee: appliedDeliveryFee,
      grandTotal: grandTotal,
    );
  }
}
