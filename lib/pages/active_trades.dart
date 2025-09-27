import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

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
        appBar: AppBar(
          title: const Text(
            'Active Trades',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Active Trades',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          const _SpaceBackground(),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

          final TableRow headerRow = TableRow(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF2F80ED), Color(0xFF56CCF2)],
              ),
            ),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('Ticker', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('QNT', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('prc', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('com', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('live prc', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('W/L', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('CHG %', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ],
          );

          final List<TableRow> dataRows = [];

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
            final winLose = (livePriceVal - buyPriceVal) * remaining;
            totalWL += winLose;
            final winLoseDisplay = formatSigned(winLose);
            final winLoseColor = valueColor(winLose);

            final baseRowColor = chg < 0
                ? Colors.red.withValues(alpha: 0.10)
                : (chg > 0
                    ? Colors.green.withValues(alpha: 0.10)
                    : Colors.grey.withValues(alpha: 0.08));
            // Header is visual index 0; data rows start at 1
            final rowIndex = dataRows.length + 1;
            final isSelected = _selectedRow == rowIndex;
            final rowColor = isSelected
                ? Colors.blue.withValues(alpha: 0.18)
                : baseRowColor;

            Widget cell(String text, {TextStyle? style}) => GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRow = rowIndex;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(text, style: style),
                  ),
                );

            dataRows.add(
              TableRow(
                decoration: BoxDecoration(
                  color: rowColor,
                  border: isSelected ? Border.all(color: Colors.blue, width: 1.0) : null,
                ),
                children: [
                  cell(ticker.toUpperCase()),
                  cell('$remaining'),
                  cell(buyPriceDisplay),
                  cell(commissionDisplay),
                  cell(livePriceDisplay),
                  cell(winLoseDisplay, style: TextStyle(color: winLoseColor, fontWeight: FontWeight.w600)),
                  cell(chgDisplay),
                ],
              ),
            );
          }

          final totalInvestedDisplay = formatNumber(totalInvested);
          final totalWLDisplay = formatSigned(totalWL);
          final totalChgPct = totalInvested != 0
              ? (totalWL / totalInvested) * 100
              : 0.0;
          final totalChgPctDisplay = formatSignedPct(totalChgPct);
          final portfolioColor = valueColor(totalChgPct);

          final summaryCard = Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Center: Total invested
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      const Text('Total invested', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Text(
                        totalInvestedDisplay,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Below: W/L left, CHG right
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(totalWL >= 0 ? Icons.trending_up : Icons.trending_down,
                                color: totalWL >= 0 ? Colors.green : Colors.red, size: 18),
                            const SizedBox(width: 6),
                            const Text('Total W/L', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 6),
                            Text(
                              totalWLDisplay,
                              style: TextStyle(
                                color: totalWL >= 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Icon(Icons.percent, color: Colors.white70, size: 18),
                            const SizedBox(width: 6),
                            const Text('Total CHG% ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 6),
                            Text(
                              totalChgPctDisplay,
                              style: TextStyle(
                                color: portfolioColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    summaryCard,
                    const SizedBox(height: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Card(
                          elevation: 0,
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Fixed header row
                                    Table(
                                      defaultColumnWidth: const IntrinsicColumnWidth(),
                                      border: TableBorder.all(color: Colors.white.withValues(alpha: 0.24), width: 0.6),
                                      children: [headerRow],
                                    ),
                                    // Scrollable body rows
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Table(
                                          defaultColumnWidth: const IntrinsicColumnWidth(),
                                          border: TableBorder.all(color: Colors.white.withValues(alpha: 0.24), width: 0.6),
                                          children: dataRows,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bottom glass action bar
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _selectedRow == null
                                        ? null
                                        : () {
                                            showDialog(
                                              context: context,
                                              builder: (context) {
                                                final priceController = TextEditingController();
                                                final qtyController = TextEditingController();
                                                final commissionController = TextEditingController(text: '0');
                                                final dateController = TextEditingController();
                                                DateTime? selectedSellDate;
                                                String fmtDate(DateTime d) {
                                                  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                                                }
                                                final selectedIndex = (_selectedRow != null && _selectedRow! - 1 < docs.length)
                                                    ? _selectedRow! - 1
                                                    : -1;
                                                final dataSel = selectedIndex >= 0 ? docs[selectedIndex].data() : <String, dynamic>{};
                                                final tickerSel = (dataSel['ticker'] ?? '') as String;
                                                final boughtSel = (dataSel['quantityBought'] ?? 0) as int;
                                                final soldSel = (dataSel['quantitySold'] ?? 0) as int;
                                                final remainingSel = boughtSel - soldSel;
                                                double? enteredPrice;
                                                int? selectedQty;

                                                bool allMandatoryValid() {
                                                  return (selectedQty != null && selectedQty! > 0 && selectedQty! <= remainingSel) &&
                                                      (enteredPrice != null && (enteredPrice ?? 0) > 0) &&
                                                      (selectedSellDate != null);
                                                }

                                                return StatefulBuilder(
                                                  builder: (context, setStateDialog) {
                                                    return AlertDialog(
                                                      title: Text('Sell $tickerSel'),
                                                      content: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Align(
                                                            alignment: Alignment.centerLeft,
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                TextButton(
                                                                  onPressed: () {
                                                                    setStateDialog(() {
                                                                      qtyController.text = remainingSel.toString();
                                                                      selectedQty = remainingSel > 0 ? remainingSel : null;
                                                                    });
                                                                  },
                                                                  child: const Text('Sell all'),
                                                                ),
                                                                const SizedBox(width: 8),
                                                                TextButton(
                                                                  onPressed: () {
                                                                    setStateDialog(() {
                                                                      final half = (remainingSel ~/ 2).clamp(0, remainingSel);
                                                                      qtyController.text = half.toString();
                                                                      selectedQty = half > 0 ? half : null;
                                                                    });
                                                                  },
                                                                  child: const Text('Sell half'),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          TextField(
                                                            controller: qtyController,
                                                            decoration: const InputDecoration(labelText: 'Quantity to sell'),
                                                            keyboardType: TextInputType.number,
                                                            onChanged: (val) {
                                                              setStateDialog(() {
                                                                selectedQty = int.tryParse(val);
                                                              });
                                                            },
                                                          ),
                                                          TextField(
                                                            controller: priceController,
                                                            decoration: const InputDecoration(labelText: 'Selling price'),
                                                            keyboardType: TextInputType.number,
                                                            onChanged: (val) {
                                                              setStateDialog(() {
                                                                enteredPrice = double.tryParse(val);
                                                              });
                                                            },
                                                          ),
                                                          TextField(
                                                            controller: commissionController,
                                                            decoration: const InputDecoration(labelText: 'Commission'),
                                                            keyboardType: TextInputType.number,
                                                          ),
                                                          TextField(
                                                            controller: dateController,
                                                            readOnly: true,
                                                            decoration: InputDecoration(
                                                              labelText: 'Sell date',
                                                              suffixIcon: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  IconButton(
                                                                    icon: const Icon(Icons.calendar_today),
                                                                    onPressed: () async {
                                                                      final now = DateTime.now();
                                                                      final picked = await showDatePicker(
                                                                        context: context,
                                                                        initialDate: selectedSellDate ?? now,
                                                                        firstDate: DateTime(now.year - 5),
                                                                        lastDate: DateTime(now.year + 5),
                                                                      );
                                                                      if (picked != null) {
                                                                        setStateDialog(() {
                                                                          selectedSellDate = picked;
                                                                          dateController.text = fmtDate(picked);
                                                                        });
                                                                      }
                                                                    },
                                                                  ),
                                                                  IconButton(
                                                                    icon: const Icon(Icons.clear),
                                                                    tooltip: 'Clear date',
                                                                    onPressed: () {
                                                                      setStateDialog(() {
                                                                        selectedSellDate = null;
                                                                        dateController.clear();
                                                                      });
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            onTap: () async {
                                                              final now = DateTime.now();
                                                              final picked = await showDatePicker(
                                                                context: context,
                                                                initialDate: selectedSellDate ?? now,
                                                                firstDate: DateTime(now.year - 5),
                                                                lastDate: DateTime(now.year + 5),
                                                              );
                                                              if (picked != null) {
                                                                setStateDialog(() {
                                                                  selectedSellDate = picked;
                                                                  dateController.text = fmtDate(picked);
                                                                });
                                                              }
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context),
                                                          child: const Text('Cancel'),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: (!allMandatoryValid())
                                                              ? null
                                                              : () async {
                                                                  final int qtyToSell = selectedQty!;
                                                                  final double sellPrice = enteredPrice!;

                                                                  final user = FirebaseAuth.instance.currentUser;
                                                                  if (user == null) return;
                                                                  final col = FirebaseFirestore.instance
                                                                      .collection('users')
                                                                      .doc(user.uid)
                                                                      .collection('stocks');

                                                                  final origData = dataSel;
                                                                  final qtyBought = (origData['quantityBought'] ?? 0) as int;
                                                                  final qtySold = (origData['quantitySold'] ?? 0) as int;
                                                                  final remaining = qtyBought - qtySold;
                                                                  if (qtyToSell <= 0 || qtyToSell > remaining) {
                                                                    return;
                                                                  }

                                                                  final batch = FirebaseFirestore.instance.batch();

                                                                  final doneRef = col.doc();
                                                                  final Map<String, dynamic> doneData = Map<String, dynamic>.from(origData);
                                                                  doneData['status'] = 'done';
                                                                  doneData['quantityBought'] = qtyToSell;
                                                                  doneData['quantitySold'] = qtyToSell;
                                                                  doneData['sellPrice'] = sellPrice;
                                                                  doneData['sellDate'] = Timestamp.fromDate(selectedSellDate!);
                                                                  doneData['commission'] = 0.0;
                                                                  doneData['createdAt'] = FieldValue.serverTimestamp();
                                                                  doneData['updatedAt'] = FieldValue.serverTimestamp();
                                                                  batch.set(doneRef, doneData);

                                                                  if (qtyToSell < remainingSel) {
                                                                    final int newQtyBought = qtyBought - qtyToSell;
                                                                    batch.update(docs[selectedIndex].reference, {
                                                                      'quantityBought': newQtyBought,
                                                                      'quantitySold': 0,
                                                                      'sellPrice': null,
                                                                      'sellDate': null,
                                                                      'status': 'active',
                                                                      'updatedAt': FieldValue.serverTimestamp(),
                                                                    });
                                                                  } else {
                                                                    batch.delete(docs[selectedIndex].reference);
                                                                  }

                                                                  try {
                                                                    await batch.commit();
                                                                    if (!context.mounted) return;
                                                                    Navigator.pop(context);
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      const SnackBar(content: Text('Sell executed successfully')),
                                                                    );
                                                                  } catch (e) {
                                                                    if (!context.mounted) return;
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      SnackBar(content: Text('Sell failed: $e')),
                                                                    );
                                                                  }
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
                                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                                    icon: const Icon(Icons.shopping_cart_checkout),
                                    label: const Text('Sell'),
                                  ),
                                  const SizedBox(width: 12),
                                  Tooltip(
                                    message: 'Delete selected trade',
                                    child: ElevatedButton.icon(
                                      onPressed: _selectedRow == null
                                          ? null
                                          : () async {
                                              final selectedIndex = (_selectedRow != null && _selectedRow! - 1 < docs.length)
                                                  ? _selectedRow! - 1
                                                  : -1;
                                              if (selectedIndex < 0) return;

                                              final docSnap = docs[selectedIndex];
                                              final tickerSel = (docSnap.data()['ticker'] ?? '') as String;

                                              final confirmed = await showDialog<bool>(
                                                context: context,
                                                builder: (context) {
                                                  return AlertDialog(
                                                    title: const Text('Delete trade'),
                                                    content: Text('Are you sure you want to delete $tickerSel? This action cannot be undone.'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context, false),
                                                        child: const Text('Cancel'),
                                                      ),
                                                      ElevatedButton.icon(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.red,
                                                          foregroundColor: Colors.white,
                                                        ),
                                                        onPressed: () => Navigator.pop(context, true),
                                                        icon: const Icon(Icons.delete_outline),
                                                        label: const Text('Delete'),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                              if (!context.mounted) return;

                                              if (confirmed == true) {
                                                try {
                                                  await docSnap.reference.delete();
                                                  if (!context.mounted) return;
                                                  if (!mounted) return;
                                                  setState(() {
                                                    _selectedRow = null;
                                                  });
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Trade deleted')),
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Failed to delete: $e')),
                                                  );
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Delete'),
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
          );
        },
          ),
        ],
      ),
    );
  }
}



class _SpaceBackground extends StatelessWidget {
  const _SpaceBackground();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(child: _StarField());
  }
}

class _StarField extends StatefulWidget {
  const _StarField();

  @override
  State<_StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<_StarField> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Offset> _positions;
  late final List<double> _radii;
  late final List<double> _twinkle;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    final rnd = Random(42);
    const count = 140;
    _positions = List.generate(count, (_) => Offset(rnd.nextDouble(), rnd.nextDouble()));
    _radii = List.generate(count, (_) => rnd.nextDouble() * 0.9 + 0.1);
    _twinkle = List.generate(count, (_) => rnd.nextDouble() * 2 * pi);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SpacePainter(
            positions: _positions,
            radii: _radii,
            twinkle: _twinkle,
            t: _controller.value,
          ),
        );
      },
    );
  }
}

class _SpacePainter extends CustomPainter {
  _SpacePainter({required this.positions, required this.radii, required this.twinkle, required this.t});
  final List<Offset> positions;
  final List<double> radii;
  final List<double> twinkle;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0B1026), Color(0xFF0E2A4F), Color(0xFF0A3D7A)],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    void glow(Offset c, double r, List<Color> colors) {
      final shader = RadialGradient(colors: colors).createShader(Rect.fromCircle(center: c, radius: r));
      final p = Paint()..shader = shader;
      canvas.drawCircle(c, r, p);
    }

    glow(Offset(size.width * 0.2, size.height * 0.25), size.shortestSide * 0.25, [
      const Color(0x332F80ED), const Color(0x112F80ED), const Color(0x00000000)
    ]);
    glow(Offset(size.width * 0.8, size.height * 0.65), size.shortestSide * 0.3, [
      const Color(0x3356CCF2), const Color(0x1156CCF2), const Color(0x00000000)
    ]);

    final starPaint = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (int i = 0; i < positions.length; i++) {
      final pos = Offset(positions[i].dx * size.width, positions[i].dy * size.height);
      final phase = twinkle[i];
      final alpha = (0.6 + 0.4 * sin(2 * pi * t + phase));
      final r = (radii[i] * 1.5 + 0.5) * (alpha);
      canvas.drawCircle(pos, r, starPaint..color = Colors.white.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(covariant _SpacePainter oldDelegate) => oldDelegate.t != t;
}