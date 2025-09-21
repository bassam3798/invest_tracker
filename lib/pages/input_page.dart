import 'package:flutter/material.dart';

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
  final TextEditingController _buyPriceController = TextEditingController();
  final TextEditingController _sellPriceController = TextEditingController();
  DateTime? _buyDate;
  DateTime? _sellDate;

  @override
  void dispose() {
    _tickerController.dispose();
    _buyPriceController.dispose();
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

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_buyDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a buy date')),
        );
        return;
      }
      // All validations passed. Process the form data here (e.g. save to database).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Stock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add space from the top to position the form lower on the page.
            const SizedBox(height: 40),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ticker field: mandatory and length must be 3–4 characters.
                  TextFormField(
                    controller: _tickerController,
                    decoration: const InputDecoration(
                      labelText: 'Ticker',
                      hintText: 'e.g. AAPL',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ticker is required';
                      }
                      if (value.length < 3 || value.length > 4) {
                        return 'Ticker must be 3 or 4 characters';
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
                        decoration: const InputDecoration(
                          labelText: 'Buy Date',
                          hintText: 'Select buy date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
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
                  // Buy Price field: mandatory integer field.
                  TextFormField(
                    controller: _buyPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Buy Price',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Buy price is required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Enter a valid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Sell Date field: optional date picker.
                  GestureDetector(
                    onTap: () => _selectDate(context, false),
                    child: AbsorbPointer(
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Sell Date',
                          hintText: 'Select sell date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        controller: TextEditingController(
                          text: _sellDate == null
                              ? ''
                              : _sellDate!.toLocal().toString().split(' ')[0],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sell Price field: optional integer field.
                  TextFormField(
                    controller: _sellPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Sell Price',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return null; // optional field
                      }
                      if (int.tryParse(value) == null) {
                        return 'Enter a valid number';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            // Spacer pushes the submit button to the bottom of the page.
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              // Apply padding to push the button slightly up and to the left
              child: Padding(
                padding: const EdgeInsets.only(right: 28, bottom: 45),
                child: ElevatedButton(
                  onPressed: _submit,
                  // Increase padding and text size to enlarge the button
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 50,
                      vertical: 20,
                    ),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: const Text('Submit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
