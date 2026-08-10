import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:manchi_app/features/domain/address_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:provider/provider.dart';
import 'package:manchi_app/features/data/cart_provider.dart';
import 'package:manchi_app/features/auth/auth_page.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class AddressesPage extends StatefulWidget {
  final bool popAfterSave;
  const AddressesPage({super.key, this.popAfterSave = false});

  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends State<AddressesPage> {
  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseNumberController = TextEditingController();
  
  List<NigerianState> _nigerianStates = [];
  NigerianState? _selectedState;
  String? _selectedLga;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;
  int? _editingIndex;
  String? _userId;

  Future<void> _promptReauth() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your session expired. Please sign in again.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
    if (mounted) {
      await _initPage();
    }
  }

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    try {
      await _loadStates();
      final user = await BackendService.getCurrentUser();
      if (user != null && user['id'] != null) {
        _userId = user['id'];
        if (mounted) {
          await Provider.of<CartProvider>(context, listen: false).loadAddresses(_userId!);
        }
      }
    } catch (e) {
      if (BackendService.isSessionExpiredError(e)) {
        await _promptReauth();
        return;
      }
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t load your addresses. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    super.dispose();
  }

  void _editAddress(int index, UserAddress address) {
    setState(() {
      _editingIndex = index;
      _areaController.text = address.area;
      _streetController.text = address.street;
      _houseNumberController.text = address.houseNumber;
      
      try {
        _selectedState = _nigerianStates.firstWhere(
          (s) => s.state == address.state,
        );
        if (_selectedState!.lgas.contains(address.lga)) {
          _selectedLga = address.lga;
        } else {
          _selectedLga = null;
        }
      } catch (e) {
        // State match failed
        _selectedState = null;
        _selectedLga = null;
      }
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
      _selectedState = null;
      _selectedLga = null;
      _areaController.clear();
      _streetController.clear();
      _houseNumberController.clear();
    });
  }

  Future<void> _loadStates() async {
    try {
      final String response = await rootBundle.loadString('assets/nigeria-state-and-lgas.json');
      final List<dynamic> data = json.decode(response);
      setState(() {
        _nigerianStates = data.map((e) => NigerianState.fromJson(e)).toList();
        // _isLoading = false; // Handled in _initPage
      });
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t load locations. Please try again.');
      }
      rethrow;
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      String? normalize(String? value) {
        if (value == null) return null;
        final v = value
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\\s-]'), ' ')
            .replaceAll(RegExp(r'\\bstate\\b'), '')
            .replaceAll(RegExp(r'\\blga\\b'), '')
            .replaceAll(RegExp(r'\\s+'), ' ')
            .trim();
        return v.isEmpty ? null : v;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Please turn on location in your device settings and try again.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location access was denied. You can enter your address manually.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location is turned off for this app. You can turn it on in settings or enter your address manually.');
      }

      Position position = await Geolocator.getCurrentPosition();
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        // Geocoding fields are inconsistent across devices/countries.
        // We use multiple candidates + normalization and fuzzy matching.
        final detectedStateRaw = place.administrativeArea;
        final detectedLgaRaw = place.subAdministrativeArea;

        // LGA often shows up as locality/subLocality when subAdministrativeArea is empty.
        final lgaFallbackRaw = place.locality ?? place.subLocality ?? place.name;

        final detectedState = normalize(detectedStateRaw);
        final detectedLga = normalize(detectedLgaRaw) ?? normalize(lgaFallbackRaw);

        NigerianState? matchedState;
        if (detectedState != null && _nigerianStates.isNotEmpty) {
          try {
            matchedState = _nigerianStates.firstWhere(
              (s) {
                final st = normalize(s.state);
                if (st == null) return false;
                return st.contains(detectedState) || detectedState.contains(st);
              },
            );
          } catch (_) {
            matchedState = null;
          }
        }

        String street =
            place.thoroughfare ?? place.street ?? place.locality ?? place.name ?? '';
        String area =
            place.subLocality ?? place.locality ?? place.name ?? '';
        String houseNumber = place.subThoroughfare ?? place.thoroughfare ?? '';
        if (houseNumber.trim().isEmpty) houseNumber = '1'; // required by validation; user can edit

        String? matchedLga;
        if (detectedLga != null) {
          if (matchedState != null) {
            try {
              matchedLga = matchedState.lgas.firstWhere((lga) {
                final l = normalize(lga);
                if (l == null) return false;
                return l == detectedLga ||
                    l.contains(detectedLga) ||
                    detectedLga.contains(l);
              });
            } catch (_) {
              matchedLga = null;
            }
          }

          // If state wasn't returned by geocoder, try to infer it from the LGA candidate.
          if (matchedState == null || matchedLga == null) {
            for (final state in _nigerianStates) {
              final inferred = state.lgas.where((lga) {
                final l = normalize(lga);
                if (l == null) return false;
                return l == detectedLga ||
                    l.contains(detectedLga) ||
                    detectedLga.contains(l);
              }).toList();
              if (inferred.isNotEmpty) {
                matchedState = state;
                matchedLga = inferred.first;
                break;
              }
            }
          }
        }

        setState(() {
          // State/LGA dropdowns must be set from the same list objects/strings.
          _selectedState = matchedState;
          _selectedLga = matchedLga;

          _streetController.text = street;
          _areaController.text = area;
          _houseNumberController.text = houseNumber;
        });

        if (mounted) {
          final hasState = _selectedState != null;
          final hasLga = _selectedLga != null;
          final message = hasState && hasLga
              ? 'Location autofilled! Please verify details.'
              : 'We couldn\'t confidently determine State/LGA from your location. Please verify or pick manually.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t detect your location. You can enter it manually.');
      }
    } finally {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _saveAddress() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to save addresses.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (_selectedState == null || _selectedLga == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select State and LGA')),
        );
        return;
      }

      setState(() => _isSaving = true);

      try {
        final newAddress = UserAddress(
          id: _editingIndex != null 
              ? Provider.of<CartProvider>(context, listen: false).savedAddresses[_editingIndex!].id 
              : null, // Let backend generate ID
          state: _selectedState!.state,
          lga: _selectedLga!,
          area: _areaController.text,
          street: _streetController.text,
          houseNumber: _houseNumberController.text,
          isDefault: _editingIndex != null 
              ? Provider.of<CartProvider>(context, listen: false).savedAddresses[_editingIndex!].isDefault
              : Provider.of<CartProvider>(context, listen: false).savedAddresses.isEmpty,
        );

        if (_editingIndex != null) {
          await Provider.of<CartProvider>(context, listen: false).updateAddress(_editingIndex!, newAddress, _userId!);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Address Updated')),
            );
          }
          setState(() {
            _editingIndex = null;
            _cancelEdit(); // Clear form
          });
        } else {
          await Provider.of<CartProvider>(context, listen: false).addAddress(newAddress, _userId!);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Address Saved')),
            );
          }
          setState(() {
            _cancelEdit(); // Clear form
          });
        }

        if (widget.popAfterSave && mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        if (BackendService.isSessionExpiredError(e)) {
          await _promptReauth();
          return;
        }
        if (mounted) {
          UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t save your address. Please try again.');
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = Provider.of<CartProvider>(context);
    final savedAddresses = cart.savedAddresses;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addresses'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // List of saved addresses
                      if (savedAddresses.isNotEmpty) ...[
                        Text(
                          'Saved Addresses',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: savedAddresses.length,
                          itemBuilder: (context, index) {
                            final address = savedAddresses[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(LucideIcons.mapPin),
                                title: Text('${address.street}, ${address.area}'),
                                subtitle: Text('${address.lga}, ${address.state}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(LucideIcons.pencil, color: Colors.blue),
                                      onPressed: () => _editAddress(index, address),
                                    ),
                                    address.isDefault 
                                      ? Icon(LucideIcons.circleCheckBig, color: theme.primaryColor)
                                      : IconButton(
                                          icon: const Icon(LucideIcons.trash2),
                                          onPressed: () async {
                                            final cartProvider = context.read<CartProvider>();
                                            setState(() => _isSaving = true);
                                            try {
                                              await cartProvider.removeAddress(index);
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              UserFacingErrors.showErrorSnackBar(
                                                context,
                                                e,
                                                contextMessage:
                                                    'We couldn\'t remove that address. Please try again.',
                                              );
                                            } finally {
                                              if (mounted) {
                                                setState(() => _isSaving = false);
                                              }
                                            }
                                          },
                                        ),
                                  ],
                                ),
                                onTap: () {
                                  // Set as active address in cart
                                  cart.setDeliveryAddressModel(address);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Selected: ${address.fullAddress}')),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                        const Divider(height: 32),
                      ],

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _editingIndex != null ? 'Edit Address' : 'Add New Address',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_editingIndex != null)
                            TextButton(
                              onPressed: _cancelEdit,
                              child: const Text('Cancel Edit'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Auto-detect Button
                      ElevatedButton.icon(
                        onPressed: (_isLocating || _isSaving) ? null : _detectLocation,
                        icon: _isLocating 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.locateFixed),
                        label: Text(_isLocating ? 'Detecting...' : 'Use Current Location'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // State Dropdown
                            DropdownButtonFormField<NigerianState>(
                              key: ValueKey(_selectedState),
                              initialValue: _selectedState,
                              decoration: const InputDecoration(
                                labelText: 'State',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(LucideIcons.map),
                              ),
                              items: _nigerianStates.map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(s.state),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedState = val;
                                  _selectedLga = null; // Reset LGA when state changes
                                });
                              },
                              validator: (val) => val == null ? 'Please select a state' : null,
                            ),
                            const SizedBox(height: 16),

                            // LGA Dropdown
                            DropdownButtonFormField<String>(
                              key: ValueKey(_selectedLga),
                              initialValue: _selectedLga,
                              decoration: const InputDecoration(
                                labelText: 'LGA',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(LucideIcons.building2),
                              ),
                              items: _selectedState?.lgas.map((lga) {
                                return DropdownMenuItem(
                                  value: lga,
                                  child: Text(lga),
                                );
                              }).toList() ?? [],
                              onChanged: _selectedState == null ? null : (val) {
                                setState(() => _selectedLga = val);
                              },
                              validator: (val) => val == null ? 'Please select an LGA' : null,
                            ),
                            const SizedBox(height: 16),

                            // Area
                            TextFormField(
                              controller: _areaController,
                              decoration: const InputDecoration(
                                labelText: 'Area',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(LucideIcons.mapPinned),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Please enter area' : null,
                            ),
                            const SizedBox(height: 16),

                            // Street
                            TextFormField(
                              controller: _streetController,
                              decoration: const InputDecoration(
                                labelText: 'Street',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(LucideIcons.mapPin),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Please enter street' : null,
                            ),
                            const SizedBox(height: 16),

                            // House Number
                            TextFormField(
                              controller: _houseNumberController,
                              decoration: const InputDecoration(
                                labelText: 'House Number',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(LucideIcons.house),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Please enter house number' : null,
                            ),
                            const SizedBox(height: 24),

                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _isSaving ? null : _saveAddress,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  foregroundColor: Colors.white,
                                ),
                                child: _isSaving
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                                    : Text( _editingIndex != null ? 'Update Address' : 'Save Address'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSaving)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}
