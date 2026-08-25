package main

import "testing"

func TestInstallValidation(t *testing.T) {
	valid := map[string]string{"child": "Child-1", "display": "Child account", "extension-update-url": "https://example.test/update.xml"}
	if err := validateInstall(valid); err != nil {
		t.Fatal(err)
	}
	for name, value := range []map[string]string{{"child": "bad name", "display": "x", "extension-update-url": "https://x"}, {"child": "child", "display": "", "extension-update-url": "https://x"}, {"child": "child", "display": "x", "extension-update-url": "http://x"}} {
		if err := validateInstall(value); err == nil {
			t.Fatalf("case %d accepted", name)
		}
	}
}
func TestGuardianAndWebActionAllowLists(t *testing.T) {
	if !hasGuardian([]int64{7, 9}, 9) || hasGuardian([]int64{7}, 8) {
		t.Fatal("guardian authorization incorrect")
	}
	if !allowedWebAction("1", "shorts-off") || allowedWebAction("2", "shorts-off") || allowedWebAction("1", "arbitrary-command") {
		t.Fatal("web action allowlist incorrect")
	}
}
func TestParseOptions(t *testing.T) {
	o := parseOptions([]string{"--child", "kid", "--display", "Kid Name"})
	if o["child"] != "kid" || o["display"] != "Kid Name" {
		t.Fatal("options not parsed")
	}
}

func TestRegistryPolicyBaseUsesSingleSeparators(t *testing.T) {
	got := registryPolicyBase("S-1-5-21-123", "Microsoft\\Edge")
	want := "HKU\\S-1-5-21-123\\Software\\Policies\\Microsoft\\Edge"
	if got != want {
		t.Fatalf("registry key = %q, want %q", got, want)
	}
}
