package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) add(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

func matchServer() (*Server, *clock) {
	c := &clock{t: time.Unix(1_800_000_000, 0)}
	s := NewServer(nil)
	s.Now = c.now
	s.Matches = NewMatches(c.now)
	s.Matches.wait = 300 * time.Millisecond
	return s, c
}

type obj = map[string]any

func call(t *testing.T, s http.Handler, op, ip string, body any) (int, obj) {
	t.Helper()
	b, _ := json.Marshal(body)
	r := httptest.NewRequest(http.MethodPost, "/pp-app/api/match/"+op, strings.NewReader(string(b)))
	r.Header.Set("X-Forwarded-For", ip)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	var out obj
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

const nonce = "00112233445566778899aabbccddeeff"

func create(t *testing.T, s http.Handler, ip string) (code, host string) {
	t.Helper()
	st, m := call(t, s, "new", ip, obj{})
	if st != 201 {
		t.Fatal("new", st)
	}
	code, host = m["code"].(string), m["token"].(string)
	if !codePattern.MatchString(code) || len(host) != 32 {
		t.Fatal(code, host)
	}
	return code, host
}

func join(t *testing.T, s http.Handler, code string) string {
	t.Helper()
	st, m := call(t, s, "join", "2.2.2.2", obj{"code": code, "nonce": nonce, "animal": 5})
	if st != 200 {
		t.Fatal("join", st)
	}
	return m["token"].(string)
}

func open(t *testing.T, s http.Handler) (code, host, guest string) {
	code, host = create(t, s, "1.1.1.1")
	return code, host, join(t, s, code)
}

func msgs(m obj) []obj {
	var out []obj
	for _, x := range m["msgs"].([]any) {
		out = append(out, x.(obj))
	}
	return out
}

func body(x obj) obj { return x["msg"].(obj) }

func recv(t *testing.T, s http.Handler, ip, code, tok string, after int) (int, []obj, int) {
	t.Helper()
	st, m := call(t, s, "recv", ip, obj{"code": code, "token": tok, "after": after})
	if st != 200 {
		return st, nil, 0
	}
	return st, msgs(m), int(m["next"].(float64))
}

func TestMatchSwapsOfferAndAnswer(t *testing.T) {
	s, _ := matchServer()
	code, host := create(t, s, "1.1.1.1")
	// the host may send before anyone joined; the guest gets it later
	if st, _ := call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": obj{"type": "hello"}}); st != 204 {
		t.Fatal(st)
	}
	guest := join(t, s, code)

	// the host learns who joined
	_, got, next := recv(t, s, "1.1.1.1", code, host, 0)
	if len(got) != 1 || got[0]["from"] != "service" || body(got[0])["type"] != "joined" || body(got[0])["animal"] != 5.0 {
		t.Fatal(got)
	}
	call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": obj{"type": "offer", "sdp": "v=0"}})
	// the guest gets the host's messages from before and after it joined,
	// and the joined note, never its own
	_, got, gnext := recv(t, s, "2.2.2.2", code, guest, 0)
	if len(got) != 3 || body(got[0])["type"] != "hello" || body(got[2])["sdp"] != "v=0" {
		t.Fatal(got)
	}
	call(t, s, "send", "2.2.2.2", obj{"code": code, "token": guest, "msg": obj{"type": "answer"}})
	_, got, _ = recv(t, s, "1.1.1.1", code, host, next)
	if len(got) != 1 || got[0]["from"] != "guest" {
		t.Fatal(got)
	}
	// nothing new for the guest: the recv times out empty
	if st, got, _ := recv(t, s, "2.2.2.2", code, guest, gnext+1); st != 200 || len(got) != 0 {
		t.Fatal(st, got)
	}
}

func TestMatchRecvWaitsForAMessage(t *testing.T) {
	s, _ := matchServer()
	s.Matches.wait = 5 * time.Second
	code, host, guest := open(t, s)
	_, _, after := recv(t, s, "2.2.2.2", code, guest, 0)
	done := make(chan []obj)
	go func() {
		_, got, _ := recv(t, s, "2.2.2.2", code, guest, after)
		done <- got
	}()
	select {
	case got := <-done:
		t.Fatal("did not wait", got)
	case <-time.After(100 * time.Millisecond):
	}
	call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": 1})
	select {
	case got := <-done:
		if len(got) != 1 {
			t.Fatal(got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("recv did not wake")
	}
}

func TestMatchNewerRecvEndsTheOlder(t *testing.T) {
	s, _ := matchServer()
	s.Matches.wait = 5 * time.Second
	code, _, guest := open(t, s)
	_, _, after := recv(t, s, "2.2.2.2", code, guest, 0)
	done := make(chan int)
	go func() {
		st, _, _ := recv(t, s, "2.2.2.2", code, guest, after)
		done <- st
	}()
	time.Sleep(50 * time.Millisecond)
	go recv(t, s, "2.2.2.2", code, guest, after)
	select {
	case st := <-done:
		if st != 200 {
			t.Error(st)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("older recv still waits")
	}
}

func TestMatchHostRejectsAStranger(t *testing.T) {
	s, _ := matchServer()
	code, host, stranger := open(t, s)
	if st, _ := call(t, s, "reject", "2.2.2.2", obj{"code": code, "token": stranger}); st != 404 {
		t.Error("guest rejected", st)
	}
	if st, _ := call(t, s, "reject", "1.1.1.1", obj{"code": code, "token": host}); st != 204 {
		t.Fatal(st)
	}
	// the stranger is out, the friend can join with the same code
	if st, _, _ := recv(t, s, "2.2.2.2", code, stranger, 0); st != 404 {
		t.Error("stranger still in", st)
	}
	st, m := call(t, s, "join", "3.3.3.3", obj{"code": code, "nonce": strings.Repeat("ab", 8), "animal": 1})
	if st != 200 || m["token"] == stranger {
		t.Fatal(st, m)
	}
}

func TestMatchJoinRetryGetsTheSameToken(t *testing.T) {
	s, _ := matchServer()
	code, _, guest := open(t, s)
	if again := join(t, s, code); again != guest {
		t.Error("retry got another token")
	}
	if st, _ := call(t, s, "join", "3.3.3.3", obj{"code": code, "nonce": strings.Repeat("cd", 8), "animal": 1}); st != 409 {
		t.Error("third phone", st)
	}
}

func TestMatchBadRequests(t *testing.T) {
	s, _ := matchServer()
	code, _, _ := open(t, s)
	other := "0000"
	if code == other {
		other = "0001"
	}
	for _, tc := range []struct {
		op   string
		body obj
		want int
	}{
		{"join", obj{"code": other, "nonce": nonce}, 404},
		{"join", obj{"code": "zz", "nonce": nonce}, 400},
		{"join", obj{"code": code, "nonce": "short"}, 400},
		{"join", obj{"code": code, "nonce": nonce, "animal": 16}, 400},
		{"send", obj{"code": code, "token": "x", "msg": 1}, 404},
		{"recv", obj{"code": code, "token": ""}, 404},
		{"reject", obj{"code": code, "token": "x"}, 404},
		{"send", obj{"code": code, "token": "x", "msg": strings.Repeat("x", matchMsg+2000)}, 413},
	} {
		if st, _ := call(t, s, tc.op, "3.3.3.3", tc.body); st != tc.want {
			t.Errorf("%s %v: %d, want %d", tc.op, tc.body["code"], st, tc.want)
		}
	}
}

func TestMatchExpires(t *testing.T) {
	s, c := matchServer()
	code, _ := create(t, s, "1.1.1.1")
	c.add(matchOpen + time.Second)
	if st, _ := call(t, s, "join", "2.2.2.2", obj{"code": code, "nonce": nonce}); st != 404 {
		t.Error("joined an expired code", st)
	}
	// a joined match lives on while the phones ask
	code, host, guest := open(t, s)
	for i := 0; i < 10; i++ {
		c.add(30 * time.Second)
		if st, _, _ := recv(t, s, "2.2.2.2", code, guest, 0); st != 200 {
			t.Fatal(i, st)
		}
	}
	// ... and ends when nobody asked for a minute
	c.add(matchIdle + time.Second)
	if st, _ := call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": 1}); st != 404 {
		t.Error("idle match lives", st)
	}
	// and after matchLife in any case
	code, host, _ = open(t, s)
	for d := time.Duration(0); d <= matchLife; d += 30 * time.Second {
		c.add(30 * time.Second)
		call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": 1, "id": "same"})
	}
	if st, _ := call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": 1}); st != 404 {
		t.Error("match outlived matchLife", st)
	}
}

func TestMatchLeave(t *testing.T) {
	s, _ := matchServer()
	code, host, guest := open(t, s)
	_, _, after := recv(t, s, "1.1.1.1", code, host, 0)
	for i := 0; i < 50; i++ { // idempotent: one "left" only
		if st, _ := call(t, s, "leave", "2.2.2.2", obj{"code": code, "token": guest}); st != 204 {
			t.Fatal(st)
		}
	}
	_, got, _ := recv(t, s, "1.1.1.1", code, host, after)
	if len(got) != 1 || body(got[0])["type"] != "left" {
		t.Fatal(got)
	}
	if st, _ := call(t, s, "send", "2.2.2.2", obj{"code": code, "token": guest, "msg": 1}); st != 404 {
		t.Error("sent after leaving", st)
	}
	// the code is open again for a friend
	if st, _ := call(t, s, "join", "3.3.3.3", obj{"code": code, "nonce": strings.Repeat("ef", 8)}); st != 200 {
		t.Error("not reopened", st)
	}
	// the host leaving ends the match; a waiting guest recv ends with 404
	s.Matches.wait = 5 * time.Second
	code, host, guest = open(t, s)
	_, _, after = recv(t, s, "2.2.2.2", code, guest, 0)
	done := make(chan int)
	go func() { st, _, _ := recv(t, s, "2.2.2.2", code, guest, after); done <- st }()
	time.Sleep(50 * time.Millisecond)
	call(t, s, "leave", "1.1.1.1", obj{"code": code, "token": host})
	select {
	case st := <-done:
		if st != 404 {
			t.Error(st)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("guest recv still waits")
	}
}

func TestMatchSendRetryIsDropped(t *testing.T) {
	s, _ := matchServer()
	code, host, guest := open(t, s)
	for i := 0; i < 3; i++ {
		call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": obj{"type": "offer"}, "id": "o1"})
	}
	if _, got, _ := recv(t, s, "2.2.2.2", code, guest, 0); len(got) != 2 { // joined + one offer
		t.Error(got)
	}
}

func TestMatchLimits(t *testing.T) {
	s, _ := matchServer()
	code, host, _ := open(t, s)
	half := strings.Repeat("x", matchMsg/2)
	n := 0
	for ; n < 10; n++ {
		if st, _ := call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": half}); st != 204 {
			break
		}
	}
	if n != matchBytes/(matchMsg/2+2) { // 3: a JSON string has its quotes
		t.Error("bytes per phone", n)
	}
	code, host, _ = open(t, s)
	n = 0
	for ; n < 100; n++ {
		if st, _ := call(t, s, "send", "1.1.1.1", obj{"code": code, "token": host, "msg": 1}); st != 204 {
			break
		}
	}
	if n != matchMsgs {
		t.Error("messages per phone", n)
	}
	// open matches per client
	for i := 0; i < matchPerOwner; i++ {
		create(t, s, "7.7.7.7")
	}
	if st, _ := call(t, s, "new", "7.7.7.7", obj{}); st != 503 {
		t.Error("open matches per client", st)
	}
	// guessing codes is rate-limited
	for i := 0; i < matchJoin; i++ {
		call(t, s, "join", "5.5.5.5", obj{"code": "ffff", "nonce": nonce})
	}
	if st, _ := call(t, s, "join", "5.5.5.5", obj{"code": "ffff", "nonce": nonce}); st != 429 {
		t.Error("guessing is not rate-limited", st)
	}
}
