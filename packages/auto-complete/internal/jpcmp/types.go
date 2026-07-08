package jpcmp

type Config struct { DictionaryPaths []string; MinChars int; BufferLimit int; DictionaryLimit int; MaxCandidates int; SourcePriority map[string]int }
func DefaultConfig() Config { return Config{DictionaryPaths: []string{"dict/domain.jsonl"}, MinChars: 2, BufferLimit: 12, DictionaryLimit: 12, MaxCandidates: 20, SourcePriority: map[string]int{"buffer":200000,"jp":100000}} }
type Token struct { Raw string; Reading string; Line int; StartChar int; EndChar int }
type Candidate struct { Word string `json:"word"`; Source string `json:"source"`; Rank int `json:"rank"`; Score int `json:"score"`; Reading string `json:"reading,omitempty"` }
type CompletionItem struct { Label string `json:"label"`; Detail string `json:"detail,omitempty"`; FilterText string `json:"filterText,omitempty"`; SortText string `json:"sortText,omitempty"`; TextEdit *TextEdit `json:"textEdit,omitempty"`; Data Candidate `json:"data,omitempty"` }
type TextEdit struct { Range Range `json:"range"`; NewText string `json:"newText"` }
type Range struct { Start Position `json:"start"`; End Position `json:"end"` }
type Position struct { Line int `json:"line"`; Character int `json:"character"` }
