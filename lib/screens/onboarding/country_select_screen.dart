import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../config/country_data.dart';
import '../../services/auth_service.dart';
import '../../app.dart' show MainShell;

class CountrySelectScreen extends StatefulWidget {
  const CountrySelectScreen({super.key});

  @override
  State<CountrySelectScreen> createState() => _CountrySelectScreenState();
}

class _CountrySelectScreenState extends State<CountrySelectScreen> {
  String _search = '';

  Future<void> _selectCountry(CountryData c) async {
    await AuthService.setCountry(c.code, c.name);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    final filtered = _search.isEmpty
        ? CountryData.countries
        : CountryData.countries.where((c) =>
            c.name.toLowerCase().contains(_search.toLowerCase()) ||
            c.nameAr.contains(_search)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.selectCountry)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search country...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final c = filtered[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 32)),
                  title: Text(c.name),
                  subtitle: Text(c.nameAr, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  onTap: () => _selectCountry(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
