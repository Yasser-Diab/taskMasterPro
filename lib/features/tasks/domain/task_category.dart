class TaskCategory {
  const TaskCategory({required this.name, required this.colorSeed});

  final String name;
  final int colorSeed;
}

const defaultLifeAreaTemplates = <TaskCategory>[
  TaskCategory(name: 'Work', colorSeed: 0xFF3B82F6),
  TaskCategory(name: 'Learning', colorSeed: 0xFF22D3EE),
  TaskCategory(name: 'Family', colorSeed: 0xFFEC4899),
  TaskCategory(name: 'Household', colorSeed: 0xFF84CC16),
  TaskCategory(name: 'Health', colorSeed: 0xFF22C55E),
  TaskCategory(name: 'Social', colorSeed: 0xFFF97316),
  TaskCategory(name: 'Personal', colorSeed: 0xFF64748B),
  TaskCategory(name: 'Finance', colorSeed: 0xFFEAB308),
  TaskCategory(name: 'University', colorSeed: 0xFFA855F7),
  TaskCategory(name: 'Business', colorSeed: 0xFF14B8A6),
  TaskCategory(name: 'Reading', colorSeed: 0xFF6366F1),
  TaskCategory(name: 'Travel', colorSeed: 0xFF0EA5E9),
];
