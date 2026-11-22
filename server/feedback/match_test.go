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
	return s, c
}

func call(t *testing.T, s http.Handler, op, ip string, body any) (int, map[string]any) {
	t.Helper()
	b, _ := json.Marshal(body)
	r := httptest.NewRequest(http.MethodPost, "/pp-app/api/match/"+op, strings.NewReader(string(b)))
	r.Header.Set("X-Forwarded-For", ip)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func open(t *testing.T, s http.Handler) (code, host, guest string) {
	t.Helper()
	st, m := call(t, s, "new", "1.1.1.1", map[string]any{})
	if st != 201 {
		t.Fatal("new", st)
	}
	code, host = m["code"].(string), m["token"].(string)
	if !codePattern.MatchString(code) || len(host) != 32 {
		t.Fatal(code, host)
	}
	st, m = call(t, s, "join", "2.2.2.2", map[string]any{"code": code})
	if st != 200 {
		t.Fatal("join", st)
	}
	return code, host, m["token"].(string)
}

func msgs(m map[string]any) []map[string]any {
	var out []map[string]any
	for _, x := range m["msgs"].([]any) {
		out = append(out, x.(map[string]any))
	}
	return out
}

func TestMatchSwapsOfferAndAnswer(t *testing.T) {
	s, _ := matchServer()
	code, host, guest := open(t, s)

	// the host learns that someone joined
	st, m := call(t, s, "recv", "1.1.1.1", map[string]any{"code": code, "token": host})
	if st != 200 || len(msgs(m)) != 1 || msgs(m)[0]["from"] != "service" {
		t.Fatal(st, m)
	}
	after := int(m["next"].(float64))

	if st, _ := call(t, s, "send", "1.1.1.1", map[string]any{"code": code, "token": host, "msg": map[string]string{"type": "offer", "sdp": "v=0"}}); st != 204 {
		t.Fatal("send", st)
	}
	// the guest gets the offer (and the joined note), not its own messages
	st, m = call(t, s, "recv", "2.2.2.2", map[string]any{"code": code, "token": guest})
	got := msgs(m)
	if st != 200 || len(got) != 2 || got[1]["from"] != "host" || got[1]["msg"].(map[string]any)["sdp"] != "v=0" {
		t.Fatal(st, m)
	}
	if st, _ := call(t, s, "send", "2.2.2.2", map[string]any{"code": code, "token": guest, "msg": map[string]string{"type": "answer"}}); st != 204 {
		t.Fatal(st)
	}
	st, m = call(t, s, "recv", "1.1.1.1", map[string]any{"code": code, "token": host, "after": after})
	if got := msgs(m); st != 200 || len(got) != 1 || got[0]["from"] != "guest" {
		t.Fatal(st, m)
	}
}

func TestMatchRecvWaitsForAMessage(t *testing.T) {
	s, _ := matchServer()
	code, host, guest := open(t, s)
	done := make(chan map[string]any)
	go func() {
		_, m := call(t, s, "recv", "2.2.2.2", map[string]any{"code": code, "token": guest, "after": 1})
		done <- m
	}()
	time.Sleep(50 * time.Millisecond)
	call(t, s, "send", "1.1.1.1", map[string]any{"code": code, "token": host, "msg": 1})
	select {
	case m := <-done:
		if len(msgs(m)) != 1 {
			t.Fatal(m)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("recv did not wake")
	}
}

func TestMatchOnlyTwoPhones(t *testing.T) {
	s, _ := matchServer()
	code, _, _ := open(t, s)
	if st, _ := call(t, s, "join", "3.3.3.3", map[string]any{"code": code}); st != 409 {
		t.Error("third phone", st)
	}
	other := "0000"
	if code == other {
		other = "0001"
	}
	if st, _ := call(t, s, "join", "3.3.3.3", map[string]any{"code": other}); st != 404 {
		t.Error("unknown code", st)
	}
	if st, _ := call(t, s, "join", "3.3.3.3", map[string]any{"code": "zz"}); st != 400 {
		t.Error("bad code", st)
	}
	// a wrong token reads and writes nothing
	if st, _ := call(t, s, "send", "3.3.3.3", map[string]any{"code": code, "token": "x", "msg": 1}); st != 404 {
		t.Error(st)
	}
	if st, _ := call(t, s, "recv", "3.3.3.3", map[string]any{"code": code, "token": ""}); st != 404 {
		t.Error(st)
	}
}

func TestMatchCodesExpire(t *testing.T) {
	s, c := matchServer()
	_, m := call(t, s, "new", "1.1.1.1", map[string]any{})
	code := m["code"].(string)
	c.add(matchOpen + time.Second)
	if st, _ := call(t, s, "join", "2.2.2.2", map[string]any{"code": code}); st != 404 {
		t.Error("joined an expired code", st)
	}
	// a joined match lives on until matchLife
	code, host, _ := open(t, s)
	c.add(matchOpen + time.Minute)
	if st, _ := call(t, s, "send", "1.1.1.1", map[string]any{"code": code, "token": host, "msg": 1}); st != 204 {
		t.Error(st)
	}
	c.add(matchLife)
	call(t, s, "new", "9.9.9.9", map[string]any{}) // sweeps
	if st, _ := call(t, s, "send", "1.1.1.1", map[string]any{"code": code, "token": host, "msg": 1}); st != 404 {
		t.Error("match outlived matchLife", st)
	}
}

func TestMatchLeave(t *testing.T) {
	s, _ := matchServer()
	code, host, guest := open(t, s)
	if st, _ := call(t, s, "leave", "2.2.2.2", map[string]any{"code": code, "token": guest}); st != 204 {
		t.Fatal(st)
	}
	_, m := call(t, s, "recv", "1.1.1.1", map[string]any{"code": code, "token": host, "after": 1})
	if got := msgs(m); len(got) != 1 || got[0]["msg"].(map[string]any)["type"] != "left" {
		t.Fatal(m)
	}
	call(t, s, "leave", "1.1.1.1", map[string]any{"code": code, "token": host})
	if st, _ := call(t, s, "recv", "1.1.1.1", map[string]any{"code": code, "token": host}); st != 404 {
		t.Error("match still there after both left", st)
	}
}

func TestMatchLimits(t *testing.T) {
	s, _ := matchServer()
	code, host, _ := open(t, s)
	big := strings.Repeat("x", matchMsg)
	if st, _ := call(t, s, "send", "1.1.1.1", map[string]any{"code": code, "token": host, "msg": big}); st != 400 {
		t.Error("oversized message", st)
	}
	half := strings.Repeat("x", matchMsg/2)
	n := 0
	for ; n < 10; n++ {
		if st, _ := call(t, s, "send", "1.1.1.1", map[string]any{"code": code, "token": host, "msg": half}); st != 204 {
			break
		}
	}
	if n != 3 { // 32 KB per phone
		t.Error("bytes per phone", n)
	}
	for i := 0; i < matchJoin; i++ {
		call(t, s, "join", "5.5.5.5", map[string]any{"code": "ffff"})
	}
	if st, _ := call(t, s, "join", "5.5.5.5", map[string]any{"code": "ffff"}); st != 429 {
		t.Error("guessing is not rate-limited", st)
	}
}
