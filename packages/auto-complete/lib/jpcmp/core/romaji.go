package core

import "strings"

func ConvertRomaji(input string) string {
	s := strings.ToLower(input)
	repl := []struct{ from, to string }{
		{"houjinbaikyaku", "ほうじんばいきゃく"},
		{"houjin", "ほうじん"},
		{"houji", "ほうじ"},
		{"houshin", "ほうしん"},
		{"hojo", "ほじょ"},
		{"hou", "ほう"},
		{"ji", "じ"},
		{"n", "ん"},
	}
	for _, r := range repl {
		s = strings.ReplaceAll(s, r.from, r.to)
	}
	return s
}
