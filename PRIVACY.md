# Privacy policy – Der Hase lacht (Android app)

*Deutsch: siehe unten.*

Last updated: 2026-11-22

Der Hase lacht is a speaking game for children. It is free, has no ads, no
in-app purchases, no account and no tracking or analytics.

## Responsible (controller) and contact

Thomas Güttler  
Bonhoefferstrasse 45  
09116 Chemnitz  
Germany

E-mail: <playstore@thomas-guettler.de>

## Microphone and recordings

The app uses the microphone so a child can say a word. Speech recognition
runs **on the phone**. A recording is kept in memory only during its round
(to score it and to play it back when the child taps the funny-voice
button); the next round, or leaving the game, discards it (with recording
reports switched on, a game keeps the last two tries of the question,
word or sound in memory until another one is played or the game is
closed). Recordings are
never saved to storage. They leave the device only as a recording report (see
below), which is off unless a grown-up switches it on. The voice games without
words ("hold it long", "low and high") measure the length and pitch of
the sound; "hold it long" also keeps the held sound in memory until the
speech recognition on the phone has checked that it was the right vowel,
then discards it.

## What is stored on the phone

In the app's private storage: progress (stars, best quiz results,
voice-game records), the child's usual voice pitch (one number, for the
"low and high" game), the chosen study language and whether recording reports
are switched on. Uninstalling the app deletes it.

## Feedback reports

A grown-up can send a feedback report. It is behind a small multiplication,
so young children do not open it by accident. The screen shows what is
sent:

- the kind of report (bug, idea, word, other) and the text that was typed,
- app version, phone manufacturer and model, Android version,
- study language and app language,
- a random report id (shown on the screen), and the time it was written.

Nothing is sent without this explicit action. If the phone is offline, the
report waits on the phone (at most 30 days) and is sent later.

The report goes over HTTPS to a server operated by the developer
(`relaxandplay.de`, at Hetzner in Helsinki, Finland, EU). The server stores
the report as listed above plus the time it arrived. It does **not** store
the sender's IP address: the address is used to deliver the request and,
only in memory and for at most one hour, to limit how many reports one
sender can send; this route writes no access logs or traces.

Reports are read only by the developer, to fix bugs and improve the app.
They are not published, not sold and not shared with anyone. Please do not
type personal data (names, addresses) into the text. Reports are deleted
automatically twelve months after they arrived. The legal basis is the
sender's consent (sending is voluntary, Art. 6(1)(a) GDPR) and the
legitimate interest in fixing the app (Art. 6(1)(f) GDPR).

## Recording reports (off unless switched on)

Behind the same multiplication, a grown-up can switch on recording
reports. It stays on until it is switched off there. Then the games that
listen (the worlds, the quiz, the sound detective, read aloud and long
sounds) show a 🐞 button;
a tap asks first (on Android the recordings can be listened to on the
phone; they stay in memory), and
"Send" sends **one** report about the question, word or sound just
played, so the developer can hear why the app did not understand the
child and improve the speech recognition:

- the child's recordings of it (at most two tries of at most 12 seconds
  each),
- the question and its answers (or the word or sound asked for), what
  the speech recognition heard (as phonetic symbols) and what the app
  made of it (the answer it chose, the stars, or the sound it heard),
- the same app and phone details and a random id as a feedback report.

Nothing is sent without a tap on the button, and nothing is kept on the
phone for later: a report that cannot be sent (no internet) is not sent.
It goes the same way as feedback reports (HTTPS, `relaxandplay.de`,
Hetzner, Helsinki, EU; no IP address stored, no access logs). Only the
developer listens to the recordings, to improve the app; they are not
published, not shared and not used to identify anyone. Recording reports
are deleted automatically **90 days** after they arrived; ask for deletion
earlier using the contact above (the time of the report is enough). The
legal basis is the consent of the grown-up who switches it on
(Art. 6(1)(a) GDPR), which can be withdrawn by switching it off.

