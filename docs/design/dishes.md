# Dishes: the design of step 1

This is the technical design for step 1 of `docs/proposals/dishes-and-recipes.html`, which James approved with its eight recommendations.
A meal can name what was on the table, one dish at a time, and every dish remembers itself.
Recipes are step 2 and are not built.

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
The newer one has the dish tables and a new `otherSources` field on the meal (standing in for the multi-select Where); the older one has today's schema.

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

Not built yet, waiting for the meal sheets: dish lines on Snap and Edit, Where above "What was it?", suggestions while typing and "Last time here" chips.
They go on top of the multi-select Where when it lands.
