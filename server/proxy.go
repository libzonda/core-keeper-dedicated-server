package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"time"
)

type ProxyTestRequest struct {
	ProxyType    string `json:"proxyType"`    // "http", "socks5", "clash"
	ProxyAddress string `json:"proxyAddress"` // e.g. "http://127.0.0.1:7890" or "socks5://127.0.0.1:7890"
	ClashApiUrl  string `json:"clashApiUrl"`  // e.g. "http://127.0.0.1:9090"
	ClashSecret  string `json:"clashSecret"`
}

type ProxyTestResponse struct {
	Success        bool   `json:"success"`
	LatencyMs      int64  `json:"latencyMs"`
	EffectiveProxy string `json:"effectiveProxy,omitempty"`
	Message        string `json:"message"`
	Error          string `json:"error,omitempty"`
}

type ClashTestResponse struct {
	Success          bool     `json:"success"`
	Version          string   `json:"version,omitempty"`
	Mode             string   `json:"mode,omitempty"`
	Port             int      `json:"port,omitempty"`
	SocksPort        int      `json:"socksPort,omitempty"`
	MixedPort        int      `json:"mixedPort,omitempty"`
	EffectiveProxy   string   `json:"effectiveProxy,omitempty"`
	CurrentNode      string   `json:"currentNode,omitempty"`
	CurrentNodeType  string   `json:"currentNodeType,omitempty"`
	CurrentNodeDelay int      `json:"currentNodeDelay,omitempty"`
	CurrentGroup     string   `json:"currentGroup,omitempty"`
	AvailableNodes   []string `json:"availableNodes,omitempty"`
	Message          string   `json:"message"`
	Error            string   `json:"error,omitempty"`
}

// GetEffectiveProxyURL returns the resolved proxy URL (e.g. "http://127.0.0.1:7890" or "socks5://127.0.0.1:7890")
// based on the configuration. If proxy is disabled, it returns "".
func GetEffectiveProxyURL(cfg ServerConfig) (string, error) {
	if !cfg.ProxyEnabled {
		return "", nil
	}

	switch strings.ToLower(cfg.ProxyType) {
	case "http", "https":
		addr := strings.TrimSpace(cfg.ProxyAddress)
		if addr == "" {
			return "", nil
		}
		if !strings.HasPrefix(addr, "http://") && !strings.HasPrefix(addr, "https://") {
			addr = "http://" + addr
		}
		return addr, nil

	case "socks5", "socks":
		addr := strings.TrimSpace(cfg.ProxyAddress)
		if addr == "" {
			return "", nil
		}
		if !strings.HasPrefix(addr, "socks5://") && !strings.HasPrefix(addr, "socks://") {
			addr = "socks5://" + addr
		}
		return addr, nil

	case "clash":
		info, err := FetchClashConfig(cfg.ClashApiUrl, cfg.ClashSecret)
		if err != nil {
			return "", fmt.Errorf("failed to fetch Clash config: %w", err)
		}
		return info.EffectiveProxy, nil

	default:
		// Default to HTTP if type is unspecified
		addr := strings.TrimSpace(cfg.ProxyAddress)
		if addr == "" {
			return "", nil
		}
		if !strings.Contains(addr, "://") {
			addr = "http://" + addr
		}
		return addr, nil
	}
}

