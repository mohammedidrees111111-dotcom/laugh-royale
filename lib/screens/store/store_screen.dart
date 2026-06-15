import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const String paypalLink = 'https://paypal.me/Mohammedid99';

  Future<void> _openPayPal() async {
    try {
      final uri = Uri.parse(paypalLink);
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      try {
        final altUri = Uri.parse('https://paypal.me/Mohammedid99/0');
        await launchUrl(altUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        _snack('PayPal not available. Visit: paypal.me/Mohammedid99');
      }
    }
  }

  Future<void> _openCheckout(String itemName, double price) async {
    try {
      final uri = Uri.parse('$paypalLink/$price');
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      try {
        await launchUrl(Uri.parse(paypalLink), mode: LaunchMode.externalApplication);
      } catch (_) {
        _snack('Cannot open PayPal. Visit: paypal.me/Mohammedid99');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3), action: SnackBarAction(label: 'Show', onPressed: () => _showPayPalInfo())));
  }

  void _showPayPalInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.payment, color: Color(0xFF0070BA)), SizedBox(width: 8), Text('PayPal')]),
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pay via:', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('paypal.me/Mohammedid99'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _confirmBuy(String item, double price) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Buy $item?'),
        content: Text('\$${price.toStringAsFixed(2)} USD\n\nPay securely with PayPal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buy Now')),
        ],
      ),
    );
    if (ok == true) _openCheckout(item, price);
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_checkout),
            onPressed: _openPayPal,
            tooltip: 'Direct PayPal',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard(theme),
          const SizedBox(height: 20),
          _sectionHeader('Featured Items', const Color(0xFF00D9FF)),
          const SizedBox(height: 12),
          _shopItem(
            theme: theme,
            emoji: '\ud83d\udc51',
            name: 'VIP Pass',
            price: 4.99,
            desc: 'Exclusive badge, priority matchmaking, ad-free',
            color: const Color(0xFFFFD700),
          ),
          _shopItem(
            theme: theme,
            emoji: '\ud83d\udc8e',
            name: 'Diamond Pack',
            price: 9.99,
            desc: 'All VIP perks + custom emotes + golden name',
            color: const Color(0xFF00D9FF),
          ),
          _shopItem(
            theme: theme,
            emoji: '\ud83c\udf1f',
            name: 'Starter Boost',
            price: 1.99,
            desc: '5 power-ups, 3 extra lives, exclusive avatar',
            color: const Color(0xFF00E676),
          ),
          _shopItem(
            theme: theme,
            emoji: '\ud83d\udd25',
            name: 'Pro Pack',
            price: 14.99,
            desc: 'All items unlocked, custom profile, analytics',
            color: const Color(0xFFFF6584),
          ),
          const SizedBox(height: 24),
          _sectionHeader('Power-Ups', const Color(0xFFFF6584)),
          const SizedBox(height: 12),
          _powerUpRow(theme),
          const SizedBox(height: 24),
          _sectionHeader('Premium', const Color(0xFF6C63FF)),
          const SizedBox(height: 12),
          _premiumCard(theme),
          const SizedBox(height: 40),
          _paypalFooter(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _heroCard(ThemeData theme) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFFFF6584)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('\ud83d\uded2', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Laugh Royale Shop',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Unlock exclusive items, power-ups & premium features',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white70)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openPayPal,
              icon: const Icon(Icons.payment),
              label: const Text('Pay with PayPal', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopItem({
    required ThemeData theme,
    required String emoji,
    required String name,
    required double price,
    required String desc,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ]),
          ),
          Column(children: [
            Text('\$${price.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => _confirmBuy(name, price),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Buy', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _powerUpRow(ThemeData theme) {
    final items = [
      {'icon': '\u2744\ufe0f', 'name': 'Freeze', 'desc': 'Lock opponent 5s', 'price': '\$0.99', 'value': 0.99},
      {'icon': '\ud83d\ude08', 'name': 'Troll', 'desc': 'Boost opp smile', 'price': '\$0.99', 'value': 0.99},
      {'icon': '\ud83d\udee1\ufe0f', 'name': 'Shield', 'desc': 'Block 1 attack', 'price': '\$1.49', 'value': 1.49},
      {'icon': '\u26a1', 'name': 'Speed', 'desc': '2x actions rate', 'price': '\$0.79', 'value': 0.79},
    ];

    return Row(children: items.map((p) {
      return Expanded(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text(p['icon'] as String, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 6),
              Text(p['name'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(p['desc'] as String, style: const TextStyle(fontSize: 10, color: Colors.white54)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _confirmBuy(p['name'] as String, p['value'] as double),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(p['price'] as String, style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ),
      );
    }).toList());
  }

  Widget _premiumCard(ThemeData theme) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF16213E), Color(0xFF1A1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4), width: 1.5),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 32),
            const SizedBox(width: 10),
            const Text('PREMIUM PASS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
          ]),
          const SizedBox(height: 16),
          _premiumFeature(Icons.all_inclusive, 'Unlimited matches'),
          _premiumFeature(Icons.emoji_emotions, 'All emotes unlocked'),
          _premiumFeature(Icons.person, 'Custom profile badge'),
          _premiumFeature(Icons.leaderboard, 'Priority leaderboard'),
          _premiumFeature(Icons.block, 'Ad-free experience'),
          _premiumFeature(Icons.support, '24/7 priority support'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _confirmBuy('Premium Pass', 19.99),
              icon: const Icon(Icons.payment),
              label: const Text('Get Premium - \$19.99', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _premiumFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFFFD700).withOpacity(0.8), size: 20),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontSize: 14, color: Colors.white70)),
      ]),
    );
  }

  Widget _paypalFooter() {
    return GestureDetector(
      onTap: _openPayPal,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0070BA).withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF0070BA).withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.account_balance_wallet, color: Color(0xFF0070BA)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Secured by PayPal',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0070BA))),
            const Text('paypal.me/Mohammedid99',
              style: TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
