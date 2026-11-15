package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

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

func newDir(t *testing.T, max int) *Dir {
	return &Dir{Path: t.TempDir(), Max: max}
}

func files(t *testing.T, d *Dir) []string {
	e, err := os.ReadDir(d.Path)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, f := range e {
		out = append(out, f.Name())
	}
	return out
}

func TestStoresAReportOnce(t *testing.T) {
	d := newDir(t, 100)
	s := NewServer(d)
	s.Now = func() time.Time { return time.Date(2026, 11, 15, 10, 1, 2, 0, time.UTC) }
	if w := post(s, report(id1, "Der Hai wird nicht erkannt"), "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code, w.Body)
	}
	// the app retries when the answer got lost: stored once
	if w := post(s, report(id1, "Der Hai wird nicht erkannt"), "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code)
	}
	f := files(t, d)
	if len(f) != 1 || f[0] != "20261115T100102Z-"+id1+".json" {
		t.Fatal(f)
	}
	var got Stored
	b, _ := os.ReadFile(filepath.Join(d.Path, f[0]))
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if got.Text != "Der Hai wird nicht erkannt" || got.Info["phone"] != "Samsung SM-A805F" || got.Received != "2026-11-15T10:01:02Z" {
		t.Fatal(string(b))
	}
	if strings.Contains(string(b), "1.1.1.1") {
		t.Fatal("client address stored")
	}
	var out bytes.Buffer
	if err := d.List(&out); err != nil || !strings.Contains(out.String(), "Der Hai") {
		t.Fatal(err, out.String())
	}
}

func TestRejectsBadReports(t *testing.T) {
	d := newDir(t, 100)
	s := NewServer(d)
	for name, body := range map[string]string{
		"id":      report("xyz", "a"),
		"path":    report("../../etc/passwd0123456789abcdef", "a"),
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
	if f := files(t, d); len(f) != 0 {
		t.Fatal(f)
	}
}

func id(i int) string {
	const hex = "0123456789abcdef"
	return strings.Repeat("0", 30) + string(hex[i/16]) + string(hex[i%16])
}

func TestRateLimits(t *testing.T) {
	s := NewServer(newDir(t, 100))
	now := time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC)
	s.Now = func() time.Time { return now }
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

func TestIPv6CountsPerSlash64(t *testing.T) {
	s := NewServer(newDir(t, 100))
	for i := 0; i < perClient; i++ {
		post(s, report(id(i), "a"), "2001:db8:1:2::"+string("123456789"[i]))
	}
	if w := post(s, report(id(40), "a"), "2001:db8:1:2:ffff::1"); w.Code != 429 {
		t.Fatal("same /64:", w.Code)
	}
	if w := post(s, report(id(41), "a"), "2001:db8:1:3::1"); w.Code != 201 {
		t.Fatal("other /64:", w.Code)
	}
}

func TestLeftoverTmpDoesNotCount(t *testing.T) {
	d := newDir(t, 1)
	os.WriteFile(filepath.Join(d.Path, "x.json.tmp"), []byte("{"), 0o600)
	if w := post(NewServer(d), report(id1, "a"), "1.1.1.1"); w.Code != 201 {
		t.Fatal(w.Code)
	}
}

func TestFullMeansLater(t *testing.T) {
	d := newDir(t, 1)
	s := NewServer(d)
	post(s, report(id(1), "a"), "1.1.1.1")
	if w := post(s, report(id(2), "a"), "2.2.2.2"); w.Code != 503 {
		t.Fatal(w.Code)
	}
}

type failing struct{}

func (failing) Save(*Report, time.Time) error { return errors.New("disk") }

func TestStoreErrorMeansLater(t *testing.T) {
	if w := post(NewServer(failing{}), report(id1, "a"), "1.1.1.1"); w.Code != 503 {
		t.Fatal(w.Code)
	}
}

func TestHealthAndMethods(t *testing.T) {
	s := NewServer(newDir(t, 1))
	w := httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/pp-app/api/health", nil))
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	w = httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/pp-app/api/feedback", nil))
	if w.Code != 405 {
		t.Fatal(w.Code)
	}
}

func TestPruneDeletesOnlyOldReports(t *testing.T) {
	d := newDir(t, 10)
	now := time.Date(2027, 12, 1, 0, 0, 0, 0, time.UTC)
	old := &Report{ID: id1, Kind: "bug", Text: "old", Created: "x"}
	fresh := &Report{ID: strings.Repeat("b", 32), Kind: "bug", Text: "new", Created: "x"}
	if err := d.Save(old, now.Add(-Keep-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := d.Save(fresh, now.Add(-Keep+time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d.Path, "notes.txt"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	n, err := d.Prune(now)
	if err != nil || n != 1 {
		t.Fatalf("pruned %d, %v", n, err)
	}
	got := strings.Join(files(t, d), " ")
	if strings.Contains(got, id1) || !strings.Contains(got, fresh.ID) || !strings.Contains(got, "notes.txt") {
		t.Fatalf("left %s", got)
	}
}

func TestDeleteByID(t *testing.T) {
	d := newDir(t, 10)
	if err := d.Save(&Report{ID: id1, Kind: "bug", Text: "x", Created: "x"}, time.Now()); err != nil {
		t.Fatal(err)
	}
	if found, err := d.Delete(id1); err != nil || !found {
		t.Fatalf("found %v, %v", found, err)
	}
	if found, err := d.Delete(id1); err != nil || found {
		t.Fatalf("twice: found %v, %v", found, err)
	}
	if _, err := d.Delete("../x"); err == nil {
		t.Fatal("a path is not an id")
	}
	if len(files(t, d)) != 0 {
		t.Fatal(files(t, d))
	}
}
