// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

/// Grupperet felt-container med lille overskrift — samler fx dato+tid visuelt
/// så det er tydeligt de hører sammen (design 10a/10b).
Widget _fieldGroup(String heading, List<Widget> children) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(heading,
            style: _body(
                size: 11, weight: FontWeight.w700, spacing: 1, color: _textSecondary)),
      ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgBlack,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderSubtle),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ],
  );
}

class _QuickDateTimeField extends StatefulWidget {
  final String label;
  final DateTime? value;
  final DateTime? fallbackDate;
  final ValueChanged<DateTime?> onChanged;
  const _QuickDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.fallbackDate,
  });

  @override
  State<_QuickDateTimeField> createState() => _QuickDateTimeFieldState();
}

class _QuickDateTimeFieldState extends State<_QuickDateTimeField> {
  DateTime? _date;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    _date = v == null ? null : DateTime(v.year, v.month, v.day);
    _time = v == null ? null : TimeOfDay(hour: v.hour, minute: v.minute);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  void _emit() {
    if (_date == null || _time == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute));
  }

  Future<void> _pickDate() async {
    final initial = _date ?? widget.fallbackDate ?? DateTime.now();
    final picked = await _showQuickDatePicker(context, initial);
    if (picked == null) return;
    setState(() => _date = picked);
    _emit();
    // Hvis tid endnu ikke er sat, åbn tidsvælger direkte bagefter
    if (mounted && _time == null) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) _pickTime();
    }
  }

  Future<void> _pickTime() async {
    final picked = await _showQuickTimePicker(context, _time);
    if (picked == null) return;
    setState(() => _time = picked);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: widget.label,
                prefixIcon: const Icon(Icons.event),
              ),
              child: Text(
                _date == null ? 'Vælg dato' : _fmtDate(_date!),
                style: TextStyle(color: _date == null ? _textMuted : null),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Tid',
                prefixIcon: Icon(Icons.schedule, size: 18),
              ),
              child: Text(
                _time == null
                    ? 'Vælg tid'
                    : '${_two(_time!.hour)}:${_two(_time!.minute)}',
                style: TextStyle(
                    color: _time == null ? _textMuted : _neon,
                    fontWeight: FontWeight.w700,
                    letterSpacing: _time == null ? 0 : 1.2),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Interval-låst tidsvælger — timer 0-23, minutter [00, 15, 30, 45].
/// Bottom sheet med to wheels i Clay Court-stilen.
Future<TimeOfDay?> _showQuickTimePicker(BuildContext ctx, TimeOfDay? initial) {
  const minuteOptions = [0, 15, 30, 45];
  int selectedHour = initial?.hour ?? 19;
  int selectedMinIdx = minuteOptions.indexOf(initial?.minute ?? 0);
  if (selectedMinIdx == -1) selectedMinIdx = 0;

  return showModalBottomSheet<TimeOfDay>(
    context: ctx,
    backgroundColor: _surfaceDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Container(
          height: 360,
          decoration: const BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              top: BorderSide(color: _borderSubtle),
              left: BorderSide(color: _borderSubtle),
              right: BorderSide(color: _borderSubtle),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header med terracotta-stribe
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 4, height: 22,
                      decoration: const BoxDecoration(
                        color: _neon,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('VÆLG TID',
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                    const Spacer(),
                    Text('15-min interval',
                        style: TextStyle(
                            color: _textSecondary,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: _borderSubtle),
              // Hurtig-valg
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Text('Hurtig:',
                      style: TextStyle(color: _textMuted, fontSize: 12)),
                  const SizedBox(width: 8),
                  for (final t in const [
                    TimeOfDay(hour: 18, minute: 0),
                    TimeOfDay(hour: 19, minute: 30),
                    TimeOfDay(hour: 20, minute: 0),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'),
                        onPressed: () => Navigator.pop(sheetCtx, t),
                        backgroundColor: _surfaceElevated,
                        side: BorderSide.none,
                      ),
                    ),
                ]),
              ),
              const Divider(height: 1, color: _borderSubtle),
              // Wheels
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        itemExtent: 44,
                        backgroundColor: _surfaceDark,
                        scrollController: FixedExtentScrollController(
                            initialItem: selectedHour),
                        onSelectedItemChanged: (i) => selectedHour = i,
                        selectionOverlay: Container(
                          decoration: BoxDecoration(
                            color: _neon.withValues(alpha: 0.12),
                            border: Border(
                              top: BorderSide(
                                  color: _neon.withValues(alpha: 0.5), width: 1),
                              bottom: BorderSide(
                                  color: _neon.withValues(alpha: 0.5), width: 1),
                            ),
                          ),
                        ),
                        children: List.generate(24, (i) => Center(
                          child: Text(
                            i.toString().padLeft(2, '0'),
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2),
                          ),
                        )),
                      ),
                    ),
                    const Text(':',
                        style: TextStyle(
                            color: _neon,
                            fontSize: 36,
                            fontWeight: FontWeight.bold)),
                    Expanded(
                      child: CupertinoPicker(
                        itemExtent: 44,
                        backgroundColor: _surfaceDark,
                        scrollController: FixedExtentScrollController(
                            initialItem: selectedMinIdx),
                        onSelectedItemChanged: (i) => selectedMinIdx = i,
                        selectionOverlay: Container(
                          decoration: BoxDecoration(
                            color: _neon.withValues(alpha: 0.12),
                            border: Border(
                              top: BorderSide(
                                  color: _neon.withValues(alpha: 0.5), width: 1),
                              bottom: BorderSide(
                                  color: _neon.withValues(alpha: 0.5), width: 1),
                            ),
                          ),
                        ),
                        children: minuteOptions.map((m) => Center(
                          child: Text(
                            m.toString().padLeft(2, '0'),
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2),
                          ),
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _borderSubtle),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('Annullér'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          sheetCtx,
                          TimeOfDay(
                            hour: selectedHour,
                            minute: minuteOptions[selectedMinIdx],
                          ),
                        ),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _TimeMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > 4 ? digits.substring(0, 4) : digits;

    final formatted = trimmed.length <= 2
        ? trimmed
        : '${trimmed.substring(0, 2)}:${trimmed.substring(2)}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

Future<DateTime?> _showQuickDatePicker(BuildContext ctx, DateTime initial) {
  final now = DateTime.now();
  return showDialog<DateTime>(
    context: ctx,
    builder: (dialogCtx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: MediaQuery(
            data: MediaQuery.of(dialogCtx).copyWith(alwaysUse24HourFormat: true),
            child: CalendarDatePicker(
              initialDate: initial,
              firstDate: now.subtract(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 365)),
              onDateChanged: (d) => Navigator.of(dialogCtx).pop(d),
            ),
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Training board — drag-and-drop kanban (Fase 2)
// ─────────────────────────────────────────────────────────────────────────────

