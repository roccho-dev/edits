package main

import (
	"flag"
	"log"
	"os"
	"strings"

	"github.com/roccho-dev/edits/packages/auto-complete/internal/jpcmp"
)

func main() {
	dict := flag.String("dict", "dict/domain.jsonl", "comma-separated JSONL dictionary paths")
	flag.Parse()
	cfg := jpcmp.DefaultConfig()
	if *dict != "" { cfg.DictionaryPaths = strings.Split(*dict, ",") }
	server := jpcmp.NewServer(jpcmp.NewEngine(cfg))
	if err := server.Serve(os.Stdin, os.Stdout); err != nil { log.Fatal(err) }
}
