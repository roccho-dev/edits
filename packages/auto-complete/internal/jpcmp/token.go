package jpcmp

import "regexp"

var tokenRE = regexp.MustCompile(`[A-Za-z_][A-Za-z0-9_]*$`)
func ExtractToken(lineText string, line, character int) Token { if character < 0 { character = 0 }; if character > len(lineText) { character = len(lineText) }; before := lineText[:character]; raw := tokenRE.FindString(before); start := character - len(raw); return Token{Raw: raw, Reading: ConvertRomaji(raw), Line: line, StartChar: start, EndChar: character} }
