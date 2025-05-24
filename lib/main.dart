import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

import 'package:glasses_try_on/main_screen.dart'; // Import MainScreen

// This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glasses Try-On', // Updated title
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), // Updated color
        useMaterial3: true,
        appBarTheme: const AppBarTheme( // Centered AppBar title
          centerTitle: true,
        ),
      ),
      home: const MainScreen(), // Set MainScreen as home
    );
  }
}
