package jpcmplsp

type Config struct {
	DictionaryPaths []string
	HQSourcePaths   []string
}

func DefaultConfig() Config { return Config{DictionaryPaths: []string{"dict/domain.jsonl"}} }
