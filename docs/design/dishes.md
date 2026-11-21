# Dishes and recipes: the design

This is the technical design for steps 1 and 2 of `docs/proposals/dishes-and-recipes.html`, which James approved with its eight recommendations.
A meal can name what was on the table, one dish at a time, and every dish remembers itself.
Step 2, recipes, is at the end ("Recipes"); the "Later" group of the proposal is not built.

## The model

| Thing | Table | Parent | Notes |
|---|---|---|---|
| Dish | `dish` | `household` | A name in one kitchen, with an emoji, a tint, a favourite star and, once merged, the dish it joined. |
| Dish line | `mealDish` | `journalEntry` | One dish on one meal: which dish (a plain id), its place in the meal, and the table's face. |
| A person's own face | `mealDishRating` | `mealDish` | Only when it differs from the table's; its id is derived from the line and the person. |

Every table follows the sync schema rules (`sync-foundation.md`): a text UUID key, one cascading parent, no unique index, plain ids for every other link.
A line names its dish with a plain id, as a meal names its restaurant, because sync can deliver a line before its dish.

### Kitchens

A dish belongs to one kitchen: ours (`home`), one restaurant (`place`, with `placeId`), or `elsewhere` (work, or a delivery or dinner out with no restaurant named).
A meal's kitchen is the restaurant it names, else home when it was home-cooked, else elsewhere (`DishKitchen.of`).
That rule already takes a set of sources, for the multi-select Where that is coming: a named restaurant wins, then home.
The same name in two kitchens is two dishes, each with its own history and faces, linked on their pages as "also had at".

### Names

Two names are the same dish when their keys match (`DishName.key`): case, accents, punctuation and spacing don't count, so "Phở tái", "pho tai " and "Pho Tai!" are one.
Different words stay different dishes ("Pho" and "Pho tai"); merging them is the cook's call.
A name is at most 60 characters, and a meal has at most 12 dishes.

### Ids

A dish made from a name gets an id derived from the household, the kitchen and the name's key (`Dish.id(householdId:kitchen:name:)`).
Two devices that add "Bun cha" at the same restaurant offline therefore write one row.
When that id is taken by a dish that has since been renamed, the new dish gets a random id, and tidying merges any twins later.
The line a meal from before dishes gets has an id derived from the meal (`MealDish.adoptedId`), so every device that adopts the meal writes the same line.

## The meal's copies

The dish lines are the truth (decision 8).
The meal's `title`, `rating`, `emoji` and `tint` are copies written from them in the same transaction, for older builds and for every place that shows a meal by one name and one face (`DishTidy.writeCopies`):

- the title is the dishes joined, the first as written and the rest lowercased unless they look like proper names, cut to 60 characters with an ellipsis ("Pho tai, spring rolls, bun cha");
- the face is the best any dish got, from the table or from anyone (`MealCopies.face`);
- the picture is the first dish's.

A meal with no dishes is titled by its slot ("Dinner") and keeps its own face, exactly as before dishes.
An edit that names no dishes (`MealDraft.dishes == nil`) leaves the lines alone and writes the copies from them again, so a title changed by an older build or an old code path is replaced on the next save.
A line whose dish hasn't arrived yet leaves the copies as they are.

## Writes

