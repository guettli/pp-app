// Command feedback takes feedback and bug reports from the Der Hase lacht
// app (lib/net/feedback.dart) and stores each as a JSON file in a
// directory (a volume on the vps). Nothing is published.
//
// Reports are anonymous: text the grown-up typed, the app version, the
// languages, phone model and Android version. This service neither stores
// nor logs client addresses; it only holds them in memory for the rate
// limit (Traefik in front of it sees them, as for every request).
//
// Quiz reports (quiz.go) also carry the child's recording of one quiz
// question; a grown-up has switched them on in the app. They are kept in
// their own directory, 90 days.
//
//	feedback               serve (LISTEN, default :8080; DIR, default
//	                       /data/feedback; QUIZ_DIR, default /data/quiz)
//	feedback list          print the stored reports, newest first
//	feedback quiz-list     the same for quiz reports (without audio)
//	feedback cat <file>    write one stored file of the quiz directory to
//	                       stdout (a recording: the image has no tar, so
//	                       kubectl cp does not work)
//	feedback delete <id>   delete a report (text or quiz) with its files
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime/debug"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// Report is what the app sends.
type Report struct {
	ID      string            `json:"id"`
	Kind    string            `json:"kind"`
	Text    string            `json:"text"`
	Info    map[string]string `json:"info"`
	Created string            `json:"created"`
}

const (
	maxBody = 128 << 10
	// The app allows 2000 characters; one emoji can be several code points.
	maxText   = 20000
	maxInfo   = 100
	perClient = 5  // reports per client and hour
	perHour   = 60 // reports per hour, all clients together
)

var (
	idPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)
	kinds     = map[string]string{"bug": "Bug", "idea": "Idea", "word": "Word or picture", "other": "Other"}
	infoKeys  = map[string]bool{"app": true, "phone": true, "android": true, "studyLang": true, "uiLang": true}
)

// Validate checks a report; the error text goes back to the app.
func (r *Report) Validate() error {
	if !idPattern.MatchString(r.ID) {
		return errors.New("bad id")
	}
	if _, ok := kinds[r.Kind]; !ok {
		return errors.New("bad kind")
	}
	t := strings.TrimSpace(r.Text)
	if t == "" || !utf8.ValidString(r.Text) || utf8.RuneCountInString(r.Text) > maxText {
		return errors.New("bad text")
	}
	if len(r.Info) > len(infoKeys) {
		return errors.New("bad info")
	}
	for k, v := range r.Info {
		if !infoKeys[k] || utf8.RuneCountInString(v) > maxInfo || !utf8.ValidString(v) {
			return errors.New("bad info")
		}
	}
	if _, err := time.Parse(time.RFC3339, r.Created); err != nil {
		return errors.New("bad created")
	}
	return nil
}

// Store keeps reports.
type Store interface {
	// Save stores r; storing the same id again is a no-op.
	Save(r *Report, received time.Time) error
}

// Server is the HTTP handler.
type Server struct {
	Store Store
	// Quiz stores quiz reports; nil: the route answers 404.
	Quiz QuizStore
	Now  func() time.Time

	limit, quizLimit *limiter
	quizSlots        chan struct{}
}

func NewServer(st Store) *Server {
	return &Server{
		Store: st, Now: time.Now,
		limit: newLimiter(perClient, perHour),
		// one question at a time while a parent watches the child play
		quizLimit: newLimiter(quizPerClient, quizPerHour),
		quizSlots: make(chan struct{}, quizUploads),
	}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/pp-app/api/health":
		fmt.Fprintln(w, "ok")
		return
	case "/pp-app/api/feedback":
	case "/pp-app/api/quiz-report":
		s.serveQuiz(w, r)
		return
	default:
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var rep Report
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBody))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&rep); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if err := rep.Validate(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.limit.allow(clientIP(r), s.Now()) {
		http.Error(w, "too many reports, try later", http.StatusTooManyRequests)
		return
	}
	if err := s.Store.Save(&rep, s.Now()); err != nil {
		log.Printf("report %s: %v", rep.ID, err)
		http.Error(w, "try later", http.StatusServiceUnavailable)
		return
	}
	log.Printf("report %s stored (%s)", rep.ID, rep.Kind)
	w.WriteHeader(http.StatusCreated)
}

// limiter counts reports per client and in all, for one hour.
type limiter struct {
	perClient, perHour int

	mu      sync.Mutex
	clients map[string][]time.Time
	all     []time.Time
}

func newLimiter(perClient, perHour int) *limiter {
	return &limiter{perClient: perClient, perHour: perHour, clients: map[string][]time.Time{}}
}

// allow counts a report of client and tells whether it is within the limits.
func (s *limiter) allow(client string, now time.Time) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	recent := func(ts []time.Time) []time.Time {
		out := ts[:0]
		for _, t := range ts {
			if now.Sub(t) < time.Hour {
				out = append(out, t)
			}
		}
		return out
	}
	s.all = recent(s.all)
	c := recent(s.clients[client])
	if len(c) >= s.perClient || len(s.all) >= s.perHour {
		s.clients[client] = c
		return false
	}
	s.clients[client] = append(c, now)
	s.all = append(s.all, now)
	if len(s.clients) > 10000 {
		s.clients = map[string][]time.Time{} // memory bound; limits restart
	}
	return true
}

