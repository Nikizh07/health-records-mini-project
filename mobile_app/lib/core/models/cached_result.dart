/// Generic wrapper for data that can be served either from a live API response
/// or from local offline cache.
class CachedResult<T> {
  final T data;
  final bool isOffline;
  final DateTime? lastUpdated;

  const CachedResult({
    required this.data,
    required this.isOffline,
    this.lastUpdated,
  });
}