With the same switch, the thinking games (no microphone) show a 🐞 button
too. After asking, it sends the question on the screen (what the phone
said, the pictures, the right one, which were tapped) and a note the
grown-up may type, as a feedback report (see above: same details, same
way, deleted after twelve months). No recording is sent.

## Playing together (two phones)

In "Together", two phones play with each other over the internet. One
phone opens a game and shows four pictures (a code); the other phone taps
them in. The child on the first phone sees an animal for the other phone
and says yes or no; only after "yes" do the phones exchange anything about
themselves. Nothing is sent unless a child opens or joins such a game.

- To find each other, both phones talk to the developer's server
  (`relaxandplay.de`, as above). It keeps, **in memory only**, the code,
  random tokens and the two connection offers. Such an offer contains the
  phone's network addresses (its IP addresses on the local network and on
  the internet), which the other phone needs to connect. All of it is gone
  when the phones are connected, after a minute without requests, and
  after two hours at the latest. Nothing of it is written to disk or
  logged; the IP address is used, in memory and for at most one hour, to
  limit requests, as for feedback.
- Then the phones talk **directly** with each other (WebRTC, encrypted).
  The other phone learns this phone's network addresses. Only game moves
  are sent (which picture was tapped), never audio, pictures or names.
- When the two phones cannot reach each other directly, the encrypted game
  moves go through a relay on the same server (TURN). It cannot read them;
  it sees the addresses and how much is sent, keeps no logs and stores
  nothing.

The legal basis is the legitimate interest in letting children play
together that wish to (Art. 6(1)(f) GDPR); a game is only started by them.

## Your rights

You can ask for access to a report, its correction or its deletion, using
the contact above; give the report id shown before sending (or the time
and roughly what you wrote). You can also complain to a data protection
supervisory authority.

## Children

The app is made for children. It does not ask children for personal
information. The feedback screen, and the switch for recording reports, are
meant for parents and teachers.

Source code: <https://github.com/guettli/pp-app>

---

# Datenschutzerklärung – Der Hase lacht (Android-App)

Stand: 22.11.2026

Der Hase lacht ist ein Sprechspiel für Kinder. Es ist kostenlos und hat
keine Werbung, keine In-App-Käufe, kein Konto und kein Tracking oder
Analyse.

## Verantwortlicher und Kontakt

Thomas Güttler  
Bonhoefferstrasse 45  
09116 Chemnitz  
Deutschland

E-Mail: <playstore@thomas-guettler.de>

## Mikrofon und Aufnahmen

Die App nutzt das Mikrofon, damit ein Kind ein Wort sagen kann. Die
Spracherkennung läuft **auf dem Handy**. Eine Aufnahme bleibt nur während
ihrer Runde im Arbeitsspeicher (zum Bewerten und um sie vorzuspielen, wenn
das Kind auf den Knopf für die lustige Stimme tippt); die nächste Runde
oder das Verlassen des Spiels verwirft sie (mit eingeschalteten Meldungen
mit Aufnahmen behält ein Spiel die letzten zwei Versuche der Frage, des
Wortes oder des Lautes im Arbeitsspeicher, bis etwas anderes gespielt
oder das Spiel geschlossen wird). Aufnahmen werden nie gespeichert. Sie
verlassen das Gerät nur als Meldung mit Aufnahme (siehe unten), die aus
ist, solange ein Erwachsener sie nicht einschaltet. Die Stimmspiele ohne
Wörter („lange halten“, „tief und hoch“) messen Dauer und Tonhöhe;
„lange halten“ behält den gehaltenen Laut außerdem im Arbeitsspeicher,
bis die Spracherkennung auf dem Handy geprüft hat, ob es der richtige
Vokal war, und verwirft ihn dann.

## Was auf dem Handy gespeichert wird

Im privaten Speicher der App: der Fortschritt (Sterne, beste
Rätsel-Ergebnisse, Rekorde der Stimmspiele), die übliche Stimmhöhe des
Kindes (eine Zahl, für das Spiel „tief und hoch“), die gewählte
Übungssprache und ob Meldungen mit Aufnahmen eingeschaltet sind. Beim
Deinstallieren wird alles gelöscht.

