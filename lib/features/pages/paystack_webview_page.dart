import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class PaystackWebViewPage extends StatefulWidget {
  final String authorizationUrl;
  final String reference;
  final double amount;

  const PaystackWebViewPage({
    super.key,
    required this.authorizationUrl,
    required this.reference,
    required this.amount,
  });

  @override
  State<PaystackWebViewPage> createState() => _PaystackWebViewPageState();
}

class _PaystackWebViewPageState extends State<PaystackWebViewPage> {
  late final WebViewController _controller;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (UrlChange change) {
            if (change.url != null) {
              final uri = Uri.tryParse(change.url!);
              if (uri != null && _shouldVerifyPayment(uri)) {
                _verifyPayment();
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }
            if (_shouldVerifyPayment(uri)) {
              _verifyPayment();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  bool _shouldVerifyPayment(Uri uri) {
    final rawUrl = uri.toString().toLowerCase();
    final reference = widget.reference.toLowerCase();
    
    // 1. Check if the URL contains the reference (standard callback behavior)
    final hasMatchingReference =
        rawUrl.contains('reference=$reference') ||
        rawUrl.contains('trxref=$reference') ||
        rawUrl.contains(reference);
        
    // 2. Check for Paystack's standard "close" or "success" endpoints
    final path = uri.path.toLowerCase();
    final isPaystackDomain = uri.host.contains('paystack.com') || uri.host.contains('paystack.co');
    final isPaystackClose = path.endsWith('/close') || path.endsWith('/done') || path.endsWith('/success');
    
    // 3. Check for typical callback indicators
    final isCallback = rawUrl.contains('callback') || rawUrl.contains('checkout-success');

    return (isPaystackDomain && isPaystackClose) || hasMatchingReference || isCallback;
  }

  Future<void> _verifyPayment() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      final data = await BackendService.verifyTransaction(widget.reference);

      // Check for success status in response
      // Typically Paystack returns { status: true, data: { status: 'success' } }
      // Or backend might simplify it.
      
      bool isSuccess = false;
      final status = data['status'];
      final isRootSuccess = status == true || status.toString().toLowerCase() == 'true' || status.toString().toLowerCase() == 'success';

      if (isRootSuccess) {
        if (data.containsKey('data') && data['data'] is Map) {
          final innerData = data['data'];
          final innerStatus = innerData['status'];
          
          if (innerStatus != null) {
            // If inner status exists, it MUST be success
            if (innerStatus.toString().toLowerCase() == 'success') {
              isSuccess = true;
            }
          } else {
            // No inner status, trust root status
            isSuccess = true;
          }
        } else {
          // No data object, trust root status
          isSuccess = true;
        }
      }

      if (isSuccess) {
        if (mounted) {
          Navigator.pop(context, true); // Return true for success
        }
      } else {
        if (mounted) {
          final raw = data['message'] ?? data['error'];
          final message = raw != null && raw.toString().length <= 120
              ? raw.toString()
              : 'We couldn\'t confirm your payment. Please check your order history or try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, false);
        }
      }
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'We couldn\'t confirm your payment. Please check your order history or try again.');
        Navigator.pop(context, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paystack Checkout'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isVerifying)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
