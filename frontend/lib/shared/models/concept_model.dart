class Concept {
  final int id;
  final String title;
  final String category;
  final String content;
  final String summary;
  final List<String> tags;
  final List<Formula> formulas;
  final List<Example> examples;
  final List<String> relatedConceptIds;
  final DateTime updatedAt;
  final int readCount;

  Concept({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    required this.summary,
    this.tags = const [],
    this.formulas = const [],
    this.examples = const [],
    this.relatedConceptIds = const [],
    required this.updatedAt,
    this.readCount = 0,
  });

  factory Concept.fromJson(Map<String, dynamic> json) {
    return Concept(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      category: _readCategory(json['category']),
      content: json['content'] ?? '',
      summary: json['summary'] ?? '',
      tags: _readTags(json['tags']),
      formulas: (json['formulas'] as List?)
              ?.map((f) => Formula.fromJson(f))
              .toList() ??
          [],
      examples: (json['examples'] as List?)
              ?.map((e) => Example.fromJson(e))
              .toList() ??
          [],
      relatedConceptIds: List<String>.from(json['related_concept_ids'] ?? []),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      readCount: json['read_count'] ?? 0,
    );
  }

  static String _readCategory(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value['name'] ?? '';
    }
    return value?.toString() ?? '';
  }

  static List<String> _readTags(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .map((tag) {
          if (tag is Map<String, dynamic>) {
            return tag['name']?.toString() ?? '';
          }
          return tag.toString();
        })
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'content': content,
      'summary': summary,
      'tags': tags,
      'formulas': formulas.map((f) => f.toJson()).toList(),
      'examples': examples.map((e) => e.toJson()).toList(),
      'related_concept_ids': relatedConceptIds,
      'updated_at': updatedAt.toIso8601String(),
      'read_count': readCount,
    };
  }
}

class Formula {
  final String name;
  final String expression;
  final String description;
  final List<FormulaVariable> variables;

  Formula({
    required this.name,
    required this.expression,
    required this.description,
    this.variables = const [],
  });

  factory Formula.fromJson(Map<String, dynamic> json) {
    return Formula(
      name: json['name'] ?? '',
      expression: json['expression'] ?? '',
      description: json['description'] ?? '',
      variables: (json['variables'] as List?)
              ?.map((v) => FormulaVariable.fromJson(v))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'expression': expression,
      'description': description,
      'variables': variables.map((v) => v.toJson()).toList(),
    };
  }
}

class FormulaVariable {
  final String symbol;
  final String name;
  final String description;

  FormulaVariable({
    required this.symbol,
    required this.name,
    required this.description,
  });

  factory FormulaVariable.fromJson(Map<String, dynamic> json) {
    return FormulaVariable(
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'name': name,
      'description': description,
    };
  }
}

class Example {
  final String title;
  final String description;
  final String solution;
  final String? result;

  Example({
    required this.title,
    required this.description,
    required this.solution,
    this.result,
  });

  factory Example.fromJson(Map<String, dynamic> json) {
    return Example(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      solution: json['solution'] ?? '',
      result: json['result'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'solution': solution,
      'result': result,
    };
  }
}
