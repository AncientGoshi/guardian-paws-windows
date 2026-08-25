//go:build windows

package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

type telegramUpdate struct {
	UpdateID int64            `json:"update_id"`
	Message  *telegramMessage `json:"message"`
}
type telegramMessage struct {
	Chat struct {
		ID   int64  `json:"id"`
		Type string `json:"type"`
	} `json:"chat"`
	From struct {
		ID int64 `json:"id"`
	} `json:"from"`
	Text       string `json:"text"`
	WebAppData *struct {
		Data string `json:"data"`
	} `json:"web_app_data"`
}
type telegramReply struct {
	OK     bool             `json:"ok"`
	Result []telegramUpdate `json:"result"`
}

func telegramAPI(h *http.Client, token, method string, body any) error {
	b, e := json.Marshal(body)
	if e != nil {
		return e
	}
	r, e := h.Post("https://api.telegram.org/bot"+token+"/"+method, "application/json", strings.NewReader(string(b)))
	if e != nil {
		return e
	}
	defer r.Body.Close()
	if r.StatusCode/100 != 2 {
		return fmt.Errorf("Telegram %s returned %s", method, r.Status)
	}
	return nil
}
func botLoop() error {
	h := &http.Client{Timeout: 45 * time.Second}
	for {
		if e := botOnce(h); e != nil {
			time.Sleep(10 * time.Second)
		}
	}
}
func botOnce(h *http.Client) error {
	c, e := readConfig()
	if e != nil {
		return e
	}
	secret, e := unprotectBase64(c.BotTokenProtected)
	if e != nil {
		return e
	}
	token := string(secret)
	_ = telegramAPI(h, token, "deleteWebhook", map[string]bool{"drop_pending_updates": false})
	offset := int64(0)
	if c.LastUpdateID != nil {
		offset = *c.LastUpdateID + 1
	}
	u := "https://api.telegram.org/bot" + token + "/getUpdates?timeout=30&offset=" + fmt.Sprint(offset)
	r, e := h.Get(u)
	if e != nil {
		return e
	}
	defer r.Body.Close()
	var reply telegramReply
	if e = json.NewDecoder(r.Body).Decode(&reply); e != nil {
		return e
	}
	for _, up := range reply.Result {
		c, e = readConfig()
		if e != nil {
			return e
		}
		id := up.UpdateID
		c.LastUpdateID = &id
		if up.Message == nil || up.Message.Chat.Type != "private" {
			if e = saveConfig(c); e != nil {
				return e
			}
			continue
		}
		if e = handleMessage(h, token, &c, *up.Message); e != nil {
			return e
		}
		if e = saveConfig(c); e != nil {
			return e
		}
	}
	return nil
}
func handleMessage(h *http.Client, token string, c *Config, m telegramMessage) error {
	text := strings.ToLower(strings.TrimSpace(m.Text))
	action := ""
	if m.WebAppData != nil {
		var p struct {
			V      string `json:"v"`
			Action string `json:"action"`
		}
		if json.Unmarshal([]byte(m.WebAppData.Data), &p) == nil && allowedWebAction(p.V, p.Action) {
			action = p.Action
		}
	}
	reply := ""
	sender := m.From.ID
	if strings.HasPrefix(text, "/pair ") && len(text) == 15 {
		code := text[6:]
		if c.Pairing.Code == code && c.Pairing.ExpiresUTC.After(time.Now().UTC()) && len(c.GuardianIDs) < 2 && !hasGuardian(c.GuardianIDs, sender) {
			c.GuardianIDs = append(c.GuardianIDs, sender)
			c.Pairing.Code = ""
			reply = "This Telegram account is now paired as a Guardian."
		} else {
			reply = "Pairing was refused."
		}
	} else if !hasGuardian(c.GuardianIDs, sender) {
		return nil
	} else if text == "/shorts off" || text == "/shorts on" || action == "shorts-off" || action == "shorts-on" {
		c.ShortsBlocked = text == "/shorts off" || action == "shorts-off"
		if e := setPolicies(c.ChildSID, c.ExtensionUpdateURL, c.ShortsBlocked); e != nil {
			return e
		}
		if c.ShortsBlocked {
			reply = "YouTube Shorts are blocked in the child Edge/Chrome profile."
		} else {
			reply = "YouTube Shorts are allowed in the child Edge/Chrome profile."
		}
	} else if text == "/downtime on" || action == "downtime-on" {
		if e := setAccount(c.ChildUserName, false); e != nil {
			return e
		}
		reply = "Downtime is active. The child account was disabled."
	} else if text == "/downtime off" || action == "downtime-off" {
		if e := setAccount(c.ChildUserName, true); e != nil {
			return e
		}
		reply = "Downtime is off. The child account may sign in again."
	} else if text == "/status" || text == "/shorts status" || text == "/downtime status" || action == "status" {
		enabled, e := accountEnabled(c.ChildUserName)
		if e != nil {
			return e
		}
		state := "downtime active"
		if enabled {
			state = "available"
		}
		shorts := "allowed"
		if c.ShortsBlocked {
			shorts = "blocked"
		}
		reply = "Child account: " + state + "\nYouTube Shorts: " + shorts
	} else if text == "/panel" || text == "/start" {
		return telegramAPI(h, token, "sendMessage", map[string]any{"chat_id": m.Chat.ID, "text": "Open Guardian Paws to control this Windows child account.", "reply_markup": map[string]any{"keyboard": [][]any{{map[string]any{"text": "Open Guardian Paws", "web_app": map[string]string{"url": c.MiniAppURL}}}}, "resize_keyboard": true, "is_persistent": true}})
	} else if text == "/help" {
		reply = "/panel\n/shorts off|on|status\n/downtime on|off|status\n/status"
	}
	if reply != "" {
		return telegramAPI(h, token, "sendMessage", map[string]any{"chat_id": m.Chat.ID, "text": reply})
	}
	return nil
}

