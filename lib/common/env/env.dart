/// Local evaluation only: dart-define values are embedded in the binary.
abstract final class Env {
  static const llmApiKey = String.fromEnvironment('LLM_API_KEY');
  static const summaryModel = String.fromEnvironment(
    'OPENAI_SUMMARY_MODEL',
    defaultValue: 'gpt-5.6-terra',
  );
}
