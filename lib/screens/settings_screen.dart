import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingTile(
            context,
            icon: Icons.bar_chart_rounded,
            title: 'Meme Stats',
            subtitle: 'View your meme stats',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemeStatsScreen()),
            ),
          ),
          _buildSettingTile(
            context,
            icon: Icons.info_outline,
            title: 'App Info',
            subtitle: 'Version, license, developer info',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppInfoScreen()),
            ),
          ),
          _buildSettingTile(
            context,
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'FAQs and Support Information',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          _buildSettingTile(
            context,
            icon: Icons.logout,
            title: 'Logout',
            subtitle: 'Sign out from your account',
            onTap: () => _showLogoutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.greenAccent.withOpacity(0.2),
          child: Icon(icon, color: Colors.greenAccent),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Confirm Logout", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to logout?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: Colors.greenAccent)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }
}

class MemeStatsScreen extends StatefulWidget {
  const MemeStatsScreen({super.key});

  @override
  State<MemeStatsScreen> createState() => _MemeStatsScreenState();
}

class _MemeStatsScreenState extends State<MemeStatsScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  int touchedIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      if (doc.exists && mounted) {
        setState(() => userData = doc.data());
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedMemes = (userData?['savedMemes'] as List?)?.length ?? 0;
    final sharedMemes = userData?['sharedMemesCount'] ?? 0;
    final likedMemes = userData?['likedMemesCount'] ?? 0;
    final creationDate = currentUser?.metadata.creationTime;
    final formattedDate = creationDate != null ? DateFormat('MMMM d, yyyy').format(creationDate) : 'Unknown';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Meme Stats', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Meme Stats',
              style: GoogleFonts.roboto(
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  infoRow('Using Since', formattedDate),
                  infoRow('Memes Saved', '$savedMemes'),
                  infoRow('Memes Shared', '$sharedMemes'),
                  infoRow('Memes Liked', '$likedMemes'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Visual Overview',
              style: GoogleFonts.roboto(
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
              ),
              height: 250,
              child: savedMemes + sharedMemes + likedMemes == 0
                  ? const Center(
                      child: Text(
                        'Not enough data, Please like, share or save some memes to get visual overview.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 0,
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(
                            color: Colors.grey[400]!,
                            width: 1,
                          ),
                        ),
                        sections: [
                          PieChartSectionData(
                            value: savedMemes.toDouble(),
                            color: Colors.greenAccent,
                            title: touchedIndex == 0 ? '$savedMemes' : 'Saved',
                            radius: 80,
                            titlePositionPercentageOffset: 0.6,
                            titleStyle: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          PieChartSectionData(
                            value: sharedMemes.toDouble(),
                            color: Colors.blueAccent,
                            title: touchedIndex == 1 ? '$sharedMemes' : 'Shared',
                            radius: 80,
                            titlePositionPercentageOffset: 0.5,
                            titleStyle: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          PieChartSectionData(
                            value: likedMemes.toDouble(),
                            color: Colors.orangeAccent,
                            title: touchedIndex == 2 ? '$likedMemes' : 'Liked',
                            radius: 80,
                            titlePositionPercentageOffset: 0.6,
                            titleStyle: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                touchedIndex = -1;
                                return;
                              }
                              touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('About Memelusion'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      border: Border.all(color: Colors.greenAccent, width: 2.5),
                      image: const DecorationImage(
                        image: AssetImage('assets/img/logo.jpg'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Memelusion',
                    style: TextStyle(
                      fontSize: 30,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Version: 1.0.0',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            buildCard(
              title: 'App Description',
              content:
                  'Memelusion is a platform for sharing, chatting, and enjoying memes in real time. '
                  'Admins can upload fresh content, while users can share memes privately with friends. '
                  'All memes and chats disappear after 24 hours, ensuring a fun and clutter-free experience!',
            ),
            buildCard(
              title: 'Developed By',
              content: 'Taksh (23020201018)\nHetshi (23020201042)\nBrinda (23020201055)\nMaharshi (23020201148)',
            ),
            buildCard(
              title: 'Institution',
              content: 'Darshan University',
            ),
            buildCard(
              title: 'Guided By',
              content: 'Vishal Makavana Sir',
            ),
            const SizedBox(height: 30),
            Center(
              child: Text(
                '© 2025 Memelusion. All rights reserved.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildCard({required String title, required String content}) {
    return Card(
      color: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.question_answer_outlined),
            title: Text('How do I share memes?'),
            subtitle: Text('Go to Home → Swipe up → Select Friend'),
          ),
          ListTile(
            leading: Icon(Icons.chat_outlined),
            title: Text('How to chat with a friend?'),
            subtitle: Text('Open Friend List → Tap on friend → Start chatting'),
          ),
          ListTile(
            leading: Icon(Icons.favorite_border),
            title: Text('How do I like a meme?'),
            subtitle: Text('Swipe right on a meme to like it'),
          ),
          ListTile(
            leading: Icon(Icons.timer_outlined),
            title: Text('Why do memes disappear after 24 hours?'),
            subtitle: Text('Memes and chats vanish after 24 hours to keep your feed fresh and engaging.'),
          ),
        ],
      ),
    );
  }
}