package main

// Quiz reports: what happened in one question of the quiz, with the
// child's recordings, so a "not understood" can be replayed and the
// recogniser improved. The app sends one only when a grown-up switched
// them on (behind the parent gate) and then tapped the button in the quiz.
// The recordings are stored as WAV files next to the report and deleted
// with it after QuizKeep.

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	// QuizKeep is how long quiz reports are kept (PRIVACY.md: 90 days).
	QuizKeep = 90 * 24 * time.Hour
	quizMax  = 1000 // reports; each is at most ~1 MB

	quizPerClient = 30
	quizPerHour   = 120

	maxTries   = 2 // a question is asked twice at most
	maxOptions = 6
	// The app listens 12 s at most: 16 kHz, 16 bit, mono, plus header.
	maxAudio    = 13*16000*2 + 44
	maxQuizBody = maxTries*(maxAudio*4/3+4) + 64<<10
	maxField    = 200
)

// QuizReport is what the app sends.
type QuizReport struct {
	ID      string            `json:"id"`
	Created string            `json:"created"`
	Info    map[string]string `json:"info"`
	Lang    string            `json:"lang"`
	// Question as shown, and as spoken by the phone.
	Question string       `json:"question"`
	Asked    string       `json:"asked"`
	Options  []QuizOption `json:"options"`
	Answer   string       `json:"answer"`
	Tries    []QuizTry    `json:"tries"`
}

type QuizOption struct {
	Text string `json:"text"`
	// IPA of each accepted way to say it.
	IPA []string `json:"ipa"`
}

type QuizTry struct {
	// Audio is a base64 WAV (16 kHz mono PCM16). It is stored as a file
	// of its own; the stored JSON has its name in File instead.
	Audio string `json:"audio,omitempty"`
	File  string `json:"file,omitempty"`
	// Speech: the endpointer heard someone speak.
	Speech bool `json:"speech"`
	// Heard is the recogniser's IPA, Said the option it chose ("" none).
	Heard  string      `json:"heard"`
	Said   string      `json:"said"`
	Scores []QuizScore `json:"scores"`
}

type QuizScore struct {
	Option string  `json:"option"`
	Score  float64 `json:"score"`
	Same   float64 `json:"same"`
}

func okString(s string, max int) bool {
	return utf8.ValidString(s) && utf8.RuneCountInString(s) <= max
}

// wav decodes a try's audio and checks it is a WAV file.
func wav(b64 string) ([]byte, error) {
	if len(b64) > maxAudio*4/3+4 {
		return nil, errors.New("audio too long")
	}
	b, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, errors.New("bad audio")
	}
	if len(b) < 44 || string(b[0:4]) != "RIFF" || string(b[8:12]) != "WAVE" {
		return nil, errors.New("audio is not WAV")
	}
	return b, nil
}

// Validate checks a report; the error text goes back to the app.
func (q *QuizReport) Validate() error {
	if !idPattern.MatchString(q.ID) {
		return errors.New("bad id")
	}
	if _, err := time.Parse(time.RFC3339, q.Created); err != nil {
		return errors.New("bad created")
	}
	if len(q.Info) > len(infoKeys) {
		return errors.New("bad info")
	}
	for k, v := range q.Info {
		if !infoKeys[k] || !okString(v, maxInfo) {
			return errors.New("bad info")
		}
	}
	for _, s := range []string{q.Lang, q.Question, q.Asked, q.Answer} {
		if !okString(s, maxField) {
			return errors.New("bad question")
		}
	}
	if len(q.Options) == 0 || len(q.Options) > maxOptions {
		return errors.New("bad options")
	}
	for _, o := range q.Options {
		if !okString(o.Text, maxField) || len(o.IPA) > 10 {
			return errors.New("bad options")
		}
		for _, i := range o.IPA {
			if !okString(i, maxField) {
				return errors.New("bad options")
			}
		}
	}
	if len(q.Tries) == 0 || len(q.Tries) > maxTries {
		return errors.New("bad tries")
	}
	for _, t := range q.Tries {
		if t.File != "" || !okString(t.Heard, 2*maxField) || !okString(t.Said, maxField) || len(t.Scores) > maxOptions {
			return errors.New("bad try")
		}
		for _, sc := range t.Scores {
			if !okString(sc.Option, maxField) {
				return errors.New("bad try")
			}
		}
		if _, err := wav(t.Audio); err != nil {
			return err
		}
	}
	return nil
}

