// wordcount is an example remote tool binary that demonstrates auto-registration.
//
// Without auto-registration (manual tools.yaml entry):
//
//	go run ./examples/wordcount --addr :9001
//
// With auto-registration (no tools.yaml needed):
//
//	go run ./examples/wordcount --addr :9001 --self http://localhost:9001 --chatbot http://localhost:8080
//
// On startup it registers itself with the chatbot.
// On SIGTERM/SIGINT it unregisters itself before shutting down.
// If killed, the chatbot's heartbeat monitor will unregister it automatically.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"strings"
	"unicode"

	"chatbot/toolserver"
)

type WordCountTool struct{}

func (WordCountTool) Name() string { return "word_count" }

func (WordCountTool) Description() string {
	return "Counts the number of words, sentences, and characters in a given text."
}

func (WordCountTool) Parameters() any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"text": map[string]any{
				"type":        "string",
				"description": "The text to analyse.",
			},
		},
		"required": []string{"text"},
	}
}

func (WordCountTool) Execute(_ context.Context, args json.RawMessage) (string, error) {
	var params struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %w", err)
	}
	if params.Text == "" {
		return "", fmt.Errorf("text is required")
	}

	words := len(strings.Fields(params.Text))
	chars := len([]rune(params.Text))
	sentences := countSentences(params.Text)

	return fmt.Sprintf("words: %d, sentences: %d, characters: %d", words, sentences, chars), nil
}

func countSentences(text string) int {
	count := 0
	for _, r := range text {
		if r == '.' || r == '!' || r == '?' {
			count++
		}
	}
	if count == 0 && len(strings.TrimFunc(text, unicode.IsSpace)) > 0 {
		count = 1
	}
	return count
}

func main() {
	addr := flag.String("addr", ":9001", "address to listen on")
	selfURL := flag.String("self", "", "URL this tool is reachable at (e.g. http://localhost:9001)")
	chatbotURL := flag.String("chatbot", "", "chatbot base URL for auto-registration (e.g. http://localhost:8080)")
	flag.Parse()

	log.Fatal(toolserver.ServeWithConfig(toolserver.Config{
		Addr:       *addr,
		SelfURL:    *selfURL,
		ChatbotURL: *chatbotURL,
	}, WordCountTool{}))
}
