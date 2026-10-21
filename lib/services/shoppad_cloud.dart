import 'package:cloud_functions/cloud_functions.dart';

/// Secret credentials and payment verification stay in Cloud Functions.
class ShopPadCloud {
  static final _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west1',
  );

  static Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
          )
          .call(data ?? {});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw StateError(
        error.code == 'not-found'
            ? 'ShopPad service is not configured yet. Contact your store administrator.'
            : error.message ?? 'Unable to reach ShopPad. Please try again.',
      );
    }
  }
}
