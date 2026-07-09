package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

func main() {
	out := os.Getenv("HQ_FAKE_EXPLORER_RECEIPT")
	if out == "" {
		fmt.Fprintln(os.Stderr, "HQ_FAKE_EXPLORER_RECEIPT is required")
		os.Exit(2)
	}
	row := map[string]any{
		"kind": "fake.explorer.invoked.v1",
		"argv": os.Args,
		"time": time.Now().UTC().Format(time.RFC3339),
	}
	b, err := json.Marshal(row)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := os.WriteFile(out, append(b, '\n'), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
