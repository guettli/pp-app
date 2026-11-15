// Command feedback takes feedback and bug reports from the Phoneme Party
// app (lib/net/feedback.dart) and files each as a GitHub issue in
// guettli/pp-app. The GitHub token stays here, never in the app.
//
// Reports are anonymous: text the grown-up typed, the app version, the
// languages, phone model and Android version. Nothing is stored here and
// client addresses are not logged; they are only held in memory for the
// rate limit.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
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
	maxBody   = 16 << 10
	maxText   = 4000
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

// Issuer files an issue; Filed tells whether a report id was filed before.
type Issuer interface {
	Create(ctx context.Context, title, body string, labels []string) error
	Filed(ctx context.Context, id string) (bool, error)
}

// Server is the HTTP handler.
type Server struct {
	Issuer Issuer
	Now    func() time.Time

	mu      sync.Mutex
	seen    map[string]bool // report ids filed since the start
	clients map[string][]time.Time
	all     []time.Time
}

func NewServer(i Issuer) *Server {
	return &Server{Issuer: i, Now: time.Now, seen: map[string]bool{}, clients: map[string][]time.Time{}}
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
	if s.wasSeen(rep.ID) {
		w.WriteHeader(http.StatusOK) // a retry: filed already
		return
	}
	if !s.allow(clientIP(r)) {
		http.Error(w, "too many reports, try later", http.StatusTooManyRequests)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	filed, err := s.Issuer.Filed(ctx, rep.ID)
	if err == nil && !filed {
		title, body := Issue(&rep)
		err = s.Issuer.Create(ctx, title, body, []string{"feedback", rep.Kind})
	}
	if err != nil {
		log.Printf("report %s: %v", rep.ID, err)
		http.Error(w, "try later", http.StatusBadGateway)
		return
	}
	s.markSeen(rep.ID)
	log.Printf("report %s filed (%s)", rep.ID, rep.Kind)
	w.WriteHeader(http.StatusCreated)
}

func (s *Server) wasSeen(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.seen[id]
}

func (s *Server) markSeen(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.seen) > 10000 {
		s.seen = map[string]bool{}
	}
	s.seen[id] = true
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
// (the ones before it come from the client and can be made up).
func clientIP(r *http.Request) string {
	if f := r.Header.Get("X-Forwarded-For"); f != "" {
		parts := strings.Split(f, ",")
		return strings.TrimSpace(parts[len(parts)-1])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// Issue renders a report as an issue. The text is user input: it goes into
// a fenced block (no markdown, links or @-mentions there), and the title
// cannot mention anyone either.
func Issue(r *Report) (title, body string) {
	text := strings.TrimSpace(r.Text)
	first := strings.SplitN(text, "\n", 2)[0]
	if utf8.RuneCountInString(first) > 60 {
		first = string([]rune(first)[:60]) + "…"
	}
	title = fmt.Sprintf("%s: %s", kinds[r.Kind], noMention(first))
	fence := "~~~~"
	for strings.Contains(text, fence) {
		fence += "~"
	}
	var b bytes.Buffer
	fmt.Fprintf(&b, "Feedback from the app (%s).\n\n%stext\n%s\n%s\n\n", kinds[r.Kind], fence, text, fence)
	keys := make([]string, 0, len(r.Info))
	for k := range r.Info {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	b.WriteString("| | |\n|---|---|\n")
	for _, k := range keys {
		fmt.Fprintf(&b, "| %s | %s |\n", k, cell(r.Info[k]))
	}
	fmt.Fprintf(&b, "| created | %s |\n\n<!-- report-id: %s -->\n", cell(r.Created), r.ID)
	return title, b.String()
}

func noMention(s string) string { return strings.ReplaceAll(s, "@", "＠") }

// cell makes a value safe for a markdown table cell.
func cell(s string) string {
	s = strings.NewReplacer("|", "\\|", "\n", " ", "\r", " ", "<", "&lt;", ">", "&gt;").Replace(s)
	return noMention("`" + strings.ReplaceAll(s, "`", "'") + "`")
}

// GitHub files issues with a token that may only write issues of one repo.
type GitHub struct {
	Token, Repo string
	API         string // https://api.github.com
	Client      *http.Client
}

func (g *GitHub) do(ctx context.Context, method, path string, in, out any) error {
	var body bytes.Buffer
	if in != nil {
		if err := json.NewEncoder(&body).Encode(in); err != nil {
			return err
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, g.API+path, &body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+g.Token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	res, err := g.Client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode/100 != 2 {
		return fmt.Errorf("github %s %s: %s", method, path, res.Status)
	}
	if out != nil {
		return json.NewDecoder(res.Body).Decode(out)
	}
	return nil
}

func (g *GitHub) Create(ctx context.Context, title, body string, labels []string) error {
	return g.do(ctx, http.MethodPost, "/repos/"+g.Repo+"/issues",
		map[string]any{"title": title, "body": body, "labels": labels}, nil)
}

// Filed searches the repo for the report id (a retry after a restart).
func (g *GitHub) Filed(ctx context.Context, id string) (bool, error) {
	var res struct {
		TotalCount int `json:"total_count"`
	}
	q := fmt.Sprintf("repo:%s is:issue in:body %q", g.Repo, "report-id: "+id)
	err := g.do(ctx, http.MethodGet, "/search/issues?q="+urlQuery(q), nil, &res)
	return res.TotalCount > 0, err
}

func urlQuery(s string) string {
	r := strings.NewReplacer(" ", "+", ":", "%3A", "\"", "%22", "/", "%2F")
	return r.Replace(s)
}

func main() {
	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		log.Fatal("GITHUB_TOKEN is not set")
	}
	repo := os.Getenv("REPO")
	if repo == "" {
		repo = "guettli/pp-app"
	}
	addr := os.Getenv("LISTEN")
	if addr == "" {
		addr = ":8080"
	}
	gh := &GitHub{Token: token, Repo: repo, API: "https://api.github.com", Client: &http.Client{Timeout: 15 * time.Second}}
	srv := &http.Server{
		Addr:              addr,
		Handler:           NewServer(gh),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       20 * time.Second,
		WriteTimeout:      40 * time.Second,
	}
	log.Printf("feedback for %s on %s", repo, addr)
	log.Fatal(srv.ListenAndServe())
}
