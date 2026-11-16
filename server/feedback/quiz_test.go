package main

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// wavBytes is a WAV header plus n samples.
func wavBytes(n int) []byte {
	var b bytes.Buffer
	b.WriteString("RIFF")
	binary.Write(&b, binary.LittleEndian, uint32(36+2*n))
	b.WriteString("WAVEfmt ")
	binary.Write(&b, binary.LittleEndian, []any{uint32(16), uint16(1), uint16(1), uint32(16000), uint32(32000), uint16(2), uint16(16)})
	b.WriteString("data")
	binary.Write(&b, binary.LittleEndian, uint32(2*n))
	b.Write(make([]byte, 2*n))
	return b.Bytes()
}

func quizReport(id string, tries ...[]byte) *QuizReport {
	q := &QuizReport{
		ID: id, Created: "2026-11-16T20:00:00Z",
		Info:     map[string]string{"app": "0.1.55", "phone": "samsung SM-A805F"},
		Lang:     "de-DE",
		Question: "Was kann fliegen?", Asked: "Was kann fliegen? Baum, Vogel oder Haus?",
		Options: []QuizOption{{Text: "Baum", IPA: []string{"baʊm"}}, {Text: "Vogel", IPA: []string{"foːɡl̩"}}, {Text: "Haus", IPA: []string{"haʊs"}}},
		Answer:  "Vogel",
	}
	for _, t := range tries {
		q.Tries = append(q.Tries, QuizTry{
			Audio: base64.StdEncoding.EncodeToString(t), Speech: true, Heard: "foːl",
			Scores: []QuizScore{{Option: "Vogel", Score: 0.6, Same: 0.5}},
		})
	}
	return q
}

func postQuiz(s http.Handler, q any, ip string) *httptest.ResponseRecorder {
	var body string
	if str, ok := q.(string); ok {
		body = str
	} else {
		b, _ := json.Marshal(q)
		body = string(b)
	}
	r := httptest.NewRequest(http.MethodPost, "/pp-app/api/quiz-report", strings.NewReader(body))
	r.Header.Set("X-Forwarded-For", ip)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}

func quizServer(t *testing.T) (*Server, *Dir) {
	d := &Dir{Path: t.TempDir(), Max: 100, Keep: QuizKeep}
	s := NewServer(newDir(t, 100))
	s.Quiz = d
	s.Now = func() time.Time { return time.Date(2026, 11, 16, 20, 1, 2, 0, time.UTC) }
	return s, d
}

func TestQuizReportStoresAudioAsFiles(t *testing.T) {
	s, d := quizServer(t)
	a1, a2 := wavBytes(16000), wavBytes(8000)
	q := quizReport(id1, a1, a2)
	if w := postQuiz(s, q, "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code, w.Body)
	}
	// a retry is stored once
	if w := postQuiz(s, q, "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code)
	}
	base := "20261116T200102Z-" + id1
	f := files(t, d)
	want := []string{base + "-1.wav", base + "-2.wav", base + ".json"}
	if strings.Join(f, " ") != strings.Join(want, " ") {
		t.Fatal(f)
	}
	for i, a := range [][]byte{a1, a2} {
		var out bytes.Buffer
		if err := d.Cat(want[i], &out); err != nil || !bytes.Equal(out.Bytes(), a) {
			t.Fatal(i, err)
		}
	}
	b, _ := os.ReadFile(filepath.Join(d.Path, want[2]))
	var got StoredQuiz
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if got.Tries[0].Audio != "" || got.Tries[0].File != want[0] || got.Tries[1].File != want[1] ||
		got.Answer != "Vogel" || got.Tries[0].Heard != "foːl" || got.Received != "2026-11-16T20:01:02Z" {
		t.Fatal(string(b))
	}
	if strings.Contains(string(b), "1.1.1.1") {
		t.Fatal("client address stored")
	}
}

func TestQuizReportRejectsBadOnes(t *testing.T) {
	s, d := quizServer(t)
	notWav := quizReport(id1, []byte(strings.Repeat("x", 100)))
	tooMany := quizReport(id1, wavBytes(10), wavBytes(10), wavBytes(10))
	noTries := quizReport(id1)
	file := quizReport(id1, wavBytes(10))
	file.Tries[0].File = "../../etc/passwd"
	badID := quizReport("x", wavBytes(10))
	for i, q := range []any{notWav, tooMany, noTries, file, badID, `{"id":"` + id1 + `","extra":1}`} {
		if w := postQuiz(s, q, "1.1.1.1"); w.Code != 400 {
			t.Fatal(i, w.Code, w.Body)
		}
	}
	long := quizReport(id1, wavBytes(maxAudio/2+10), wavBytes(maxAudio/2+10), wavBytes(maxAudio/2+10))
	if w := postQuiz(s, long, "1.1.1.1"); w.Code != 413 {
		t.Fatal(w.Code, w.Body)
	}
	if f := files(t, d); len(f) != 0 {
		t.Fatal(f)
	}
}

