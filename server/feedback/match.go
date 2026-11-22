package main

// The meeting point of the two-player games: one phone opens a match and
// shows its code (four pictures); the other joins with the code and gets an
// animal picked here. Both screens show it; the host's child sees "🐻
// wants to play" and accepts or rejects; only after accepting does the host send its WebRTC offer, so a
// stranger who guesses a code learns nothing and gets in nowhere. Then the
// two phones swap offer and answer here and talk directly (or through
// coturn, turn.go). Nothing is stored: matches live in memory.
//
//	POST new    {}                          -> 201 {code, token}
//	POST join   {code, nonce}               -> 200 {token, animal} | 404 | 409
//	POST reject {code, token}               -> 204   (host: reopen the code)
//	POST send   {code, token, msg, id?}     -> 204
//	POST recv   {code, token, after}        -> 200 {msgs, next}
//	POST leave  {code, token}               -> 204
//
// (all under /pp-app/api/match/). recv waits up to Matches.wait for a
// message of the other phone. The host also gets "joined" (with the
// animal) and "left" from the service; a guest sees only what the host
// sent after it joined (an earlier guest's offer is not its business). Tokens are in bodies, never in URLs
// (access logs). A join with the same nonce again (a lost answer) gets the
// same token; a send with the same id again is dropped.

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	matchOpen = 5 * time.Minute // an unjoined code lives this long
	matchLife = 2 * time.Hour   // a match in any case
	// a match is gone when no phone in it asked for a minute (an app that
	// crashed or went away; recv is asked again every matchWait)
	matchIdle = time.Minute
	// recv long-poll; must stay well below the server's WriteTimeout (20 s)
	matchWait     = 15 * time.Second
	matchMax      = 500      // matches at a time
	matchPerOwner = 10       // open matches per client (a school Wi-Fi is one)
	matchPerNet   = 30       // ... per IPv6 /48 or IPv4 /24
	matchMsgs     = 50       // messages per phone and match
	matchMsg      = 8 << 10  // bytes per message (an SDP with all candidates)
	matchBytes    = 16 << 10 // bytes per phone and match: 500 matches = 16 MiB
	matchReopens  = 10       // guests a host may reject or lose per match
	matchWaiters  = 1000     // recvs waiting at a time
	waitersPerIP  = 20       // ... per client
	matchNew      = 30       // new matches per client and hour
	matchJoin     = 20       // joins per client and hour (wrong codes count)
	matchPerHour  = 20000    // each of new and join, all clients
	matchAnimals  = 16       // the app's animal pictures
	codeChars     = "0123456789abcdef"
)

var (
	codePattern  = regexp.MustCompile(`^[0-9a-f]{4}$`)
	noncePattern = regexp.MustCompile(`^[0-9a-f]{16,64}$`)
)

// MatchMsg is one message; From is "host", "guest" or "service".
type MatchMsg struct {
	Seq  int             `json:"seq"`
	From string          `json:"from"`
	Msg  json.RawMessage `json:"msg"`
}

type side struct {
	token string
	seen  time.Time // last request
	left  bool
	msgs  int
	bytes int
	ids   map[string]bool
	kick  chan struct{} // closed to end this side's waiting recv
	base  int           // a guest sees messages after this seq only
}

type match struct {
	code       string
	owner      string // client of the host, for matchPerOwner
	net        string // its network, for matchPerNet
	reopens    int
	host       side
	guest      side
	guestNonce string
	animal     int // the guest's picture, both screens show it
	created    time.Time
	opened     time.Time // since when it can be joined (again)
	msgs       []MatchMsg
	changed    chan struct{} // closed and replaced on each message
}

func (m *match) side(tok string) (string, *side) {
	switch {
	case tok == "":
	case tok == m.host.token:
		return "host", &m.host
	case tok == m.guest.token:
		return "guest", &m.guest
	}
	return "", nil
}

// gone tells whether the match is over at now.
func (m *match) gone(now time.Time) bool {
	age := now.Sub(m.created)
	joined := m.guest.token != ""
	idle := now.Sub(m.host.seen) > matchIdle && (!joined || now.Sub(m.guest.seen) > matchIdle)
	return age > matchLife || (!joined && now.Sub(m.opened) > matchOpen) || m.host.left || idle
}

// post appends a message and wakes the waiting recvs.
func (m *match) post(from string, msg json.RawMessage) {
	m.msgs = append(m.msgs, MatchMsg{Seq: len(m.msgs) + 1, From: from, Msg: msg})
	close(m.changed)
	m.changed = make(chan struct{})
}

// Matches holds the open matches.
type Matches struct {
	mu      sync.Mutex
	byCode  map[string]*match
	now     func() time.Time
	wait    time.Duration
	newLim  *limiter
	joinLim *limiter
	waiters chan struct{}
	perIP   map[string]int // waiting recvs per client
}

