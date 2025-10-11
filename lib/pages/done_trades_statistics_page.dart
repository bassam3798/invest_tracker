import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DoneTradesStatisticsPage extends StatefulWidget {
  const DoneTradesStatisticsPage({super.key});

  @override
  State<DoneTradesStatisticsPage> createState() => _DoneTradesStatisticsPageState();
}

class _DoneTradesStatisticsPageState extends State<DoneTradesStatisticsPage> {
  int? _selectedRow;
  // Sticky header <-> body horizontal controllers
  final ScrollController _hHeader = ScrollController();
  final ScrollController _hBody = ScrollController();
  bool _syncingH = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _doneTradesStream;
  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _doneTradesStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('stocks')
          .where('status', isEqualTo: 'done')
          .orderBy('createdAt', descending: true)
          .snapshots();
    }
    _hBody.addListener(() {
      if (_syncingH) return;
      _syncingH = true;
      if (_hHeader.hasClients && _hHeader.offset != _hBody.offset) {
        _hHeader.jumpTo(_hBody.offset);
      }
      _syncingH = false;
    });
  }

  @override
  void dispose() {
    _hHeader.dispose();
    _hBody.dispose();
    super.dispose();
  }

  String _fmtNum(num v) {
    if (v.isNaN || v.isInfinite) return '-';
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  String _fmtSigned(num v) {
    final sign = v > 0 ? '+' : '';
    return '$sign${_fmtNum(v)}';
  }

  Color _valueColor(num v) => v > 0
      ? Colors.green
      : (v < 0
          ? Colors.red
          : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey);

  Future<bool> _confirmDelete(BuildContext context, String ticker) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete trade'),
            content: Text('Are you sure you want to delete $ticker? This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final headingStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    final cellStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.92),
      fontSize: 13,
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Done Trades Statistics')),
        body: const Center(child: Text('Please sign in to view your statistics')),
      );
    }

    return _buildAppThemeBackground(
      context,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Done Trades Statistics',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _doneTradesStream,
          builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('No completed (done) trades'));
          }

          // Build rows for Table
          final bodyRows = <TableRow>[];

          double totalInvested = 0;
          double totalWL = 0;

          for (int i = 0; i < docs.length; i++) {
            final doc = docs[i];
            final data = doc.data();
            final ticker = (data['ticker'] ?? '').toString();
            final qtyBought = (data['quantityBought'] ?? 0) as int;
            final qtySold = (data['quantitySold'] ?? 0) as int;
            final commission = (data['commission'] ?? 0).toDouble();

            // support both `buyPrice` and `priceBought` keys
            final buyPrice = (data['buyPrice'] ?? data['priceBought'] ?? 0).toDouble();
            // support both `sellPrice` and `priceSold` keys
            final sellPrice = (data['sellPrice'] ?? data['priceSold'] ?? 0).toDouble();

            final invested = buyPrice * qtyBought + commission;
            final proceeds = sellPrice * qtySold;
            final wl = proceeds - invested;
            final chgPct = invested != 0 ? (wl / invested) * 100.0 : 0.0;

            totalInvested += invested;
            totalWL += wl;

            bodyRows.add(
              TableRow(
                decoration: BoxDecoration(
                  color: (_selectedRow == i)
                      ? Colors.blue.withValues(alpha: 0.20)
                      : (wl >= 0
                          ? Colors.green.withValues(alpha: 0.10)
                          : Colors.red.withValues(alpha: 0.10)),
                  border: Border(
                    bottom: BorderSide(
                      color: wl >= 0 ? Colors.green : Colors.red,
                      width: 1.2,
                    ),
                  ),
                ),
                children: [
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(ticker, style: cellStyle))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(qtyBought.toString(), style: cellStyle, textAlign: TextAlign.center))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(_fmtNum(buyPrice), style: cellStyle, textAlign: TextAlign.center))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(_fmtNum(sellPrice), style: cellStyle, textAlign: TextAlign.center))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(_fmtNum(commission), style: cellStyle, textAlign: TextAlign.center))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(_fmtNum(invested), style: cellStyle, textAlign: TextAlign.center))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text('${_fmtSigned(chgPct)}% ',
                              style: cellStyle.copyWith(
                                  color: _valueColor(wl), fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center))),
                  GestureDetector(
                      onTap: () => setState(() => _selectedRow = _selectedRow == i ? null : i),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Text(_fmtSigned(wl),
                              style: cellStyle.copyWith(
                                  color: _valueColor(wl), fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center))),
                ],
              ),
            );
          }

          final totalChgPct = totalInvested != 0 ? (totalWL / totalInvested) * 100.0 : 0.0;

          final Map<int, TableColumnWidth> columnWidths = <int, TableColumnWidth>{
            0: const FixedColumnWidth(90),   // Ticker
            1: const FixedColumnWidth(60),   // Qty
            2: const FixedColumnWidth(70),   // Buy
            3: const FixedColumnWidth(70),   // Sell
            4: const FixedColumnWidth(60),   // Com
            5: const FixedColumnWidth(90),   // Invested
            6: const FixedColumnWidth(80),   // CHG%
            7: const FixedColumnWidth(80),   // W/L
          };

          return Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Column(
            children: [
              // Totals summary bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Centered Total W/L (label normal color, value colored)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Total W/L: ', style: TextStyle(color: Colors.white70)),
                          TextSpan(
                            text: _fmtSigned(totalWL),
                            style: TextStyle(color: _valueColor(totalWL), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    // Row below: left = Total Invested, right = Total CHG%
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Total Invested: ', style: TextStyle(color: Colors.white70)),
                                TextSpan(
                                  text: _fmtNum(totalInvested),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: 'Total CHG%: ', style: TextStyle(color: Colors.white70)),
                                  TextSpan(
                                    text: '${_fmtSigned(totalChgPct)}%',
                                    style: TextStyle(color: _valueColor(totalChgPct), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),
              // Sticky header + scrollable body using shared column widths
              // 1) Header (only horizontal scroll)
              SingleChildScrollView(
                controller: _hHeader,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Table(
                  columnWidths: columnWidths,
                  border: TableBorder(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.20), width: 1),
                    verticalInside: BorderSide(color: Colors.white.withValues(alpha: 0.20), width: 1),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Colors.transparent),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('Ticker', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('Qty', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('Buy', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('Sell', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('Com', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('Invested', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('CHG%', style: headingStyle, textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Text('W/L', style: headingStyle, textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          // 2) Body (horizontal + vertical scroll)
          Expanded(
            child: SingleChildScrollView(
              controller: _hBody,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                child: Table(
                  columnWidths: columnWidths,
                  border: TableBorder(
                    verticalInside: BorderSide(color: Colors.white.withValues(alpha: 0.20), width: 1),
                  ),
                  children: bodyRows,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _selectedRow == null
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final idx = _selectedRow!;
                                if (idx < 0 || idx >= docs.length) return;
                                final data = docs[idx].data();
                                final ticker = (data['ticker'] ?? '').toString();
                                final bool confirmed = await _confirmDelete(context, ticker.isEmpty ? 'this trade' : ticker);
                                if (!confirmed) return;
                                final toDelete = docs[idx].reference;
                                try {
                                  await toDelete.delete();
                                  if (!mounted) return;
                                  setState(() => _selectedRow = null);
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Deleted ${ticker.isEmpty ? 'trade' : ticker}')),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Failed to delete: $e')),
                                  );
                                }
                              },
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
        },
      ),
    ));
  }
}

// App theme background (light space-blue like the home screen)
Widget _buildAppThemeBackground(BuildContext context, {required Widget child}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0F2534), // top teal/space blue
          Color(0xFF1E3A4B), // middle
          Color(0xFF213F52), // bottom
        ],
        stops: [0.0, 0.55, 1.0],
      ),
    ),
    child: child,
  );
}

