import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PageThree extends StatefulWidget {
  const PageThree({super.key});

  @override
  State<PageThree> createState() => _PageThreeState();
}

class _PageThreeState extends State<PageThree> {
  int? _selectedRow;

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

          for (int i = 0; i < docs.length; i++) {
            final doc = docs[i];
            final data = doc.data();
            final isSelected = _selectedRow == i;
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
              DataRow(
                onSelectChanged: (_) {
                  setState(() => _selectedRow = _selectedRow == i ? null : i);
                },
                color: isSelected
                    ? WidgetStateProperty.all(Colors.blue.withValues(alpha: 0.2))
                    : null,
                cells: [
                  DataCell(Text(ticker)),
                  DataCell(Text(qtyBought.toString())),
                  DataCell(Text(_fmtNum(buyPrice))),
                  DataCell(Text(_fmtNum(sellPrice))),
                  DataCell(Text(_fmtNum(commission))),
                  DataCell(Text(_fmtNum(invested))),
                  DataCell(Text('${_fmtSigned(chgPct)}% ', style: TextStyle(color: _valueColor(wl)))),
                  DataCell(Text(_fmtSigned(wl), style: TextStyle(color: _valueColor(wl)))),
                ],
              ),
            );
          }

          final totalChgPct = totalInvested != 0 ? (totalWL / totalInvested) * 100.0 : 0.0;

          return Column(
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
                          const TextSpan(text: 'Total W/L: '),
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
                                const TextSpan(text: 'Total Invested: '),
                                TextSpan(
                                  text: _fmtNum(totalInvested),
                                  style: const TextStyle(fontWeight: FontWeight.w500),
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
                                  const TextSpan(text: 'Total CHG%: '),
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
                        border: TableBorder.all(color: Colors.grey.shade400, width: 1),
                        showBottomBorder: true,
                        showCheckboxColumn: false,
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
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _selectedRow == null
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final idx = _selectedRow!;
                                if (idx < 0 || idx >= docs.length) return;
                                final toDelete = docs[idx].reference;
                                try {
                                  await toDelete.delete();
                                  if (!mounted) return;
                                  setState(() => _selectedRow = null);
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Row deleted')),
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
                        ),
                      ),
                    ],
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
