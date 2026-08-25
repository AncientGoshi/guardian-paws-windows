//go:build windows

package main

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var root = filepath.Join(os.Getenv("ProgramData"), "GuardianPaws")
var app = filepath.Join(root, "app")
var configPath = filepath.Join(root, "config.json")

func main() {
	if len(os.Args) < 2 {
		usage()
		return
	}
	var err error
	switch strings.ToLower(os.Args[1]) {
	case "install":
		err = install(parseOptions(os.Args[2:]))
	case "bot":
		err = botLoop()
	case "enforcer":
		err = enforce()
	case "uninstall":
		err = uninstall()
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Guardian Paws:", err)
		os.Exit(1)
	}
}
func usage() {
	fmt.Fprintln(os.Stderr, "Usage: GuardianPaws-Go.exe install --child NAME --display NAME --extension-update-url HTTPS_URL")
}

// run always receives a program name and separate arguments; it never invokes cmd.exe.
func run(name string, args ...string) (string, error) {
	c := exec.Command(name, args...)
	var b bytes.Buffer
	c.Stdout, c.Stderr = &b, &b
	err := c.Run()
	return b.String(), err
}
func mustRun(name string, args ...string) error {
	out, err := run(name, args...)
	if err != nil {
		return fmt.Errorf("%s failed: %w: %s", name, err, out)
	}
	return nil
}
func requireAdmin() error {
	_, err := run("net.exe", "session")
	if err != nil {
		return errors.New("run Install-GuardianPaws-Go.cmd from an elevated Command Prompt")
	}
	return nil
}

