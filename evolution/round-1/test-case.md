# Round 1 Test Case

Two-cell program:
1. **greet** — takes `name` as input, produces `{ message: str }`
2. **wrap** — depends on greet's output, produces `{ text: str, emoji: str }`

## Eval-one test:
Given state `{ name: "Alice" }`, executing greet should produce something like `{ message: "Hello, Alice!" }`.
Then executing wrap (with greet's output available) should produce something like `{ text: "Hello, Alice!", emoji: "👋" }`.

## Scoring (per variant):
- 50% execute accuracy: can an LLM eval-one correctly?
- 30% distill quality: could you mechanically replace the LLM step?
- 20% readability: is it obvious what the program does?
