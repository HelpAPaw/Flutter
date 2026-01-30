import 'signal_repository.dart';
import 'storage_repository.dart';
import 'user_repository.dart';
import 'firebase/firebase_signal_repository.dart';
import 'firebase/firebase_storage_repository.dart';
import 'firebase/firebase_user_repository.dart';

/// Service locator for repository instances.
/// Supports dependency injection for testing.
class RepositoryProvider {
  static RepositoryProvider? _instance;
  static RepositoryProvider get instance => _instance ??= RepositoryProvider._();

  RepositoryProvider._();

  SignalRepository? _signalRepository;
  StorageRepository? _storageRepository;
  UserRepository? _userRepository;

  /// Get the signal repository
  SignalRepository get signalRepository =>
      _signalRepository ??= FirebaseSignalRepository();

  /// Get the storage repository
  StorageRepository get storageRepository =>
      _storageRepository ??= FirebaseStorageRepository();

  /// Get the user repository
  UserRepository get userRepository =>
      _userRepository ??= FirebaseUserRepository();

  /// Override signal repository (for testing)
  void setSignalRepository(SignalRepository repository) {
    _signalRepository = repository;
  }

  /// Override storage repository (for testing)
  void setStorageRepository(StorageRepository repository) {
    _storageRepository = repository;
  }

  /// Override user repository (for testing)
  void setUserRepository(UserRepository repository) {
    _userRepository = repository;
  }

  /// Reset all repositories to defaults (for testing cleanup)
  void reset() {
    _signalRepository = null;
    _storageRepository = null;
    _userRepository = null;
  }

  /// Reset singleton instance (for testing)
  static void resetInstance() {
    _instance = null;
  }
}
