import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';

const mealIcons = [Icons.free_breakfast_outlined, Icons.lunch_dining_outlined, Icons.dinner_dining_outlined, Icons.cookie_outlined];
const ramadanMealIcons = [Icons.nights_stay_outlined, Icons.wb_twilight, Icons.dinner_dining_outlined, Icons.cookie_outlined];

String mealName(BuildContext context, int meal) {
  final ramadan = context.read<AppState>().ramadan;
  return context.tr(ramadan ? 'rmeal$meal' : 'meal$meal');
}

IconData mealIcon(BuildContext context, int meal) => (context.read<AppState>().ramadan ? ramadanMealIcons : mealIcons)[meal];

String lang(BuildContext context) => Localizations.localeOf(context).languageCode;

/// "Today", "Yesterday" or a short date in the current language.
String dayLabel(BuildContext context, DateTime d) {
  final now = DateUtils.dateOnly(DateTime.now());
  final diff = DateUtils.dateOnly(d).difference(now).inDays;
  if (diff == 0) return context.tr('today');
  if (diff == -1) return context.tr('yesterday');
  if (diff == 1) return context.tr('tomorrow');
  return DateFormat.MMMEd(lang(context)).format(d);
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(BuildContext context, String title, {String? body, String? ok}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok ?? context.tr('ok'))),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title, {String initial = '', String? hint, TextInputType? keyboard}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(context.tr('ok'))),
      ],
    ),
  );
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.').replaceAll('٫', '.'));
