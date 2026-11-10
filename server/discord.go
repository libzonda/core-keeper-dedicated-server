package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type DiscordEmbedFooter struct {
	Text    string `json:"text,omitempty"`
	IconURL string `json:"icon_url,omitempty"`
}

type DiscordEmbedField struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Inline bool   `json:"inline,omitempty"`
}

type DiscordEmbed struct {
	Title       string              `json:"title,omitempty"`
	Description string              `json:"description,omitempty"`
	Color       int                 `json:"color,omitempty"`
	Fields      []DiscordEmbedField `json:"fields,omitempty"`
	Footer      *DiscordEmbedFooter `json:"footer,omitempty"`
	Timestamp   string              `json:"timestamp,omitempty"`
}

type DiscordWebhookPayload struct {
	Username  string         `json:"username,omitempty"`
	AvatarURL string         `json:"avatar_url,omitempty"`
	Content   string         `json:"content,omitempty"`
	Embeds    []DiscordEmbed `json:"embeds,omitempty"`
}

type DiscordTestRequest struct {
	WebhookURL string `json:"webhookUrl"`
	BotName    string `json:"botName"`
	AvatarURL  string `json:"avatarUrl"`
}

type DiscordTestResponse struct {
	Success   bool   `json:"success"`
	LatencyMs int64  `json:"latencyMs"`
	Message   string `json:"message"`
	Error     string `json:"error,omitempty"`
}

func parseHexColor(hexStr string) int {
	hexStr = strings.TrimPrefix(strings.TrimSpace(hexStr), "#")
	if hexStr == "" {
		return 0x2ECC71
	}
	val, err := strconv.ParseInt(hexStr, 16, 32)
	if err != nil {
		return 0x2ECC71
	}
	return int(val)
}

func renderTemplate(tmpl string, vars map[string]string) string {
	res := tmpl
	for k, v := range vars {
		res = strings.ReplaceAll(res, "{"+k+"}", v)
	}
	return res
}

func buildHTTPClient(proxyURL string, useProxy bool, timeout time.Duration) *http.Client {
	transport := &http.Transport{}
	if useProxy && strings.TrimSpace(proxyURL) != "" {
		if parsed, err := url.Parse(strings.TrimSpace(proxyURL)); err == nil {
			transport.Proxy = http.ProxyURL(parsed)
		}
	}
	return &http.Client{
		Transport: transport,
		Timeout:   timeout,
	}
}

func SendDiscordWebhook(webhookURL string, payload DiscordWebhookPayload, proxyURL string, useProxy bool) error {
	webhookURL = strings.TrimSpace(webhookURL)
	if webhookURL == "" {
		return fmt.Errorf("discord webhook URL is empty")
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal discord payload: %w", err)
	}

	client := buildHTTPClient(proxyURL, useProxy, 12*time.Second)
	req, err := http.NewRequest(http.MethodPost, webhookURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create http request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "CoreKeeper-Dedicated-Server-Manager/"+Version)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("webhook network request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("discord API responded with HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	return nil
}

func NotifyDiscordEvent(cfg ServerConfig, eventKey string, vars map[string]string) {
	if !cfg.Discord.Enabled || strings.TrimSpace(cfg.Discord.WebhookURL) == "" {
		return
	}

	tmpl, exists := cfg.Discord.Messages[eventKey]
	if !exists || !tmpl.Enabled {
		return
	}

	title := renderTemplate(tmpl.Title, vars)
	desc := renderTemplate(tmpl.Description, vars)
	color := parseHexColor(tmpl.Color)

	botName := cfg.Discord.BotName
	if botName == "" {
		botName = "Core Keeper Bot"
	}
	avatarURL := cfg.Discord.AvatarURL
	if avatarURL == "" {
		avatarURL = "https://raw.githubusercontent.com/libzonda/core-keeper-dedicated-server/main/logo.png"
	}

	payload := DiscordWebhookPayload{
		Username:  botName,
		AvatarURL: avatarURL,
		Embeds: []DiscordEmbed{
			{
				Title:       title,
				Description: desc,
				Color:       color,
				Footer: &DiscordEmbedFooter{
					Text: fmt.Sprintf("Core Keeper Dedicated Server Manager • %s", Version),
				},
				Timestamp: time.Now().UTC().Format(time.RFC3339),
			},
		},
	}

	var proxyURL string
	useProxy := cfg.ProxyEnabled && cfg.ProxyDiscord
	if useProxy {
		proxyURL, _ = GetEffectiveProxyURL(cfg)
	}

	go func() {
		if err := SendDiscordWebhook(cfg.Discord.WebhookURL, payload, proxyURL, useProxy); err != nil {
			log.Printf("[Discord] Failed to send webhook event '%s': %v", eventKey, err)
		} else {
			log.Printf("[Discord] Successfully sent webhook event '%s'", eventKey)
		}
	}()
}

