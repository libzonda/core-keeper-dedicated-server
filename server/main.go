package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

// Version is injected during compilation via -ldflags="-X main.Version=vX.Y.Z"
var Version = "v0.1.4"

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for web management
	},
}

func main() {
	serverDir := flag.String("server-dir", getEnv("GAME_PATH", "/server/game"), "Path to Core Keeper game files")
	dataDir := flag.String("data-dir", getEnv("DATA_PATH", "/server/data"), "Path to server save and data files")
	webDir := flag.String("web-dir", getEnv("WEB_DIR", "/server/web"), "Path to Flutter Web frontend files")
	webPort := flag.Int("port", getEnvInt("WEB_PORT", 8080), "Web manager listening port")
	flag.Parse()

	_ = os.MkdirAll(*serverDir, 0755)
	_ = os.MkdirAll(*dataDir, 0755)

	instanceMgr := NewInstanceManager(*dataDir, *serverDir, *webPort)
	globalConfigMgr := NewConfigManager(*dataDir, *serverDir, *webPort)
	instanceMgr.SetGlobalConfigManager(globalConfigMgr)

	mux := http.NewServeMux()

	resolveRuntime := func(w http.ResponseWriter, r *http.Request) *InstanceRuntime {
		instID := r.URL.Query().Get("instance")
		if instID == "" {
			instID = r.Header.Get("X-Instance-ID")
		}
		if instID == "" {
			instID = instanceMgr.GetActiveInstanceID()
		}
		if instID == "" {
			http.Error(w, "No server instances available", http.StatusNotFound)
			return nil
		}
		runtime, err := instanceMgr.GetInstanceRuntime(instID)
		if err != nil {
			http.Error(w, fmt.Sprintf("Instance not found: %s", instID), http.StatusNotFound)
			return nil
		}
		return runtime
	}

	// Instance Management Routes
	mux.HandleFunc("/api/instances", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, instanceMgr.ListInstances())
		case http.MethodPost:
			var req ServerInstance
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			inst, err := instanceMgr.CreateInstance(req)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]interface{}{
				"success":   true,
				"instance":  inst,
				"instances": instanceMgr.ListInstances(),
			})
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc("/api/instances/switch", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			ID string `json:"id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID == "" {
			http.Error(w, "Instance ID required", http.StatusBadRequest)
			return
		}
		if err := instanceMgr.SetActiveInstanceID(req.ID); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]interface{}{
			"success":          true,
			"activeInstanceId": req.ID,
			"instances":        instanceMgr.ListInstances(),
		})
	})

	mux.HandleFunc("/api/instances/", func(w http.ResponseWriter, r *http.Request) {
		sub := strings.TrimPrefix(r.URL.Path, "/api/instances/")
		parts := strings.Split(sub, "/")
		instID := parts[0]
		if instID == "" {
			http.Error(w, "Instance ID required", http.StatusBadRequest)
			return
		}

		if len(parts) == 1 {
			// /api/instances/{id}
			switch r.Method {
			case http.MethodGet:
				runtime, err := instanceMgr.GetInstanceRuntime(instID)
				if err != nil {
					http.Error(w, err.Error(), http.StatusNotFound)
					return
				}
				writeJSON(w, runtime.Instance)
			case http.MethodPut:
				var req ServerInstance
				if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				if err := instanceMgr.UpdateInstance(instID, req); err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				writeJSON(w, instanceMgr.ListInstances())
			case http.MethodDelete:
				if err := instanceMgr.DeleteInstance(instID); err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				writeJSON(w, instanceMgr.ListInstances())
			default:
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		action := parts[1]
		runtime, err := instanceMgr.GetInstanceRuntime(instID)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}

		switch action {
		case "start":
			if r.Method != http.MethodPost {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			if err := runtime.ProcMgr.Start(); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]string{"message": "Instance started successfully"})
		case "stop":
			if r.Method != http.MethodPost {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			if err := runtime.ProcMgr.Stop(); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]string{"message": "Instance stopped successfully"})
		case "restart":
			if r.Method != http.MethodPost {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			if err := runtime.ProcMgr.Restart(); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]string{"message": "Instance restarting"})
		case "status":
			if r.Method != http.MethodGet {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			writeJSON(w, runtime.GetStatus())
		case "logs":
			if r.Method != http.MethodGet {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			writeJSON(w, runtime.ProcMgr.GetLogs())
		default:
			http.NotFound(w, r)
		}
	})

	// Application Version endpoint
	mux.HandleFunc("/api/version", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"version": Version,
		})
	})

	// Server Control & Status (Instance-Aware)
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		instID := r.URL.Query().Get("instance")
		if instID == "" {
			instID = r.Header.Get("X-Instance-ID")
		}
		if instID == "" {
			instID = instanceMgr.GetActiveInstanceID()
		}
		if instID == "" {
			writeJSON(w, StatusResponse{
				Status:       StatusStopped,
				ServerName:   "暂无实例",
				InstanceName: "暂无实例",
				Version:      Version,
			})
			return
		}
		runtime, err := instanceMgr.GetInstanceRuntime(instID)
		if err != nil {
			writeJSON(w, StatusResponse{
				Status:       StatusStopped,
				ServerName:   "暂无实例",
				InstanceName: "暂无实例",
				Version:      Version,
			})
			return
		}
		writeJSON(w, runtime.GetStatus())
	})

	mux.HandleFunc("/api/server/start", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		if err := runtime.ProcMgr.Start(); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]string{"message": "Server started successfully"})
	})

	mux.HandleFunc("/api/server/stop", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		if err := runtime.ProcMgr.Stop(); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]string{"message": "Server stopped successfully"})
	})

	mux.HandleFunc("/api/server/restart", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		if err := runtime.ProcMgr.Restart(); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]string{"message": "Server restarting"})
	})

	mux.HandleFunc("/api/server/update", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			SteamUser string `json:"steamUser"`
			SteamPass string `json:"steamPass"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)

		if err := runtime.ProcMgr.UpdateServer(req.SteamUser, req.SteamPass); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]string{"message": "Server update triggered"})
	})

	// Logs (Instance-Aware)
	mux.HandleFunc("/api/logs", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		writeJSON(w, runtime.ProcMgr.GetLogs())
	})

	// WebSocket for real-time logs (Instance-Aware)
	mux.HandleFunc("/api/ws/logs", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("[WS] Upgrade error: %v", err)
			return
		}
		defer conn.Close()

		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}

		// Send recent history
		for _, l := range runtime.ProcMgr.GetLogs() {
			if err := conn.WriteMessage(websocket.TextMessage, []byte(l)); err != nil {
				return
			}
		}

		ch, unsubscribe := runtime.ProcMgr.SubscribeLogs()
		defer unsubscribe()

		done := make(chan struct{})
		go func() {
			for {
				if _, _, err := conn.ReadMessage(); err != nil {
					close(done)
					return
				}
			}
		}()

		for {
			select {
			case <-done:
				return
			case line, ok := <-ch:
				if !ok {
					return
				}
				if err := conn.WriteMessage(websocket.TextMessage, []byte(line)); err != nil {
					return
				}
			}
		}
	})

	// Configuration (Instance-Aware)
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, runtime.ConfigMgr.Get())
		case http.MethodPut, http.MethodPost:
			var cfg ServerConfig
			if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
				http.Error(w, "Invalid JSON: "+err.Error(), http.StatusBadRequest)
				return
			}
			if err := runtime.ConfigMgr.Update(cfg); err != nil {
				http.Error(w, "Failed to save config: "+err.Error(), http.StatusInternalServerError)
				return
			}
			runtime.ProcMgr.SetRestartRequired(true)
			_ = instanceMgr.UpdateInstance(runtime.Instance.ID, ServerInstance{
				Name:        cfg.WorldName,
				NetworkMode: cfg.NetworkMode,
				Port:        cfg.Port,
				Password:    cfg.Password,
				MaxPlayers:  cfg.MaxPlayers,
				AutoStart:   cfg.AutoStart,
				WorldIndex:  cfg.WorldIndex,
				WorldName:   cfg.WorldName,
				WorldMode:   cfg.WorldMode,
				WorldSeed:   cfg.WorldSeed,
			})
			writeJSON(w, runtime.ConfigMgr.Get())
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	// Proxy Test
	mux.HandleFunc("/api/proxy/test", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req ProxyTestRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON: "+err.Error(), http.StatusBadRequest)
			return
		}

		runtime := resolveRuntime(w, r)
		var cfg ServerConfig
		if runtime != nil {
			cfg = runtime.ConfigMgr.Get()
		} else {
			cfg = globalConfigMgr.Get()
		}
		if req.ProxyType != "" {
			cfg.ProxyType = req.ProxyType
		}
		if req.ProxyAddress != "" {
			cfg.ProxyAddress = req.ProxyAddress
		}
		if req.ClashApiUrl != "" {
			cfg.ClashApiUrl = req.ClashApiUrl
		}
		if req.ClashSecret != "" {
			cfg.ClashSecret = req.ClashSecret
		}
		cfg.ProxyEnabled = true

		effectiveURL, err := GetEffectiveProxyURL(cfg)
		if err != nil {
			writeJSON(w, ProxyTestResponse{
				Success: false,
				Message: "代理地址解析失败",
				Error:   err.Error(),
			})
			return
		}

		if effectiveURL == "" {
			writeJSON(w, ProxyTestResponse{
				Success: false,
				Message: "未配置代理地址",
				Error:   "proxy address is empty",
			})
			return
		}

		latency, err := TestProxyConnectivity(effectiveURL)
		if err != nil {
			writeJSON(w, ProxyTestResponse{
				Success:        false,
				EffectiveProxy: effectiveURL,
				Message:        "代理连接测试失败",
				Error:          err.Error(),
			})
			return
		}

		writeJSON(w, ProxyTestResponse{
			Success:        true,
			LatencyMs:      latency,
			EffectiveProxy: effectiveURL,
			Message:        fmt.Sprintf("代理测试成功，往返延迟: %d ms", latency),
		})
	})

	// Clash Controller Test
	mux.HandleFunc("/api/clash/test", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			ClashApiUrl string `json:"clashApiUrl"`
			ClashSecret string `json:"clashSecret"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON: "+err.Error(), http.StatusBadRequest)
			return
		}

		runtime := resolveRuntime(w, r)
		var cfg ServerConfig
		if runtime != nil {
			cfg = runtime.ConfigMgr.Get()
		} else {
			cfg = globalConfigMgr.Get()
		}

		apiUrl := req.ClashApiUrl
		if apiUrl == "" {
			apiUrl = cfg.ClashApiUrl
		}
		secret := req.ClashSecret
		if secret == "" {
			secret = cfg.ClashSecret
		}

		info, err := FetchClashConfig(apiUrl, secret)
		if err != nil {
			writeJSON(w, ClashTestResponse{
				Success: false,
				Message: "Clash 控制器连接失败",
				Error:   err.Error(),
			})
			return
		}

		writeJSON(w, info)
	})

	// Clash Switch Node
	mux.HandleFunc("/api/clash/switch-node", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			ClashApiUrl string `json:"clashApiUrl"`
			ClashSecret string `json:"clashSecret"`
			Group       string `json:"group"`
			Node        string `json:"node"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON: "+err.Error(), http.StatusBadRequest)
			return
		}

		runtime := resolveRuntime(w, r)
		var cfg ServerConfig
		if runtime != nil {
			cfg = runtime.ConfigMgr.Get()
		} else {
			cfg = globalConfigMgr.Get()
		}

		apiUrl := req.ClashApiUrl
		if apiUrl == "" {
			apiUrl = cfg.ClashApiUrl
		}
		secret := req.ClashSecret
		if secret == "" {
			secret = cfg.ClashSecret
		}

		if err := SwitchClashNode(apiUrl, secret, req.Group, req.Node); err != nil {
			http.Error(w, "Failed to switch node: "+err.Error(), http.StatusBadRequest)
			return
		}

		// Persist the selected Clash node and group to instance config
		if runtime != nil {
			c := runtime.ConfigMgr.Get()
			c.ClashGroup = req.Group
			c.ClashNode = req.Node
			_ = runtime.ConfigMgr.Update(c)
			runtime.ProcMgr.SetRestartRequired(true)
		} else {
			c := globalConfigMgr.Get()
			c.ClashGroup = req.Group
			c.ClashNode = req.Node
			_ = globalConfigMgr.Update(c)
		}

		info, err := FetchClashConfig(apiUrl, secret)
		if err == nil {
			writeJSON(w, info)
			return
		}
		writeJSON(w, map[string]string{"message": "Node switched successfully"})
	})

	// Save Proxy Config directly (Instance-Scoped)
	mux.HandleFunc("/api/config/proxy", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost && r.Method != http.MethodPut {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			ProxyEnabled  bool   `json:"proxyEnabled"`
			ProxySDR      *bool  `json:"proxySDR"`
			ProxySteamCmd *bool  `json:"proxySteamCmd"`
			ProxyMods     *bool  `json:"proxyMods"`
			ProxyType     string `json:"proxyType"`
			ProxyAddress  string `json:"proxyAddress"`
			ClashApiUrl   string `json:"clashApiUrl"`
			ClashSecret   string `json:"clashSecret"`
			ClashNode     string `json:"clashNode"`
			ClashGroup    string `json:"clashGroup"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid JSON: "+err.Error(), http.StatusBadRequest)
			return
		}
		cur := runtime.ConfigMgr.Get()
		sdr := cur.ProxySDR
		if req.ProxySDR != nil {
			sdr = *req.ProxySDR
		}
		steamcmd := cur.ProxySteamCmd
		if req.ProxySteamCmd != nil {
			steamcmd = *req.ProxySteamCmd
		}
		mods := cur.ProxyMods
		if req.ProxyMods != nil {
			mods = *req.ProxyMods
		}

		if err := runtime.ConfigMgr.UpdateProxy(req.ProxyEnabled, sdr, steamcmd, mods, req.ProxyType, req.ProxyAddress, req.ClashApiUrl, req.ClashSecret, req.ClashNode, req.ClashGroup); err != nil {
			http.Error(w, "Failed to save proxy config: "+err.Error(), http.StatusInternalServerError)
			return
		}
		runtime.ProcMgr.SetRestartRequired(true)
		writeJSON(w, runtime.ConfigMgr.Get())
	})

	// Admins (Instance-Aware)
	mux.HandleFunc("/api/admins", func(w http.ResponseWriter, r *http.Request) {
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		switch r.Method {
		case http.MethodGet:
			admins, err := runtime.AdminMgr.GetAdmins()
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			if admins == nil {
				admins = []AdminItem{}
			}
			writeJSON(w, admins)
		case http.MethodPost:
			var req struct {
				Name       string      `json:"name"`
				SteamID    interface{} `json:"steamId"`
				Privileges int         `json:"privileges"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			var sId int64
			switch v := req.SteamID.(type) {
			case string:
				parsed, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
				if err != nil {
					http.Error(w, "Invalid steamId format", http.StatusBadRequest)
					return
				}
				sId = parsed
			case float64:
				sId = int64(v)
			case json.Number:
				parsed, err := v.Int64()
				if err != nil {
					http.Error(w, "Invalid steamId format", http.StatusBadRequest)
					return
				}
				sId = parsed
			default:
				http.Error(w, "steamId is required", http.StatusBadRequest)
				return
			}

			if err := runtime.AdminMgr.AddAdmin(req.Name, sId, req.Privileges); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			admins, _ := runtime.AdminMgr.GetAdmins()
			if admins == nil {
				admins = []AdminItem{}
			}
			writeJSON(w, admins)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc("/api/admins/", func(w http.ResponseWriter, r *http.Request) {
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		idStr := strings.TrimSpace(strings.TrimPrefix(r.URL.Path, "/api/admins/"))
		if idStr == "" {
			http.Error(w, "Missing steamId in path", http.StatusBadRequest)
			return
		}

		switch r.Method {
		case http.MethodPut:
			var req struct {
				Name       string `json:"name"`
				Privileges int    `json:"privileges"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			sId, err := strconv.ParseInt(idStr, 10, 64)
			if err != nil {
				http.Error(w, "Invalid steamId", http.StatusBadRequest)
				return
			}
			if err := runtime.AdminMgr.UpdateAdmin(sId, req.Name, req.Privileges); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			admins, _ := runtime.AdminMgr.GetAdmins()
			if admins == nil {
				admins = []AdminItem{}
			}
			writeJSON(w, admins)
		case http.MethodDelete:
			if err := runtime.AdminMgr.DeleteAdmin(idStr); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			admins, _ := runtime.AdminMgr.GetAdmins()
			if admins == nil {
				admins = []AdminItem{}
			}
			writeJSON(w, admins)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	// Worlds (Instance-Aware)
	mux.HandleFunc("/api/worlds", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		cfg := runtime.ConfigMgr.Get()
		worlds := runtime.WorldMgr.GetWorlds(cfg.WorldIndex)
		writeJSON(w, worlds)
	})

	mux.HandleFunc("/api/worlds/switch", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			Index int `json:"index"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		meta, err := runtime.WorldMgr.GetWorldMeta(req.Index)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		if err := instanceMgr.SetInstanceWorld(runtime.Instance.ID, meta.Index, meta.Name, meta.Mode, meta.Seed); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[Manager] Switched active world to: %s", meta.Name))
		writeJSON(w, map[string]interface{}{"activeWorld": req.Index, "message": "World switched successfully"})
	})

	mux.HandleFunc("/api/worlds/rename", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			Index int    `json:"index"`
			Name  string `json:"name"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		req.Name = strings.TrimSpace(req.Name)
		if req.Name == "" {
			http.Error(w, "World name cannot be empty", http.StatusBadRequest)
			return
		}

		if err := runtime.WorldMgr.RenameWorld(req.Index, req.Name); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		cfg := runtime.ConfigMgr.Get()
		// If renaming the currently active world, sync to server config & instance metadata
		if req.Index == cfg.WorldIndex {
			cfg.WorldName = req.Name
			_ = runtime.ConfigMgr.Update(cfg)
			runtime.ProcMgr.SetRestartRequired(true)
			_ = instanceMgr.UpdateInstance(runtime.Instance.ID, ServerInstance{
				WorldName: req.Name,
			})
			runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[Manager] Active world renamed to: %s (server restart required to apply to connecting clients)", req.Name))
		} else {
			runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[Manager] World slot #%d renamed to: %s", req.Index, req.Name))
		}

		writeJSON(w, map[string]interface{}{
			"message": "World renamed successfully",
			"worlds":  runtime.WorldMgr.GetWorlds(cfg.WorldIndex),
		})
	})

	mux.HandleFunc("/api/worlds/create", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			Index *int   `json:"index"`
			Name  string `json:"name"`
			Seed  int64  `json:"seed"`
			Mode  int    `json:"mode"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		targetIndex := -1
		if req.Index != nil {
			targetIndex = *req.Index
		}

		assignedIndex, err := runtime.WorldMgr.AddWorld(targetIndex, req.Name, req.Mode, req.Seed)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[Manager] Added world '%s' (internal ID %d)", req.Name, assignedIndex))
		cfg := runtime.ConfigMgr.Get()
		writeJSON(w, runtime.WorldMgr.GetWorlds(cfg.WorldIndex))
	})

	mux.HandleFunc("/api/worlds/import", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		if err := r.ParseMultipartForm(100 << 20); err != nil {
			http.Error(w, "Failed to parse form: "+err.Error(), http.StatusBadRequest)
			return
		}
		file, header, err := r.FormFile("file")
		if err != nil {
			http.Error(w, "File upload required (field 'file')", http.StatusBadRequest)
			return
		}
		defer file.Close()

		data, err := io.ReadAll(file)
		if err != nil {
			http.Error(w, "Failed to read file: "+err.Error(), http.StatusInternalServerError)
			return
		}
		if len(data) == 0 {
			http.Error(w, "Uploaded file is empty", http.StatusBadRequest)
			return
		}

		name := strings.TrimSpace(r.FormValue("name"))
		if name == "" {
			origName := header.Filename
			origName = strings.TrimSuffix(origName, ".gzip")
			origName = strings.TrimSuffix(origName, ".world")
			origName = strings.TrimSuffix(origName, ".world.gzip")
			if origName != "" {
				name = origName
			} else {
				name = "导入世界"
			}
		}

		mode, _ := strconv.Atoi(r.FormValue("mode"))
		seed, _ := strconv.ParseInt(r.FormValue("seed"), 10, 64)

		newIndex, err := runtime.WorldMgr.ImportWorld(name, mode, seed, data)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[Manager] Imported world '%s' (index %d, size %d bytes)", name, newIndex, len(data)))
		cfg := runtime.ConfigMgr.Get()
		writeJSON(w, runtime.WorldMgr.GetWorlds(cfg.WorldIndex))
	})

	mux.HandleFunc("/api/worlds/", func(w http.ResponseWriter, r *http.Request) {
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		// Handle /api/worlds/{id}/export
		if strings.HasSuffix(r.URL.Path, "/export") {
			if r.Method != http.MethodGet {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			trimmed := strings.TrimPrefix(r.URL.Path, "/api/worlds/")
			trimmed = strings.TrimSuffix(trimmed, "/export")
			trimmed = strings.Trim(trimmed, "/")
			index, err := strconv.Atoi(trimmed)
			if err != nil {
				http.Error(w, "Invalid world index", http.StatusBadRequest)
				return
			}
			var buf bytes.Buffer
			filename, err := runtime.WorldMgr.ExportWorldZip(index, &buf)
			if err != nil {
				http.Error(w, err.Error(), http.StatusNotFound)
				return
			}
			w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, url.PathEscape(filename)))
			w.Header().Set("Content-Type", "application/zip")
			w.Header().Set("Content-Length", strconv.Itoa(buf.Len()))
			_, _ = w.Write(buf.Bytes())
			return
		}

		if r.Method != http.MethodDelete {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		idStr := strings.TrimPrefix(r.URL.Path, "/api/worlds/")
		idStr = strings.Trim(idStr, "/")
		index, err := strconv.Atoi(idStr)
		if err != nil {
			http.Error(w, "Invalid world index", http.StatusBadRequest)
			return
		}
		cfg := runtime.ConfigMgr.Get()
		if err := runtime.WorldMgr.DeleteWorld(index, cfg.WorldIndex); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[Manager] Deleted world save %d", index))
		writeJSON(w, runtime.WorldMgr.GetWorlds(cfg.WorldIndex))
	})

	// Mods (Shared Pool with Instance-Specific Enablement)
	mux.HandleFunc("/api/mods", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		mods, err := instanceMgr.modMgr.ListModsWithEnabled(runtime.Instance.EnabledMods)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if mods == nil {
			mods = []ModInfo{}
		}
		writeJSON(w, mods)
	})

	installModHandler := func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			Target     string `json:"target"`
			WorkshopID string `json:"workshopId"`
			URL        string `json:"url"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		target := req.Target
		if target == "" {
			target = req.WorkshopID
		}
		if target == "" {
			target = req.URL
		}
		target = strings.TrimSpace(target)
		if target == "" {
			http.Error(w, "Mod URL or Workshop ID is required", http.StatusBadRequest)
			return
		}

		instanceMgr.modMgr.SetConfigManager(runtime.ConfigMgr)
		mod, err := instanceMgr.modMgr.InstallMod(target, func(s string) {
			runtime.ProcMgr.BroadcastLog(s)
		})
		if err != nil {
			runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[ModManager] Failed to install mod: %v", err))
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		// When installed in current instance, automatically enable it for current instance!
		instanceMgr.AddModToInstance(runtime.Instance.ID, mod.ID)
		mod.Enabled = true

		runtime.ProcMgr.SetRestartRequired(true)
		mods, _ := instanceMgr.modMgr.ListModsWithEnabled(runtime.Instance.EnabledMods)
		writeJSON(w, map[string]interface{}{
			"success": true,
			"message": fmt.Sprintf("Mod '%s' installed and enabled for current instance", mod.Name),
			"mod":     mod,
			"mods":    mods,
		})
	}

	mux.HandleFunc("/api/mods/install", installModHandler)
	mux.HandleFunc("/api/mods/install-workshop", installModHandler)

	mux.HandleFunc("/api/mods/upload", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		// Max upload 150 MB
		if err := r.ParseMultipartForm(150 << 20); err != nil {
			http.Error(w, "Failed to parse upload: "+err.Error(), http.StatusBadRequest)
			return
		}
		file, header, err := r.FormFile("file")
		if err != nil {
			http.Error(w, "File upload missing", http.StatusBadRequest)
			return
		}
		defer file.Close()

		mod, err := instanceMgr.modMgr.InstallUploadedZip(header.Filename, file, header.Size, func(s string) {
			runtime.ProcMgr.BroadcastLog(s)
		})
		if err != nil {
			runtime.ProcMgr.BroadcastLog(fmt.Sprintf("[ModManager] Uploaded mod installation failed: %v", err))
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		instanceMgr.AddModToInstance(runtime.Instance.ID, mod.ID)
		mod.Enabled = true

		runtime.ProcMgr.SetRestartRequired(true)
		mods, _ := instanceMgr.modMgr.ListModsWithEnabled(runtime.Instance.EnabledMods)
		writeJSON(w, map[string]interface{}{
			"success": true,
			"message": fmt.Sprintf("Mod '%s' uploaded and enabled for current instance", mod.Name),
			"mod":     mod,
			"mods":    mods,
		})
	})

	mux.HandleFunc("/api/mods/toggle", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		var req struct {
			ModID   string `json:"modId"`
			Enabled bool   `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := instanceMgr.ToggleModForInstance(runtime.Instance.ID, req.ModID, req.Enabled); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		runtime.ProcMgr.SetRestartRequired(true)
		mods, _ := instanceMgr.modMgr.ListModsWithEnabled(runtime.Instance.EnabledMods)
		writeJSON(w, mods)
	})

	mux.HandleFunc("/api/mods/", func(w http.ResponseWriter, r *http.Request) {
		runtime := resolveRuntime(w, r)
		if runtime == nil {
			return
		}
		sub := strings.TrimPrefix(r.URL.Path, "/api/mods/")

		// Handle POST /api/mods/{id}/update
		if strings.HasSuffix(sub, "/update") {
			if r.Method != http.MethodPost {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
				return
			}
			modID := strings.TrimSuffix(sub, "/update")
			instanceMgr.modMgr.SetConfigManager(runtime.ConfigMgr)
			mod, err := instanceMgr.modMgr.UpdateMod(modID, func(s string) {
				runtime.ProcMgr.BroadcastLog(s)
			})
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			runtime.ProcMgr.SetRestartRequired(true)
			mods, _ := instanceMgr.modMgr.ListModsWithEnabled(runtime.Instance.EnabledMods)
			writeJSON(w, map[string]interface{}{
				"success": true,
				"message": fmt.Sprintf("Mod '%s' updated successfully", mod.Name),
				"mod":     mod,
				"mods":    mods,
			})
			return
		}

		if r.Method != http.MethodDelete {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		modID := sub
		if err := instanceMgr.modMgr.DeleteMod(modID); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		// Also clean from instance EnabledMods
		for _, inst := range instanceMgr.ListInstances() {
			_ = instanceMgr.ToggleModForInstance(inst.ID, modID, false)
		}
		runtime.ProcMgr.SetRestartRequired(true)
		mods, _ := instanceMgr.modMgr.ListModsWithEnabled(runtime.Instance.EnabledMods)
		writeJSON(w, mods)
	})

	// Mod.io Global Configuration & Connectivity Test
	mux.HandleFunc("/api/modio/config", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			apiKey := globalConfigMgr.Get().ModioApiKey
			writeJSON(w, map[string]interface{}{
				"configured": apiKey != "",
				"apiKey":     apiKey,
			})
		case http.MethodPost:
			var req struct {
				ApiKey string `json:"apiKey"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			cleanKey := strings.TrimSpace(req.ApiKey)
			if err := globalConfigMgr.SetModioApiKey(cleanKey); err != nil {
				http.Error(w, "Failed to update global config: "+err.Error(), http.StatusInternalServerError)
				return
			}
			// Propagate to all instance runtimes
			for _, runtime := range instanceMgr.GetAllRuntimes() {
				_ = runtime.ConfigMgr.SetModioApiKey(cleanKey)
			}
			writeJSON(w, map[string]interface{}{
				"success":    true,
				"message":    "Mod.io API Key 已保存并同步至所有实例",
				"configured": cleanKey != "",
				"apiKey":     cleanKey,
			})
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc("/api/modio/test", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			ApiKey string `json:"apiKey"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		apiKey := strings.TrimSpace(req.ApiKey)
		if apiKey == "" {
			apiKey = globalConfigMgr.Get().ModioApiKey
		}
		if apiKey == "" {
			writeJSON(w, map[string]interface{}{
				"success": false,
				"message": "API Key 不能为空",
			})
			return
		}

		cfg := globalConfigMgr.Get()
		transport := &http.Transport{}
		if cfg.ProxyEnabled && cfg.ProxyMods {
			if p, err := GetEffectiveProxyURL(cfg); err == nil && p != "" {
				if pu, err := url.Parse(p); err == nil {
					transport.Proxy = http.ProxyURL(pu)
				}
			}
		}
		client := &http.Client{
			Transport: transport,
			Timeout:   30 * time.Second,
		}

		game, err := TestModioApiKey(client, apiKey)
		if err != nil {
			writeJSON(w, map[string]interface{}{
				"success": false,
				"message": "连接失败: " + err.Error(),
				"error":   err.Error(),
			})
			return
		}

		writeJSON(w, map[string]interface{}{
			"success":  true,
			"message":  fmt.Sprintf("连接成功: 已连接至 %s (游戏ID: %d)", game.Name, game.ID),
			"gameId":   game.ID,
			"gameName": game.Name,
		})
	})

	// Dedicated font handler: serve local font slices with aggressive caching; on cache-miss, optionally proxy and cache from gstatic
	mux.HandleFunc("/fonts/", func(w http.ResponseWriter, r *http.Request) {
		cleanPath := filepath.Clean(r.URL.Path)
		targetPath := filepath.Join(*webDir, cleanPath)
		if fi, err := os.Stat(targetPath); err == nil && !fi.IsDir() {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			if strings.HasSuffix(cleanPath, ".woff2") {
				w.Header().Set("Content-Type", "font/woff2")
			}
			http.ServeFile(w, r, targetPath)
			return
		}

		// If not locally present, attempt upstream fetch from Google Fonts CDN
		subPath := strings.TrimPrefix(cleanPath, "/fonts/")
		upstreamURL := "https://fonts.gstatic.com/" + subPath
		client := &http.Client{Timeout: 4 * time.Second}
		resp, err := client.Get(upstreamURL)
		if err == nil && resp.StatusCode == http.StatusOK {
			defer resp.Body.Close()
			_ = os.MkdirAll(filepath.Dir(targetPath), 0755)
			data, readErr := io.ReadAll(resp.Body)
			if readErr == nil && len(data) > 0 {
				_ = os.WriteFile(targetPath, data, 0644)
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
				w.Header().Set("Content-Type", "font/woff2")
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write(data)
				return
			}
		}

		// Font genuinely unavailable: return 404 with cache header so browser doesn't spam retries
		w.Header().Set("Cache-Control", "public, max-age=3600")
		http.NotFound(w, r)
	})

	// Static SPA handler for Flutter Web with safe asset routing
	fileServer := http.FileServer(http.Dir(*webDir))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api") {
			http.NotFound(w, r)
			return
		}
		cleanPath := filepath.Clean(r.URL.Path)
		targetPath := filepath.Join(*webDir, cleanPath)
		if fi, err := os.Stat(targetPath); err == nil && !fi.IsDir() {
			fileServer.ServeHTTP(w, r)
			return
		}
		// Asset / font / binary missing: return 404, never serve index.html
		if strings.HasPrefix(cleanPath, "/fonts") ||
			strings.HasPrefix(cleanPath, "/canvaskit") ||
			strings.HasPrefix(cleanPath, "/assets") ||
			filepath.Ext(cleanPath) != "" {
			http.NotFound(w, r)
			return
		}
		// SPA routing fallback
		http.ServeFile(w, r, filepath.Join(*webDir, "index.html"))
	})

	// Setup CORS wrapper
	handler := corsMiddleware(mux)

	// Auto-start instances if configured
	instanceMgr.StartAllAutoStart()

	addr := fmt.Sprintf("0.0.0.0:%d", *webPort)
	server := &http.Server{
		Addr:    addr,
		Handler: handler,
	}

	// Handle OS signals
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("[Manager] Core Keeper Web Management Server listening on %s (WebDir: %s)", addr, *webDir)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[Manager] Listen error: %v", err)
		}
	}()

	<-stopChan
	log.Println("[Manager] Shutting down all instances...")
	instanceMgr.StopAll()
	_ = server.Close()
	log.Println("[Manager] Goodbye!")
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(data)
}

func getEnv(key, def string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return def
}

func getEnvInt(key string, def int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return def
}

func getEnvInt64(key string, def int64) int64 {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.ParseInt(val, 10, 64); err == nil {
			return i
		}
	}
	return def
}

func getEnvBool(key string, def bool) bool {
	if val := os.Getenv(key); val != "" {
		lower := strings.ToLower(val)
		return lower == "true" || lower == "1" || lower == "yes"
	}
	return def
}
