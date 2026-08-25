package main

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

const extensionID = "llkmcggfkabiooejicbdngjaagobgaen"

// Config is deliberately restricted to the controls exposed to a guardian.
type Config struct {
	Version            int     `json:"version"`
	ChildUserName      string  `json:"childUserName"`
	ChildSID           string  `json:"childSid"`
	BotTokenProtected  string  `json:"botTokenProtected"`
	MiniAppURL         string  `json:"miniAppUrl"`
	ExtensionUpdateURL string  `json:"extensionUpdateUrl"`
	GuardianIDs        []int64 `json:"guardianIds"`
	Pairing            Pairing `json:"pairing"`
	LastUpdateID       *int64  `json:"lastUpdateId,omitempty"`
	ShortsBlocked      bool    `json:"shortsBlocked"`
}
type Pairing struct {
	Code       string    `json:"code"`
	ExpiresUTC time.Time `json:"expiresUtc"`
}

func parseOptions(args []string) map[string]string {
	out := make(map[string]string)
	for i := 0; i+1 < len(args); i++ {
		if strings.HasPrefix(args[i], "--") {
			out[strings.TrimPrefix(args[i], "--")] = args[i+1]
			i++
		}
	}
	return out
}
func validateInstall(o map[string]string) error {
	child, display, update := o["child"], o["display"], o["extension-update-url"]
	if !regexp.MustCompile(`^[A-Za-z0-9._-]{1,20}$`).MatchString(child) {
		return fmt.Errorf("--child must be a new 1-20 character name containing only letters, numbers, dot, underscore, or hyphen")
	}
	if len(display) < 1 || len(display) > 64 {
		return fmt.Errorf("--display is required (1-64 characters)")
	}
	if !strings.HasPrefix(strings.ToLower(update), "https://") || len(update) <= len("https://") {
		return fmt.Errorf("--extension-update-url must be an HTTPS URL")
	}
	return nil
}
func allowedWebAction(v, action string) bool {
	return v == "1" && (action == "shorts-off" || action == "shorts-on" || action == "downtime-on" || action == "downtime-off" || action == "status")
}
func hasGuardian(ids []int64, id int64) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}
