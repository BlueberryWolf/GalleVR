import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// A widget that displays a horizontal step indicator
class StepIndicator extends StatelessWidget {
  // List of step labels
  final List<String> steps;
  
  // Current active step (0-based)
  final int currentStep;

  // Default constructor
  const StepIndicator({
    super.key,
    required this.steps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        // Even indices are step indicators, odd indices are connectors
        if (index.isEven) {
          final stepIndex = index ~/ 2;
          final isActive = stepIndex <= currentStep;
          final isCurrentStep = stepIndex == currentStep;
          
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primaryColor : Colors.grey.shade700,
                    shape: BoxShape.circle,
                    border: isCurrentStep
                        ? Border.all(
                            color: AppTheme.primaryLightColor,
                            width: 2,
                          )
                        : null,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isCurrentStep ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  steps[stepIndex],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.grey,
                    fontWeight: isCurrentStep ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        } else {
          final leftStepIndex = index ~/ 2;
          final isActive = leftStepIndex < currentStep;
          
          return Expanded(
            child: Container(
              height: 2,
              color: isActive ? AppTheme.primaryColor : Colors.grey.shade700,
            ),
          );
        }
      }),
    );
  }
}