// FetchClashConfig calls Clash external controller to resolve proxy port and build effective URL.
// It also queries /proxies to detect the current selected node and available nodes in the active selector group.
func FetchClashConfig(apiUrl, secret string) (*ClashTestResponse, error) {
	apiUrl = strings.TrimSpace(apiUrl)
	if apiUrl == "" {
		apiUrl = "http://127.0.0.1:9090"
	}
	if !strings.HasPrefix(apiUrl, "http://") && !strings.HasPrefix(apiUrl, "https://") {
		apiUrl = "http://" + apiUrl
	}
	apiUrl = strings.TrimRight(apiUrl, "/")

	parsedApi, err := url.Parse(apiUrl)
	if err != nil {
		return nil, fmt.Errorf("invalid Clash API URL: %w", err)
	}

	clashHost := parsedApi.Hostname()
	if clashHost == "" {
		clashHost = "127.0.0.1"
	}

	client := &http.Client{Timeout: 5 * time.Second}

	// 1. Fetch Version
	version := "Unknown"
	{
		req, _ := http.NewRequest(http.MethodGet, apiUrl+"/version", nil)
		if secret != "" {
			req.Header.Set("Authorization", "Bearer "+secret)
		}
		if resp, err := client.Do(req); err == nil {
			defer resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				var vData struct {
					Version string `json:"version"`
				}
				if err := json.NewDecoder(resp.Body).Decode(&vData); err == nil && vData.Version != "" {
					version = vData.Version
				}
			}
		}
	}

	// 2. Fetch Configs
	req, err := http.NewRequest(http.MethodGet, apiUrl+"/configs", nil)
	if err != nil {
		return nil, err
	}
	if secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("could not connect to Clash API at %s: %w", apiUrl, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("clash API responded with status %d: %s", resp.StatusCode, string(b))
	}

	var cfg struct {
		Port      int    `json:"port"`
		SocksPort int    `json:"socks-port"`
		MixedPort int    `json:"mixed-port"`
		Mode      string `json:"mode"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse Clash configs JSON: %w", err)
	}

	effectiveProxy := ""
	if cfg.MixedPort > 0 {
		effectiveProxy = fmt.Sprintf("http://%s:%d", clashHost, cfg.MixedPort)
	} else if cfg.Port > 0 {
		effectiveProxy = fmt.Sprintf("http://%s:%d", clashHost, cfg.Port)
	} else if cfg.SocksPort > 0 {
		effectiveProxy = fmt.Sprintf("socks5://%s:%d", clashHost, cfg.SocksPort)
	} else {
		return nil, fmt.Errorf("clash reported no active mixed-port, http port or socks-port")
	}

	// 3. Detect Current Node and Available Nodes via /proxies
	group, currentNode, nodeType, delay, availableNodes := detectClashNodes(apiUrl, secret, cfg.Mode, client)

	msg := fmt.Sprintf("Clash API connected successfully (version: %s, mode: %s)", version, cfg.Mode)
	if currentNode != "" {
		if delay > 0 {
			msg = fmt.Sprintf("Clash connected · Active node: %s (%s, %dms)", currentNode, nodeType, delay)
		} else {
			msg = fmt.Sprintf("Clash connected · Active node: %s (%s)", currentNode, nodeType)
		}
	}

	return &ClashTestResponse{
		Success:          true,
		Version:          version,
		Mode:             cfg.Mode,
		Port:             cfg.Port,
		SocksPort:        cfg.SocksPort,
		MixedPort:        cfg.MixedPort,
		EffectiveProxy:   effectiveProxy,
		CurrentNode:      currentNode,
		CurrentNodeType:  nodeType,
		CurrentNodeDelay: delay,
		CurrentGroup:     group,
		AvailableNodes:   availableNodes,
		Message:          msg,
	}, nil
}

type clashRawProxy struct {
	Name    string   `json:"name"`
	Type    string   `json:"type"`
	Now     string   `json:"now"`
	All     []string `json:"all"`
	History []struct {
		Time  string `json:"time"`
		Delay int    `json:"delay"`
	} `json:"history"`
}

// detectClashNodes queries Clash /proxies and determines the current active node
func detectClashNodes(apiUrl, secret, mode string, client *http.Client) (group, node, nodeType string, delay int, availableNodes []string) {
	req, err := http.NewRequest(http.MethodGet, apiUrl+"/proxies", nil)
	if err != nil {
		return
	}
	if secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}

	resp, err := client.Do(req)
	if err != nil || resp.StatusCode != http.StatusOK {
		if resp != nil {
			_ = resp.Body.Close()
		}
		return
	}
	defer resp.Body.Close()

	var result struct {
		Proxies map[string]clashRawProxy `json:"proxies"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return
	}
	proxies := result.Proxies
	if len(proxies) == 0 {
		return
	}

	// 1. Determine the root selector group
	var rootGroup string
	if strings.ToLower(mode) == "global" {
		rootGroup = "GLOBAL"
	} else {
		// Common priority group names in Clash rule configurations
		candidates := []string{"PROXY", "Proxy", "节点选择", "🚀 节点选择", "默认", "Auto", "Select", "GLOBAL"}
		for _, c := range candidates {
			if _, exists := proxies[c]; exists {
				rootGroup = c
				break
			}
		}
		if rootGroup == "" {
			for name, p := range proxies {
				if strings.EqualFold(p.Type, "Selector") && name != "GLOBAL" {
					rootGroup = name
					break
				}
			}
		}
		if rootGroup == "" {
			if _, exists := proxies["GLOBAL"]; exists {
				rootGroup = "GLOBAL"
			}
		}
	}

	if rootGroup == "" {
		return
	}

	group = rootGroup
	curr := rootGroup
	visited := make(map[string]bool)

	for curr != "" && !visited[curr] {
		visited[curr] = true
		p, exists := proxies[curr]
		if !exists {
			break
		}

		if len(p.All) > 0 {
			group = curr
			availableNodes = p.All
		}

		if p.Now == "" {
			// Reached leaf node
			break
		}

		curr = p.Now
	}

	node = curr
	if p, exists := proxies[node]; exists {
		nodeType = p.Type
		if len(p.History) > 0 {
			delay = p.History[len(p.History)-1].Delay
		}
	}

	return
}