func TestQuizReportTakesTheLongestRecording(t *testing.T) {
	s, _ := quizServer(t)
	n := (maxAudio - 44) / 2
	if w := postQuiz(s, quizReport(id1, wavBytes(n), wavBytes(n)), "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code, w.Body)
	}
}

func TestQuizRouteNeedsAStore(t *testing.T) {
	s := NewServer(newDir(t, 100))
	if w := postQuiz(s, quizReport(id1, wavBytes(10)), "1.1.1.1"); w.Code != 404 {
		t.Fatal(w.Code)
	}
}

func TestQuizHasItsOwnLimit(t *testing.T) {
	s, _ := quizServer(t)
	for i := 0; i < quizPerClient; i++ {
		id := strings.Repeat("0", 30) + string("0123456789abcdef"[i/16]) + string("0123456789abcdef"[i%16])
		if w := postQuiz(s, quizReport(id, wavBytes(10)), "2.2.2.2"); w.Code != 201 {
			t.Fatal(i, w.Code, w.Body)
		}
	}
	if w := postQuiz(s, quizReport(id1, wavBytes(10)), "2.2.2.2"); w.Code != 429 {
		t.Fatal(w.Code)
	}
	// text feedback is counted apart
	if w := post(s, report(id1, "a"), "2.2.2.2"); w.Code != 201 {
		t.Fatal(w.Code, w.Body)
	}
}

func valid(t *testing.T, q *QuizReport) *QuizReport {
	t.Helper()
	if err := q.Validate(); err != nil {
		t.Fatal(err)
	}
	return q
}

func TestQuizFailedSaveLeavesNoRecordings(t *testing.T) {
	d := &Dir{Path: t.TempDir(), Max: 100, Keep: QuizKeep}
	now := time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	// the report's JSON cannot be written: a directory is in its place
	if err := os.Mkdir(filepath.Join(d.Path, now.Format(stamp)+"-"+id1+".json.tmp"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := d.SaveQuiz(valid(t, quizReport(id1, wavBytes(10), wavBytes(10))), now); err == nil {
		t.Fatal("saved")
	}
	for _, f := range files(t, d) {
		if strings.HasSuffix(f, ".wav") {
			t.Fatal("recording left:", f)
		}
	}
}

func TestQuizBusy(t *testing.T) {
	s, _ := quizServer(t)
	for i := 0; i < quizUploads; i++ {
		s.quizSlots <- struct{}{}
	}
	if w := postQuiz(s, quizReport(id1, wavBytes(10)), "1.1.1.1"); w.Code != 503 {
		t.Fatal(w.Code)
	}
	<-s.quizSlots
	if w := postQuiz(s, quizReport(id1, wavBytes(10)), "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code, w.Body)
	}
}

func TestQuizPruneAndDelete(t *testing.T) {
	d := &Dir{Path: t.TempDir(), Max: 100, Keep: QuizKeep}
	now := time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	id2 := strings.Repeat("ab", 16)
	if err := d.SaveQuiz(valid(t, quizReport(id1, wavBytes(10))), now.Add(-QuizKeep-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := d.SaveQuiz(valid(t, quizReport(id2, wavBytes(10), wavBytes(10))), now.Add(-QuizKeep+time.Hour)); err != nil {
		t.Fatal(err)
	}
	if n, err := d.Prune(now); err != nil || n != 2 {
		t.Fatal(n, err)
	}
	if f := files(t, d); len(f) != 3 || strings.Contains(strings.Join(f, " "), id1) {
		t.Fatal(f)
	}
	// "delete <id>" looks in both directories, takes the recordings along
	text := newDir(t, 100)
	var out bytes.Buffer
	if err := command([]string{"delete", id2}, text, d, &out); err != nil {
		t.Fatal(err)
	}
	if f := files(t, d); len(f) != 0 {
		t.Fatal(f)
	}
	if err := command([]string{"delete", id2}, text, d, &out); err == nil {
		t.Fatal("deleted twice")
	}
}

func TestCatOnlyTakesNames(t *testing.T) {
	d := &Dir{Path: t.TempDir()}
	for _, n := range []string{"", "../x", "a/b", ".hidden"} {
		if err := d.Cat(n, &bytes.Buffer{}); err == nil {
			t.Fatal(n)
		}
	}
}
