import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  const BrandLogo({super.key, this.size = 88, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: size,
          width: size,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
          ),
          child: Image.asset('assets/logo_quansfer.png', fit: BoxFit.contain),
        ),
        if (showWordmark) ...[
          const SizedBox(height: 12),
          Text('Quansfer', style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          )),
          Text('BB84 secure transfer', style: Theme.of(context).textTheme.labelMedium),
        ]
      ],
    );
  }
}