// Windows APIs keep the token machine-protected, so the SYSTEM scheduled task can decrypt it.
type dataBlob struct {
	cbData uint32
	pbData *byte
}

var crypt32 = syscall.NewLazyDLL("crypt32.dll")
var kernel32 = syscall.NewLazyDLL("kernel32.dll")
var getConsoleMode = kernel32.NewProc("GetConsoleMode")
var setConsoleMode = kernel32.NewProc("SetConsoleMode")
var cryptProtect = crypt32.NewProc("CryptProtectData")
var cryptUnprotect = crypt32.NewProc("CryptUnprotectData")
var localFree = kernel32.NewProc("LocalFree")

const cryptprotectLocalMachine = 0x4

func getConsoleInputMode(handle uintptr) (uint32, error) {
	var mode uint32
	r, _, e := getConsoleMode.Call(handle, uintptr(unsafe.Pointer(&mode)))
	if r == 0 {
		return 0, e
	}
	return mode, nil
}
func setConsoleInputMode(handle uintptr, mode uint32) error {
	r, _, e := setConsoleMode.Call(handle, uintptr(mode))
	if r == 0 {
		return e
	}
	return nil
}

func dpapi(in []byte, protectMode bool) ([]byte, error) {
	if len(in) == 0 {
		return nil, fmt.Errorf("empty DPAPI input")
	}
	input := dataBlob{uint32(len(in)), &in[0]}
	var output dataBlob
	p := cryptUnprotect
	if protectMode {
		p = cryptProtect
	}
	r, _, e := p.Call(uintptr(unsafe.Pointer(&input)), 0, 0, 0, 0, cryptprotectLocalMachine, uintptr(unsafe.Pointer(&output)))
	if r == 0 {
		return nil, fmt.Errorf("Windows DPAPI failed: %v", e)
	}
	defer localFree.Call(uintptr(unsafe.Pointer(output.pbData)))
	return append([]byte(nil), unsafe.Slice(output.pbData, output.cbData)...), nil
}
func protect(in []byte) ([]byte, error) { return dpapi(in, true) }
func unprotectBase64(v string) ([]byte, error) {
	b, e := base64.StdEncoding.DecodeString(v)
	if e != nil {
		return nil, e
	}
	return dpapi(b, false)
}

var advapi32 = syscall.NewLazyDLL("advapi32.dll")
var lookupAccountName = advapi32.NewProc("LookupAccountNameW")

func lookupSID(name string) (string, error) {
	n, e := syscall.UTF16PtrFromString(name)
	if e != nil {
		return "", e
	}
	var sidN, domN uint32
	var use uint32
	lookupAccountName.Call(0, uintptr(unsafe.Pointer(n)), 0, uintptr(unsafe.Pointer(&sidN)), 0, uintptr(unsafe.Pointer(&domN)), uintptr(unsafe.Pointer(&use)))
	if sidN == 0 {
		return "", fmt.Errorf("could not size SID for %q", name)
	}
	sid := make([]byte, sidN)
	dom := make([]uint16, domN)
	r, _, e := lookupAccountName.Call(0, uintptr(unsafe.Pointer(n)), uintptr(unsafe.Pointer(&sid[0])), uintptr(unsafe.Pointer(&sidN)), uintptr(unsafe.Pointer(&dom[0])), uintptr(unsafe.Pointer(&domN)), uintptr(unsafe.Pointer(&use)))
	if r == 0 {
		return "", e
	}
	var out *uint16
	r, _, e = advapi32.NewProc("ConvertSidToStringSidW").Call(uintptr(unsafe.Pointer(&sid[0])), uintptr(unsafe.Pointer(&out)))
	if r == 0 {
		return "", e
	}
	return sidString(uintptr(unsafe.Pointer(out)), nil)
}
func sidString(ptr uintptr, err error) (string, error) {
	if ptr == 0 {
		return "", err
	}
	defer localFree.Call(ptr)
	p := (*[32768]uint16)(unsafe.Pointer(ptr))
	n := 0
	for n < len(p) && p[n] != 0 {
		n++
	}
	return string(utf16.Decode(p[:n])), nil
}
