/// Domain exception hierarchy. Services translate low-level failures
/// (sockets, status codes, parse errors) into these so the presentation layer
/// can react without depending on `http`/`xml` internals.
sealed class CabinaException implements Exception {
  const CabinaException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class NetworkException extends CabinaException {
  const NetworkException(super.message, {super.cause});
}

class ApiException extends CabinaException {
  const ApiException(super.message, {this.statusCode, super.cause});

  final int? statusCode;

  bool get isRateLimited => statusCode == 429;
}

class FeedParseException extends CabinaException {
  const FeedParseException(super.message, {super.cause});
}

class CabinaPlayerException extends CabinaException {
  const CabinaPlayerException(super.message, {super.cause});
}

class LibraryStorageException extends CabinaException {
  const LibraryStorageException(super.message, {super.cause});
}
