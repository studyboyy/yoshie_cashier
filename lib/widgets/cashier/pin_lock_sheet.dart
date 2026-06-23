import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PinLockSheet extends StatefulWidget {
  const PinLockSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.confirmPin = false,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final bool confirmPin;

  @override
  State<PinLockSheet> createState() => _PinLockSheetState();
}

class _PinLockSheetState extends State<PinLockSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    final confirmation = _confirmController.text.trim();

    if (pin.length < 4) {
      setState(() => _error = 'PIN minimal 4 digit.');
      return;
    }

    if (widget.confirmPin && pin != confirmation) {
      setState(() => _error = 'Konfirmasi PIN belum sama.');
      return;
    }

    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: widget.confirmPin
                ? TextInputAction.next
                : TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: 'PIN',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            onSubmitted: (_) {
              if (!widget.confirmPin) {
                _submit();
              }
            },
          ),
          if (widget.confirmPin) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(
                labelText: 'Konfirmasi PIN',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.lock_open_outlined),
            label: Text(widget.actionLabel),
          ),
        ],
      ),
    );
  }
}
