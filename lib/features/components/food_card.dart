import 'package:flutter/material.dart';
import 'package:manchi_app/features/domain/models.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class FoodCard extends StatelessWidget {
  final Food food;
  final VoidCallback onTap;

  const FoodCard({super.key, required this.food, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
    final isOutOfStock = food.isOutOfStock;
    final showCustomize = food.hasOptions && !isOutOfStock;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: isDark ? Border.all(color: Colors.white.withValues(alpha: 0.05)) : null,
          boxShadow: isDark 
              ? [] // Minimal shadow in dark mode
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Opacity(
                    opacity: isOutOfStock ? 0.55 : 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200],
                        image: (food.imageUrl != null && food.imageUrl!.isNotEmpty)
                            ? DecorationImage(
                                image: NetworkImage(food.imageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (food.imageUrl == null || food.imageUrl!.isEmpty)
                          ? Icon(
                              LucideIcons.utensilsCrossed,
                              size: 40,
                              color: isDark ? Colors.white24 : Colors.grey,
                            )
                          : null,
                    ),
                  ),
                  if (isOutOfStock)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Out of stock',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else if (showCustomize)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(food.price),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? theme.colorScheme.secondary : theme.primaryColor,
                      fontFamily: 'Roboto', // Fallback to system font for currency symbol
                    ),
                  ),
                  if (isOutOfStock) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Currently unavailable to order',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
