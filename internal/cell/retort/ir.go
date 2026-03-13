package retort

// RetortCell is the intermediate representation for a Cell computation unit.
// Both frontends (markdown-recipe Syntax A and turnstile Syntax B) lower to this.
type RetortCell struct {
	Name     string
	BodyType BodyType // hard, soft, passthrough, spawner, evolution
	Body     string   // ⊢= expression or ∴ prompt text
	Givens   []RetortGiven
	Yields   []RetortYield
	Oracles  []RetortOracle
	Recovery *RetortRecovery
}

// BodyType classifies how a cell computes its output.
type BodyType string

const (
	BodyHard        BodyType = "hard"
	BodySoft        BodyType = "soft"
	BodyPassthrough BodyType = "passthrough"
	BodyScript      BodyType = "script"
	BodySpawner     BodyType = "spawner"
	BodyEvolution   BodyType = "evolution"
)

// RetortGiven represents an input dependency of a cell.
type RetortGiven struct {
	Name        string  // binding name (param name or field alias)
	SourceCell  string  // upstream cell name (empty for defaults/params)
	SourceField string  // field on source cell (empty = same as Name)
	Default     *string // default value (nil = no default)
	HasDefault  bool
	IsOptional  bool   // given? syntax
	IsQuotation bool   // §cell-name syntax
	GuardExpr   string // where clause expression (empty = no guard)
}

// RetortYield represents an output slot of a cell.
type RetortYield struct {
	Name         string  // field name
	DefaultValue *string // for yield X ≡ val syntax (data cells)
}

// RetortOracle represents an assertion on a cell's output.
type RetortOracle struct {
	Assertion string // the oracle text (e.g., "sum = 8", "message is a string")
	Ordinal   int    // declaration order
}

// RetortRecovery represents a recovery policy for oracle failures.
type RetortRecovery struct {
	MaxRetries        int
	ExhaustionAction  string // "bottom", "escalate", "partial_accept"
	ExhaustionExpr    string // predicate for partial_accept
	RecoveryDirective string // raw recovery text (e.g., "retry with «oracle.failures» appended")
}

// RetortProgram is a collection of cells loaded from a single source file.
type RetortProgram struct {
	Name       string
	SourceFile string
	SourceHash string
	Cells      []RetortCell
}