- `AppDatabase.addMeal` and `updateMeal` take `MealDraft.dishes`, an ordered list of `DishLineDraft` (a name, the dish picked if any, the table's face).
  A dish picked from another kitchen is looked up by name in the meal's own; the same dish twice is one line.
  Editing keeps the line of every dish still on the meal, and so everyone's own faces on it.
- A meal that changes restaurant, or from home to delivery, takes its lines to the dishes of the same names in the new kitchen (`moveDishes`); dishes left with no meals go, unless they are favourites.
- `renameDish` changes the name everywhere and rewrites every affected title; a name another dish of the kitchen has throws `nameTaken`, so the screen offers to merge.
- `mergeDish` moves every line and face to the survivor; a meal that had both keeps the survivor's line, with any face only the other had; the merged dish stays as a pointer (`mergedInto`), never shown, so a line that arrives late still finds its dish.
- `removeDish` takes a dish off every meal and returns a `DishRemoval`; `restore` puts it back for Undo.
- `setTableFace` and `setPersonFace` change faces and rewrite the meal's face.

## Tidying

`DishTidy.run`, through `AppDatabase.tidyDishes`, does three things, and nothing when all is tidy:

1. gives every meal with a typed name and no lines one line: a meal from before dishes, or one an older build logged since;
2. merges live dishes that share a household, a kitchen and a name key (two devices made them), into the oldest;
3. points lines that name a merged dish at the survivor.

A title that is a meal's name ("Dinner", "Lunch", or one of the journal's slots) is no dish.
A meal whose lines are already waiting in the sync engine's metadata is not adopted: those are lines iCloud sent while this device's build didn't know them, and the engine puts them in when it starts with the new tables.
`FoodStore` checks after every change of the diary (`dishesNeedTidying`, a read) and tidies off the main actor when there is something to do.

## The upgrade

The migration "dishes v1" creates the three tables and their indexes, then adopts every named meal, with the same rules as tidying.
Its rows have derived ids, so every device that updates writes the same ones.
SQLiteData sends every row of a table the first time it starts with that table, so the adopted rows reach iCloud without anything else.

## Older builds