// clientIP is the address Traefik saw: the last X-Forwarded-For entry
// (the ones before it come from the client and can be made up). An IPv6
// address counts as its /64: one connection usually has a whole /64.
func clientIP(r *http.Request) string {
	addr := ""
	if f := r.Header.Get("X-Forwarded-For"); f != "" {
		parts := strings.Split(f, ",")
		addr = strings.TrimSpace(parts[len(parts)-1])
	} else if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		addr = host
	} else {
		addr = r.RemoteAddr
	}
	ip := net.ParseIP(addr)
	if ip == nil || ip.To4() != nil {
		return addr
	}
	return ip.Mask(net.CIDRMask(64, 128)).String() + "/64"
}

// Dir stores each report as <dir>/<received>-<id>.json.
type Dir struct {
	Path string
	mu   sync.Mutex // one Save at a time: the duplicate and Max checks

	// Max reports kept; more are refused (a full disk would hurt the
	// other services on the vps).
	Max int

	// Keep is how long a report is kept; 0 means [Keep].
	Keep time.Duration
}

func (d *Dir) keep() time.Duration {
	if d.Keep > 0 {
		return d.Keep
	}
	return Keep
}

// stored tells whether a report with this id is stored, and how many
// reports are (a .tmp left by a crash and a report's other files do not
// count). Call with d.mu held.
func (d *Dir) stored(id string) (found bool, n int, err error) {
	entries, err := os.ReadDir(d.Path)
	if err != nil {
		return false, 0, err
	}
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		n++
		if strings.HasSuffix(e.Name(), "-"+id+".json") {
			found = true
		}
	}
	return found, n, nil
}

// write writes b to name atomically.
func write(name string, b []byte) error {
	tmp := name + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, name)
}

// Stored is a report as written to disk.
type Stored struct {
	Report
	Received string `json:"received"`
}

func (d *Dir) Save(r *Report, received time.Time) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	found, n, err := d.stored(r.ID)
	if err != nil {
		return err
	}
	if found {
		return nil // a retry: stored already
	}
	if n >= d.Max {
		return errors.New("store is full")
	}
	b, err := json.MarshalIndent(Stored{Report: *r, Received: received.UTC().Format(time.RFC3339)}, "", "  ")
	if err != nil {
		return err
	}
	return write(filepath.Join(d.Path, received.UTC().Format(stamp)+"-"+r.ID+".json"), append(b, '\n'))
}

// stamp is the time format of the file names.
const stamp = "20060102T150405Z"

// Keep is how long a report is kept (PRIVACY.md says twelve months).
const Keep = 365 * 24 * time.Hour

// Prune deletes the files of reports received more than d's keep time
// before now; it returns how many files. The time is the file name's
// prefix.
func (d *Dir) Prune(now time.Time) (int, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	entries, err := os.ReadDir(d.Path)
	if err != nil {
		return 0, err
	}
	cut := now.Add(-d.keep())
	n := 0
	for _, e := range entries {
		ts, _, ok := strings.Cut(e.Name(), "-")
		if !ok {
			continue
		}
		t, err := time.Parse(stamp, ts)
		if err != nil || !t.Before(cut) {
			continue
		}
		if err := os.Remove(filepath.Join(d.Path, e.Name())); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

// Delete removes the report with this id (a deletion request: the app
// shows the id before sending). It reports whether one was found.
func (d *Dir) Delete(id string) (bool, error) {
	if !idPattern.MatchString(id) {
		return false, errors.New("not a report id")
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	entries, err := os.ReadDir(d.Path)
	if err != nil {
		return false, err
	}
	found := false
	for _, e := range entries {
		// the report and its recordings (<stamp>-<id>-<n>.wav)
		if strings.Contains(e.Name(), "-"+id+".") || strings.Contains(e.Name(), "-"+id+"-") {
			if err := os.Remove(filepath.Join(d.Path, e.Name())); err != nil {
				return found, err
			}
			found = true
		}
	}
	return found, nil
}

// List prints all stored reports, newest first.
func (d *Dir) List(w io.Writer) error {
	entries, err := os.ReadDir(d.Path)
	if err != nil {
		return err
	}
	var names []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".json") {
			names = append(names, e.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(names)))
	for _, n := range names {
		b, err := os.ReadFile(filepath.Join(d.Path, n))
		if err != nil {
			return err
		}
		fmt.Fprintf(w, "== %s\n%s\n", n, b)
	}
	return nil
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	if os.Getenv("GOMEMLIMIT") == "" {
		debug.SetMemoryLimit(48 << 20) // the pod has 64 MiB
	}
	dir := &Dir{Path: env("DIR", "/data/feedback"), Max: 20000}
	quiz := &Dir{Path: env("QUIZ_DIR", "/data/quiz"), Max: quizMax, Keep: QuizKeep}
	if len(os.Args) > 1 {
		if err := command(os.Args[1:], dir, quiz, os.Stdout); err != nil {
			log.Fatal(err)
		}
		return
	}
	for _, d := range []*Dir{dir, quiz} {
		if err := os.MkdirAll(d.Path, 0o700); err != nil {
			log.Fatal(err)
		}
	}
	addr := env("LISTEN", ":8080")
	handler := NewServer(dir)
	handler.Quiz = quiz
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		// text reports; the quiz route sets its own deadlines
		ReadTimeout:  20 * time.Second,
		WriteTimeout: 20 * time.Second,
	}
	go func() {
		for {
			for _, d := range []*Dir{dir, quiz} {
				if n, err := d.Prune(time.Now()); err != nil {
					log.Printf("prune %s: %v", d.Path, err)
				} else if n > 0 {
					log.Printf("pruned %d files older than %s in %s", n, d.keep(), d.Path)
				}
			}
			time.Sleep(24 * time.Hour)
		}
	}()
	log.Printf("feedback into %s on %s", dir.Path, addr)
	log.Fatal(srv.ListenAndServe())
}
