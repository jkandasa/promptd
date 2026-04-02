package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode"
)

// CalculatorTool evaluates basic arithmetic expressions.
type CalculatorTool struct{}

func (CalculatorTool) Name() string { return "calculate" }

func (CalculatorTool) Description() string {
	return "Evaluates a mathematical expression and returns the result. Supports +, -, *, /, ^, parentheses, and functions: sqrt, abs, floor, ceil, round."
}

func (CalculatorTool) Parameters() any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"expression": map[string]any{
				"type":        "string",
				"description": "The math expression to evaluate, e.g. '2 + 3 * (4 - 1)' or 'sqrt(16) + 2^3'",
			},
		},
		"required": []string{"expression"},
	}
}

func (CalculatorTool) Execute(_ context.Context, args json.RawMessage) (string, error) {
	var params struct {
		Expression string `json:"expression"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}

	result, err := evaluate(params.Expression)
	if err != nil {
		return "", fmt.Errorf("could not evaluate %q: %w", params.Expression, err)
	}

	// Format: omit decimal if result is a whole number
	if result == math.Trunc(result) {
		return fmt.Sprintf("%g", result), nil
	}
	return strconv.FormatFloat(result, 'f', 10, 64), nil
}

// --- Recursive descent parser ---
// Grammar:
//   expr   = term   (('+' | '-') term)*
//   term   = factor (('*' | '/') factor)*
//   factor = ('+' | '-') factor | base '^' factor | base
//   base   = number | ident '(' expr ')' | '(' expr ')'

type parser struct {
	input []rune
	pos   int
}

func evaluate(expr string) (float64, error) {
	p := &parser{input: []rune(strings.TrimSpace(expr))}
	result, err := p.parseExpr()
	if err != nil {
		return 0, err
	}
	p.skipSpaces()
	if p.pos != len(p.input) {
		return 0, fmt.Errorf("unexpected character %q at position %d", string(p.input[p.pos]), p.pos)
	}
	return result, nil
}

func (p *parser) peek() (rune, bool) {
	p.skipSpaces()
	if p.pos >= len(p.input) {
		return 0, false
	}
	return p.input[p.pos], true
}

func (p *parser) consume() rune {
	ch := p.input[p.pos]
	p.pos++
	return ch
}

func (p *parser) skipSpaces() {
	for p.pos < len(p.input) && unicode.IsSpace(p.input[p.pos]) {
		p.pos++
	}
}

func (p *parser) parseExpr() (float64, error) {
	left, err := p.parseTerm()
	if err != nil {
		return 0, err
	}
	for {
		ch, ok := p.peek()
		if !ok || (ch != '+' && ch != '-') {
			break
		}
		p.consume()
		right, err := p.parseTerm()
		if err != nil {
			return 0, err
		}
		if ch == '+' {
			left += right
		} else {
			left -= right
		}
	}
	return left, nil
}

func (p *parser) parseTerm() (float64, error) {
	left, err := p.parseFactor()
	if err != nil {
		return 0, err
	}
	for {
		ch, ok := p.peek()
		if !ok || (ch != '*' && ch != '/') {
			break
		}
		p.consume()
		right, err := p.parseFactor()
		if err != nil {
			return 0, err
		}
		if ch == '*' {
			left *= right
		} else {
			if right == 0 {
				return 0, fmt.Errorf("division by zero")
			}
			left /= right
		}
	}
	return left, nil
}

func (p *parser) parseFactor() (float64, error) {
	ch, ok := p.peek()
	if !ok {
		return 0, fmt.Errorf("unexpected end of expression")
	}
	// Unary +/-
	if ch == '+' || ch == '-' {
		p.consume()
		val, err := p.parseFactor()
		if err != nil {
			return 0, err
		}
		if ch == '-' {
			return -val, nil
		}
		return val, nil
	}

	base, err := p.parseBase()
	if err != nil {
		return 0, err
	}

	// Exponentiation (right-associative)
	if ch, ok := p.peek(); ok && ch == '^' {
		p.consume()
		exp, err := p.parseFactor()
		if err != nil {
			return 0, err
		}
		return math.Pow(base, exp), nil
	}

	return base, nil
}

func (p *parser) parseBase() (float64, error) {
	ch, ok := p.peek()
	if !ok {
		return 0, fmt.Errorf("unexpected end of expression")
	}

	// Parenthesized expression
	if ch == '(' {
		p.consume()
		val, err := p.parseExpr()
		if err != nil {
			return 0, err
		}
		p.skipSpaces()
		if p.pos >= len(p.input) || p.input[p.pos] != ')' {
			return 0, fmt.Errorf("missing closing parenthesis")
		}
		p.consume()
		return val, nil
	}

	// Function or number
	if unicode.IsLetter(ch) {
		return p.parseFunc()
	}

	return p.parseNumber()
}

func (p *parser) parseFunc() (float64, error) {
	start := p.pos
	for p.pos < len(p.input) && unicode.IsLetter(p.input[p.pos]) {
		p.pos++
	}
	name := string(p.input[start:p.pos])

	p.skipSpaces()
	if p.pos >= len(p.input) || p.input[p.pos] != '(' {
		return 0, fmt.Errorf("expected '(' after function %q", name)
	}
	p.consume() // (

	arg, err := p.parseExpr()
	if err != nil {
		return 0, err
	}

	p.skipSpaces()
	if p.pos >= len(p.input) || p.input[p.pos] != ')' {
		return 0, fmt.Errorf("missing closing parenthesis for function %q", name)
	}
	p.consume() // )

	switch name {
	case "sqrt":
		if arg < 0 {
			return 0, fmt.Errorf("sqrt of negative number")
		}
		return math.Sqrt(arg), nil
	case "abs":
		return math.Abs(arg), nil
	case "floor":
		return math.Floor(arg), nil
	case "ceil":
		return math.Ceil(arg), nil
	case "round":
		return math.Round(arg), nil
	default:
		return 0, fmt.Errorf("unknown function %q", name)
	}
}

func (p *parser) parseNumber() (float64, error) {
	start := p.pos
	for p.pos < len(p.input) && (unicode.IsDigit(p.input[p.pos]) || p.input[p.pos] == '.') {
		p.pos++
	}
	if start == p.pos {
		return 0, fmt.Errorf("expected number at position %d, got %q", p.pos, string(p.input[p.pos:]))
	}
	return strconv.ParseFloat(string(p.input[start:p.pos]), 64)
}
