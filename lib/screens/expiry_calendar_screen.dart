import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/grocery_item.dart';
import '../providers/grocery_provider.dart';
import '../theme/app_theme.dart';
import 'item_detail_screen.dart';

/// Calendar view of upcoming item expiries. Days with expiring items are
/// marked; selecting a day lists the items expiring that day.
class ExpiryCalendarScreen extends StatefulWidget {
  const ExpiryCalendarScreen({super.key});

  @override
  State<ExpiryCalendarScreen> createState() => _ExpiryCalendarScreenState();
}

class _ExpiryCalendarScreenState extends State<ExpiryCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<DateTime, List<GroceryItem>> _buildEventMap(List<GroceryItem> items) {
    final map = <DateTime, List<GroceryItem>>{};
    for (final item in items) {
      final expiry = item.expiryDate;
      if (expiry == null) continue;
      // Only track items still in the home (not already needing purchase).
      if (item.status == GroceryStatus.needsPurchase) continue;
      final key = _dayKey(expiry);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Expiry calendar')),
      body: Consumer<GroceryProvider>(
        builder: (context, provider, _) {
          final events = _buildEventMap(provider.allItems);
          final selected = _selectedDay ?? _focusedDay;
          final dayItems = events[_dayKey(selected)] ?? const [];

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: TableCalendar<GroceryItem>(
                  firstDay: DateTime.now()
                      .subtract(const Duration(days: 365)),
                  lastDay:
                      DateTime.now().add(const Duration(days: 365 * 2)),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) =>
                      _selectedDay != null && isSameDay(_selectedDay, d),
                  eventLoader: (d) => events[_dayKey(d)] ?? const [],
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Month',
                  },
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: BoxDecoration(
                      color: AppTheme.statusColor(GroceryStatus.runningLow),
                      shape: BoxShape.circle,
                    ),
                    markersMaxCount: 3,
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: dayItems.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Nothing expiring on\n${DateFormat.yMMMMd().format(selected)}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: dayItems.length,
                        itemBuilder: (context, index) {
                          final item = dayItems[index];
                          final color = item.isExpired
                              ? AppTheme.statusColor(
                                  GroceryStatus.needsPurchase)
                              : AppTheme.statusColor(
                                  GroceryStatus.runningLow);
                          return ListTile(
                            leading: Icon(Icons.event_busy_outlined,
                                color: color),
                            title: Text(item.name),
                            subtitle: Text(
                                '${_trimQty(item.quantity)} ${item.unit} · ${item.category}'),
                            trailing: Text(
                              item.isExpired ? 'Expired' : 'Expires',
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.w600),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ItemDetailScreen(itemId: item.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _trimQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
