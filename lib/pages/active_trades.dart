import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String kFinnhubApiKey = 'd3a8l5pr01qli8jd590gd3a8l5pr01qli8jd5910';

class PageTwo extends StatefulWidget {
  const PageTwo({super.key});

  @override
  State<PageTwo> createState() => _PageTwoState();
}

class _PageTwoState extends State<PageTwo> {
  // Live prices map and polling state
  final Map<String, double> _livePrices = {};
  Timer? _poller;
  Set<String> _symbols = {};
  int? _selectedRow;

  Future<void> _saveLivePriceToDb(String symbol, double price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('stocks');
    // Update all active docs for this ticker
    final q = await col
        .where('status', isEqualTo: 'active')
        .where('ticker', isEqualTo: symbol)
        .get();
    for (final doc in q.docs) {
      await doc.reference.update({
        'livePrice': price,
        'livePriceUpdatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<double?> _fetchFinnhubPrice(String symbol) async {
    if (kFinnhubApiKey == 'YOUR_FINNHUB_API_KEY' || kFinnhubApiKey.isEmpty) {
      // No key provided; skip network call.
      return null;
    }
    final uri = Uri.parse('https://finnhub.io/api/v1/quote?symbol=$symbol&token=$kFinnhubApiKey');
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;
      // Finnhub returns current price in the "c" field.
      final price = (data['c'] ?? 0).toDouble();
      if (price == 0) return null;
      return price;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _fetchAll(Set<String> symbols) async {
    for (final s in symbols) {
      final p = await _fetchFinnhubPrice(s);
      if (!mounted) return;
      if (p != null) {
        await _saveLivePriceToDb(s, p);
        setState(() {
          _livePrices[s] = p;
        });
      }
    }
  }

  void _ensurePolling(Set<String> symbols) {
    // Update symbols set
    final newSet = Set<String>.from(symbols);
    final changed = newSet.length != _symbols.length || !newSet.containsAll(_symbols);
    _symbols = newSet;

    // Start/stop polling based on window
    _maybeStartOrStopPolling();
    // If symbols changed and we are within window, kick an immediate refresh
    if (changed && _isWithinTradingWindow()) {
      _fetchAll(_symbols);
    }
  }

  bool _isWithinTradingWindow() {
    final now = DateTime.now(); // Device local time; assume Asia/Jerusalem
    // Monday=1 ... Sunday=7
    if (now.weekday < DateTime.monday || now.weekday > DateTime.friday) return false;
    final minutes = now.hour * 60 + now.minute;
    const start = 16 * 60 + 30; // 16:30
    const end = 23 * 60;        // 23:00
    return minutes >= start && minutes <= end;
  }

  void _maybeStartOrStopPolling() {
    if (_isWithinTradingWindow()) {
      if (_poller == null) {
        _poller = Timer.periodic(const Duration(minutes: 15), (_) {
          // Guard inside timer in case window closes while running
          if (_isWithinTradingWindow()) {
            _fetchAll(_symbols);
          } else {
            _poller?.cancel();
            _poller = null;
          }
        });
        // Immediate refresh when entering window
        _fetchAll(_symbols);
      }
    } else {
      // Outside trading window: stop polling
      _poller?.cancel();
      _poller = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Active Trades')),
        body: const Center(
          child: Text('Please sign in to view your active trades'),
        ),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('stocks')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Trades')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('No active trades'));
          }

          // Collect unique ticker symbols and start polling Finnhub
          final Set<String> symbols = {
            for (final d in docs) ((d.data()['ticker'] ?? '') as String).toUpperCase()
          }..removeWhere((e) => e.isEmpty);
          _ensurePolling(symbols);

          String formatNumber(num value) {
            if (value is int) return value.toString();
            final s = value.toStringAsFixed(2);
            if (s.endsWith('.00')) return s.substring(0, s.length - 3);
            if (s.endsWith('.0')) return s.substring(0, s.length - 2);
            return s;
          }

          String formatSigned(num value) {
            final absVal = value.abs();
            final s = formatNumber(absVal);
            if (value > 0) return '+$s';
            if (value < 0) return '-$s';
            return '0';
          }

          Color valueColor(num value) {
            if (value > 0) return Colors.green;
            if (value < 0) return Colors.red;
            return Colors.grey;
          }

          String formatSignedPct(double value) {
            final s = value.abs().toStringAsFixed(2);
            if (value > 0) return '+$s%';
            if (value < 0) return '-$s%';
            return '0%';
          }

          final List<TableRow> rows = [
            const TableRow(
              decoration: BoxDecoration(color: Color(0xFFEFEFEF)),
              children: [
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'Ticker',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'QNT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'prc',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'com',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'live prc',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'W/L',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'CHG %',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ];

          double totalInvested = 0.0;
          double totalWL = 0.0;
          for (final doc in docs) {
            final data = doc.data();
            final ticker = (data['ticker'] ?? '') as String;
            final qtyBought = (data['quantityBought'] ?? 0) as int;
            final qtySold = (data['quantitySold'] ?? 0) as int;

            final commissionVal = (data['commission'] ?? 0).toDouble();
            final buyPriceVal = (data['buyPrice'] ?? 0).toDouble();

            final remaining = qtyBought - qtySold;

            final total = remaining * buyPriceVal + commissionVal;
            totalInvested += total;

            final buyPriceDisplay = formatNumber(buyPriceVal);
            final commissionDisplay = formatNumber(commissionVal);

            final livePriceVal = (data['livePrice'] ?? _livePrices[ticker.toUpperCase()] ?? buyPriceVal).toDouble();
            final livePriceDisplay = formatNumber(livePriceVal);
            final chg = buyPriceVal > 0 ? ((livePriceVal - buyPriceVal) / buyPriceVal) * 100.0 : 0.0;
            final chgDisplay = chg.toStringAsFixed(2) + '%';

            final baseRowColor = chg < 0
                ? Colors.red.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1);

            final winLose = (livePriceVal - buyPriceVal) * remaining;
            totalWL += winLose;
            final winLoseDisplay = formatSigned(winLose);
            final winLoseColor = valueColor(winLose);

            int rowIndex = rows.length; // before adding
            final isSelected = _selectedRow == rowIndex;
            final rowColor = isSelected
                ? Colors.blue.withValues(alpha: 0.18)
                : baseRowColor;

            rows.add(
              TableRow(
                decoration: BoxDecoration(
                  color: rowColor,
                  border: isSelected ? Border.all(color: Colors.blue, width: 1.0) : null,
                ),
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(ticker),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text('$remaining'),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(buyPriceDisplay),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(commissionDisplay),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(livePriceDisplay),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        winLoseDisplay,
                        style: TextStyle(color: winLoseColor),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRow = rowIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(chgDisplay),
                    ),
                  ),
                ],
              ),
            );
          }

          final totalInvestedDisplay = formatNumber(totalInvested);
          final totalWLDisplay = formatSigned(totalWL);
          final totalWLColor = valueColor(totalWL);
          final totalChgPct = totalInvested != 0
              ? (totalWL / totalInvested) * 100
              : 0.0;
          final totalChgPctDisplay = formatSignedPct(totalChgPct);
          final totalChgPctColor = valueColor(totalChgPct);
          final portfolioColor = valueColor(totalChgPct);

          final portfolio = totalInvested + totalWL;
          final portfolioDisplay = formatNumber(portfolio);
          final portfolioSummary = Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Portfolio',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: portfolioColor),
                  ),
                  Text(
                    portfolioDisplay,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: portfolioColor,
                    ),
                  ),
                ],
              ),
            ),
          );

          final headerSummary = Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Total invested',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      totalInvestedDisplay,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Total W/L',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      totalWLDisplay,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: totalWLColor,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Total CHG%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      totalChgPctDisplay,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: totalChgPctColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              portfolioSummary,
              headerSummary,
              const SizedBox(height: 12),
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 16,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Table(
                        defaultColumnWidth: const IntrinsicColumnWidth(),
                        border: TableBorder.all(color: Colors.grey, width: 0.5),
                        children: rows,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _selectedRow == null
                        ? null
                        : () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                final priceController = TextEditingController();
                                final selectedIndex = (_selectedRow != null && _selectedRow! - 1 < docs.length)
                                    ? _selectedRow! - 1
                                    : -1;
                                final dataSel = selectedIndex >= 0 ? docs[selectedIndex].data() : <String, dynamic>{};
                                final tickerSel = (dataSel['ticker'] ?? '') as String;
                                final qtyBoughtSel = (dataSel['quantityBought'] ?? 0) as int;
                                final qtySoldSel = (dataSel['quantitySold'] ?? 0) as int;
                                final remainingSel = (qtyBoughtSel - qtySoldSel).clamp(0, 1 << 31);
                                final List<int> qtyOptions = List<int>.generate(remainingSel, (i) => i + 1);
                                int? selectedQty = qtyOptions.isNotEmpty ? qtyOptions.first : null;

                                return StatefulBuilder(
                                  builder: (context, setStateDialog) {
                                    return AlertDialog(
                                      title: Text('Sell $tickerSel'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          DropdownButtonFormField<int>(
                                            initialValue: selectedQty,
                                            items: qtyOptions
                                                .map((q) => DropdownMenuItem<int>(
                                                      value: q,
                                                      child: Text(q.toString()),
                                                    ))
                                                .toList(),
                                            onChanged: (val) => setStateDialog(() => selectedQty = val),
                                            decoration: const InputDecoration(labelText: 'Quantity to sell'),
                                          ),
                                          TextField(
                                            controller: priceController,
                                            decoration: const InputDecoration(labelText: 'Selling price'),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: (selectedQty == null)
                                              ? null
                                              : () {
                                                  // handle sell logic here with selectedQty and priceController.text
                                                  Navigator.pop(context);
                                                },
                                          child: const Text('Confirm'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                    child: const Text('Sell'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
