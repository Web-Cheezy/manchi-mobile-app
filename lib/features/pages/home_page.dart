import 'package:flutter/material.dart';
import 'package:manchi_app/features/data/food_repository.dart';
import 'package:manchi_app/features/domain/models.dart';
import 'package:manchi_app/features/components/food_card.dart';
import 'package:manchi_app/features/components/food_detail_modal.dart';
import 'package:manchi_app/features/pages/addresses_page.dart';
import 'package:manchi_app/features/pages/notifications_page.dart';
import 'package:manchi_app/features/pages/orders_page.dart';
import 'package:manchi_app/features/pages/personal_info_page.dart';
import 'package:manchi_app/features/pages/about_page.dart';
import 'package:manchi_app/features/pages/appearance_page.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/features/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:manchi_app/features/data/cart_provider.dart';
import 'package:manchi_app/features/auth/auth_page.dart';
import 'package:manchi_app/features/pages/order_history_page.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FoodRepository _repository = FoodRepository();
  
  List<Category> _categories = [];
  List<Food> _cachedFoods = [];
  List<Food> _menuItems = [];
  int? _selectedCategoryId;
  bool _isLoading = true;
  String _userName = 'Guest';
  String? _userFullName;
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _requestNotificationPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureStoreSelectedAndLoadData();
    });
  }

  Future<void> _requestNotificationPermission() async {
    await Permission.notification.request();
    await NotificationService().refreshTokenRegistration();
  }

  Future<void> _loadUserProfile() async {
    final user = await BackendService.getCurrentUser();
    if (user != null) {
      setState(() {
        _user = user;
        _userName = user['email']?.split('@')[0] ?? 'User'; // Fallback to email prefix
      });
      
      // Try to get full profile for name
      if (user['id'] != null) {
        try {
          final profile = await BackendService.getProfile(user['id']);
          if (profile != null && profile['full_name'] != null) {
            final fullName = profile['full_name'].toString();
            if (fullName.isNotEmpty) {
              setState(() {
                _userFullName = fullName;
                _userName = fullName.split(' ').first;
              });
            }
          }
        } catch (e) {
          // Ignore
        }
      }
    }
  }

  Future<void> _ensureStoreSelectedAndLoadData() async {
    final cart = context.read<CartProvider>();
    if (cart.selectedStore != null) {
      await _loadData();
      return;
    }
    final store = await _showStorePicker(forceSelection: true);
    if (store == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    await _applyStoreSelection(store, clearCartOnChange: false);
  }

  Future<void> _loadData() async {
    final store = context.read<CartProvider>().selectedStore;
    if (store == null) {
      if (mounted) {
        setState(() {
          _categories = [];
          _cachedFoods = [];
          _menuItems = [];
          _isLoading = false;
        });
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      final menu = await _repository.getMenu(
        storeCode: store.code,
        stateName: store.state,
      );
      if (menu == null) {
        throw Exception('We couldn\'t load the menu. Please pull to refresh.');
      }
      setState(() {
        _categories = menu.categories;
        _cachedFoods = menu.foods;
      });
      await _loadMenuItems();
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t load the menu. Please pull to refresh.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMenuItems() async {
    setState(() => _isLoading = true);
    try {
      final items = _selectedCategoryId == null
          ? _cachedFoods
          : _cachedFoods
              .where((f) => f.categoryId == _selectedCategoryId)
              .toList();

      setState(() {
        _menuItems = items;
      });
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t load items. Please pull to refresh.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onCategorySelected(int? categoryId) {
    if (_selectedCategoryId == categoryId) return;
    setState(() {
      _selectedCategoryId = categoryId;
    });
    _loadMenuItems();
  }

  Future<void> _applyStoreSelection(
    StoreLocation store, {
    required bool clearCartOnChange,
  }) async {
    final cart = context.read<CartProvider>();
    final cartCleared = cart.setSelectedStore(
      store,
      clearCartOnChange: clearCartOnChange,
    );
    if (mounted) {
      setState(() {
        _selectedCategoryId = null;
      });
    }
    if (cartCleared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cart cleared. You are now shopping from ${store.state}.'),
        ),
      );
    }
    await _loadData();
  }

  Future<StoreLocation?> _showStorePicker({
    required bool forceSelection,
  }) {
    return showModalBottomSheet<StoreLocation>(
      context: context,
      isDismissible: !forceSelection,
      enableDrag: !forceSelection,
      showDragHandle: !forceSelection,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose your store',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select where you want to order from.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),
                ...supportedStores.map((store) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, store),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.2),
                          ),
                          color: theme.cardColor,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.state,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              store.address,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openExternalLink(String value) async {
    final uri = Uri.parse(value);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open that link right now.')),
      );
    }
  }

  Future<void> _openAccountDeletionRequestEmail() async {
    final email = (_user?['email'] as String?)?.trim();
    final fullName = _userFullName?.trim();
    final fullNameValue =
        (fullName != null && fullName.isNotEmpty) ? fullName : '(fill in your details)';
    final emailValue = (email != null && email.isNotEmpty) ? email : '(fill in your details)';

    final body = [
      'Dear Team,',
      '',
      'I want my account to be deleted',
      'Full name: $fullNameValue',
      'Email Address: $emailValue',
      'Reason for deletion: (fill in your reason)',
      '',
      'Thank You',
    ].join('\n');

    final uri = Uri.parse(
      'mailto:hi@manchi.ng'
      '?cc=manchi_takeout@gmail.com'
      '&subject=${Uri.encodeComponent('Account Deletion Request')}'
      '&body=${Uri.encodeComponent(body)}',
    );

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open your email app right now.')),
      );
    }
  }

  Future<void> _startAccountDeletionFlow() async {
    if (_user == null) {
      await _openAccountDeletionRequestEmail();
      return;
    }

    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Delete account?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will permanently delete your profile and saved data. Your past orders will be kept but anonymized.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (reason == null) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await BackendService.deleteAccount(reason: reason);
      await BackendService.signOut();
      if (!mounted) return;

      Navigator.of(context).pop();
      setState(() {
        _user = null;
        _userName = 'Guest';
        _userFullName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(
          context,
          e,
          contextMessage: 'We couldn\'t delete your account. Please try again.',
        );
      }
    }
  }

  void _showContactUsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contact Us',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Live Support coming soon!')),
                      );
                    },
                    icon: const Icon(LucideIcons.messageCircle),
                    label: const Text('Live Support'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openExternalLink('tel:+2347072452303'),
                    icon: const Icon(LucideIcons.phone),
                    label: const Text('Call Us • +2347072452303'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openExternalLink(
                      'mailto:hi@manchi.ng?subject=Manchi Support',
                    ),
                    icon: const Icon(LucideIcons.mail),
                    label: const Text('Email Us • hi@manchi.ng'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _startAccountDeletionFlow();
                    },
                    icon: const Icon(LucideIcons.trash2),
                    label: Text(
                      _user == null ? 'Delete Account Request' : 'Delete My Account',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    await NotificationService().unregisterToken();
    await BackendService.signOut();
    if (mounted) {
      setState(() {
        _user = null;
        _userName = 'Guest';
        _userFullName = null;
      });
      Navigator.pop(context); // Close drawer
    }
  }

  void _navigateTo(Widget page) {
    Navigator.pop(context); // Close drawer
    if (_user == null && page is! AuthPage) {
       Navigator.push(context, MaterialPageRoute(builder: (_) => AuthPage(onLoginSuccess: _loadUserProfile)));
    } else {
       Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurface),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = context.watch<CartProvider>();
    final selectedStore = cart.selectedStore;
    final deliveryAddress = cart.deliveryAddress;
    String displayLocation = 'Select Location';
    if (deliveryAddress != 'Loading location...') {
      final parts = deliveryAddress.split(',');
      if (parts.isNotEmpty) {
        displayLocation = parts.length > 1 ? parts[parts.length - 2].trim() : parts[0].trim();
        if (displayLocation.length > 15) displayLocation = '${displayLocation.substring(0, 15)}...';
      }
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: Drawer(
        backgroundColor: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Scrollable content (logo, menu header, items, user info)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      Center(
                        child: Image.asset(
                          theme.brightness == Brightness.dark
                              ? 'assets/darkmanchi.png'
                              : 'assets/lightmanchi.png',
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(LucideIcons.utensilsCrossed,
                                size: 80, color: theme.colorScheme.primary);
                          },
                        ),
                      ),
                      const SizedBox(height: 40),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          'Menu',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildDrawerItem(
                        icon: LucideIcons.user,
                        title: 'Profile',
                        onTap: () => _navigateTo(const PersonalInfoPage()),
                        theme: theme,
                      ),
                      _buildDrawerItem(
                        icon: LucideIcons.bell,
                        title: 'Notifications',
                        onTap: () => _navigateTo(const NotificationsPage()),
                        theme: theme,
                      ),
                      _buildDrawerItem(
                        icon: LucideIcons.mapPin,
                        title: 'Addresses',
                        onTap: () => _navigateTo(const AddressesPage()),
                        theme: theme,
                      ),
                      _buildDrawerItem(
                        icon: LucideIcons.history,
                        title: 'Order History',
                        onTap: () => _navigateTo(const OrderHistoryPage()),
                        theme: theme,
                      ),
                      _buildDrawerItem(
                        icon: LucideIcons.messageCircle,
                        title: 'Contact Us',
                        onTap: () {
                          Navigator.pop(context);
                          _showContactUsSheet();
                        },
                        theme: theme,
                      ),
                      _buildDrawerItem(
                        icon: LucideIcons.palette,
                        title: 'Appearance',
                        onTap: () => _navigateTo(const AppearancePage()),
                        theme: theme,
                      ),
                      _buildDrawerItem(
                        icon: LucideIcons.info,
                        title: 'About',
                        onTap: () => _navigateTo(const AboutPage()),
                        theme: theme,
                      ),
                      if (_user != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 12.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.2),
                                child: Text(
                                  _userName.isNotEmpty
                                      ? _userName[0].toUpperCase()
                                      : 'G',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (_user!['phone'] != null)
                                    Text(
                                      _user!['phone'].toString(),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurface
                                                  .withValues(alpha: 0.6)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // Fixed Sign In/Out button at the bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _user == null
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _user == null
                          ? Colors.transparent
                          : theme.colorScheme.error,
                      width: 1.5,
                    ),
                    boxShadow: _user == null
                        ? [
                            BoxShadow(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _user == null
                          ? () => _navigateTo(
                              AuthPage(onLoginSuccess: _loadUserProfile))
                          : _signOut,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _user == null ? LucideIcons.logIn : LucideIcons.logOut,
                              color: _user == null
                                  ? Colors.white
                                  : theme.colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _user == null ? 'Sign In' : 'Sign Out',
                              style: TextStyle(
                                color: _user == null
                                    ? Colors.white
                                    : theme.colorScheme.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: Icon(LucideIcons.menu, color: theme.colorScheme.onSurface),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Center(
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressesPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.mapPin, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      displayLocation,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronDown, size: 16, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.bell, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(LucideIcons.shoppingBag, color: theme.colorScheme.onSurface),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersPage())),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    if (cart.itemCount == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Greeting Section
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello $_userName',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'ready to satisfy your cravings?',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 16),
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  final store = await _showStorePicker(forceSelection: false);
                                  if (store != null) {
                                    await _applyStoreSelection(
                                      store,
                                      clearCartOnChange: true,
                                    );
                                  }
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: theme.cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.store,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Shopping from',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              selectedStore?.state ?? 'Choose store',
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (selectedStore != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                selectedStore.address,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Change',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Banner
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              color: Colors.red, // Placeholder color
                              borderRadius: BorderRadius.circular(16),
                              image: const DecorationImage(
                                image: AssetImage('assets/IMG-20260226-WA0022.jpg'),
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.7),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Welcome to Manchi!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'What are you\ngetting today?',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Categories
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length + 1,
                            separatorBuilder: (context, index) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final isAll = index == 0;
                              final category = isAll ? null : _categories[index - 1];
                              final isSelected = isAll 
                                  ? _selectedCategoryId == null 
                                  : _selectedCategoryId == category!.id;
                              
                              return FilterChip(
                                selected: isSelected,
                                label: Text(isAll ? 'All' : category!.name),
                                onSelected: (_) => _onCategorySelected(isAll ? null : category!.id),
                                backgroundColor: theme.cardColor,
                                selectedColor: theme.colorScheme.primary,
                                labelStyle: TextStyle(
                                  color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: isSelected ? Colors.transparent : Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                                showCheckmark: false,
                              );
                            },
                          ),
                        ),
                        
                        const SizedBox(height: 16),

                        // Menu Items
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _menuItems.isEmpty
                              ? const Center(child: Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Text('No items found'),
                                ))
                              : GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 0.75,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: _menuItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _menuItems[index];
                                    return FoodCard(
                                      food: item,
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (context) =>
                                              FoodDetailModal(food: item),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 80), // Bottom padding
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