func NewMatches(now func() time.Time) *Matches {
	return &Matches{
		byCode: map[string]*match{}, now: now, wait: matchWait,
		newLim:  newLimiter(matchNew, matchPerHour),
		joinLim: newLimiter(matchJoin, matchPerHour),
		waiters: make(chan struct{}, matchWaiters),
		perIP:   map[string]int{},
	}
}

func token() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func newSide(now time.Time) side {
	return side{token: token(), seen: now, ids: map[string]bool{}, kick: make(chan struct{})}
}

// sweep drops the matches that are over. Call with mu held.
func (ms *Matches) sweep(now time.Time) {
	for c, m := range ms.byCode {
		if m.gone(now) {
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

// get returns the live match of code and the asking side, or errNoMatch.
// Call with mu held.
func (ms *Matches) get(code, tok string) (*match, string, *side, error) {
	m := ms.byCode[code]
	now := ms.now()
	if m != nil && m.gone(now) {
		ms.drop(code)
		m = nil
	}
	if m == nil {
		return nil, "", nil, errNoMatch
	}
	who, s := m.side(tok)
	if s == nil || s.left {
		return nil, "", nil, errNoMatch
	}
	s.seen = now
	return m, who, s, nil
}

var (
	errNoMatch = errors.New("no such match")
	errFull    = errors.New("someone joined already")
	errBusy    = errors.New("try later")
	errBudget  = errors.New("too many messages")
)

func (ms *Matches) create(owner, net string) (code, tok string, err error) {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	now := ms.now()
	ms.sweep(now)
	if len(ms.byCode) >= matchMax {
		return "", "", errBusy
	}
	mine, ours := 0, 0
	for _, m := range ms.byCode {
		if m.owner == owner {
			mine++
		}
		if m.net == net {
			ours++
		}
	}
	if mine >= matchPerOwner || ours >= matchPerNet {
		return "", "", errBusy
	}
	for {
		b := make([]byte, 4)
		_, _ = rand.Read(b)
		for i := range b {
			b[i] = codeChars[b[i]%16]
		}
		code = string(b)
		if ms.byCode[code] == nil {
			break
		}
	}
	m := &match{code: code, owner: owner, net: net, host: newSide(now), created: now, opened: now, changed: make(chan struct{})}
	ms.byCode[code] = m
	return code, m.host.token, nil
}

func (ms *Matches) join(code, nonce string) (tok string, animal int, err error) {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	now := ms.now()
	m := ms.byCode[code]
	if m != nil && m.gone(now) {
		ms.drop(code)
		m = nil
	}
	if m == nil {
		return "", 0, errNoMatch
	}
	if m.guest.token != "" {
		if m.guestNonce == nonce && !m.guest.left {
			m.guest.seen = now
			return m.guest.token, m.animal, nil // the answer got lost: the same again
		}
		return "", 0, errFull
	}
	m.guest = newSide(now)
	m.guest.base = len(m.msgs)
	m.guestNonce = nonce
	b := make([]byte, 1)
	_, _ = rand.Read(b)
	m.animal = int(b[0]) % matchAnimals
	m.post("service", json.RawMessage(`{"type":"joined","animal":`+strconv.Itoa(m.animal)+`}`))
	return m.guest.token, m.animal, nil
}

// reopen forgets the guest (the host rejected it, or it left): its token
// stops working and the code can be joined again, with a fresh budget for
// the host's next offer. It reports false when the match had enough
// guests. Call with mu held and a guest in the match.
func (m *match) reopen(now time.Time) bool {
	close(m.guest.kick)
	m.guest = side{}
	m.guestNonce = ""
	m.host.msgs, m.host.bytes = 0, 0
	m.opened = now // a fresh window to join (matchLife still counts)
	m.reopens++
	return m.reopens <= matchReopens
}

func (ms *Matches) reject(code, tok string) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	m, who, _, err := ms.get(code, tok)
	if err != nil {
		return err
	}
	if who != "host" {
		return errNoMatch
	}
	if m.guest.token != "" && !m.reopen(ms.now()) {
		ms.drop(code)
	}
	return nil
}

func (ms *Matches) send(code, tok, id string, msg json.RawMessage) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	m, who, s, err := ms.get(code, tok)
	if err != nil {
		return err
	}
	if id != "" && s.ids[id] {
		return nil // a retry: sent already
	}
	if s.msgs >= matchMsgs || s.bytes+len(msg) > matchBytes {
		return errBudget
	}
	s.msgs++
	s.bytes += len(msg)
	if id != "" {
		s.ids[id] = true
	}
	m.post(who, msg)
	return nil
}

// recv returns the other phone's (and the service's) messages after seq
// after, waiting up to ms.wait for one. A newer recv of the same phone
// ends this one.
func (ms *Matches) recv(r *http.Request, client, code, tok string, after int) ([]MatchMsg, int, error) {
	select {
	case ms.waiters <- struct{}{}:
		defer func() { <-ms.waiters }()
	default:
		return nil, 0, errBusy
	}
	ms.mu.Lock()
	if ms.perIP[client] >= waitersPerIP {
		ms.mu.Unlock()
		return nil, 0, errBusy
	}
	ms.perIP[client]++
	defer func() {
		ms.mu.Lock()
		if ms.perIP[client]--; ms.perIP[client] <= 0 {
			delete(ms.perIP, client)
		}
		ms.mu.Unlock()
	}()
	_, _, s, err := ms.get(code, tok)
	if err != nil {
		ms.mu.Unlock()
		return nil, 0, err
	}
	close(s.kick) // end an older recv of this phone
	s.kick = make(chan struct{})
	kick := s.kick
	ms.mu.Unlock()

	deadline := time.NewTimer(ms.wait)
	defer deadline.Stop()
	for {
		ms.mu.Lock()
		m, me, s, err := ms.get(code, tok)
		if err != nil {
			ms.mu.Unlock()
			return nil, 0, err
		}
		next := len(m.msgs)
		if after > next || after < s.base {
			after = s.base // a stale client: everything (of its own) again
		}
		var out []MatchMsg
		for _, x := range m.msgs[after:] {
			if (me == "host" && x.From != "host") || (me == "guest" && x.From == "host") {
				out = append(out, x)
			}
		}
		wake := m.changed
		ms.mu.Unlock()
		if len(out) > 0 {
			return out, next, nil
		}
		select {
		case <-wake:
		case <-kick:
			return []MatchMsg{}, next, nil
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
	m, who, s, err := ms.get(code, tok)
	if err != nil {
		return nil // gone or left already: fine
	}
	s.left = true
	close(s.kick)
	s.kick = make(chan struct{})
	if who == "host" {
		ms.drop(code) // the guest's recv ends with 404
		return nil
	}
	if !m.reopen(ms.now()) {
		ms.drop(code)
		return nil
	}
	m.post("service", json.RawMessage(`{"type":"left"}`))
	return nil
}

type matchReq struct {
	Code  string          `json:"code"`
	Token string          `json:"token"`
	Nonce string          `json:"nonce"`
	ID    string          `json:"id"`
	Msg   json.RawMessage `json:"msg"`
	After int             `json:"after"`
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func busy(w http.ResponseWriter) {
	w.Header().Set("Retry-After", "30")
	http.Error(w, "try later", http.StatusServiceUnavailable)
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
	// unknown fields are fine: a newer app may send more
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, matchMsg+1024)).Decode(&q); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			http.Error(w, "too big", http.StatusRequestEntityTooLarge)
			return
		}
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
		code, tok, err := ms.create(clientIP(r), clientNet(r))
		if err != nil {
			busy(w)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]string{"code": code, "token": tok})
	case "join":
		if !noncePattern.MatchString(q.Nonce) {
			http.Error(w, "bad join", http.StatusBadRequest)
			return
		}
		if !ms.joinLim.allow(clientIP(r), s.Now()) {
			http.Error(w, "too many, try later", http.StatusTooManyRequests)
			return
		}
		tok, animal, err := ms.join(q.Code, q.Nonce)
		switch {
		case errors.Is(err, errFull):
			http.Error(w, err.Error(), http.StatusConflict)
		case err != nil:
			http.Error(w, err.Error(), http.StatusNotFound)
		default:
			writeJSON(w, http.StatusOK, map[string]any{"token": tok, "animal": animal})
		}
	case "reject":
		if err := ms.reject(q.Code, q.Token); err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	case "send":
		if len(q.Msg) == 0 || len(q.Msg) > matchMsg || len(q.ID) > 64 {
			http.Error(w, "bad msg", http.StatusBadRequest)
			return
		}
		switch err := ms.send(q.Code, q.Token, q.ID, q.Msg); {
		case errors.Is(err, errBudget):
			http.Error(w, err.Error(), http.StatusRequestEntityTooLarge)
		case err != nil:
			http.Error(w, err.Error(), http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusNoContent)
		}
	case "recv":
		msgs, next, err := ms.recv(r, clientIP(r), q.Code, q.Token, q.After)
		switch {
		case errors.Is(err, errBusy):
			busy(w)
		case err != nil:
			http.Error(w, "no such match", http.StatusNotFound)
		default:
			writeJSON(w, http.StatusOK, map[string]any{"msgs": msgs, "next": next})
		}
	case "leave":
		_ = ms.leave(q.Code, q.Token)
		w.WriteHeader(http.StatusNoContent)
	default:
		http.NotFound(w, r)
	}
}

// clientNet is the client's wider network: an IPv6 /48 (one customer can
// have all of it) or an IPv4 /24.
func clientNet(r *http.Request) string {
	c := clientIP(r)
	if p, ok := strings.CutSuffix(c, "/64"); ok {
		ip := net.ParseIP(p)
		if ip != nil {
			return ip.Mask(net.CIDRMask(48, 128)).String() + "/48"
		}
	}
	if ip := net.ParseIP(c); ip != nil && ip.To4() != nil {
		return ip.Mask(net.CIDRMask(24, 32)).String() + "/24"
	}
	return c
}
