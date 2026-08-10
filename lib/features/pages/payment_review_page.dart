import 'package:flutter/material.dart';
import 'package:manchi_app/features/pages/paystack_webview_page.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class PaymentReviewPage extends StatefulWidget {
  final String email;
  final double amount;
  final String location;
  final String orderId;

  const PaymentReviewPage({
    super.key,
    required this.email,
    required this.amount,
    required this.location,
    required this.orderId,
  });

  @override
  State<PaymentReviewPage> createState() => _PaymentReviewPageState();
}

class _PaymentReviewPageState extends State<PaymentReviewPage> {
  bool _isLoading = false;

  Future<void> _initiatePayment() async {
    setState(() => _isLoading = true);
    try {
      final data = await BackendService.initializeTransaction(
        email: widget.email,
        amount: widget.amount,
        location: widget.location,
        orderId: widget.orderId,
      );

      String? authUrl;
      String? reference;

      if (data.containsKey('authorization_url')) {
        authUrl = data['authorization_url'];
        reference = data['reference'];
      } else if (data.containsKey('data')) {
        final innerData = data['data'];
        authUrl = innerData['authorization_url'];
        reference = innerData['reference'];
      }

      if (authUrl != null && reference != null) {
        if (mounted) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaystackWebViewPage(
                authorizationUrl: authUrl!,
                reference: reference!,
                amount: widget.amount,
              ),
            ),
          );

          if (result == true && mounted) {
            Navigator.pop(context, true);
          }
        }
      } else {
        throw Exception('We couldn\'t start the payment. Please try again.');
      }
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(context, e, contextMessage: 'Payment could not be started. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Payment')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confirm Payment',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount:', style: TextStyle(fontSize: 16)),
                        Text(
                          '₦${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Email:', style: TextStyle(fontSize: 16)),
                        Text(widget.email, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Location:', style: TextStyle(fontSize: 16)),
                        Text(
                          widget.location,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _isLoading ? null : _initiatePayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Proceed to Pay',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
