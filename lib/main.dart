import 'package:flutter/material.dart';
import 'package:glasses_tryon/main_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


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
