import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingWidget extends StatelessWidget {
  final String? message;

  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(message!, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ),
        Expanded(
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade900,
            highlightColor: Colors.grey.shade700,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: List.generate(6, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}
