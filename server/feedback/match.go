package main

// The meeting point of the two-player games: one phone opens a match and
// shows its code (four pictures, or a link); the other joins with it.
// Then the two phones swap their WebRTC offer and answer here and talk
// directly (or through coturn, turn.go). Nothing is stored: matches live in
// memory and are gone after matchLife, or once a phone leaves.
//
//	POST /pp-app/api/match/new   {}                        -> {code, token}
//	POST /pp-app/api/match/join  {code}                    -> {token}
//	POST /pp-app/api/match/send  {code, token, msg}        -> 204
//	POST /pp-app/api/match/recv  {code, token, after}      -> {msgs, next}
//	POST /pp-app/api/match/leave {code, token}             -> 204
//
// recv waits up to matchWait for a message of the other phone; "joined"
// and "left" are sent by the service itself. The token says which phone
// asks; it is in the body, never in a URL (access logs).
//
// A code has 16^4 = 65536 values and is open for joining matchOpen; joins
// are rate-limited per client, so guessing someone's code is hopeless.

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"sync"
	"time"
)

const (
	matchOpen = 15 * time.Minute // a code can be joined this long
	matchLife = 2 * time.Hour    // then the match is gone in any case
	matchWait = 15 * time.Second // recv long-poll (WriteTimeout is 20 s)
	matchMax  = 300              // matches at a time
	matchMsgs = 100              // messages per phone and match
	matchMsg  = 16 << 10         // bytes per message (an SDP with candidates)
	// bytes per phone and match: an offer or answer is a few KB, the game
	// itself runs on the data channel. 300 matches stay within the pod's
	// 64 MiB.
	matchBytes     = 32 << 10
	matchNew       = 30    // new matches per client and hour
	matchJoin      = 30    // joins per client and hour (wrong codes count)
	matchPerHour   = 20000 // new + join, all clients
	matchCodeChars = "0123456789abcdef"
)

var codePattern = regexp.MustCompile(`^[0-9a-f]{4}$`)

// MatchMsg is one message; From is "host", "guest" or "service".
type MatchMsg struct {
	Seq  int             `json:"seq"`
	From string          `json:"from"`
	Msg  json.RawMessage `json:"msg"`
}

type match struct {
	code        string
	host, guest string // tokens; guest "" until someone joins
	created     time.Time
	msgs        []MatchMsg
	sent        map[string]int // messages per sender
	bytes       map[string]int // message bytes per sender
	changed     chan struct{}  // closed and replaced on each message
	hostLeft    bool
	guestLeft   bool
}

func (m *match) who(token string) string {
	switch {
	case token == "":
		return ""
	case token == m.host:
		return "host"
	case token == m.guest:
		return "guest"
	}
	return ""
}

// Matches holds the open matches.
type Matches struct {
	mu      sync.Mutex
	byCode  map[string]*match
	now     func() time.Time
	newLim  *limiter
	joinLim *limiter
}

func NewMatches(now func() time.Time) *Matches {
	return &Matches{
		byCode: map[string]*match{}, now: now,
		newLim:  newLimiter(matchNew, matchPerHour),
		joinLim: newLimiter(matchJoin, matchPerHour),
	}
}

func token() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// sweep drops matches past their life, unjoined ones past matchOpen and
// ones both phones left. Call with mu held.
func (ms *Matches) sweep(now time.Time) {
	for c, m := range ms.byCode {
		age := now.Sub(m.created)
		if age > matchLife || (m.guest == "" && age > matchOpen) || (m.hostLeft && (m.guestLeft || m.guest == "")) {
			ms.drop(c)
		}
	}
}

func (ms *Matches) drop(code string) {
	if m := ms.byCode[code]; m != nil {
		close(m.changed) // wake waiting recvs: they find no match
		delete(ms.byCode, code)
	}
}

// post appends a message and wakes the waiting recvs. Call with mu held.
func (m *match) post(from string, msg json.RawMessage) {
	m.msgs = append(m.msgs, MatchMsg{Seq: len(m.msgs) + 1, From: from, Msg: msg})
	close(m.changed)
	m.changed = make(chan struct{})
}

var errNoMatch = errors.New("no such match")

func (ms *Matches) create() (code, tok string, err error) {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	now := ms.now()
	ms.sweep(now)
	if len(ms.byCode) >= matchMax {
		return "", "", errors.New("full")
	}
	for {
		b := make([]byte, 4)
		_, _ = rand.Read(b)
		for i := range b {
			b[i] = matchCodeChars[b[i]%16]
		}
		code = string(b)
		if ms.byCode[code] == nil {
			break
		}
	}
	tok = token()
	ms.byCode[code] = &match{code: code, host: tok, created: now, sent: map[string]int{}, bytes: map[string]int{}, changed: make(chan struct{})}
	return code, tok, nil
}

