import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../controllers/concepts_controller.dart';
import '../../../../core/services/api_client.dart';
import '../../../../shared/models/concept_model.dart';
import '../../../../shared/widgets/tex_formula_view.dart';

class ConceptDetailView extends GetView<ConceptsController> {
  const ConceptDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final concept = Get.arguments as Concept;

    return Scaffold(
      appBar: AppBar(
        title: Text(concept.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            onPressed: () {
              // TODO: 实现收藏功能
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: 实现分享功能
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, concept),
            const SizedBox(height: 24),
            _buildContent(context, concept),
            if (concept.formulas.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildFormulas(context, concept),
            ],
            if (concept.examples.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildExamples(context, concept),
            ],
            const SizedBox(height: 24),
            _buildTags(context, concept),
            const SizedBox(height: 24),
            _buildRelatedConcepts(context, concept),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Concept concept) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(context, concept.category)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    concept.category,
                    style: TextStyle(
                      color: _getCategoryColor(context, concept.category),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  '${concept.readCount}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              concept.summary,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Concept concept) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '详细说明',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildConceptMarkdown(context, concept, concept.content),
          ],
        ),
      ),
    );
  }

  Widget _buildConceptMarkdown(
    BuildContext context,
    Concept concept,
    String data, {
    bool stripRelatedSection = true,
    TextStyle? paragraphStyle,
  }) {
    return Obx(() {
      final titles = controller.concepts.map((item) => item.title).toList();
      final markdown = _prepareConceptMarkdown(
        data,
        currentTitle: concept.title,
        knownTitles: titles,
        stripRelatedSection: stripRelatedSection,
      );
      return MarkdownBody(
        data: markdown,
        onTapLink: (text, href, title) {
          controller.openConceptLink(href);
        },
        imageBuilder: (uri, title, alt) {
          final imageUrl = ApiClient().absoluteUrl(uri.toString());
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.16),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      alt ?? '图片加载失败',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        styleSheet: MarkdownStyleSheet(
          p: paragraphStyle ?? Theme.of(context).textTheme.bodyLarge,
          h1: Theme.of(context).textTheme.headlineMedium,
          h2: Theme.of(context).textTheme.titleLarge,
          h3: Theme.of(context).textTheme.titleMedium,
          a: (paragraphStyle ?? Theme.of(context).textTheme.bodyLarge)
              ?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
          code: TextStyle(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            fontFamily: 'monospace',
          ),
          codeblockDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    });
  }

  String _prepareConceptMarkdown(
    String data, {
    required String currentTitle,
    required Iterable<String> knownTitles,
    required bool stripRelatedSection,
  }) {
    final source =
        stripRelatedSection ? _stripRelatedConceptSection(data) : data;
    return _addInlineConceptLinks(
      source,
      currentTitle: currentTitle,
      knownTitles: knownTitles,
    );
  }

  String _stripRelatedConceptSection(String data) {
    var value = data.trimRight();
    final patterns = [
      RegExp(r'\n{0,2}#{1,6}\s*相关概念\s*\n[\s\S]*?(?=\n#{1,6}\s|$)'),
      RegExp(r'\n{0,2}\*\*相关概念\*\*\s*[：:]\s*.*?(?=\n#{1,6}\s|$)'),
    ];
    for (final pattern in patterns) {
      value = value.replaceFirst(pattern, '').trimRight();
    }
    return value;
  }

  String _addInlineConceptLinks(
    String markdown, {
    required String currentTitle,
    required Iterable<String> knownTitles,
  }) {
    final candidates = knownTitles
        .map((title) => title.trim())
        .where((title) =>
            title.isNotEmpty &&
            title != currentTitle &&
            title.length >= 2 &&
            !title.contains('\n'))
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (candidates.isEmpty || markdown.trim().isEmpty) return markdown;

    final placeholders = <String, String>{};
    var protectedMarkdown = markdown.replaceAllMapped(
      RegExp(r'```[\s\S]*?```|`[^`]*`|!?\[[^\]]+\]\([^)]+\)'),
      (match) {
        final token = '@@BSH_MD_${placeholders.length}@@';
        placeholders[token] = match.group(0)!;
        return token;
      },
    );

    for (final title in candidates) {
      final index = protectedMarkdown.indexOf(title);
      if (index < 0) continue;
      final token = '@@BSH_LINK_${placeholders.length}@@';
      placeholders[token] =
          '[${_escapeMarkdownLabel(title)}](concept:${Uri.encodeComponent(title)})';
      protectedMarkdown =
          protectedMarkdown.replaceRange(index, index + title.length, token);
    }

    for (final entry in placeholders.entries) {
      protectedMarkdown = protectedMarkdown.replaceAll(entry.key, entry.value);
    }
    return protectedMarkdown;
  }

  String _escapeMarkdownLabel(String value) {
    return value.replaceAll('[', r'\[').replaceAll(']', r'\]');
  }

  Widget _buildFormulas(BuildContext context, Concept concept) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.functions,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '相关公式',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...concept.formulas
                .map((formula) => _buildFormulaItem(context, concept, formula)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaItem(
    BuildContext context,
    Concept concept,
    Formula formula,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formula.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          TexFormulaView(expression: formula.expression),
          const SizedBox(height: 8),
          _buildConceptMarkdown(
            context,
            concept,
            formula.description,
            stripRelatedSection: false,
            paragraphStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          if (formula.variables.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '变量说明:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            ...formula.variables.map((variable) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${variable.symbol}: ',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${variable.name} - ${variable.description}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildExamples(BuildContext context, Concept concept) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  '示例',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...concept.examples
                .map((example) => _buildExampleItem(context, concept, example)),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleItem(
    BuildContext context,
    Concept concept,
    Example example,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .tertiaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            example.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          _buildConceptMarkdown(
            context,
            concept,
            example.description,
            stripRelatedSection: false,
            paragraphStyle: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '解答:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                _buildConceptMarkdown(
                  context,
                  concept,
                  example.solution,
                  stripRelatedSection: false,
                  paragraphStyle: Theme.of(context).textTheme.bodyMedium,
                ),
                if (example.result != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '结果: ${example.result}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTags(BuildContext context, Concept concept) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '相关标签',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: concept.tags.map((tag) {
                return Chip(
                  label: Text(tag),
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  side: BorderSide.none,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedConcepts(BuildContext context, Concept concept) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '相关概念',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Concept>>(
              future: controller.loadRelatedConcepts(concept.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                final related = snapshot.data ?? [];
                if (related.isEmpty) {
                  return Text(
                    '暂无相关概念',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                  );
                }
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: related.map((item) {
                    return ActionChip(
                      avatar: Icon(
                        Icons.link,
                        size: 16,
                        color: _getCategoryColor(context, item.category),
                      ),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          item.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: () =>
                          controller.openConceptByTitle(item.title),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(BuildContext context, String category) {
    late final Color color;
    switch (category) {
      case '统计基础':
        color = Colors.indigo;
        break;
      case '研究设计':
        color = Colors.teal;
        break;
      case '假设检验与估计':
      case '假设检验':
        color = Colors.blue;
        break;
      case '回归与建模':
        color = Colors.purple;
        break;
      case '生存分析':
        color = Colors.red;
        break;
      case '纵向与重复测量':
        color = Colors.deepPurple;
        break;
      case '临床试验统计':
        color = Colors.green;
        break;
      case '流行病学':
        color = Colors.cyan;
        break;
      case '数据管理DM':
        color = Colors.brown;
        break;
      case 'CDISC与提交':
        color = Colors.deepOrange;
        break;
      case 'SAS程序':
        color = Colors.blueGrey;
        break;
      case 'R与可重复研究':
        color = Colors.lightGreen;
        break;
      case '统计报告与沟通':
        color = Colors.orange;
        break;
      case '高级方法':
        color = Colors.blueGrey;
        break;
      default:
        color = Colors.blueGrey;
    }
    if (Theme.of(context).brightness == Brightness.dark &&
        color.computeLuminance() < 0.32) {
      return Color.lerp(color, Colors.white, 0.42)!;
    }
    return color;
  }
}
