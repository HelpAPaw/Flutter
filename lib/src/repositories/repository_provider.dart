import '../services/app_preferences_service.dart';
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
  String? _currentCollectionName;
  StorageRepository? _storageRepository;
  UserRepository? _userRepository;

  /// Get the signal repository, recreating if test mode changed
  SignalRepository get signalRepository {
    final collectionName = AppPreferencesService().signalsCollectionName;
    if (_signalRepository == null || _currentCollectionName != collectionName) {
      _currentCollectionName = collectionName;
      _signalRepository = FirebaseSignalRepository(collectionName: collectionName);
    }
    return _signalRepository!;
  }

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

  /// Reset the signal repository so it picks up the current collection name
  void resetSignalRepository() {
    _signalRepository = null;
    _currentCollectionName = null;
  }

  /// Reset all repositories to defaults (for testing cleanup)
  void reset() {
    _signalRepository = null;
    _currentCollectionName = null;
    _storageRepository = null;
    _userRepository = null;
  }

  /// Reset singleton instance (for testing)
  static void resetInstance() {
    _instance = null;
  }
}
