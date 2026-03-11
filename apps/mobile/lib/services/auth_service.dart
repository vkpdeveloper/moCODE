import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final String _serverClientId;
  bool _googleInitialized = false;

  AuthService(this._firebaseAuth, this._googleSignIn, this._serverClientId);

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    if (_serverClientId.isEmpty) {
      throw StateError('Missing GOOGLE_SERVER_CLIENT_ID in .env.');
    }
    await _googleSignIn.initialize(serverClientId: _serverClientId);
    _googleInitialized = true;
  }

  Future<UserCredential?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'Google Sign-In authenticate flow is not supported',
      );
    }

    final account = await _googleSignIn.authenticate();
    final auth = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken);

    return _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await Future.wait([_firebaseAuth.signOut(), _googleSignIn.signOut()]);
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return _firebaseAuth.currentUser?.getIdToken(forceRefresh);
  }
}
