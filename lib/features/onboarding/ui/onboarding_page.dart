import 'package:flutter/material.dart';


class OnboardingPage extends StatelessWidget {
	const OnboardingPage({super.key});

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Onboarding')),
			body: const Center(
				child: Text(
					'Welcome — complete onboarding here',
					textAlign: TextAlign.center,
				),
			),
		);
	}
}