## Rückmeldungen

Ein Erwachsener kann eine Rückmeldung senden. Sie liegt hinter einer
Malaufgabe, damit kleine Kinder sie nicht aus Versehen öffnen. Der
Bildschirm zeigt, was gesendet wird:

- die Art (Fehler, Idee, Wort, Sonstiges) und der eingegebene Text,
- App-Version, Hersteller und Modell des Handys, Android-Version,
- Übungssprache und Sprache der App,
- eine zufällige Kennung der Rückmeldung (auf dem Bildschirm angezeigt)
  und der Zeitpunkt.

Ohne diese ausdrückliche Handlung wird nichts gesendet. Ist das Handy
offline, wartet die Rückmeldung auf dem Handy (höchstens 30 Tage) und wird
später gesendet.

Die Rückmeldung geht per HTTPS an einen Server des Entwicklers
(`relaxandplay.de`, bei Hetzner in Helsinki, Finnland, EU). Der Server
speichert die oben genannten Angaben und den Zeitpunkt des Eingangs. Die
IP-Adresse des Absenders speichert er **nicht**: Sie dient der Zustellung
und, nur im Arbeitsspeicher und höchstens eine Stunde lang, der Begrenzung,
wie viele Rückmeldungen ein Absender senden kann; für diesen Weg werden
keine Zugriffsprotokolle oder Traces geschrieben.

Rückmeldungen liest nur der Entwickler, um Fehler zu beheben und die App
zu verbessern. Sie werden nicht veröffentlicht, nicht verkauft und an
niemanden weitergegeben. Bitte keine persönlichen Daten (Namen, Adressen)
in den Text schreiben. Rückmeldungen werden zwölf Monate nach Eingang
automatisch gelöscht. Rechtsgrundlage ist die Einwilligung des Absenders
(das Senden ist freiwillig, Art. 6 Abs. 1 lit. a DSGVO) und das berechtigte
Interesse, die App zu verbessern (Art. 6 Abs. 1 lit. f DSGVO).

## Meldungen mit Aufnahmen (aus, solange nicht eingeschaltet)

Hinter derselben Malaufgabe kann ein Erwachsener Meldungen mit Aufnahmen
einschalten. Sie bleiben eingeschaltet, bis man sie dort ausschaltet.
Dann zeigen die Spiele, die zuhören (die Welten, das Rätsel, der
Anlaut-Detektiv, Lies vor und Lange Laute), einen 🐞-Knopf; ein Tipp
fragt zuerst nach (unter
Android lassen sich die Aufnahmen auf dem Handy anhören; sie bleiben im
Arbeitsspeicher), und „Senden“ sendet
**eine** Meldung über die gerade gespielte Frage, das Wort oder den Laut,
damit der Entwickler hören kann, warum die App das Kind nicht verstanden
hat, und die Spracherkennung verbessern kann:

- die Aufnahmen des Kindes dazu (höchstens zwei Versuche zu höchstens
  12 Sekunden),
- die Frage und ihre Antworten (oder das verlangte Wort, den verlangten
  Laut), was die Spracherkennung gehört hat (als Lautschrift) und was die
  App daraus gemacht hat (die gewählte Antwort, die Sterne oder den
  gehörten Laut),
- dieselben Angaben zu App und Handy und eine zufällige Kennung wie bei
  einer Rückmeldung.