`PorchlightTests/Sync/OlderBuildSyncTests.swift` puts a newer and an older device on one stand-in for iCloud (SQLiteData's `MockCloudContainer`, reached with `@testable import SQLiteData`).
The newer one is today's app, with the dish tables and the meal's `otherSources` (multi-select Where); the older one is the build from before both, without the tables, the field or their mirrors.

- **Records of a type it doesn't know:** the older build keeps them in the engine's metadata and changes nothing; no error.
- **Fields it doesn't know on a record it knows:** an edit on the older build sends only what it changed, from the last record iCloud gave it, so iCloud keeps the newer field, and the newer device still has its dish lines.
- **Updating:** when the older device updates, the engine puts the waiting records in when it first starts with the new tables.
  The upgrade doesn't adopt a meal whose lines are waiting, which would otherwise have given it a third line made from its title.
- **Removing a meal that has dishes:** the older build deletes the meal but not its lines, which it doesn't know, and iCloud refuses to delete a record that other records name as their parent (`referenceViolation`).
  SQLiteData then fetches the meal again, so it comes back on that device; on every other device nothing changed.
  Once that device updates, removing the meal removes its lines with it, everywhere.

So during the update, an older build can do everything with meals except remove one that has dishes, which it gets back, losing nothing.
That is the reason to update every device, wall first.

## CloudKit

Production needs three new record types, all in the household zone of the private database and shared with it, with no indexes (SQLiteData never queries).
`Config/cloudkit-schema.ckdb` has them; `scripts/cloud-schema.sh seed` teaches Development from the mirrors, and James deploys from the CloudKit Console.

| Record type | Fields (each encrypted, each with its `sqlitedata_icloud_userModificationTime_<field>`) |
|---|---|
| `dish` | `id`, `householdId`, `name`, `emoji` (strings), `tint` (int64), `kitchen`, `placeId` (strings), `favorite` (int64), `mergedInto` (string), `createdAt` (timestamp) |
| `mealDish` | `id`, `entryId`, `dishId` (strings), `sortOrder`, `rating` (int64) |
| `mealDishRating` | `id`, `mealDishId`, `personId` (strings), `rating` (int64) |

Each also has `sqlitedata_icloud_userModificationTime` and its parent reference.

Until Production has them, a newer build's dish rows stay on the device: iCloud turns each down ("Cannot create new type"), the meal itself still syncs, and `SyncController` offers the rows again every ten minutes and at launch, saying "iCloud isn't taking N changes yet" meanwhile (`sync-icloud.md`, "When iCloud turns changes down").
Nothing is lost, and the next offer after the deploy goes through.

James accepted this (November 20): dish lines stay on the meal, and an older build can't remove a meal that has dishes until it updates.
The other way, hanging lines off the household, would let an older build remove such a meal, but a newer device could then not tell a meal that was removed from one that hasn't arrived yet, and would risk deleting lines.

## Release notes

For the build that brings dishes, in TestFlight's "What to Test" and the App Store's notes:

> Meals can now name their dishes, and every dish remembers itself: where you had it, how often, and how each of you liked it.
> Open Food › Dishes to find them, or a restaurant to see what you get there.
> Update Porchlight on every device, the wall first: until a device updates, it can't remove a meal that has dishes.

## Screens

The phone (`Porchlight/Phone/Food/PocketDishes.swift`):

- The Food tab has two views, Diary (as before) and Dishes, switched by `PhoneSegments`; its small line says "48 dishes · 11 places" over the dishes.
- Dishes: one search field over dishes and places, filters (All, ★ Favourites, 🏠 Home, 📍 Out), then favourites, home, each restaurant (its name opens its page, with its three best dishes) and elsewhere.
  After the update, a card says once per phone what the diary already knew ("Your diary already knew 19 dishes").
  A household with no dishes sees why the view is empty.
- A dish's page: its picture, name and kitchen (a restaurant opens its page), times had, first and last, each person's usual face, photos of the meals it was on, every time (each opens its meal), "Also had at", and Favourite, Rename and Remove.
  Renaming onto a name the kitchen has offers to merge; removing says how many meals it leaves, and offers Undo.
- A restaurant's page: visits and last visit, last time's order (opens that meal), everything we had there best face first with the one to skip greyed, and Directions.
- A meal's page gains "What we had": each dish with its face, opening the dish, and "Rate each", where everyone who ate gets their own face, dish by dish, starting from the table's.
  The slot's other meals are "meals" now, not "dishes".

The wall (`Porchlight/Features/Food/WallDishes.swift`):

- Dishes sits beside Week and Month: a grid of dish cards (favourites, home, elsewhere; or each restaurant under 📍 Out), and "Ordering in?", our places by visits with the dish we like best.
- A dish opens as a sheet with the same memory, and Favourite, Rename (merging) and Remove (with Undo in the sheet).
- A restaurant opens as "What we get here", with last time's order and its polaroid.
- A meal's sheet gains "What we had" and "How was it?": a row per person who ate, big faces, dish by dish.
  "Another dinner dish" is "Another meal at dinner".
- The wall keeps its one light look, so the proposal's night frames of the wall don't apply.

## The editor

Snap and Edit name a meal's dishes one by one, on the phone (`PocketMealFields`, in Snap's details and in Edit) and on the wall (`CaptureFormView` and `MealEditForm`), through one view, `DishLinesField`, in two styles.
What the form holds is `DishLinesEdit`: the ordered lines, each with the table's face, and the text typed for the next one.

- Where comes first, then the restaurant when a kind has one, then "What we had", then the time, the meal and who ate.
  The dishes' kitchen follows from Where, so suggestions and "Last time here" know where we are before the first letter.
- "What we had" says whose dishes they are: "· from Pho Saigon House", "· home-cooked" or "· from elsewhere" (`DishFormKitchen`).
  With several kinds picked it is the same rule as saving: a named restaurant wins, then home, else elsewhere, so the form never asks which kitchen; it says it.
  A restaurant typed but never eaten at has a kitchen of its own with nothing in it yet, so nothing is suggested as "here".
- Each line is the dish's picture, its name, "3rd time here" or "New here" (counting this meal), × to take it off, and the four faces for the table, optional, with last time's face as a hint.
  Moving a line up or down is in its context menu and its accessibility actions; the first dish names the meal's polaroid.