var errFull = errors.New("someone joined already")

func (ms *Matches) join(code string) (string, error) {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	ms.sweep(ms.now())
	m := ms.byCode[code]
	if m == nil || m.hostLeft {
		return "", errNoMatch
	}
	if m.guest != "" {
		return "", errFull
	}
	m.guest = token()
	m.post("service", json.RawMessage(`{"type":"joined"}`))
	return m.guest, nil
}

func (ms *Matches) send(code, tok string, msg json.RawMessage) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	m := ms.byCode[code]
	if m == nil {
		return errNoMatch
	}
	from := m.who(tok)
	if from == "" {
		return errNoMatch
	}
	if m.sent[from] >= matchMsgs || m.bytes[from]+len(msg) > matchBytes {
		return errors.New("too many messages")
	}
	m.sent[from]++
	m.bytes[from] += len(msg)
	m.post(from, msg)
	return nil
}

// recv returns the other phone's (and the service's) messages after seq
// after, waiting up to matchWait for one.
func (ms *Matches) recv(r *http.Request, code, tok string, after int) ([]MatchMsg, int, error) {
	deadline := time.NewTimer(matchWait)
	defer deadline.Stop()
	for {
		ms.mu.Lock()
		m := ms.byCode[code]
		if m == nil || m.who(tok) == "" {
			ms.mu.Unlock()
			return nil, 0, errNoMatch
		}
		me := m.who(tok)
		var out []MatchMsg
		for _, x := range m.msgs {
			if x.Seq > after && x.From != me {
				out = append(out, x)
			}
		}
		next := len(m.msgs)
		wake := m.changed
		ms.mu.Unlock()
		if len(out) > 0 {
			return out, next, nil
		}
		select {
		case <-wake:
		case <-deadline.C:
			return []MatchMsg{}, next, nil
		case <-r.Context().Done():
			return nil, 0, r.Context().Err()
		}
	}
}

func (ms *Matches) leave(code, tok string) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	m := ms.byCode[code]
	if m == nil {
		return nil // gone already: fine
	}
	switch m.who(tok) {
	case "host":
		m.hostLeft = true
	case "guest":
		m.guestLeft = true
	default:
		return errNoMatch
	}
	m.post("service", json.RawMessage(`{"type":"left"}`))
	ms.sweep(ms.now())
	return nil
}

type matchReq struct {
	Code  string          `json:"code"`
	Token string          `json:"token"`
	Msg   json.RawMessage `json:"msg"`
	After int             `json:"after"`
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) serveMatch(w http.ResponseWriter, r *http.Request, op string) {
	if s.Matches == nil {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var q matchReq
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, matchMsg+1024))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if op != "new" && !codePattern.MatchString(q.Code) {
		http.Error(w, "bad code", http.StatusBadRequest)
		return
	}
	ms := s.Matches
	switch op {
	case "new":
		if !ms.newLim.allow(clientIP(r), s.Now()) {
			http.Error(w, "too many, try later", http.StatusTooManyRequests)
			return
		}
		code, tok, err := ms.create()
		if err != nil {
			http.Error(w, "try later", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]string{"code": code, "token": tok})
	case "join":
		if !ms.joinLim.allow(clientIP(r), s.Now()) {
			http.Error(w, "too many, try later", http.StatusTooManyRequests)
			return
		}
		tok, err := ms.join(q.Code)
		switch {
		case errors.Is(err, errFull):
			http.Error(w, err.Error(), http.StatusConflict)
		case err != nil:
			http.Error(w, err.Error(), http.StatusNotFound)
		default:
			writeJSON(w, http.StatusOK, map[string]string{"token": tok})
		}
	case "send":
		if len(q.Msg) == 0 || len(q.Msg) > matchMsg || !json.Valid(q.Msg) {
			http.Error(w, "bad msg", http.StatusBadRequest)
			return
		}
		if err := ms.send(q.Code, q.Token, q.Msg); err != nil {
			status := http.StatusNotFound
			if !errors.Is(err, errNoMatch) {
				status = http.StatusTooManyRequests
			}
			http.Error(w, err.Error(), status)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	case "recv":
		msgs, next, err := ms.recv(r, q.Code, q.Token, q.After)
		if err != nil {
			http.Error(w, "no such match", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"msgs": msgs, "next": next})
	case "leave":
		if err := ms.leave(q.Code, q.Token); err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.NotFound(w, r)
	}
}
