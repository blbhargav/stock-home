import 'recipe.dart';

/// Curated recipes bundled with the app. These are read-only.
///
/// Each demonstrates the interactive model: ingredients that need prep (which
/// auto-insert a preparation step) and optional ingredients (whose steps only
/// appear when the user ticks them).
const List<Recipe> kBuiltInRecipes = [
  Recipe(
    id: 'builtin_aloo_jeera',
    name: 'Aloo Jeera',
    description: 'Simple cumin-spiced potatoes.',
    servings: 2,
    category: 'Side dish',
    tags: ['quick', 'vegetarian'],
    isBuiltIn: true,
    ingredients: [
      RecipeIngredient(
        id: 'potato',
        name: 'Potatoes',
        quantity: '3',
        prep: 'peeled and cubed',
      ),
      RecipeIngredient(id: 'oil', name: 'Oil', quantity: '2', unit: 'tbsp'),
      RecipeIngredient(
        id: 'cumin',
        name: 'Cumin seeds',
        quantity: '1',
        unit: 'tsp',
      ),
      RecipeIngredient(
        id: 'turmeric',
        name: 'Turmeric',
        quantity: '1/2',
        unit: 'tsp',
      ),
      RecipeIngredient(id: 'salt', name: 'Salt'),
      RecipeIngredient(
        id: 'green_chilli',
        name: 'Green chilli',
        quantity: '1',
        prep: 'slit',
        optional: true,
      ),
      RecipeIngredient(
        id: 'coriander',
        name: 'Coriander leaves',
        prep: 'chopped',
        optional: true,
      ),
    ],
    steps: [
      RecipeStep(
        text: 'Heat the oil in a pan over medium heat.',
        requiresIngredients: ['oil'],
      ),
      RecipeStep(
        text: 'Add the cumin seeds and let them splutter.',
        requiresIngredients: ['cumin'],
        timerSeconds: 15,
      ),
      RecipeStep(
        text: 'Add the slit green chilli and sauté for a few seconds.',
        requiresIngredients: ['green_chilli'],
        timerSeconds: 10,
      ),
      RecipeStep(
        text: 'Add the potatoes, turmeric and salt. Toss to coat.',
        requiresIngredients: ['potato'],
      ),
      RecipeStep(
        text: 'Cover and cook on low, stirring occasionally, until the potatoes are tender (about 12–15 min).',
        timerSeconds: 20,
      ),
      RecipeStep(
        text: 'Garnish with chopped coriander leaves before serving.',
        requiresIngredients: ['coriander'],
      ),
    ],
  ),
  Recipe(
    id: 'builtin_masala_omelette',
    name: 'Masala Omelette',
    description: 'A spiced Indian-style omelette.',
    servings: 1,
    category: 'Breakfast',
    tags: ['quick', 'egg'],
    isBuiltIn: true,
    ingredients: [
      RecipeIngredient(id: 'eggs', name: 'Eggs', quantity: '2'),
      RecipeIngredient(
        id: 'onion',
        name: 'Onion',
        quantity: '1/2',
        prep: 'finely chopped',
      ),
      RecipeIngredient(
        id: 'tomato',
        name: 'Tomato',
        quantity: '1/2',
        prep: 'finely chopped',
        optional: true,
      ),
      RecipeIngredient(
        id: 'green_chilli',
        name: 'Green chilli',
        quantity: '1',
        prep: 'finely chopped',
        optional: true,
      ),
      RecipeIngredient(id: 'salt', name: 'Salt'),
      RecipeIngredient(id: 'oil', name: 'Oil', quantity: '1', unit: 'tbsp'),
      RecipeIngredient(
        id: 'coriander',
        name: 'Coriander leaves',
        prep: 'chopped',
        optional: true,
      ),
    ],
    steps: [
      RecipeStep(
        text: 'Crack the eggs into a bowl and whisk with salt.',
        requiresIngredients: ['eggs'],
      ),
      RecipeStep(
        text: 'Mix in the chopped onion.',
        requiresIngredients: ['onion'],
      ),
      RecipeStep(
        text: 'Mix in the chopped tomato.',
        requiresIngredients: ['tomato'],
      ),
      RecipeStep(
        text: 'Mix in the chopped green chilli.',
        requiresIngredients: ['green_chilli'],
      ),
      RecipeStep(
        text: 'Mix in the chopped coriander.',
        requiresIngredients: ['coriander'],
      ),
      RecipeStep(
        text: 'Heat the oil in a non-stick pan over medium heat.',
        requiresIngredients: ['oil'],
      ),
      RecipeStep(
        text: 'Pour in the egg mixture, spread evenly, and cook until the base sets.',
        timerSeconds: 15,
      ),
      RecipeStep(
        text: 'Flip and cook the other side for a minute. Serve hot.',
        timerSeconds: 10,
      ),
      RecipeStep(
        text: 'Serve with toast or ketchup on the side.',
        optional: true,
      ),
    ],
  ),
];