- "Last time here" offers the dishes of the restaurant's last other meal as chips; a chip goes once its dish is on the meal.
- Typing suggests dishes whose words start with what was typed, this kitchen's first, then the same words elsewhere (picked, those are the same name here, not the same dish), and "Add "…"" for a new one.
  The suggestions sit above the field, because the field rides just over the keyboard.
  The keyboard's Done adds what is typed and puts the keyboard away, on the phone and the wall, since it would otherwise cover Save; the field, now "Add another dish", is one tap for the next.
  On the phone the form scrolls as the suggestions open, so the field stays just over the keyboard (`keepsDishFieldInView`).
- Save never waits for a dish: what is still typed when Save is tapped is the last dish, and no dish at all is a whole meal titled by its slot.
- "Would eat again?" shows only while the meal names no dish; with dishes, the faces are on them.
- On the phone the lines grow with Dynamic Type and, at the accessibility sizes, the faces drop under the name at full width; the wall keeps its sizes, one line per dish with the faces beside it.

## Recipes

Step 2: a home dish can know how it is made.
A recipe is not a second kind of food: it belongs to one home dish, so cooking the dish is cooking the recipe, and "cooked 6 times" is that dish's meals (every meal of a home dish was cooked at home).

### The model

| Thing | Table | Parent | Notes |
|---|---|---|---|
| Recipe | `recipe` | `dish` | Serves, ingredients and steps (plain lines), link, notes, who added it, created and updated at. At most one per dish: its id is derived from the dish's (`Recipe.id(dishId:)`). |
| Card photo | `recipePhoto` | `dish` | Its recipe (a plain id), its place in order, and its two pictures in the row: the small square (`thumbnail`) and the whole card (`image`). |
| Planned dinner's dish | `mealPlan.dishId` | | A plain id, nil for every dinner planned so far. |

Ingredients and steps are stored as text, one line each (`RecipeText`): pasted text loses its bullets and numbering, never its amounts.
There are no quantities or units to keep up.
A line becomes a grocery item by dropping its amount, its unit and how it is cut (`Ingredient.groceryName`: "1 thumb of ginger" is "Ginger").
Limits (`RecipeLimits`): 80 lines each, 200 characters a line, 2,000 for notes, 6 card photos, serves 1 to 99, and the link a web address ("https://" is added when left off).

### Why a card photo hangs off the dish

The proposal had card photos as a meal's photos are: a `recipePhoto` row under the recipe, with its pictures in two tables under it.
That shape loses card photos on a device that updates after recipes were made elsewhere.

A device on the build before recipes keeps the recipe records in the sync engine's metadata (see "Older builds" below).
When it updates, the engine puts those records into the new tables one table at a time, in no set order (SQLiteData 1.13.0, `SyncEngine.updateLocalFromSchemaChange`, iterates a dictionary).
A child table that comes before its parent fails its foreign key, the engine stops there, and the rest wait for a later launch, which tries again in another order.
`OlderBuildSyncTests.updatingBringsInRecipes` failed exactly so with the proposal's shape ("FOREIGN KEY constraint failed" inserting into `recipePhotoThumb`).
The engine's ordinary fetch has no such problem: it sorts records parents first and retries any that fail.

So no new table may hang off another new one.
`recipe` and `recipePhoto` both hang off `dish`, which every such device has, and a card photo names its recipe with a plain id.
Its two pictures are columns of its row (both iCloud assets), and nothing reads them but `PhotoImages` and the recipe's page: `RecipePhoto` selects everything else, `RecipePhotoRow` is the whole row for saving and for Undo, and the storage meter reads their sizes with `LENGTH`, which doesn't load them.
Removing a recipe removes its card photos itself (`RecipeTidy.delete`), since they don't cascade from it; removing the dish takes both.

