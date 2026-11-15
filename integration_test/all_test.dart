// Everything that runs on the phone (tool/device_test.sh).
import 'flow_test.dart' as flow;
import 'quiz_test.dart' as quiz;
import 'voice_test.dart' as voice;

void main() {
  flow.main();
  voice.main();
  quiz.main();
}
