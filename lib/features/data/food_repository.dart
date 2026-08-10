import '../domain/models.dart';
import '../services/backend_service.dart';

List<Category> _foodCategoriesOnly(List<Category> categories) {
  return categories
      .where((c) => c.name.trim().toLowerCase() != 'sides')
      .toList();
}

class FoodRepository {
  Future<({List<Category> categories, List<Food> foods})?> getMenu({
    String? storeCode,
    String? stateName,
  }) async {
    final response = await BackendService.getMenu(
      storeCode: storeCode,
      stateName: stateName,
    );
    if (response == null) return null;

    final categoriesRaw = response['categories'];
    final foodsRaw = response['foods'];
    final categories = _foodCategoriesOnly(
      (categoriesRaw is List ? categoriesRaw : <dynamic>[])
          .whereType<Map>()
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
    final foods = (foodsRaw is List ? foodsRaw : <dynamic>[])
        .whereType<Map>()
        .map((e) => Food.fromJson(Map<String, dynamic>.from(e)))
        .where((f) => f.isVisible)
        .toList();

    return (categories: categories, foods: foods);
  }

  Future<List<Category>> getCategories({
    String? storeCode,
    String? stateName,
  }) async {
    final raw = await BackendService.getCategories(
      storeCode: storeCode,
      stateName: stateName,
    );
    return _foodCategoriesOnly(
      raw
          .whereType<Map>()
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Future<List<Food>> getFoods({
    int? categoryId,
    String? storeCode,
    String? stateName,
  }) async {
    final raw = await BackendService.getFoods(
      categoryId: categoryId,
      storeCode: storeCode,
      stateName: stateName,
    );
    return raw
        .whereType<Map>()
        .map((e) => Food.fromJson(Map<String, dynamic>.from(e)))
        .where((f) => f.isVisible)
        .toList();
  }

  Future<Food> getFoodDetail(
    int foodId, {
    String? storeCode,
    String? stateName,
  }) async {
    final response = await BackendService.getFoodDetail(
      foodId,
      storeCode: storeCode,
      stateName: stateName,
    );
    return Food.fromJson(response);
  }
}
