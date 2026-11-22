// A match code is four hex digits (server/feedback/match.go); children see
// and type it as four pictures. The guest's animal (picked by the service)
// is shown on both phones, so the host's child knows who wants to play.

/// One picture per hex digit 0-f: things a small child names easily and
/// does not mix up (no 🏠: that is the host's button and picture).
const codePictures = [
  '🍎', '🍌', '🚗', '🌙', '🎸', '🌻', '🚀', '⚽', //
  '🎈', '🧸', '🌈', '🍐', '☀️', '🔑', '🎁', '🚲',
];

/// The guest's animal, by the number the service sends (0-15).
const animals = [
  '🐶', '🐱', '🐭', '🐰', '🦊', '🐻', '🐸', '🐵', //
  '🦁', '🐷', '🐮', '🐔', '🐟', '🐞', '🐘', '🦒',
];

const codeLength = 4;

/// The pictures of [code] ("3f0a").
List<String> codeToPictures(String code) => [
  for (final c in code.split('')) codePictures[int.parse(c, radix: 16)],
];

/// The code of four picture indexes.
String picturesToCode(List<int> picked) =>
    picked.map((i) => i.toRadixString(16)).join();

/// The animal for the service's number (any number gives one).
String animalFor(int n) => animals[n % animals.length];
