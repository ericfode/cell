package subzero

import (
	"bytes"
	"testing"
)

func TestSmoke(t *testing.T) {
	var buf bytes.Buffer
	if err := RunSmoke(&buf); err != nil {
		t.Fatalf("smoke test failed:\n%s", buf.String())
	}
	t.Log(buf.String())
}
