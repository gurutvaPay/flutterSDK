# GurutvaPay Flutter SDK

This README explains how to integrate and use the **GurutvaPay Flutter SDK** for in-app payments.  
It provides a simple widget (`GurutvaPaySDK`) that handles the payment flow via WebView, launches UPI intents, and reports payment status back to your app.

---

## 📦 What is included
- **`lib/gurutvapay-sdk-flutter.dart`**
  - `GurutvaPaySDK` widget → embed SDK flow in your app
  - `checkTransactionStatus` helper → verify payments via API
- **Sample `main.dart`**
  - Shows how to create order, open SDK, list transactions, and check status

---

## ⚙️ Requirements
- Flutter **3.x** (stable)
- Dart **>=2.18**
- Android **minSdk 24**, **compileSdk 35**
- iOS **11+** (if extending later)
- Dependencies:
  - `flutter_inappwebview`
  - `http`
  - `package_info_plus`
  - `url_launcher`

---

## 📂 Project layout
flutter_gurutvapay_sdk/
lib/
gurutvapay-sdk-flutter.dart
example/
lib/main.dart
pubspec.yaml

---

## 🔌 Installation

### From pub.dev (when published)
```yaml
dependencies:
  gurutvapay_sdk: ^1.0.0
```

Local (for development)

Copy lib/gurutvapay-sdk-flutter.dart into your project.

Add dependencies in pubspec.yaml:

```
dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.0.0
  http: ^1.1.0
  package_info_plus: ^8.0.0
  url_launcher: ^6.2.6
```

▶️ Usage
1. Import the SDK
   ```
   import 'package:gurutvapay_sdk/gurutvapay-sdk-flutter.dart';


2. Create an order payload
```
   final payload = {
  'amount': 100,
  'merchantOrderId': 'ORDER_2025_001',
  'channel': 'android',
  'purpose': 'Test Payment',
  'customer': {
    'buyer_name': 'Test User',
    'email': 'test@example.com',
    'phone': '+911234567890',
    'address1': 'Flat 12, Test Address',
    'address2': 'Mumbai',
  }
};
```
3. Launch SDK widget
```
     Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => Scaffold(
    appBar: AppBar(title: const Text('GurutvaPay')),
    body: GurutvaPaySDK(
      liveSaltKey1: "live_xxxxx",
      orderPayload: payload,
      brandLogoUrl: "https://jaikalki.com/static/assets/img/Gravity_logo.png",
      showHeader: true,
      showSdkPopups: false,
      onAnyEvent: (e) => debugPrint("Event: $e"),
      onSuccess: (p) => debugPrint("Success: $p"),
      onFailure: (p) => debugPrint("Failure: $p"),
      onPending: (p) => debugPrint("Pending: $p"),
      onIntentLaunched: (p) => debugPrint("Intent launched: $p"),
    ),
  ),
));
```
📡 Check Transaction Status

```
final res = await GurutvaPaySDK.checkTransactionStatus(
  "live_xxxxx",
  "ORDER_2025_001",
);

if (res != null) {
  print("Transaction Status: ${res['status']}");
}
```

Response example:
```
{
  "status": "success",
  "orderId": "ORD_123",
  "transactionId": "TXN_987"
}
```

🎨 UI / Branding

Header gradient is applied by default if showHeader = true.

You can pass your brand logo URL via brandLogoUrl.

For full control, wrap GurutvaPaySDK in your own Scaffold with a custom AppBar.

🐞 Troubleshooting

UPI app not launching → ensure upi://, phonepe://, paytmmp://, or tez:// schemes are installed.

White screen / missing WebView → check flutter_inappwebview setup for Android/iOS.

Network error → verify Live-Salt-Key1 and server URL (envBaseUrl).

📧 Contact

For integration help:
Team GurutvaPay
📩 info@gurutvapay.com


