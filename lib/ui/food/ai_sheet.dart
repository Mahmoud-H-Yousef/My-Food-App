import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../services/ai.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'amount_sheet.dart';
import 'food_search_page.dart';

const _permissions = MethodChannel('myfood/permissions');

/// Asks the AI what's in a description or photo, lets the user check it, and
/// returns the chosen items. [recipe] reads a pasted recipe's ingredients.
Future<List<AiItem>?> runAi(BuildContext context, {bool recipe = false}) async {
  final input = await showModalBottomSheet<_AiInput>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AiInputSheet(recipe: recipe),
  );
  if (input == null || !context.mounted) return null;
  final app = context.read<AppState>();
  final l = lang(context);
  List<AiItem>? items;
  Object? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      Ai.instance
          .recognise(app.prefs, l, text: input.text, image: input.image, recipe: recipe)
          .then((r) => items = r, onError: (Object e) => error = e)
          .whenComplete(() {
        if (c.mounted) Navigator.pop(c);
      });
      return AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(context.tr(Ai.instance.engineFor(app.prefs, photo: input.image != null) == 'gemma' ? 'aiThinkingLocal' : 'aiThinking'))),
        ]),
      );
    },
  );
  if (!context.mounted) return null;
  if (error != null) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('aiFailed')),
        content: SingleChildScrollView(child: Text(error is AiNotReady ? context.tr('aiNotReady') : '$error')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(context.tr('ok')))],
      ),
    );
    return null;
  }
  if (items == null || items!.isEmpty) {
    toast(context, context.tr('aiNothing'));
    return null;
  }
  return Navigator.push<List<AiItem>>(context, MaterialPageRoute(builder: (_) => AiReviewPage(items: items!, recipe: recipe)));
}

/// Recognise, review, then log to [meal].
Future<bool> aiLog(BuildContext context, int meal) async {
  final app = context.read<AppState>();
  final items = await runAi(context);
  if (items == null || !context.mounted) return false;
  final chosenMeal = app.prefs.getInt('aiLastMeal') ?? meal;
  for (final it in items) {
    final n = it.nutrition;
    await app.addEntry(LogEntry(
      day: app.dayStr,
      meal: chosenMeal,
      foodId: it.match?.id,
      name: it.match?.name(lang(context)) ?? it.name,
      grams: it.grams,
      qty: it.grams,
      unit: 'g',
      kcal: n.kcal,
      p: n.p,
      c: n.c,
      f: n.f,
    ));
  }
  if (context.mounted) toast(context, context.tr('loggedN', {'n': '${items.length}'}));
  return true;
}

class _AiInput {
  final String? text;
  final Uint8List? image;
  const _AiInput({this.text, this.image});
}

class _AiInputSheet extends StatefulWidget {
  final bool recipe;
  const _AiInputSheet({required this.recipe});

  @override
  State<_AiInputSheet> createState() => _AiInputSheetState();
}

class _AiInputSheetState extends State<_AiInputSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _photo(ImageSource source) async {
    if (source == ImageSource.camera) {
      final ok = await _permissions.invokeMethod<bool>('camera') ?? false;
      if (!ok) {
        if (mounted) toast(context, context.tr('cameraDenied'));
        return;
      }
    }
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) Navigator.pop(context, _AiInput(image: bytes, text: _text.text.trim().isEmpty ? null : _text.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final noEngine = Ai.instance.engineFor(app.prefs, photo: true) == 'none';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: brandGreen),
          const SizedBox(width: 8),
          Text(context.tr(widget.recipe ? 'aiRecipeTitle' : 'aiTitle'), style: Theme.of(context).textTheme.titleLarge),
        ]),
        const SizedBox(height: 12),
        if (noEngine)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(context.tr('aiNotReady'))),
          ),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: widget.recipe ? 5 : 2,
          maxLines: widget.recipe ? 12 : 4,
          decoration: InputDecoration(hintText: context.tr(widget.recipe ? 'aiRecipeHint' : 'aiHint')),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            if (_text.text.trim().isEmpty) return;
            Navigator.pop(context, _AiInput(text: _text.text.trim()));
          },
          icon: const Icon(Icons.auto_awesome),
          label: Text(context.tr('aiRecognise')),
        ),
        if (!widget.recipe) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _photo(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: Text(context.tr('takePhoto')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _photo(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(context.tr('choosePhoto')))),
          ]),
          const SizedBox(height: 8),
          Text(context.tr('aiPhotoTip'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

/// Check what the AI found: untick, fix grams, or swap for a food from the database.
class AiReviewPage extends StatefulWidget {
  final List<AiItem> items;
  final bool recipe;
  const AiReviewPage({super.key, required this.items, this.recipe = false});

  @override
  State<AiReviewPage> createState() => _AiReviewPageState();
}

class _AiReviewPageState extends State<AiReviewPage> {
  late int _meal = context.read<AppState>().suggestedMeal;

  Future<void> _editGrams(AiItem it) async {
    final s = await promptText(context, it.match?.name(lang(context)) ?? it.name, initial: fmtNum(it.grams), keyboard: TextInputType.number);
    final v = parseNum(s ?? '');
    if (v == null || v <= 0) return;
    setState(() {
      if (it.match == null && it.grams > 0) it.n = it.n.scale(v / it.grams);
      it.grams = v;
    });
  }

  Future<void> _swap(AiItem it) async {
    final picked = await Navigator.push<Picked>(
        context, MaterialPageRoute(builder: (_) => FoodSearchPage(pickOnly: true, showMeal: false, title: it.name)));
    if (picked == null) return;
    setState(() {
      it.match = picked.food;
      it.grams = picked.grams;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = lang(context);
    final chosen = widget.items.where((i) => i.selected).toList();
    final total = chosen.fold(Nutrition.zero, (a, i) => a + i.nutrition);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('aiReview'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(context.tr('aiReviewHelp'), style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final it in widget.items)
          Card(
            child: Column(children: [
              CheckboxListTile(
                value: it.selected,
                onChanged: (v) => setState(() => it.selected = v ?? false),
                title: Text(it.match?.name(l) ?? it.name),
                subtitle: Text('${fmtNum(it.grams)} g · ${it.nutrition.kcal.round()} ${context.tr('kcal')}'
                    '${it.match == null ? ' · ${context.tr('aiEstimate')}' : ''}'),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(onPressed: () => _editGrams(it), icon: const Icon(Icons.scale_outlined, size: 18), label: Text(context.tr('grams'))),
                TextButton.icon(onPressed: () => _swap(it), icon: const Icon(Icons.swap_horiz, size: 18), label: Text(context.tr('aiSwap'))),
                if (it.match != null)
                  TextButton(onPressed: () => setState(() => it.match = null), child: Text(context.tr('aiUseEstimate'))),
                const SizedBox(width: 8),
              ]),
            ]),
          ),
        if (!widget.recipe)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(spacing: 8, children: [
              for (var m = 0; m < 4; m++)
                ChoiceChip(label: Text(mealName(context, m)), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
            ]),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: chosen.isEmpty
                ? null
                : () {
                    context.read<AppState>().prefs.setInt('aiLastMeal', _meal);
                    Navigator.pop(context, chosen);
                  },
            icon: const Icon(Icons.check),
            label: Text('${context.tr(widget.recipe ? 'aiAddIngredients' : 'aiAddN', {'n': '${chosen.length}'})} · ${total.kcal.round()} ${context.tr('kcal')}'),
          ),
        ),
      ),
    );
  }
}