Ohne Tipp auf den Knopf wird nichts gesendet, und nichts wird für später
auf dem Handy aufbewahrt: Eine Meldung, die nicht gesendet werden kann
(kein Internet), wird nicht gesendet. Sie nimmt denselben Weg wie
Rückmeldungen (HTTPS, `relaxandplay.de`, Hetzner, Helsinki, EU; keine
Speicherung der IP-Adresse, keine Zugriffsprotokolle). Nur der Entwickler
hört die Aufnahmen an, um die App zu verbessern; sie werden nicht
veröffentlicht, nicht weitergegeben und nicht verwendet, um jemanden zu
erkennen. Meldungen mit Aufnahmen werden **90 Tage** nach Eingang automatisch
gelöscht; eine frühere Löschung können Sie über den Kontakt oben
verlangen (der Zeitpunkt der Meldung genügt). Rechtsgrundlage ist die
Einwilligung des Erwachsenen, der sie einschaltet (Art. 6 Abs. 1 lit. a
DSGVO); Ausschalten widerruft sie.

Mit demselben Schalter zeigen auch die Denkspiele (ohne Mikrofon) einen
🐞-Knopf. Nach einer Rückfrage sendet er die Frage auf dem Bildschirm
(was das Handy gesagt hat, die Bilder, das richtige, welche getippt
wurden) und eine Notiz, die der Erwachsene schreiben kann, als
Rückmeldung (siehe oben: dieselben Angaben, derselbe Weg, Löschung nach
zwölf Monaten). Es wird keine Aufnahme gesendet.

## Zusammen spielen (zwei Handys)

Bei „Zusammen“ spielen zwei Handys über das Internet miteinander. Ein
Handy macht ein Spiel auf und zeigt vier Bilder (einen Code); das andere
Handy tippt sie ein. Das Kind am ersten Handy sieht ein Tier für das andere
Handy und sagt Ja oder Nein; erst nach „Ja“ tauschen die Handys etwas über
sich aus. Es wird nichts gesendet, solange kein Kind so ein Spiel aufmacht
oder ihm beitritt.

- Damit sie sich finden, sprechen beide Handys mit dem Server des
  Entwicklers (`relaxandplay.de`, wie oben). Er hält **nur im
  Arbeitsspeicher** den Code, zufällige Schlüssel und die beiden
  Verbindungsangebote. So ein Angebot enthält die Netzwerkadressen des
  Handys (seine IP-Adressen im lokalen Netz und im Internet), die das andere
  Handy zum Verbinden braucht. Alles ist weg, sobald die Handys verbunden
  sind, nach einer Minute ohne Anfragen und spätestens nach zwei Stunden.
  Nichts davon wird auf Platte geschrieben oder protokolliert; die
  IP-Adresse dient, wie bei Rückmeldungen, nur im Arbeitsspeicher und
  höchstens eine Stunde lang dazu, Anfragen zu begrenzen.
- Danach sprechen die Handys **direkt** miteinander (WebRTC,
  verschlüsselt). Das andere Handy erfährt dabei die Netzwerkadressen dieses
  Handys. Gesendet werden nur Spielzüge (welches Bild getippt wurde), nie
  Ton, Bilder oder Namen.
- Erreichen sich die Handys nicht direkt, laufen die verschlüsselten
  Spielzüge über eine Weiterleitung auf demselben Server (TURN). Sie kann
  sie nicht lesen; sie sieht die Adressen und wie viel gesendet wird, führt
  kein Protokoll und speichert nichts.

Rechtsgrundlage ist das berechtigte Interesse, Kindern das gemeinsame
Spielen zu ermöglichen, das sie selbst starten (Art. 6 Abs. 1 lit. f
DSGVO).

## Ihre Rechte

Sie können Auskunft über eine Rückmeldung, ihre Berichtigung oder Löschung
verlangen, über den Kontakt oben; nennen Sie dazu die vor dem Senden
angezeigte Kennung (oder den Zeitpunkt und ungefähr den Inhalt). Sie
können sich außerdem bei einer Datenschutz-Aufsichtsbehörde beschweren.

## Kinder

Die App ist für Kinder gemacht. Sie fragt Kinder nicht nach
personenbezogenen Daten. Der Rückmelde-Bildschirm und der Schalter für
Meldungen mit Aufnahmen sind für Eltern und Lehrkräfte gedacht.

Quellcode: <https://github.com/guettli/pp-app>
