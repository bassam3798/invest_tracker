import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PageTwo extends StatelessWidget {
  const PageTwo({super.key});

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

            final livePriceVal =
                buyPriceVal; // placeholder until live data implemented
            final livePriceDisplay = formatNumber(livePriceVal);
            final chg = 0.0; // placeholder change %
            final chgDisplay = '${chg.toStringAsFixed(2)}%';

            final rowColor = chg < 0
                ? Colors.red.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1);

            final winLose = (livePriceVal - buyPriceVal) * remaining;
            totalWL += winLose;
            final winLoseDisplay = formatSigned(winLose);
            final winLoseColor = valueColor(winLose);

            rows.add(
              TableRow(
                decoration: BoxDecoration(color: rowColor),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(ticker),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('$remaining'),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(buyPriceDisplay),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(commissionDisplay),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(livePriceDisplay),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      winLoseDisplay,
                      style: TextStyle(color: winLoseColor),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(chgDisplay),
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
            ],
          );
        },
      ),
    );
  }
}
