package core

func ReplaceRange(token Token) Range {
	return Range{Start: Position{Line: token.Line, Character: token.StartChar}, End: Position{Line: token.Line, Character: token.EndChar}}
}
