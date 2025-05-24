import 'package:flutter/material.dart';
import 'package:glasses_try_on/try_on_screen.dart'; // Import TryOnScreen

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glasses Try-On'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TryOnScreen(isLiveCamera: true),
                  ),
                );
              },
              child: const Text('Live Camera Try-On'),
            ),
            const SizedBox(height: 20), // Spacer between buttons
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TryOnScreen(isLiveCamera: false),
                  ),
                );
              },
              child: const Text('Upload Image Try-On'),
            ),
          ],
        ),
      ),
    );
  }
}
