package main

// TURN credentials for the app's two-player games (WebRTC). Two phones that
// cannot reach each other directly (mobile carrier NAT) relay their game
// moves through coturn on the vps. coturn runs with use-auth-secret (the
// "TURN REST API"): the username is the expiry time, the password its
// HMAC-SHA1 under a secret this service and coturn share. So a credential
// stops working after turnTTL, and nothing is stored here.
//
// Anyone can ask for one, as anyone can send feedback: coturn's bandwidth
// and quota limits are what make a relay worthless for anything but game
// moves. The credential carries no id of the phone.

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	// turnTTL is how long a credential lets a phone open a relay: long
	// enough for one match.
	turnTTL       = time.Hour
	turnPerClient = 20 // credentials per client and hour
	turnPerHour   = 600
)

// TURN signs credentials; nil Secret: the route answers 404.
type TURN struct {
	Secret []byte
	// URLs of the relay, e.g. turn:relaxandplay.de:3478?transport=udp.
	URLs []string
}

// ICEServer is one entry of WebRTC's RTCConfiguration.iceServers.
type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

// TURNAnswer is what the app gets.
type TURNAnswer struct {
	ICEServers []ICEServer `json:"iceServers"`
	// TTL in seconds, so the app knows when to ask again.
	TTL int `json:"ttl"`
}

// credential is coturn's REST API credential valid until expires.
func (t *TURN) credential(expires time.Time) (user, pass string) {
	user = strconv.FormatInt(expires.Unix(), 10) + ":pp"
	m := hmac.New(sha1.New, t.Secret)
	m.Write([]byte(user))
	return user, base64.StdEncoding.EncodeToString(m.Sum(nil))
}

// stunURLs are the relay's urls as plain STUN (no credential needed).
func (t *TURN) stunURLs() []string {
	seen := map[string]bool{}
	var out []string
	for _, u := range t.URLs {
		host, ok := strings.CutPrefix(u, "turn:")
		if !ok {
			continue
		}
		host, _, _ = strings.Cut(host, "?")
		if !seen[host] {
			seen[host] = true
			out = append(out, "stun:"+host)
		}
	}
	return out
}

func (s *Server) serveTURN(w http.ResponseWriter, r *http.Request) {
	if s.TURN == nil || len(s.TURN.Secret) == 0 {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	if !s.turnLimit.allow(clientIP(r), s.Now()) {
		http.Error(w, "too many, try later", http.StatusTooManyRequests)
		return
	}
	user, pass := s.TURN.credential(s.Now().Add(turnTTL))
	ans := TURNAnswer{TTL: int(turnTTL / time.Second)}
	if stun := s.TURN.stunURLs(); len(stun) > 0 {
		ans.ICEServers = append(ans.ICEServers, ICEServer{URLs: stun})
	}
	ans.ICEServers = append(ans.ICEServers, ICEServer{URLs: s.TURN.URLs, Username: user, Credential: pass})
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(ans)
}

// turnFromEnv reads TURN_SECRET and TURN_URLS (comma separated); without
// a secret there is no TURN route.
func turnFromEnv() *TURN {
	secret := strings.TrimSpace(env("TURN_SECRET", ""))
	if secret == "" {
		return nil
	}
	var urls []string
	for _, u := range strings.Split(env("TURN_URLS", "turn:relaxandplay.de:3478?transport=udp,turn:relaxandplay.de:3478?transport=tcp"), ",") {
		if u = strings.TrimSpace(u); u != "" {
			urls = append(urls, u)
		}
	}
	return &TURN{Secret: []byte(secret), URLs: urls}
}
