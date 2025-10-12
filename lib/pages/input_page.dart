import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

/// A page that allows the user to input stock trade information.
///
/// This page includes the following form fields:
/// 1. Ticker – a required text field allowing 3–4 characters only.
/// 2. Buy Date – a required date picker for selecting the purchase date.
/// 3. Buy Price – a required integer field.
/// 4. Sell Date – an optional date picker for selecting the sale date.
/// 5. Sell Price – an optional integer field.
///
/// A submit button is anchored to the bottom right of the page.
class PageOne extends StatefulWidget {
  const PageOne({super.key});

  @override
  State<PageOne> createState() => _PageOneState();
}

class _PageOneState extends State<PageOne> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _tickerController = TextEditingController();
  final TextEditingController _commissionController = TextEditingController();
  final TextEditingController _buyPriceController = TextEditingController();
  final TextEditingController _quantityBoughtController = TextEditingController();
  final TextEditingController _quantitySoldController = TextEditingController();
  final TextEditingController _sellPriceController = TextEditingController();
  DateTime? _buyDate;
  DateTime? _sellDate;

  // Helper to determine if any sell-group field is active
  bool _isSellGroupActive() {
    final hasQtySold = _quantitySoldController.text.trim().isNotEmpty;
    final hasSellPrice = _sellPriceController.text.trim().isNotEmpty;
    final hasSellDate = _sellDate != null;
    return hasQtySold || hasSellPrice || hasSellDate;
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _commissionController.dispose();
    _buyPriceController.dispose();
    _quantityBoughtController.dispose();
    _quantitySoldController.dispose();
    _sellPriceController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isBuyDate) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        if (isBuyDate) {
          _buyDate = picked;
        } else {
          _sellDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    // First, run field-level validators that depend on current state
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    // Ensure Buy Date exists always (independent requirement)
    if (_buyDate == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select a buy date')),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You must be signed in to save a stock')),
      );
      return;
    }
    try {
      final ticker = _tickerController.text.trim().toUpperCase();
      final commissionText = _commissionController.text.trim();
      final commission = commissionText.isEmpty ? 0.0 : double.parse(commissionText);
      final buyPrice = double.parse(_buyPriceController.text.trim());
      final quantityBought = int.parse(_quantityBoughtController.text.trim());
      final quantitySold = _quantitySoldController.text.trim().isEmpty
          ? null
          : int.parse(_quantitySoldController.text.trim());
      final sellPrice = _sellPriceController.text.trim().isEmpty
          ? null
          : double.parse(_sellPriceController.text.trim());

      // No need for cross-field sell date or quantity sold checks here; validators handle them

      final sold = quantitySold ?? 0;
      final remaining = quantityBought - sold;
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('stocks');

      if (sold > 0 && sold < quantityBought) {
        // 1) DONE trade: represents the sold portion only, commission forced to 0
        final doneData = <String, dynamic>{
          'ticker': ticker,
          'commission': 0.0,
          'buyPrice': buyPrice,
          'quantityBought': sold,
          'buyDate': Timestamp.fromDate(_buyDate!),
          'quantitySold': sold,
          'sellDate': _sellDate != null ? Timestamp.fromDate(_sellDate!) : null,
          'sellPrice': sellPrice,
          'status': 'done',
          'createdAt': FieldValue.serverTimestamp(),
        };
        await col.add(doneData);

        // 2) ACTIVE trade: remaining portion, sell fields cleared
        final activeData = <String, dynamic>{
          'ticker': ticker,
          'commission': commission,
          'buyPrice': buyPrice,
          'quantityBought': remaining,
          'buyDate': Timestamp.fromDate(_buyDate!),
          'quantitySold': 0,
          'sellDate': null,
          'sellPrice': null,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        };
        await col.add(activeData);
      } else {
        // Single-entry behavior for pure buy or full exit
        final status = remaining > 0 ? 'active' : 'done';
        final data = <String, dynamic>{
          'ticker': ticker,
          'commission': commission,
          'buyPrice': buyPrice,
          'quantityBought': quantityBought,
          'buyDate': Timestamp.fromDate(_buyDate!),
          'quantitySold': sold,
          'sellDate': _sellDate != null ? Timestamp.fromDate(_sellDate!) : null,
          'sellPrice': sellPrice,
          'status': status,
          'createdAt': FieldValue.serverTimestamp(),
        };
        await col.add(data);
      }

      if (!mounted) return;

      // Show blocking success dialog; require explicit OK to dismiss
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Saved'),
          content: Text('Stock $ticker saved successfully'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Clear the form after acknowledging
      _tickerController.clear();
      _commissionController.clear();
      _buyPriceController.clear();
      _quantityBoughtController.clear();
      _quantitySoldController.clear();
      _sellPriceController.clear();
      if (!mounted) return;
      setState(() {
        _buyDate = null;
        _sellDate = null;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F2534),
            Color(0xFF1E3A4B),
            Color(0xFF213F52),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text(
            'Add Stock',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 10,
                  // Add bottom padding that expands when the keyboard is open
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ticker field: mandatory and length must be 3–4 characters.
                          TextFormField(
                            controller: _tickerController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Ticker', style: TextStyle(color: Colors.white)),
                                  Text('*', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                              hintText: 'e.g. AAPL',
                              hintStyle: TextStyle(color: Colors.white70),
                              labelStyle: TextStyle(color: Colors.white),
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            maxLength: 4,
                            buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                              return Text(
                                '$currentLength/$maxLength',
                                style: const TextStyle(color: Colors.white),
                              );
                            },
                            inputFormatters: [
                              UpperCaseTextFormatter(),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Ticker is required';
                              }
                              if (!RegExp(r'^[A-Z]+$').hasMatch(value)) {
                                return 'Ticker must contain only capital letters';
                              }
                              if (value.length > 4) {
                                return 'Ticker cannot be more than 4 letters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _commissionController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelStyle: TextStyle(color: Colors.white),
                              hintStyle: TextStyle(color: Colors.white70),
                              labelText: 'Commission',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return null; // default to 0 if empty
                              }
                              if (double.tryParse(value) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Buy Date field: mandatory date picker.
                          GestureDetector(
                            onTap: () => _selectDate(context, true),
                            child: AbsorbPointer(
                              child: TextFormField(
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Buy Date', style: TextStyle(color: Colors.white)),
                                      Text('*', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                  hintText: 'Select buy date',
                                  hintStyle: TextStyle(color: Colors.white70),
                                  labelStyle: TextStyle(color: Colors.white),
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white, width: 2),
                                  ),
                                  suffixIcon: Icon(Icons.calendar_today, color: Colors.white70),
                                ),
                                controller: TextEditingController(
                                  text: _buyDate == null
                                      ? ''
                                      : _buyDate!.toLocal().toString().split(' ')[0],
                                ),
                                validator: (value) {
                                  if (_buyDate == null) {
                                    return 'Buy date is required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Buy Price field: mandatory double field.
                          TextFormField(
                            controller: _buyPriceController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Buy Price', style: TextStyle(color: Colors.white)),
                                  Text('*', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                              hintStyle: TextStyle(color: Colors.white70),
                              labelStyle: TextStyle(color: Colors.white),
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Buy price is required';
                              }
                              if (double.tryParse(value) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _quantityBoughtController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Quantity Bought', style: TextStyle(color: Colors.white)),
                                  Text('*', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                              hintStyle: TextStyle(color: Colors.white70),
                              labelStyle: TextStyle(color: Colors.white),
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Quantity bought is required';
                              }
                              if (int.tryParse(value) == null) {
                                return 'Enter a valid integer';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _quantitySoldController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelStyle: TextStyle(color: Colors.white),
                              hintStyle: TextStyle(color: Colors.white70),
                              labelText: 'Quantity Sold',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final active = _isSellGroupActive();
                              if ((value == null || value.isEmpty)) {
                                return active ? 'Quantity sold is required when selling' : null;
                              }
                              final sold = int.tryParse(value);
                              if (sold == null) {
                                return 'Enter a valid integer';
                              }
                              final bought = int.tryParse(_quantityBoughtController.text);
                              if (bought != null && sold > bought) {
                                return 'Quantity sold cannot exceed quantity bought';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Sell Date field: optional date picker.
                          TextFormField(
                            readOnly: true,
                            style: const TextStyle(color: Colors.white),
                            onTap: () => _selectDate(context, false),
                            decoration: InputDecoration(
                              labelStyle: const TextStyle(color: Colors.white),
                              hintStyle: const TextStyle(color: Colors.white70),
                              labelText: 'Sell Date',
                              hintText: 'Select sell date',
                              border: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today, color: Colors.white70),
                                  IconButton(
                                    tooltip: 'Clear',
                                    icon: const Icon(Icons.clear, color: Colors.white70),
                                    onPressed: () {
                                      setState(() {
                                        _sellDate = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            controller: TextEditingController(
                              text: _sellDate == null
                                  ? ''
                                  : _sellDate!.toLocal().toString().split(' ')[0],
                            ),
                            validator: (value) {
                              final active = _isSellGroupActive();
                              if (!active) return null; // optional unless selling info provided
                              if (_sellDate == null) return 'Sell date is required when selling';
                              if (_buyDate == null) return 'Buy date is required when selling';
                              if (_sellDate!.isBefore(_buyDate!)) return 'Sell date cannot be before buy date';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Sell Price field: optional double field.
                          TextFormField(
                            controller: _sellPriceController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelStyle: TextStyle(color: Colors.white),
                              hintStyle: TextStyle(color: Colors.white70),
                              labelText: 'Sell Price',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final active = _isSellGroupActive();
                              if (value == null || value.isEmpty) {
                                return active ? 'Sell price is required when selling' : null;
                              }
                              if (double.tryParse(value) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                          // Fill remaining space so the bottom button stays at the bottom when keyboard is closed.
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
    ));
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
