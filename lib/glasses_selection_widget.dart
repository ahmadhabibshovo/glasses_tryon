import 'package:flutter/material.dart';

class GlassesSelectionWidget extends StatelessWidget {
  final Function(String glassesId)? onGlassesSelected;

  const GlassesSelectionWidget({super.key, required this.onGlassesSelected});

  @override
  Widget build(BuildContext context) {
    // Placeholder data for glasses
    // Placeholder data for glasses with image paths
    final List<Map<String, dynamic>> glassesList = [
      {'id': 1, 'name': 'Glasses 1', 'imagePath': 'assets/images/glasses1.png'},
      {'id': 2, 'name': 'Glasses 2', 'imagePath': 'assets/images/glasses2.png'},
      {'id': 3, 'name': 'Glasses 3', 'imagePath': 'assets/images/glasses3.png'},
      // Add more glasses as needed
    ];

    return SizedBox(
      height: 120, // Define a fixed height for the horizontal list
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: glassesList.length,
        itemBuilder: (BuildContext context, int index) {
          final item = glassesList[index];
          return GestureDetector(
            onTap: () {
              if (onGlassesSelected != null) {
                onGlassesSelected!(item['imagePath']);
              }
              print('Selected ${item['name']} (${item['imagePath']})');
            },
            child: Container(
              width: 100, // Define a fixed width for each item
              margin: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black54, width: 1),
              ),
              child: ClipRRect( // Clip the child to respect the border radius
                borderRadius: BorderRadius.circular(9.0), // Slightly less than container's radius
                child: Image.asset(
                  item['imagePath'],
                  fit: BoxFit.cover, // Cover the container space
                  errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                    // Fallback for when image fails to load
                    return Container(
                      color: Colors.grey[300],
                      child: Center(
                        child: Text(
                          item['imagePath'],
                          style: const TextStyle(color: Colors.red, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                )
              ),
            ),
          );
        },
      ),
    );
  }
}