Step 1 has the same shape in one place: `mealDishRating` hangs off `mealDish`, both new in "dishes v1".
By the same path, a device that updated from before dishes, while other devices had given their own faces, can have needed more than one launch to show them; no test covers that case yet.

### Ids and joining

A recipe added from the bank names its dish.
A home dish of that name (by `DishName.key`) is joined, with its history and faces ("Joins the dish you already cook", `RecipeBank.joins`); otherwise the dish is made with the derived id dishes get from a name.
Two devices that add a recipe to the same dish offline therefore write one row, and each field settles on its own: Mia's new steps and James's new note both survive.
Saving again edits that row; it never makes a second.

### Writes

- `AppDatabase.saveRecipe(_:householdId:addedBy:)` takes a `RecipeDraft`: the name, the dish when editing, serves, lines, link, notes, and the card photos in order (`RecipePhotoItem`: kept or added).
  Only a home dish can have one (`notAHomeDish`).
  Changing the name renames the dish everywhere, as renaming a dish does, unless another home dish has it (`nameTaken`, so the editor can offer that dish).
- `removeRecipe(dishId:)` takes the recipe and its card photos and returns a `RecipeRemoval`; `restore` puts them back while the dish is there (Undo).
  The dish, its meals, its faces and its planned dinners stay.
- `removeDish` now also takes the dish's recipe (and any on a dish merged into it), and unlinks the dinners planned from it: they keep their words.
  `DishRemoval` carries both, and `restore` puts them back; a dinner relinks only if it still has the same words.
- `DishTidy.dropIfUnused` keeps a dish with a recipe, so a recipe not cooked yet is never tidied away, and neither is one whose last meal moved kitchen.
- Merging leaves a recipe where it is.
  The survivor's own recipe wins, else readers find the merged dish's through the merge (`DishBook.recipe(of:)`, `RecipeTidy.recipe(ofLive:)`), as late dish lines do, and editing it from the survivor edits that row.
- Renaming or merging a dish renames the dinners planned from it that still had its old name (`PlannedDish.rename`).
- `HomeDatabase.addListItems(titles:to:addedBy:)` adds several items in one write, each in its guessed aisle, skipping a title the list has unchecked; `deleteListItems(ids:)` is its Undo.
- `setMeal(day:title:emoji:householdId:dishId:)` plans a dinner from a dish; edited by its words with the same name, it keeps the dish.
- `FoodStore` has `recipeBank`, `saveRecipe`, `removeRecipe` and `restore`; `HomeStore` has `setMeal(on:title:emoji:dishId:)`, `addIngredients` and `removeItems`.

### Planned dinners

A planned dinner names a home dish when it was planned from one (`mealPlan.dishId`), and the link holds only while its title still names that dish (`PlannedDish.dish`).
Otherwise a dinner whose words match a home dish links to it, which is how dinners planned before recipes link too.
The title is checked because an older build that renames the dinner sends only the title: iCloud keeps the id, but the words have moved on.

### The bank

`RecipeBank` reads the dish book: every live home dish with a recipe, most cooked first, then most recently, then by name, with recipes not cooked yet last.

- "Haven't made in a while": a recipe whose usual face is at least 🙂, last cooked 21 or more whole days ago in the household's time zone; the best liked first, then the longest ago.
- "You cook these often": home dishes had twice or more with no recipe, most first, three at most.
- Search matches every word typed against the name or any ingredient ("curry powder" finds the chicken curry).
- Words (`RecipeWords`): "Mia's · cooked 6 times · last Nov 2", "From a link · cooked twice", "📷 Card photo · not cooked yet", and on the dish page "Cooked 6 times, last on Nov 2".

### Older builds

`OlderBuildSyncTests` adds a device on the build before recipes: dishes, but no recipe tables and no `mealPlan.dishId`.

