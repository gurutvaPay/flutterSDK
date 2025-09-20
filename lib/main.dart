// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'gurutvapay-sdk-flutter.dart';

void main() {
  runApp(const MyApp());
}

/// Brand gradient (approximated colors from your HSL spec)
final Gradient brandGradient = const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFFFA500), // approx brand-secondary
    Color(0xFF8F00FF), // approx brand-primary
  ],
);

const String brandLogoUrl = 'https://jaikalki.com/static/assets/img/Gravity_logo.png';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GurutvaPay Demo',
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

class TransactionItem {
  String merchantOrderId;
  int amount;
  String status;
  String? orderId;
  String? transactionId;

  TransactionItem({
    required this.merchantOrderId,
    required this.amount,
    this.status = 'pending',
    this.orderId,
    this.transactionId,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _orderCtrl = TextEditingController(text: 'ORDER_2025_001');
  final _amountCtrl = TextEditingController(text: '100');
  final _nameCtrl = TextEditingController(text: 'Integration Tester');
  final _emailCtrl = TextEditingController(text: 'integ@example.com');
  final _phoneCtrl = TextEditingController(text: '+919876543210');
  final _address1Ctrl = TextEditingController(text: 'Flat 12, Test Address');
  final _address2Ctrl = TextEditingController(text: 'Somewhere mumbai');

  // Transactions
  final List<TransactionItem> _txns = [];

  // API config (replace keys for production)
  String _liveSaltKey1 = 'live_234f9************************';


  @override
  void dispose() {
    _orderCtrl.dispose();
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _address1Ctrl.dispose();
    _address2Ctrl.dispose();
    super.dispose();
  }

  /// Calls the SDK helper which sends a form-encoded POST to transaction-status-android.
  /// Returns the decoded JSON map on success, or a map with 'error'.
  Future<Map<String, dynamic>?> _transactionStatus(String merchantOrderId) async {
    try {
      final res = await GurutvaPaySDK.checkTransactionStatus(
        _liveSaltKey1,
        merchantOrderId,
        timeoutSeconds: 10,
      );
      return res;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  void _createOrderAndOpenSDK() {
    if (!_formKey.currentState!.validate()) return;

    final amount = int.tryParse(_amountCtrl.text) ?? 0;
    final merchantOrderId = _orderCtrl.text.trim();

    final payload = {
      'amount': amount,
      'merchantOrderId': merchantOrderId,
      'channel': 'android',
      'purpose': 'Integration Test Payment',
      'customer': {
        'buyer_name': _nameCtrl.text,
        'email': _emailCtrl.text,
        'phone': _phoneCtrl.text,
        'address1': _address1Ctrl.text,
        'address2': _address2Ctrl.text,
      }
    };

    // add to local txn list
    final txn = TransactionItem(merchantOrderId: merchantOrderId, amount: amount, status: 'created');
    setState(() => _txns.insert(0, txn));

    // Push the SDK page. We pass callbacks which update the txn list.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (sdkRouteContext) {
        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            automaticallyImplyLeading: true,
            flexibleSpace: Container(decoration: BoxDecoration(gradient: brandGradient)),
            title: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                child: ClipOval(child: Image.network(brandLogoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_wallet, color: Colors.white))),
              ),
              const SizedBox(width: 8),
              const Text('GurutvaPay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            centerTitle: true,
          ),
          body: GurutvaPaySDK(
            liveSaltKey1: _liveSaltKey1,
            orderPayload: payload,
            showHeader: false,
            brandLogoUrl: brandLogoUrl,
            onAnyEvent: (e) {
              debugPrint('SDK any event: $e');
              // If event contains merchantOrderId or payload, update txn
              final mo = e['merchantOrderId'] ?? e['merchant_order_id'] ?? e['payload']?['merchantOrderId'];
              if (mo != null) {
                final moStr = mo.toString();
                final idx = _txns.indexWhere((t) => t.merchantOrderId == moStr);
                if (idx != -1) {
                  setState(() {
                    final status = e['status'] ?? e['state'] ?? (e['payload'] is Map ? e['payload']['status'] : null);
                    if (status != null) _txns[idx].status = status.toString();
                    _txns[idx].orderId = e['orderId'] ?? e['order_id'] ?? (e['payload'] is Map ? e['payload']['orderId'] : _txns[idx].orderId);
                    _txns[idx].transactionId = e['transactionId'] ?? (e['payload'] is Map ? e['payload']['transactionId'] : _txns[idx].transactionId);
                  });
                }
              }
            },
            onSuccess: (payload) async {
              debugPrint('SDK onSuccess payload: $payload');
              // Preferred merchantOrderId from payload, fallback to created one
              final mo = payload['merchantOrderId']?.toString() ?? merchantOrderId;

              // Optimistically update local txn to 'success'
              final idx = _txns.indexWhere((t) => t.merchantOrderId == mo);
              if (idx != -1) {
                setState(() {
                  _txns[idx].status = 'success';
                  _txns[idx].orderId = payload['orderId']?.toString() ?? _txns[idx].orderId;
                  _txns[idx].transactionId = payload['transactionId']?.toString() ?? _txns[idx].transactionId;
                });
              } else {
                if (_txns.isNotEmpty) {
                  setState(() => _txns[0].status = 'success');
                }
              }

              // Confirm with server (optional): refresh status from API
              final serverRes = await _transactionStatus(mo);
              if (serverRes != null && serverRes.containsKey('status')) {
                final idx2 = _txns.indexWhere((t) => t.merchantOrderId == mo);
                if (idx2 != -1) {
                  setState(() {
                    _txns[idx2].status = serverRes['status'].toString();
                    _txns[idx2].orderId = serverRes['orderId']?.toString() ?? _txns[idx2].orderId;
                    _txns[idx2].transactionId = serverRes['transactionId']?.toString() ?? _txns[idx2].transactionId;
                  });
                }
              }

              // NO DIALOG, NO AUTO POP.
              if (mounted) {
                ScaffoldMessenger.of(sdkRouteContext).showSnackBar(
                  const SnackBar(content: Text('Payment successful — press back to return')),
                );
              }
            },
            onFailure: (payload) async {
              debugPrint('SDK onFailure payload: $payload');
              final mo = payload['merchantOrderId']?.toString() ?? merchantOrderId;
              final idx = _txns.indexWhere((t) => t.merchantOrderId == mo);
              if (idx != -1) {
                setState(() => _txns[idx].status = 'failed');
              }
              if (mounted) {
                ScaffoldMessenger.of(sdkRouteContext).showSnackBar(const SnackBar(content: Text('Payment failed')));
              }
            },
            onPending: (payload) {
              debugPrint('SDK onPending payload: $payload');
              final mo = payload['merchantOrderId']?.toString() ?? merchantOrderId;
              final idx = _txns.indexWhere((t) => t.merchantOrderId == mo);
              if (idx != -1) {
                setState(() => _txns[idx].status = 'pending');
              }
              if (mounted) {
                ScaffoldMessenger.of(sdkRouteContext).showSnackBar(const SnackBar(content: Text('Payment pending')));
              }
            },
            onIntentLaunched: (p) {
              debugPrint('Intent launched: $p');
              if (mounted) ScaffoldMessenger.of(sdkRouteContext).showSnackBar(const SnackBar(content: Text('UPI / intent launched')));
            },
          ),
        );
      }),
    );
  }

  Widget _txnList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _txns.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final t = _txns[i];
        return ListTile(
          title: Text('${t.merchantOrderId} — ₹${t.amount}'),
          subtitle: Text('Status: ${t.status}${t.transactionId != null ? '\nTxn: ${t.transactionId}' : ''}'),
          trailing: ElevatedButton(
            child: const Text('Check status'),
            onPressed: () async {
              final snackCtx = ScaffoldMessenger.of(context);
              snackCtx.showSnackBar(const SnackBar(content: Text('Checking status...')));

              final res = await _transactionStatus(t.merchantOrderId);
              if (res == null) {
                snackCtx.showSnackBar(const SnackBar(content: Text('Network error checking status')));
                return;
              }
              if (res.containsKey('error')) {
                snackCtx.showSnackBar(SnackBar(content: Text('Error: ${res['error']}')));
                return;
              }

              setState(() {
                if (res.containsKey('status')) t.status = res['status'].toString();
                t.orderId = res['orderId']?.toString() ?? t.orderId;
                t.transactionId = res['transactionId']?.toString() ?? t.transactionId;
              });

              final snack = res.containsKey('status') ? 'Status: ${res['status']}' : 'Response: ${jsonEncode(res)}';
              snackCtx.showSnackBar(SnackBar(content: Text(snack)));
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: brandGradient)),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
            child: ClipOval(child: Image.network(brandLogoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_wallet, color: Colors.white))),
          ),
          const SizedBox(width: 8),
          const Text('GurutvaPay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  TextFormField(
                    controller: _orderCtrl,
                    decoration: const InputDecoration(labelText: 'merchantOrderId'),
                    validator: (v) => (v == null || v.isEmpty) ? 'required' : null,
                  ),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(labelText: 'Amount (INR)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.isEmpty) ? 'required' : null,
                  ),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Buyer name'),
                    validator: (v) => (v == null || v.isEmpty) ? 'required' : null,
                  ),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  TextFormField(
                    controller: _address1Ctrl,
                    decoration: const InputDecoration(labelText: 'Address 1'),
                    validator: (v) => (v == null || v.isEmpty) ? 'required' : null,
                  ),
                  TextFormField(
                    controller: _address2Ctrl,
                    decoration: const InputDecoration(labelText: 'Address 2'),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: ElevatedButton(onPressed: _createOrderAndOpenSDK, child: const Text('Create order & Open SDK'))),
                  ]),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _txns.isEmpty ? const Text('No transactions yet') : _txnList(),
          const SizedBox(height: 40),
          const Text('Note: Use the "Check status" to call transaction-status endpoint.'),
        ]),
      ),
    );
  }
}
