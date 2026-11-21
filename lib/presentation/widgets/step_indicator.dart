import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StepIndicator extends StatelessWidget {
  final List<String> steps;
  final int currentStep;
  final List<IconData>? icons;

  const StepIndicator({
    super.key,
    required this.steps,
    required this.currentStep,
    this.icons,
  });

  static const List<IconData> _defaultIcons = [
    Icons.person_search_rounded,
    Icons.people_outline_rounded,
    Icons.verified_outlined,
  ];

  static const List<Color> _stepColors = [
    AppTheme.iconWorld,
    AppTheme.brandPurple,
    AppTheme.successColor,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isEven) {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            final isCurrent = stepIndex == currentStep;
            final stepColor = _stepColors[stepIndex % _stepColors.length];
            final stepIcon =
                isCompleted
                    ? Icons.check_rounded
                    : (icons != null && stepIndex < icons!.length
                        ? icons![stepIndex]
                        : _defaultIcons[stepIndex % _defaultIcons.length]);

            return Opacity(
              opacity: isCurrent || isCompleted ? 1.0 : 0.55,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    stepIcon,
                    size: 20,
                    color: isCompleted ? AppTheme.successColor : stepColor,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'STEP ${stepIndex + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color:
                              isCurrent
                                  ? Colors.white
                                  : AppTheme.secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps[stepIndex],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              isCurrent
                                  ? Colors.white
                                  : AppTheme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          } else {
            final leftStepIndex = index ~/ 2;
            final isCompleted = leftStepIndex < currentStep;

            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color:
                      isCompleted
                          ? AppTheme.brandPurple.withValues(alpha: 0.7)
                          : AppTheme.cardBorderColor,
                ),
              ),
            );
          }
        }),
      ),
    );
  }
}