- **Recipes and card photos:** it keeps them in the engine's metadata and changes nothing; no error.
- **A planned dinner it edits:** it sends only what it changed, so iCloud keeps `dishId`, and the newer devices still link it while the words name the dish.
- **Removing a dish that has a recipe:** it deletes the dish and its lines, but not the recipe it doesn't know, and iCloud refuses to delete a record that other records name as their parent.
  The dish comes back on that device, with its recipe untouched everywhere; the meals lose that dish, as removing asked.
  An older build can't otherwise reach such a dish: it drops only dishes with no meals that a meal just left, and a dish that came back that way is one again.
- **Updating:** the engine puts the waiting recipes and card photos in, pictures and all, and `mealPlan.dishId` with them.

So during the update an older build can do everything but remove a dish that has a recipe, which it gets back, losing nothing.

### One deploy, one build

Everything step 2 writes is in one Production deploy, made before any build with recipes reaches a device:

| Record type | Fields (each encrypted, each with its `sqlitedata_icloud_userModificationTime_<field>`) |
|---|---|
| `recipe` (new) | `id`, `dishId` (strings), `serves` (int64), `ingredients`, `steps`, `link`, `notes`, `addedById` (strings), `createdAt`, `updatedAt` (timestamps) |
| `recipePhoto` (new) | `id`, `dishId`, `recipeId` (strings), `sortOrder` (int64), `createdAt` (timestamp), `thumbnail`, `image` (assets, each with an encrypted `_hash`) |
| `mealPlan` (changed) | adds `dishId` (string) and its `sqlitedata_icloud_userModificationTime_dishId` |

Each new type also has `sqlitedata_icloud_userModificationTime` and its parent reference.
`Config/cloudkit-schema.ckdb` has them (`SchemaFileTests` derives it from `SyncMirror.all`), and `scripts/cloud-schema.sh import` put them in Development.
Until Production has them, a newer build's recipe rows stay on the device, and the planned dinners it saves are turned down too (a field iCloud doesn't know); both are offered again every ten minutes, nothing is lost, and the next offer after the deploy goes through.
Hence the order: James deploys, then the build ships.

### Screens

To be built in this order, each with its hosted looks (light, dark, largest) and one UI journey per real journey on each shell:

1. The phone's Food tab gains Recipes beside Diary and Dishes: the bank, "Haven't made in a while" with Plan it, "You cook these often" with + Recipe, search by name and ingredient, and the empty bank (P6a, P6b).
2. The recipe editor on the phone: the name, with "Joins the dish you already cook"; serves; ingredients and steps, cleaned when pasted; the link; card photos from the camera or the picker; notes (P6c).
3. The recipe page on the phone: picture, whose, serves, "cooked N times · last …", We made this (Snap with Home-cooked and the dish filled in), Plan it, ingredients picked for groceries with Undo, steps, notes, link, card photos, Edit, and Remove with Undo (P6d, P6e, P6f, P7d).
   A home dish's page shows its recipe or "Add a recipe", and "Cooked N times, last on …".
4. Planned dinners: Lists › Dinners suggests what we cook, marks a dinner with a recipe 📖, and "What does it need?" starts from its ingredients (P6g); Plan it from the bank picks the day.
5. The wall: Recipes beside Week, Month and Dishes as cards; a recipe's kitchen view readable from the stove, ingredients beside steps in large type; the card snapped with the wall's camera; and dinner planned from the bank (W4).
   The wall keeps its one light look.
6. The night look and the largest text for the recipe screens (P9), with ink-bounds checks wherever the handwriting draws a recipe's name.

UI journeys, on the phone and on the wall: adding a recipe to a dish we cook, cooking from the bank, planning a dinner from the bank, and ingredients to the grocery list.

### Release notes

For the build that brings recipes:

> Home dishes can now keep their recipe: type it, paste it from a website, or snap the card.
> Open Food › Recipes to find them, plan a dinner from one, or add what it needs to the grocery list.
> Update Porchlight on every device: until a device updates, it can't remove a dish that has a recipe.
