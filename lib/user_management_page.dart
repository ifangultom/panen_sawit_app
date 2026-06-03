import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'register_page.dart';

class UserManagementPage extends StatefulWidget {
  final bool isWebView;
  const UserManagementPage({super.key, this.isWebView = false});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String searchQuery = "";

  final Color primaryBlue = const Color(0xFF0D47A1);
  final Color accentBlue = const Color(0xFF1976D2);
  final Color bgGrey = const Color(0xFFF5F7FA);
  final Color cardShadow = Colors.black.withOpacity(0.05);

  @override
  Widget build(BuildContext context) {
    Widget body = Column(
      children: [
        // Header / Search Bar
        if (widget.isWebView)
          _buildWebHeader()
        else
          _buildMobileHeader(),

        // User List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Terjadi kesalahan: ${snapshot.error}"));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = snapshot.data!.docs;
              
              // Filter locally
              if (searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final email = (data['email'] ?? "").toString().toLowerCase();
                  final role = (data['role'] ?? "").toString().toLowerCase();
                  final nama = (data['nama'] ?? "").toString().toLowerCase();
                  return email.contains(searchQuery) || role.contains(searchQuery) || nama.contains(searchQuery);
                }).toList();
              }

              if (docs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Tidak ada user ditemukan", style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                );
              }

              if (widget.isWebView) {
                return _buildWebGrid(docs);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final String docId = docs[index].id;
                  final String email = data['email'] ?? '-';
                  final String role = data['role'] ?? 'KCS';
                  final String afd = data['afdeling'] ?? '-';
                  final String createdAt = data['created_at']?.toString().split("T")[0] ?? '-';

                  return _buildUserCard(docId, email, role, afd, createdAt, data);
                },
              );
            },
          ),
        ),
      ],
    );

    if (widget.isWebView) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: body,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
          },
          label: const Text("Tambah User Baru"),
          icon: const Icon(Icons.person_add),
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgGrey,
      appBar: AppBar(
        title: const Text("Manajemen User", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
        },
        label: const Text("User Baru"),
        icon: const Icon(Icons.person_add),
        backgroundColor: accentBlue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildWebHeader() {
    return Container(
      margin: const EdgeInsets.all(25),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cardShadow, blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Manajemen User & Hak Akses", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text("Kelola akun petugas lapangan dan admin di sini", style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                icon: const Icon(Icons.add),
                label: const Text("REGISTRASI USER"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          TextField(
            onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
            decoration: InputDecoration(
              hintText: "Cari berdasarkan nama, email, atau role (contoh: ADMIN, MANDOR, KCS)...",
              prefixIcon: Icon(Icons.search, color: accentBlue),
              filled: true,
              fillColor: bgGrey,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: BoxDecoration(
        color: primaryBlue,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: TextField(
        onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Cari email atau role...",
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildWebGrid(List<QueryDocumentSnapshot> docs) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        mainAxisExtent: 140,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        final String docId = docs[index].id;
        final String email = data['email'] ?? '-';
        final String role = data['role'] ?? 'KCS';
        final String afd = data['afdeling'] ?? '-';
        final String createdAt = data['created_at']?.toString().split("T")[0] ?? '-';
        
        return _buildUserCard(docId, email, role, afd, createdAt, data);
      },
    );
  }

  Widget _buildUserCard(String docId, String email, String role, String afd, String date, Map<String, dynamic> data) {
    Color roleColor = Colors.blue;
    IconData roleIcon = Icons.person;
    String nama = data['nama'] ?? "";

    if (role == 'ADMIN') {
      roleColor = const Color(0xFFD32F2F); // Merah untuk Admin
      roleIcon = Icons.admin_panel_settings;
    } else if (role == 'MANDOR') {
      roleColor = Colors.orange;
      roleIcon = Icons.supervisor_account;
    } else {
      roleColor = const Color(0xFF0D47A1); // Biru untuk KCS/Pemanen (Konsistensi Tema)
      roleIcon = Icons.hail_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: cardShadow, blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(roleIcon, color: roleColor, size: 28),
          ),
          title: Text(
            nama.isNotEmpty ? nama : email,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nama.isNotEmpty)
                Text(email, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(
                children: [
                  _badge(role, roleColor),
                  const SizedBox(width: 8),
                  if (role != 'ADMIN') _badge("AFD: $afd", Colors.blueGrey),
                ],
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            onSelected: (val) {
              if (val == 'edit') _showEditDialog(docId, data);
              if (val == 'reset_pwd') _resetPassword(email);
              if (val == 'delete') _confirmDelete(docId, email);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [Icon(Icons.edit_note, size: 20), SizedBox(width: 10), Text("Edit Role & Akses")]),
              ),
              const PopupMenuItem(
                value: 'reset_pwd',
                child: Row(children: [Icon(Icons.lock_reset, size: 20), SizedBox(width: 10), Text("Reset Password")]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(Icons.delete_forever, size: 20, color: Colors.red), SizedBox(width: 10), Text("Hapus User", style: TextStyle(color: Colors.red))]),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _resetPassword(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Password"),
        content: Text("Kirim link reset password ke $email?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              try {
                // Menggunakan FirebaseAuth jika sudah diimplementasikan, 
                // atau cukup simpan request reset di Firestore.
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur reset password belum terintegrasi dengan Firebase Auth")));
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("Kirim"),
          )
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showEditDialog(String docId, Map<String, dynamic> data) {
    String selectedRole = data['role'] ?? 'KCS';
    String selectedAfd = data['afdeling'] ?? 'AFD1';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Edit Akses User"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data['email'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: "Role", border: OutlineInputBorder()),
                items: ['ADMIN', 'MANDOR', 'KCS'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedAfd,
                decoration: const InputDecoration(labelText: "Afdeling", border: OutlineInputBorder()),
                items: ['ALL', 'AFD1', 'AFD2', 'AFD3'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setDialogState(() => selectedAfd = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection('users').doc(docId).update({
                  'role': selectedRole,
                  'afdeling': selectedRole == "ADMIN" ? "ALL" : selectedAfd,
                });
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Simpan", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String docId, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus User"),
        content: Text("Apakah Anda yakin ingin menghapus user $email?\n\nTindakan ini tidak dapat dibatalkan."),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _firestore.collection('users').doc(docId).delete();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
