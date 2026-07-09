package main

import (
	"flag"
	app "github.com/roccho-dev/edits/packages/auto-complete/app/jpcmp-lsp"
	"log"
	"os"
	"strings"
)

func main() {
	dict := flag.String("dict", "dict/domain.jsonl", "comma-separated JSONL dictionary paths")
	hqSource := flag.String("hq-source", "", "comma-separated hq source JSONL paths")
	flag.Parse()
	cfg := app.DefaultConfig()
	if *dict != "" {
		cfg.DictionaryPaths = strings.Split(*dict, ",")
	}
	if *hqSource != "" {
		cfg.HQSourcePaths = strings.Split(*hqSource, ",")
	}
	server := app.NewServer(cfg)
	if err := server.Serve(os.Stdin, os.Stdout); err != nil {
		log.Fatal(err)
	}
}
