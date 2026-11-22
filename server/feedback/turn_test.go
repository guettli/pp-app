package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

func turnServer() *Server {
	s := NewServer(nil)
	s.Now = func() time.Time { return time.Unix(1_800_000_000, 0) }
	s.TURN = &TURN{Secret: []byte("geheim"), URLs: []string{
		"turn:relaxandplay.de:3478?transport=udp", "turn:relaxandplay.de:3478?transport=tcp"}}
	return s
}

func askTURN(s http.Handler, method, ip string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "/pp-app/api/turn", nil)
	r.Header.Set("X-Forwarded-For", ip)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}

func TestTURNCredentialIsCoturnsRESTCredential(t *testing.T) {
	w := askTURN(turnServer(), http.MethodPost, "1.1.1.1")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Error("cacheable")
	}
	var a TURNAnswer
	if err := json.Unmarshal(w.Body.Bytes(), &a); err != nil {
		t.Fatal(err)
	}
	if a.TTL != 3600 || len(a.ICEServers) != 2 {
		t.Fatalf("%+v", a)
	}
	if got := a.ICEServers[0].URLs; len(got) != 1 || got[0] != "stun:relaxandplay.de:3478" || a.ICEServers[0].Username != "" {
		t.Errorf("stun %+v", a.ICEServers[0])
	}
	relay := a.ICEServers[1]
	exp, ok := strings.CutSuffix(relay.Username, ":pp")
	if !ok {
		t.Fatal(relay.Username)
	}
	// valid for turnTTL from now
	if n, _ := strconv.ParseInt(exp, 10, 64); n != 1_800_000_000+3600 {
		t.Error(exp)
	}
	m := hmac.New(sha1.New, []byte("geheim"))
	m.Write([]byte(relay.Username))
	if relay.Credential != base64.StdEncoding.EncodeToString(m.Sum(nil)) {
		t.Error("credential is not HMAC-SHA1(secret, username)")
	}
	if len(relay.URLs) != 2 {
		t.Error(relay.URLs)
	}
}

func TestTURNNeedsASecretAndPOST(t *testing.T) {
	s := turnServer()
	if w := askTURN(s, http.MethodGet, "1.1.1.1"); w.Code != 405 {
		t.Error(w.Code)
	}
	s.TURN = nil
	if w := askTURN(s, http.MethodPost, "1.1.1.1"); w.Code != 404 {
		t.Error(w.Code)
	}
}

func TestTURNIsRateLimited(t *testing.T) {
	s := turnServer()
	for i := 0; i < turnPerClient; i++ {
		if w := askTURN(s, http.MethodPost, "1.1.1.1"); w.Code != 200 {
			t.Fatal(i, w.Code)
		}
	}
	if w := askTURN(s, http.MethodPost, "1.1.1.1"); w.Code != 429 {
		t.Error(w.Code)
	}
	if w := askTURN(s, http.MethodPost, "2.2.2.2"); w.Code != 200 {
		t.Error("other client", w.Code)
	}
}

func TestTURNFromEnv(t *testing.T) {
	t.Setenv("TURN_SECRET", "")
	if turnFromEnv() != nil {
		t.Error("no secret, no route")
	}
	t.Setenv("TURN_SECRET", "x\n")
	t.Setenv("TURN_URLS", " turn:a:3478?transport=udp, ,turn:a:3478?transport=tcp")
	tu := turnFromEnv()
	if string(tu.Secret) != "x" || len(tu.URLs) != 2 || tu.URLs[0] != "turn:a:3478?transport=udp" {
		t.Errorf("%q %q", tu.Secret, tu.URLs)
	}
	if s := tu.stunURLs(); len(s) != 1 || s[0] != "stun:a:3478" {
		t.Error(s)
	}
}
