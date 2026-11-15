package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type fakeIssuer struct {
	created []string
	filed   map[string]bool
	err     error
}

func (f *fakeIssuer) Create(_ context.Context, title, body string, labels []string) error {
	if f.err != nil {
		return f.err
	}
	f.created = append(f.created, title+"\n"+body+"\n"+strings.Join(labels, ","))
	return nil
}

func (f *fakeIssuer) Filed(_ context.Context, id string) (bool, error) {
	return f.filed[id], f.err
}

func report(id, text string) string {
	b, _ := json.Marshal(Report{
		ID: id, Kind: "bug", Text: text,
		Info:    map[string]string{"app": "0.1.40", "phone": "Samsung SM-A805F"},
		Created: "2026-11-15T10:00:00Z",
	})
	return string(b)
}

func post(s http.Handler, body, ip string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodPost, "/pp-app/api/feedback", strings.NewReader(body))
	r.Header.Set("X-Forwarded-For", "6.6.6.6, "+ip)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}

const id1 = "0123456789abcdef0123456789abcdef"

func TestFilesAnIssueOnce(t *testing.T) {
	f := &fakeIssuer{}
	s := NewServer(f)
	if w := post(s, report(id1, "Der Hai wird nicht erkannt"), "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code, w.Body)
	}
	// the app retries when the answer got lost: not filed twice
	if w := post(s, report(id1, "Der Hai wird nicht erkannt"), "1.1.1.1"); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if len(f.created) != 1 {
		t.Fatal(f.created)
	}
	c := f.created[0]
	for _, want := range []string{"Bug: Der Hai wird nicht erkannt", "~~~~text\nDer Hai", "| phone | `Samsung SM-A805F` |", "report-id: " + id1, "feedback,bug"} {
		if !strings.Contains(c, want) {
			t.Errorf("missing %q in\n%s", want, c)
		}
	}
}

func TestFiledBeforeARestart(t *testing.T) {
	f := &fakeIssuer{filed: map[string]bool{id1: true}}
	if w := post(NewServer(f), report(id1, "x"), "1.1.1.1"); w.Code != 201 || len(f.created) != 0 {
		t.Fatal(w.Code, f.created)
	}
}

func TestRejectsBadReports(t *testing.T) {
	s := NewServer(&fakeIssuer{})
	for name, body := range map[string]string{
		"id":      report("xyz", "a"),
		"empty":   report(id1, "   "),
		"long":    report(id1, strings.Repeat("a", maxText+1)),
		"json":    "{",
		"unknown": `{"id":"` + id1 + `","kind":"bug","text":"a","created":"2026-11-15T10:00:00Z","audio":"..."}`,
		"info":    `{"id":"` + id1 + `","kind":"bug","text":"a","created":"2026-11-15T10:00:00Z","info":{"email":"x"}}`,
		"kind":    `{"id":"` + id1 + `","kind":"spam","text":"a","created":"2026-11-15T10:00:00Z"}`,
	} {
		if w := post(s, body, "1.1.1.1"); w.Code != 400 {
			t.Errorf("%s: %d", name, w.Code)
		}
	}
}

func TestRateLimits(t *testing.T) {
	f := &fakeIssuer{}
	s := NewServer(f)
	now := time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC)
	s.Now = func() time.Time { return now }
	id := func(i int) string {
		return strings.Repeat("0", 30) + string("0123456789abcdef"[i/16]) + string("0123456789abcdef"[i%16])
	}
	for i := 0; i < perClient; i++ {
		if w := post(s, report(id(i), "a"), "1.1.1.1"); w.Code != 201 {
			t.Fatal(i, w.Code)
		}
	}
	if w := post(s, report(id(50), "a"), "1.1.1.1"); w.Code != 429 {
		t.Fatal("per client:", w.Code)
	}
	// the made-up first X-Forwarded-For entry does not help
	if w := post(s, report(id(51), "a"), "2.2.2.2"); w.Code != 201 {
		t.Fatal("other client:", w.Code)
	}
	now = now.Add(61 * time.Minute)
	if w := post(s, report(id(52), "a"), "1.1.1.1"); w.Code != 201 {
		t.Fatal("after an hour:", w.Code)
	}
}

func TestGitHubDownMeansLater(t *testing.T) {
	f := &fakeIssuer{err: context.DeadlineExceeded}
	if w := post(NewServer(f), report(id1, "a"), "1.1.1.1"); w.Code != 502 {
		t.Fatal(w.Code)
	}
}

func TestUserTextCannotMentionOrBreakOut(t *testing.T) {
	r := &Report{ID: id1, Kind: "idea", Text: "@guettli look\n~~~~\n# boom", Created: "2026-11-15T10:00:00Z",
		Info: map[string]string{"phone": "x | y @z"}}
	title, body := Issue(r)
	if strings.Contains(title, "@") {
		t.Error(title)
	}
	if !strings.Contains(body, "~~~~~text\n@guettli look\n~~~~\n# boom\n~~~~~\n") {
		t.Error(body)
	}
	if !strings.Contains(body, "`x \\| y ＠z`") {
		t.Error(body)
	}
}

func TestGitHubClient(t *testing.T) {
	var got []string
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = append(got, r.Method+" "+r.URL.RequestURI()+" "+r.Header.Get("Authorization"))
		if r.Method == http.MethodGet {
			w.Write([]byte(`{"total_count":0}`))
			return
		}
		w.WriteHeader(201)
	}))
	defer api.Close()
	g := &GitHub{Token: "t", Repo: "guettli/pp-app", API: api.URL, Client: api.Client()}
	filed, err := g.Filed(context.Background(), id1)
	if err != nil || filed {
		t.Fatal(filed, err)
	}
	if err := g.Create(context.Background(), "a", "b", []string{"feedback"}); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got[0], "GET /search/issues?q=repo%3Aguettli%2Fpp-app+is%3Aissue") || !strings.HasSuffix(got[1], "Bearer t") {
		t.Fatal(got)
	}
}

func TestNoTokenMeansLater(t *testing.T) {
	if w := post(NewServer(nil), report(id1, "a"), "1.1.1.1"); w.Code != 503 {
		t.Fatal(w.Code)
	}
}