// QuizStore keeps quiz reports.
type QuizStore interface {
	// SaveQuiz stores q; storing the same id again is a no-op.
	SaveQuiz(q *QuizReport, received time.Time) error
}

// StoredQuiz is a quiz report as written to disk (without the audio,
// which is in the files named by the tries).
type StoredQuiz struct {
	QuizReport
	Received string `json:"received"`
}

// SaveQuiz writes <stamp>-<id>-<n>.wav per try, then <stamp>-<id>.json:
// the report counts as stored once its JSON is there.
func (d *Dir) SaveQuiz(q *QuizReport, received time.Time) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	found, n, err := d.stored(q.ID)
	if err != nil {
		return err
	}
	if found {
		return nil
	}
	if n >= d.Max {
		return errors.New("store is full")
	}
	base := received.UTC().Format(stamp) + "-" + q.ID
	out := StoredQuiz{QuizReport: *q, Received: received.UTC().Format(time.RFC3339)}
	out.Tries = make([]QuizTry, len(q.Tries))
	for i, t := range q.Tries {
		b, err := wav(t.Audio)
		if err != nil {
			return err
		}
		name := base + "-" + strconv.Itoa(i+1) + ".wav"
		if err := write(filepath.Join(d.Path, name), b); err != nil {
			return err
		}
		t.Audio = ""
		t.File = name
		out.Tries[i] = t
	}
	b, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return err
	}
	return write(filepath.Join(d.Path, base+".json"), append(b, '\n'))
}

func (s *Server) serveQuiz(w http.ResponseWriter, r *http.Request) {
	if s.Quiz == nil {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var q QuizReport
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxQuizBody))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&q); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			http.Error(w, "too large", http.StatusRequestEntityTooLarge)
			return
		}
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if err := q.Validate(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.quizLimit.allow(clientIP(r), s.Now()) {
		http.Error(w, "too many reports, try later", http.StatusTooManyRequests)
		return
	}
	if err := s.Quiz.SaveQuiz(&q, s.Now()); err != nil {
		log.Printf("quiz report %s: %v", q.ID, err)
		http.Error(w, "try later", http.StatusServiceUnavailable)
		return
	}
	log.Printf("quiz report %s stored (%d tries)", q.ID, len(q.Tries))
	w.WriteHeader(http.StatusCreated)
}

// Cat writes the stored file name (a plain name in d, no path) to w.
func (d *Dir) Cat(name string, w io.Writer) error {
	if name == "" || name != filepath.Base(name) || strings.HasPrefix(name, ".") {
		return errors.New("not a file name")
	}
	b, err := os.ReadFile(filepath.Join(d.Path, name))
	if err != nil {
		return err
	}
	_, err = io.Copy(w, bytes.NewReader(b))
	return err
}

// command runs a command-line action (see the package comment).
func command(args []string, dir, quiz *Dir, w io.Writer) error {
	switch {
	case len(args) == 1 && args[0] == "list":
		return dir.List(w)
	case len(args) == 1 && args[0] == "quiz-list":
		return quiz.List(w)
	case len(args) == 2 && args[0] == "cat":
		return quiz.Cat(args[1], w)
	case len(args) == 2 && args[0] == "delete":
		any := false
		for _, d := range []*Dir{dir, quiz} {
			found, err := d.Delete(args[1])
			if err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
			any = any || found
		}
		if !any {
			return fmt.Errorf("no report %s", args[1])
		}
		fmt.Fprintln(w, "deleted", args[1])
		return nil
	}
	names := []string{"list", "quiz-list", "cat <file>", "delete <id>"}
	sort.Strings(names)
	return fmt.Errorf("usage: feedback [%s]", strings.Join(names, " | "))
}
