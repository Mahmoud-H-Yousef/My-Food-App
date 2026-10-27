import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../food/amount_sheet.dart';
import '../theme.dart';
import 'recipe_editor_page.dart';

/// "My Pot": home-cooked recipes with calories per ladle, plate or 100 g.
class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  List<Recipe>? _recipes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repo.recipes();
    if (mounted) setState(() => _recipes = r);
  }

  Future<void> _open([Recipe? r]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeEditorPage(recipe: r)));
    _load();
  }

  Future<void> _log(Recipe r) async {
    final app = context.read<AppState>();
    final food = await Repo.food(r.foodId!);
    if (food == null || !mounted) return;
    final picked = await showAmountSheet(context, food, meal: app.suggestedMeal);
    if (picked == null || !mounted) return;
    await app.addEntry(picked.toEntry(app.dayStr, lang(context)));
    if (mounted) toast(context, context.tr('addedTo', {'meal': mealName(context, picked.meal)}));
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _recipes;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('myPotTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newPot',
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: Text(context.tr('newPot')),
      ),
      body: recipes == null
          ? const Center(child: CircularProgressIndicator())
          : recipes.isEmpty
              ? _empty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 96),
                    itemCount: recipes.length,
                    itemBuilder: (_, i) {
                      final r = recipes[i];
                      final per = r.per100;
                      final serving = r.servings > 0 ? r.finalGrams / r.servings : r.finalGrams;
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          leading: const CircleAvatar(backgroundColor: Color(0x22FF5722), child: Icon(Icons.soup_kitchen, color: Colors.deepOrange)),
                          title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${fmtNum(per.kcal)} ${context.tr('kcal')} / 100 g\n'
                            '${fmtNum(per.kcal * serving / 100)} ${context.tr('kcal')} / ${context.tr('serving')} (${fmtNum(serving)} ${context.tr('g')}) · '
                            '${context.tr('nIngredients', {'n': '${r.ingredients.length}'})}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton.filledTonal(icon: const Icon(Icons.add), tooltip: context.tr('logIt'), onPressed: () => _log(r)),
                          onTap: () => _open(r),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.soup_kitchen_outlined, size: 72, color: brandGreen),
            const SizedBox(height: 16),
            Text(context.tr('myPotEmptyTitle'), style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(context.tr('myPotEmptyBody'), textAlign: TextAlign.center),
          ]),
        ),
      );
}
