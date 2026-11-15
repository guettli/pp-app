// Command feedback takes feedback and bug reports from the Phoneme Party
// app (lib/net/feedback.dart) and stores each as a JSON file in a
// directory (a volume on the vps). Nothing is published.
//
// Reports are anonymous: text the grown-up typed, the app version, the
// languages, phone model and Android version. This service neither stores
// nor logs client addresses; it only holds them in memory for the rate
// limit (Traefik in front of it sees them, as for every request).
//
//	feedback            serve (LISTEN, default :8080; DIR, default /data/feedback)
//	feedback list       print the stored reports, newest first
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
	Now   func() time.Time

	mu      sync.Mutex
	clients map[string][]time.Time
	all     []time.Time
}

func NewServer(st Store) *Server {
	return &Server{Store: st, Now: time.Now, clients: map[string][]time.Time{}}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/pp-app/api/health":
		fmt.Fprintln(w, "ok")
		return
	case "/pp-app/api/feedback":
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
	if !s.allow(clientIP(r)) {
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

// allow counts a report of client and tells whether it is within the limits.
func (s *Server) allow(client string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.Now()
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
	if len(c) >= perClient || len(s.all) >= perHour {
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
}

// Stored is a report as written to disk.
type Stored struct {
	Report
	Received string `json:"received"`
}

func (d *Dir) Save(r *Report, received time.Time) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	entries, err := os.ReadDir(d.Path)
	if err != nil {
		return err
	}
	stored := 0
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue // a .tmp left by a crash
		}
		stored++
		if strings.HasSuffix(e.Name(), "-"+r.ID+".json") {
			return nil // a retry: stored already
		}
	}
	if stored >= d.Max {
		return errors.New("store is full")
	}
	b, err := json.MarshalIndent(Stored{Report: *r, Received: received.UTC().Format(time.RFC3339)}, "", "  ")
	if err != nil {
		return err
	}
	name := filepath.Join(d.Path, received.UTC().Format("20060102T150405Z")+"-"+r.ID+".json")
	tmp := name + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, name)
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
	dir := &Dir{Path: env("DIR", "/data/feedback"), Max: 20000}
	if len(os.Args) > 1 && os.Args[1] == "list" {
		if err := dir.List(os.Stdout); err != nil {
			log.Fatal(err)
		}
		return
	}
	if err := os.MkdirAll(dir.Path, 0o700); err != nil {
		log.Fatal(err)
	}
	addr := env("LISTEN", ":8080")
	srv := &http.Server{
		Addr:              addr,
		Handler:           NewServer(dir),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       20 * time.Second,
		WriteTimeout:      20 * time.Second,
	}
	log.Printf("feedback into %s on %s", dir.Path, addr)
	log.Fatal(srv.ListenAndServe())
}