// SwitchClashNode changes the selected proxy for a given group via Clash API
func SwitchClashNode(apiUrl, secret, group, nodeName string) error {
	apiUrl = strings.TrimSpace(apiUrl)
	if apiUrl == "" {
		apiUrl = "http://127.0.0.1:9090"
	}
	if !strings.HasPrefix(apiUrl, "http://") && !strings.HasPrefix(apiUrl, "https://") {
		apiUrl = "http://" + apiUrl
	}
	apiUrl = strings.TrimRight(apiUrl, "/")

	group = strings.TrimSpace(group)
	if group == "" {
		group = "GLOBAL"
	}

	bodyData, err := json.Marshal(map[string]string{"name": nodeName})
	if err != nil {
		return err
	}

	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodPut, fmt.Sprintf("%s/proxies/%s", apiUrl, url.PathEscape(group)), bytes.NewReader(bodyData))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to switch node: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("clash API responded with status %d: %s", resp.StatusCode, string(b))
	}

	return nil
}

// TestProxyConnectivity attempts to make a request through the given proxy URL and measures latency.
func TestProxyConnectivity(proxyURL string) (int64, error) {
	proxyURL = strings.TrimSpace(proxyURL)
	if proxyURL == "" {
		return 0, fmt.Errorf("proxy address cannot be empty")
	}

	parsedProxy, err := url.Parse(proxyURL)
	if err != nil {
		return 0, fmt.Errorf("invalid proxy URL format: %w", err)
	}

	transport := &http.Transport{
		Proxy: http.ProxyURL(parsedProxy),
	}

	client := &http.Client{
		Transport: transport,
		Timeout:   8 * time.Second,
	}

	// Endpoints to test connectivity
	endpoints := []string{
		"https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/",
		"https://store.steampowered.com",
		"https://www.cloudflare.com/cdn-cgi/trace",
	}

	var lastErr error
	for _, endpoint := range endpoints {
		start := time.Now()
		req, err := http.NewRequest(http.MethodGet, endpoint, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", "CoreKeeper-Dedicated-Server-Manager/1.0")

		resp, err := client.Do(req)
		if err == nil {
			_ = resp.Body.Close()
			latency := time.Since(start).Milliseconds()
			return latency, nil
		}
		lastErr = err
	}

	return 0, fmt.Errorf("proxy connection failed: %w", lastErr)
}

// ApplyProxyEnv configures the environment variables on the exec.Cmd to route network through the proxy.
func ApplyProxyEnv(cmd *exec.Cmd, proxyURL string) {
	if proxyURL == "" {
		return
	}

	var baseEnv []string
	if len(cmd.Env) > 0 {
		baseEnv = cmd.Env
	} else {
		baseEnv = os.Environ()
	}

	proxyEnv := []string{
		"HTTP_PROXY=" + proxyURL,
		"HTTPS_PROXY=" + proxyURL,
		"ALL_PROXY=" + proxyURL,
		"http_proxy=" + proxyURL,
		"https_proxy=" + proxyURL,
		"all_proxy=" + proxyURL,
	}

	// Filter out any previous proxy variables to avoid duplicates
	var merged []string
	for _, e := range baseEnv {
		upper := strings.ToUpper(e)
		if strings.HasPrefix(upper, "HTTP_PROXY=") ||
			strings.HasPrefix(upper, "HTTPS_PROXY=") ||
			strings.HasPrefix(upper, "ALL_PROXY=") {
			continue
		}
		merged = append(merged, e)
	}

	// Ensure essential variables like HOME and USER are never empty
	hasHome := false
	for _, e := range merged {
		if strings.HasPrefix(e, "HOME=") && len(e) > 5 {
			hasHome = true
			break
		}
	}
	if !hasHome {
		home := os.Getenv("HOME")
		if home == "" {
			home = "/home/steam"
		}
		merged = append(merged, "HOME="+home)
	}

	cmd.Env = append(merged, proxyEnv...)
}
