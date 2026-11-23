import 'package:flutter/material.dart';

class LearningPathCard extends StatelessWidget {
  final Map<String, dynamic> path;
  final VoidCallback? onTap;

  const LearningPathCard({
    super.key,
    required this.path,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      path['icon'] ?? '📚',
                      style: const TextStyle(fontSize: 32),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getPathColor(path['id']).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(path['steps'] as List).length}步',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getPathColor(path['id']),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  path['name'] ?? '',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  path['description'] ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                LinearProgressIndicator(
                  value: 0.3,
                  backgroundColor:
                      _getPathColor(path['id']).withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getPathColor(path['id']),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '进度: 30%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _getPathColor(path['id']),
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPathColor(String pathId) {
    switch (pathId) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.blue;
      case 'advanced':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
