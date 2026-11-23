import 'package:flutter/material.dart';
import '../models/concept_model.dart';

class ConceptCard extends StatelessWidget {
  final Concept concept;
  final VoidCallback? onTap;
  final bool showSummary;

  const ConceptCard({
    super.key,
    required this.concept,
    this.onTap,
    this.showSummary = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              if (showSummary) ...[
                const SizedBox(height: 8),
                _buildSummary(context),
              ],
              const SizedBox(height: 12),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getCategoryColor(context, concept.category)
                .withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getCategoryIcon(concept.category),
            color: _getCategoryColor(context, concept.category),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                concept.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getCategoryColor(context, concept.category)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  concept.category,
                  style: TextStyle(
                    fontSize: 12,
                    color: _getCategoryColor(context, concept.category),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    return Text(
      concept.summary,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.visibility_outlined,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
        const SizedBox(width: 16),
        Icon(
          Icons.access_time,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          _formatTimeAgo(concept.updatedAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
        ),
        const Spacer(),
        if (concept.formulas.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.functions,
                  size: 12,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  '${concept.formulas.length}个公式',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
      ],
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '统计基础':
        return Icons.calculate_outlined;
      case '研究设计':
        return Icons.assignment_outlined;
      case '假设检验与估计':
      case '假设检验':
        return Icons.science;
      case '回归与建模':
        return Icons.analytics;
      case '生存分析':
        return Icons.timeline;
      case '纵向与重复测量':
        return Icons.repeat;
      case '临床试验统计':
        return Icons.medical_services_outlined;
      case '流行病学':
        return Icons.public;
      case '数据管理DM':
        return Icons.storage_outlined;
      case 'CDISC与提交':
        return Icons.inventory_2_outlined;
      case 'SAS程序':
        return Icons.terminal;
      case 'R与可重复研究':
        return Icons.account_tree_outlined;
      case '统计报告与沟通':
        return Icons.article_outlined;
      case '高级方法':
        return Icons.hub_outlined;
      default:
        return Icons.school;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}
