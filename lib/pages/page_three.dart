import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PageThree extends StatefulWidget {
  const PageThree({super.key});

  @override
  State<PageThree> createState() => _PageThreeState();
}

class _PageThreeState extends State<PageThree> {
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Done Trades Statistics')),
        body: const Center(child: Text('Please sign in to view your statistics')),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('stocks')
        .where('status', isEqualTo: 'done')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Done Trades Statistics')),
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
            return const Center(child: Text('No completed (done) trades'));
          }

          // Build rows
          final rows = <DataRow>[];

          double totalInvested = 0;
          double totalWL = 0;

          for (final doc in docs) {
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

            rows.add(
              DataRow(cells: [
                DataCell(Text(ticker)),
                DataCell(Text(qtyBought.toString())),
                DataCell(Text(_fmtNum(buyPrice))),
                DataCell(Text(_fmtNum(sellPrice))),
                DataCell(Text(_fmtNum(commission))),
                DataCell(Text(_fmtNum(invested))),
                DataCell(Text('${_fmtSigned(chgPct)}% ', style: TextStyle(color: _valueColor(wl)))),
                DataCell(Text(_fmtSigned(wl), style: TextStyle(color: _valueColor(wl)))),
              ]),
            );
          }

          final totalChgPct = totalInvested != 0 ? (totalWL / totalInvested) * 100.0 : 0.0;

          return Column(
            children: [
              // Totals summary bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Total Invested: ${_fmtNum(totalInvested)}'),
                    Text('Total W/L: ${_fmtSigned(totalWL)}', style: TextStyle(color: _valueColor(totalWL))),
                    Text('Total CHG%: ${_fmtSigned(totalChgPct)}%', style: TextStyle(color: _valueColor(totalWL))),
                  ],
                ),
              ),
              const Divider(height: 0),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: MediaQuery.of(context).size.width,
                      ),
                      child: DataTable(
                        horizontalMargin: 8,
                        columnSpacing: 8,
                        headingRowHeight: 40,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 56,
                        columns: const [
                          DataColumn(label: Text('Ticker')),
                          DataColumn(label: Text('Qty')),
                          DataColumn(label: Text('Buy')),
                          DataColumn(label: Text('Sell')),
                          DataColumn(label: Text('Com')),
                          DataColumn(label: Text('Invested')),
                          DataColumn(label: Text('CHG%')),
                          DataColumn(label: Text('W/L')),
                        ],
                        rows: rows,
                      ),
                    ),
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