func install(o map[string]string) error {
	if err := requireAdmin(); err != nil {
		return err
	}
	if err := validateInstall(o); err != nil {
		return err
	}
	child, display, update := o["child"], o["display"], o["extension-update-url"]
	if _, err := run("net.exe", "user", child); err == nil {
		return fmt.Errorf("%q already exists; refusing to alter an existing account", child)
	}
	token, err := readSecret("Paste the existing Telegram bot token: ")
	if err != nil || token == "" {
		return errors.New("no bot token was supplied")
	}
	password, err := readSecret("Create a password for the new child account " + child + ": ")
	if err != nil || password == "" {
		return errors.New("no child password was supplied")
	}
	// Password is an individual argv element, including spaces and punctuation.
	if err := mustRun("net.exe", "user", child, password, "/add", "/expires:never", "/fullname:"+display); err != nil {
		return err
	}
	rollback := true
	defer func() {
		if rollback {
			_, _ = run("net.exe", "user", child, "/delete")
		}
	}()
	if err := os.MkdirAll(app, 0755); err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	installed := filepath.Join(app, "GuardianPaws-Go.exe")
	if err := copyFile(exe, installed); err != nil {
		return err
	}
	sid, err := lookupSID(child)
	if err != nil {
		return err
	}
	protected, err := protect([]byte(token))
	if err != nil {
		return err
	}
	code, err := pairingCode()
	if err != nil {
		return err
	}
	c := Config{Version: 2, ChildUserName: child, ChildSID: sid, BotTokenProtected: base64.StdEncoding.EncodeToString(protected), MiniAppURL: "https://guard.catbiologymc.com/guardian", ExtensionUpdateURL: update, GuardianIDs: []int64{}, Pairing: Pairing{Code: code, ExpiresUTC: time.Now().UTC().Add(15 * time.Minute)}}
	if err := saveConfig(c); err != nil {
		return err
	}
	if err := setPolicies(sid, update, false); err != nil {
		return err
	}
	account := os.Getenv("COMPUTERNAME") + `\` + child
	// icacls receives each ACL component as a distinct argv element (no hand-built command line).
	if err := mustRun("icacls.exe", root, "/inheritance:r", "/grant:r", "SYSTEM:(OI)(CI)F", "Administrators:(OI)(CI)F", account+":(OI)(CI)RX"); err != nil {
		return err
	}
	if err := mustRun("icacls.exe", configPath, "/inheritance:r", "/grant:r", "SYSTEM:F", "Administrators:F"); err != nil {
		return err
	}
	if err := createTask("DirectBot", "ONSTART", installed+" bot", "/RU", "SYSTEM", "/RL", "HIGHEST"); err != nil {
		return err
	}
	if err := createTask("Enforcer", "MINUTE", installed+" enforcer", "/MO", "1", "/RU", "SYSTEM", "/RL", "HIGHEST"); err != nil {
		return err
	}
	if err := mustRun("schtasks.exe", "/Run", "/TN", "GuardianPaws-DirectBot"); err != nil {
		return err
	}
	if err := mustRun("schtasks.exe", "/Run", "/TN", "GuardianPaws-Enforcer"); err != nil {
		return err
	}
	rollback = false
	fmt.Printf("Installed. In a private chat with the bot, send: /pair %s\nThe code expires in 15 minutes and permits at most two guardian Telegram accounts.\nParent-admin recovery: Task Scheduler > Task Scheduler Library > GuardianPaws-DirectBot / GuardianPaws-Enforcer, or run Install-GuardianPaws-Go.cmd uninstall.\n", code)
	return nil
}
func createTask(name, schedule, taskRun string, extra ...string) error {
	a := []string{"/Create", "/F", "/TN", "GuardianPaws-" + name, "/SC", schedule}
	a = append(a, extra...)
	a = append(a, "/TR", taskRun)
	return mustRun("schtasks.exe", a...)
}
func uninstall() error {
	if err := requireAdmin(); err != nil {
		return err
	}
	_, _ = run("schtasks.exe", "/Delete", "/F", "/TN", "GuardianPaws-DirectBot")
	_, _ = run("schtasks.exe", "/Delete", "/F", "/TN", "GuardianPaws-Enforcer")
	fmt.Println("Tasks removed. Delete %ProgramData%\\GuardianPaws only after saving required pairing/configuration data.")
	return nil
}

const enableEchoInput = 0x0004

func readSecret(prompt string) (string, error) {
	fmt.Print(prompt)
	h := os.Stdin.Fd()
	originalMode, err := getConsoleInputMode(h)
	if err != nil {
		return "", fmt.Errorf("read secret from a Command Prompt window: %w", err)
	}
	if err := setConsoleInputMode(h, originalMode&^enableEchoInput); err != nil {
		return "", fmt.Errorf("disable console echo: %w", err)
	}
	defer setConsoleInputMode(h, originalMode)
	s, e := bufio.NewReader(os.Stdin).ReadString('\n')
	fmt.Println()
	return strings.TrimRight(s, "\r\n"), e
}
func copyFile(from, to string) error {
	in, e := os.Open(from)
	if e != nil {
		return e
	}
	defer in.Close()
	out, e := os.Create(to)
	if e != nil {
		return e
	}
	_, e = io.Copy(out, in)
	ce := out.Close()
	if e != nil {
		return e
	}
	return ce
}
func pairingCode() (string, error) {
	var b [4]byte
	if _, e := rand.Read(b[:]); e != nil {
		return "", e
	}
	return fmt.Sprintf("%09d", binary.BigEndian.Uint32(b[:])%900000000+100000000), nil
}
func saveConfig(c Config) error {
	if err := os.MkdirAll(root, 0755); err != nil {
		return err
	}
	b, e := json.MarshalIndent(c, "", "  ")
	if e != nil {
		return e
	}
	tmp := configPath + ".tmp"
	if e = os.WriteFile(tmp, b, 0600); e != nil {
		return e
	}
	return os.Rename(tmp, configPath)
}
func readConfig() (Config, error) {
	var c Config
	b, e := os.ReadFile(configPath)
	if e != nil {
		return c, e
	}
	e = json.Unmarshal(b, &c)
	return c, e
}

func setPolicies(sid, update string, shorts bool) error {
	for _, browser := range []string{"Microsoft\\Edge", "Google\\Chrome"} {
		base := registryPolicyBase(sid, browser)
		if e := mustRun("reg.exe", "add", base+`\ExtensionInstallForcelist`, "/v", "GuardianPaws1", "/t", "REG_SZ", "/d", extensionID+";"+update, "/f"); e != nil {
			return e
		}
		key := base + `\URLBlocklist`
		if shorts {
			for i, u := range []string{"*://www.youtube.com/shorts*", "*://youtube.com/shorts*"} {
				if e := mustRun("reg.exe", "add", key, "/v", fmt.Sprintf("GuardianPaws%d", i+1), "/t", "REG_SZ", "/d", u, "/f"); e != nil {
					return e
				}
			}
		} else {
			_, _ = run("reg.exe", "delete", key, "/v", "GuardianPaws1", "/f")
			_, _ = run("reg.exe", "delete", key, "/v", "GuardianPaws2", "/f")
		}
	}
	return nil
}
func enforce() error {
	c, e := readConfig()
	if e != nil {
		return e
	}
	return setPolicies(c.ChildSID, c.ExtensionUpdateURL, c.ShortsBlocked)
}
func accountEnabled(child string) (bool, error) {
	o, e := run("net.exe", "user", child)
	return strings.Contains(strings.ToLower(o), "account active               yes"), e
}
func setAccount(child string, enabled bool) error {
	v := "/active:no"
	if enabled {
		v = "/active:yes"
	}
	return mustRun("net.exe", "user", child, v)
}
