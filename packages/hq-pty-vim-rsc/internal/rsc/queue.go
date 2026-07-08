package rsc

import (
	"encoding/json"
	"os"
)

func AppendInstruction(path string, ins Instruction) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(ins)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}
