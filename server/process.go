package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	rePlayerConnect    = regexp.MustCompile(`(?i)(?:player entity.*?player\s+|player\s+['"]?)([^'"\n\r]+?)['"]?\s+connected`)
	rePlayerDisconnect = regexp.MustCompile(`(?i)(?:player entity.*?player\s+|player\s+['"]?)([^'"\n\r]+?)['"]?\s+disconnected`)
)

type ServerStatus string

const (
	StatusStopped  ServerStatus = "stopped"
	StatusStarting ServerStatus = "starting"
	StatusRunning  ServerStatus = "running"
	StatusStopping ServerStatus = "stopping"
	StatusUpdating ServerStatus = "updating"
)

type StatusResponse struct {
	Status          ServerStatus `json:"status"`
	PID             int          `json:"pid"`
	UptimeSec       int64        `json:"uptimeSec"`
	GameID          string       `json:"gameId"`
	NetworkMode     string       `json:"networkMode"`
	Port            int          `json:"port"`
	ActiveWorld     int          `json:"activeWorld"`
	MaxPlayers      int          `json:"maxPlayers"`
	ServerName      string       `json:"serverName"`
	InstanceID      string       `json:"instanceId"`
	InstanceName    string       `json:"instanceName"`
	WorldName       string       `json:"worldName"`
	RestartRequired bool         `json:"restartRequired"`
	Version         string       `json:"version"`
}

type ProcessManager struct {
	configMgr *ConfigManager
	cmd       *exec.Cmd
	status    ServerStatus
	startTime time.Time
	mu        sync.RWMutex

	updateCmd    *exec.Cmd
	cancelUpdate context.CancelFunc

	logRing     []string
	maxLogLines int
	subscribers map[chan string]struct{}
	subMu       sync.RWMutex

	detectedGameID  string
	restartRequired bool
	prepareSandbox  func() (string, error)
	onlineNotified  bool
	manualStop      bool
}

func NewProcessManager(cm *ConfigManager) *ProcessManager {
	return &ProcessManager{
		configMgr:   cm,
		status:      StatusStopped,
		logRing:     make([]string, 0, 1000),
		maxLogLines: 1000,
		subscribers: make(map[chan string]struct{}),
	}
}

func (pm *ProcessManager) SetSandboxPreparer(fn func() (string, error)) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	pm.prepareSandbox = fn
}

func (pm *ProcessManager) SubscribeLogs() (chan string, func()) {
	pm.subMu.Lock()
	defer pm.subMu.Unlock()

	ch := make(chan string, 100)
	pm.subscribers[ch] = struct{}{}

	unsubscribe := func() {
		pm.subMu.Lock()
		defer pm.subMu.Unlock()
		delete(pm.subscribers, ch)
		close(ch)
	}

	return ch, unsubscribe
}

func (pm *ProcessManager) BroadcastLog(line string) {
	if line != "__CLEAR_LOGS__" {
		pm.mu.Lock()
		if len(pm.logRing) >= pm.maxLogLines {
			pm.logRing = pm.logRing[1:]
		}
		pm.logRing = append(pm.logRing, line)
		pm.mu.Unlock()
	}

	pm.subMu.RLock()
	defer pm.subMu.RUnlock()

	for ch := range pm.subscribers {
		select {
		case ch <- line:
		default:
		}
	}
}

func (pm *ProcessManager) GetLogs() []string {
	pm.mu.RLock()
	defer pm.mu.RUnlock()

	logsCopy := make([]string, len(pm.logRing))
	copy(logsCopy, pm.logRing)
	return logsCopy
}

func (pm *ProcessManager) SetRestartRequired(val bool) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	pm.restartRequired = val
}

func (pm *ProcessManager) IsRestartRequired() bool {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	return pm.restartRequired
}

func (pm *ProcessManager) GetStatus() StatusResponse {
	pm.mu.RLock()
	defer pm.mu.RUnlock()

	cfg := pm.configMgr.Get()

	var uptime int64 = 0
	pid := 0
	if pm.status == StatusRunning && !pm.startTime.IsZero() {
		uptime = int64(time.Since(pm.startTime).Seconds())
		if pm.cmd != nil && pm.cmd.Process != nil {
			pid = pm.cmd.Process.Pid
		}
	}

	gameID := pm.detectedGameID
	if gameID == "" {
		gameID = cfg.GameID
	}
	if gameID == "" {
		// Try reading GameID.txt directly from instance dataDir
		gameID = pm.readGameIDFile(cfg.DataDir, "")
	}

	return StatusResponse{
		Status:          pm.status,
		PID:             pid,
		UptimeSec:       uptime,
		GameID:          gameID,
		NetworkMode:     cfg.NetworkMode,
		Port:            cfg.Port,
		ActiveWorld:     cfg.WorldIndex,
		MaxPlayers:      cfg.MaxPlayers,
		ServerName:      cfg.WorldName,
		RestartRequired: pm.restartRequired && (pm.status == StatusRunning || pm.status == StatusStarting),
		Version:         Version,
	}
}

func (pm *ProcessManager) Start() error {
	pm.mu.Lock()
	if pm.status == StatusRunning || pm.status == StatusStarting {
		pm.mu.Unlock()
		return fmt.Errorf("server is already running or starting")
	}
	pm.status = StatusStarting
	pm.detectedGameID = ""
	pm.restartRequired = false
	pm.onlineNotified = false
	pm.manualStop = false
	// Reset log buffer so only current startup logs are shown
	pm.logRing = make([]string, 0, pm.maxLogLines)
	pm.mu.Unlock()

	// Clear logs on all connected clients and mark new run session
	pm.BroadcastLog("__CLEAR_LOGS__")
	pm.BroadcastLog("[Manager] === Starting Core Keeper Server (resetting live logs) ===")

	go pm.runServer()
	return nil
}

func (pm *ProcessManager) Stop() error {
	pm.mu.Lock()
	if pm.status != StatusRunning && pm.status != StatusStarting && pm.status != StatusUpdating {
		pm.mu.Unlock()
		return fmt.Errorf("server is not running")
	}
	pm.status = StatusStopping
	pm.manualStop = true
	cmd := pm.cmd
	updateCmd := pm.updateCmd
	cancelUpdate := pm.cancelUpdate
	pm.mu.Unlock()

	// If SteamCMD is running, cancel and kill it immediately
	if cancelUpdate != nil {
		cancelUpdate()
	}
	if updateCmd != nil && updateCmd.Process != nil {
		pm.BroadcastLog("[Manager] Aborting active SteamCMD update operation...")
		_ = updateCmd.Process.Kill()
	}

	pm.BroadcastLog("[Manager] Initiating graceful server shutdown (SIGINT)...")

	if cmd != nil && cmd.Process != nil {
		pgid, err := syscall.Getpgid(cmd.Process.Pid)
		if err == nil {
			_ = syscall.Kill(-pgid, syscall.SIGINT)
		} else {
			_ = cmd.Process.Signal(syscall.SIGINT)
		}

		// Wait up to 10 seconds, then SIGKILL if still running
		done := make(chan struct{})
		go func() {
			for i := 0; i < 20; i++ {
				pm.mu.RLock()
				st := pm.status
				pm.mu.RUnlock()
				if st == StatusStopped {
					close(done)
					return
				}
				time.Sleep(500 * time.Millisecond)
			}
			close(done)
		}()

		select {
		case <-done:
		case <-time.After(10 * time.Second):
			pm.BroadcastLog("[Manager] Force killing server process (SIGKILL)...")
			if err == nil {
				_ = syscall.Kill(-pgid, syscall.SIGKILL)
			} else {
				_ = cmd.Process.Kill()
			}
		}
	}

	pm.mu.Lock()
	pm.status = StatusStopped
	pm.cmd = nil
	pm.updateCmd = nil
	pm.cancelUpdate = nil
	pm.mu.Unlock()
	pm.BroadcastLog("[Manager] Server stopped.")
	return nil
}

func (pm *ProcessManager) ResetGameID() {
	pm.mu.Lock()
	pm.detectedGameID = ""
	pm.mu.Unlock()
}

func (pm *ProcessManager) Restart() error {
	_ = pm.Stop()
	for i := 0; i < 60; i++ {
		pm.mu.RLock()
		st := pm.status
		pm.mu.RUnlock()
		if st == StatusStopped {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	time.Sleep(500 * time.Millisecond)
	return pm.Start()
}

func (pm *ProcessManager) UpdateServer(steamUser, steamPass string) error {
	pm.mu.Lock()
	if pm.status == StatusRunning || pm.status == StatusStarting || pm.status == StatusUpdating {
		pm.mu.Unlock()
		return fmt.Errorf("cannot update while server is in state: %s", pm.status)
	}
	pm.status = StatusUpdating
	pm.logRing = make([]string, 0, pm.maxLogLines)
	pm.mu.Unlock()

	pm.BroadcastLog("__CLEAR_LOGS__")
	pm.BroadcastLog("[Manager] === Checking and updating server files via SteamCMD ===")

	go func() {
		defer func() {
			pm.mu.Lock()
			pm.status = StatusStopped
			pm.cancelUpdate = nil
			pm.updateCmd = nil
			pm.mu.Unlock()
		}()

		cfg := pm.configMgr.Get()
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
		pm.mu.Lock()
		pm.cancelUpdate = cancel
		pm.mu.Unlock()
		defer cancel()

		_ = pm.runSteamCmdUpdate(ctx, cfg, steamUser, steamPass)
	}()

	return nil
}

func (pm *ProcessManager) runSteamCmdUpdate(ctx context.Context, cfg ServerConfig, steamUser, steamPass string) error {
	pm.BroadcastLog("[SteamCMD] Connecting to SteamCMD to check Core Keeper Dedicated Server (AppID: 1963720)...")

	steamcmdPath := findSteamCmd()
	loginArgs := []string{"+login", "anonymous"}
	if steamUser != "" {
		loginArgs = []string{"+login", steamUser, steamPass}
	}

	args := []string{}
	var proxyURL string
	if cfg.ProxyEnabled && cfg.ProxySteamCmd {
		if p, err := GetEffectiveProxyURL(cfg); err == nil && p != "" {
			proxyURL = p
			pm.BroadcastLog(fmt.Sprintf("[SteamCMD] Updating server files via configured proxy: %s", proxyURL))
		}
	}

	args = append(args, "+force_install_dir", cfg.ServerDir)
	args = append(args, loginArgs...)
	args = append(args, "+app_update", "1963720", "validate", "+quit")

	cmd := exec.CommandContext(ctx, steamcmdPath, args...)
	if proxyURL != "" {
		ApplyProxyEnv(cmd, proxyURL)
	}

	pm.mu.Lock()
	pm.updateCmd = cmd
	pm.mu.Unlock()

	defer func() {
		pm.mu.Lock()
		if pm.updateCmd == cmd {
			pm.updateCmd = nil
		}
		pm.mu.Unlock()
	}()

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		pm.BroadcastLog(fmt.Sprintf("[SteamCMD] Error opening stdout: %v", err))
		return err
	}
	stderr, _ := cmd.StderrPipe()

	if err := cmd.Start(); err != nil {
		pm.BroadcastLog(fmt.Sprintf("[SteamCMD] Failed to start steamcmd: %v", err))
		return err
	}

	go pm.streamPipe(stdout, "[SteamCMD]")
	go pm.streamPipe(stderr, "[SteamCMD]")

	err = cmd.Wait()
	if err != nil {
		if errors.Is(ctx.Err(), context.Canceled) {
			pm.BroadcastLog("[SteamCMD] Update operation was canceled by user.")
		} else if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			pm.BroadcastLog("[SteamCMD] Update operation timed out.")
		} else {
			pm.BroadcastLog(fmt.Sprintf("[SteamCMD] Finished with status: %v", err))
		}
	} else {
		pm.BroadcastLog("[SteamCMD] Server files are verified and up to date!")
	}
	return err
}

var (
	globalSteamUpdateMu sync.Mutex
	lastSteamUpdateTime time.Time
)

func (pm *ProcessManager) runServer() {
	defer func() {
		pm.mu.Lock()
		if pm.status == StatusStarting {
			pm.status = StatusStopped
			pm.cmd = nil
			pm.updateCmd = nil
		}
		pm.mu.Unlock()
	}()

	cfg := pm.configMgr.Get()

	// Locate executable
	execName := "CoreKeeperServer"
	masterExecPath := filepath.Join(cfg.ServerDir, execName)

	hasBinary := fileExists(masterExecPath)
	needsUpdate := !hasBinary

	if hasBinary && cfg.AutoUpdate {
		globalSteamUpdateMu.Lock()
		if time.Since(lastSteamUpdateTime) > 10*time.Minute {
			needsUpdate = true
		}
		globalSteamUpdateMu.Unlock()
	}

	if needsUpdate {
		// Non-blocking attempt to acquire the SteamCMD mutex
		acquired := false
		for i := 0; i < 50; i++ {
			pm.mu.RLock()
			st := pm.status
			pm.mu.RUnlock()
			if st != StatusStarting && st != StatusUpdating {
				return // cancelled by user (e.g. Stop() called)
			}
			if globalSteamUpdateMu.TryLock() {
				acquired = true
				break
			}
			time.Sleep(100 * time.Millisecond)
		}

		if acquired {
			hasBinary = fileExists(masterExecPath)
			if !hasBinary || time.Since(lastSteamUpdateTime) > 10*time.Minute {
				timeout := 20 * time.Minute
				if !hasBinary {
					pm.BroadcastLog("[Manager] Server binary not found. Initiating initial download via SteamCMD (AppID: 1963720)...")
					pm.BroadcastLog("[Manager] Tip: Downloading game files (~600MB) may take several minutes depending on network bandwidth. If you are in China or behind a firewall, configure a proxy in Settings -> Network Proxy.")
				} else {
					pm.BroadcastLog("[Manager] Auto-update is enabled. Running pre-flight SteamCMD check & update...")
					timeout = 90 * time.Second
				}

				ctx, cancel := context.WithTimeout(context.Background(), timeout)
				pm.mu.Lock()
				pm.cancelUpdate = cancel
				pm.mu.Unlock()

				err := pm.runSteamCmdUpdate(ctx, cfg, "", "")
				cancel()
				pm.mu.Lock()
				pm.cancelUpdate = nil
				pm.mu.Unlock()

				if err != nil {
					if errors.Is(ctx.Err(), context.Canceled) {
						globalSteamUpdateMu.Unlock()
						return
					}
					if hasBinary {
						pm.BroadcastLog(fmt.Sprintf("[Manager] Warning: Pre-flight SteamCMD check failed or timed out (%v), but existing server binary is available. Proceeding to launch...", err))
					} else {
						pm.BroadcastLog(fmt.Sprintf("[Manager] Failed to download server files via SteamCMD: %v", err))
						pm.BroadcastLog("[Manager] Please check your network connection/proxy settings, or download game files manually.")
						globalSteamUpdateMu.Unlock()
						return
					}
				} else {
					lastSteamUpdateTime = time.Now()
					time.Sleep(2 * time.Second)
				}
			}
			globalSteamUpdateMu.Unlock()
		} else {
			if hasBinary {
				pm.BroadcastLog("[Manager] SteamCMD check is currently busy with another operation. Proceeding to launch existing server binary...")
			} else {
				pm.BroadcastLog("[Manager] Waiting for background SteamCMD download to complete...")
				globalSteamUpdateMu.Lock()
				globalSteamUpdateMu.Unlock()
			}
		}
	}

	// Re-verify status in case user clicked Stop while downloading
	pm.mu.RLock()
	st := pm.status
	pm.mu.RUnlock()
	if st != StatusStarting {
		return
	}

	if !fileExists(masterExecPath) {
		pm.BroadcastLog(fmt.Sprintf("[Manager] Server binary not found at %s even after SteamCMD check.", masterExecPath))
		pm.BroadcastLog("[Manager] Please check your network connection/proxy settings or trigger an update manually from the Overview page.")
		pm.mu.Lock()
		pm.status = StatusStopped
		pm.mu.Unlock()
		return
	}

	runDir := cfg.ServerDir
	pm.mu.RLock()
	preparer := pm.prepareSandbox
	pm.mu.RUnlock()

	if preparer != nil {
		if sb, err := preparer(); err == nil && sb != "" {
			runDir = sb
		} else if err != nil {
			pm.BroadcastLog(fmt.Sprintf("[Manager] Failed to prepare instance runtime sandbox: %v, falling back to base server directory", err))
		}
	}

	execPath := filepath.Join(runDir, execName)
	_ = os.Chmod(execPath, 0755)
	_ = os.MkdirAll(cfg.DataDir, 0755)

	// Ensure Steam library symlinks or directory
	pm.setupSteamLibs(runDir)
	pm.setupSteamLibs(cfg.ServerDir)

	// Build arguments
	args := []string{
		"-batchmode",
		"-datapath", cfg.DataDir,
		"-world", fmt.Sprintf("%d", cfg.WorldIndex),
		"-worldname", cfg.WorldName,
	}

	if cfg.WorldSeed != 0 {
		args = append(args, "-worldseed", fmt.Sprintf("%d", cfg.WorldSeed))
	}

	modeStr := "Normal"
	switch cfg.WorldMode {
	case 1:
		modeStr = "Hard"
	case 2:
		modeStr = "Creative"
	case 4:
		modeStr = "Casual"
	}
	args = append(args, "-worldmode", modeStr)

	args = append(args,
		"-maxplayers", fmt.Sprintf("%d", cfg.MaxPlayers),
		"-logfile", "/dev/stdout",
	)

	// Clean up any stale runtime identification files in runDir before starting
	if runDir != "" {
		_ = os.Remove(filepath.Join(runDir, "GameInfo.txt"))
		_ = os.Remove(filepath.Join(runDir, "GameID.txt"))
		_ = os.Remove(filepath.Join(runDir, "CoreKeeperServerLog.txt"))
	}

	// Ensure persistent GameID in SDR mode across restarts (only from instance's own persistent DataDir)
	if cfg.NetworkMode != "direct" && cfg.GameID == "" {
		if cachedID := pm.readGameIDFile(cfg.DataDir, ""); cachedID != "" {
			cfg.GameID = cachedID
			_ = pm.configMgr.Update(cfg)
		}
	}

	if cfg.NetworkMode == "direct" {
		port := cfg.Port
		if port <= 0 {
			port = 27015
		}
		args = append(args, "-port", fmt.Sprintf("%d", port), "-ip", cfg.IP)
		if cfg.Password != "" {
			args = append(args, "-password", cfg.Password)
		}
		pm.BroadcastLog(fmt.Sprintf("[Manager] Starting Core Keeper Server in DIRECT CONNECT mode on %s:%d (world slot: %d)", cfg.IP, port, cfg.WorldIndex))
	} else {
		// Pure Steam SDR Mode (Official default!)
		// Note: DO NOT pass -port here! Passing -port forces Core Keeper into Direct IP mode,
		// which skips Steam SDR relay registration and causes clients to fail finding the game.
		if cfg.GameID != "" {
			args = append(args, "-gameid", cfg.GameID)
			pm.BroadcastLog(fmt.Sprintf("[Manager] Starting Core Keeper Server in STEAM SDR mode with persistent GameID: %s (world slot: %d)", cfg.GameID, cfg.WorldIndex))
		} else {
			pm.BroadcastLog(fmt.Sprintf("[Manager] Starting Core Keeper Server in STEAM SDR mode (world slot: %d, GameID will be auto-generated by Steam SDR)", cfg.WorldIndex))
		}
	}

	// Unity games on headless Linux require Xvfb
	var cmd *exec.Cmd
	if os.Getenv("DISPLAY") != "" {
		cmd = exec.Command(execPath, args...)
	} else {
		// Use xvfb-run
		xvfbArgs := append([]string{"-a", "-s", "-screen 0 640x480x16", execPath}, args...)
		cmd = exec.Command("xvfb-run", xvfbArgs...)
	}

	cmd.Dir = runDir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	// Construct clean environment with correct HOME and LD_LIBRARY_PATH
	home := os.Getenv("HOME")
	if home == "" || home == "/root" {
		home = "/home/steam"
	}
	env := os.Environ()
	newEnv := make([]string, 0, len(env)+5)
	for _, e := range env {
		if strings.HasPrefix(e, "HOME=") || strings.HasPrefix(e, "USER=") || strings.HasPrefix(e, "LD_LIBRARY_PATH=") {
			continue
		}
		newEnv = append(newEnv, e)
	}
	newEnv = append(newEnv,
		fmt.Sprintf("HOME=%s", home),
		"USER=steam",
		fmt.Sprintf("LD_LIBRARY_PATH=%s:%s/linux64:%s:%s/linux64:%s", runDir, runDir, cfg.ServerDir, cfg.ServerDir, os.Getenv("LD_LIBRARY_PATH")),
	)
	if os.Getenv("DISPLAY") != "" {
		newEnv = append(newEnv, fmt.Sprintf("DISPLAY=%s", os.Getenv("DISPLAY")))
	} else {
		newEnv = append(newEnv, "DISPLAY=:99")
	}
	cmd.Env = newEnv

	if cfg.ProxyEnabled && cfg.ProxySDR {
		if p, err := GetEffectiveProxyURL(cfg); err == nil && p != "" {
			pm.BroadcastLog(fmt.Sprintf("[Manager] Server network proxy configured (SDR): %s", p))
			ApplyProxyEnv(cmd, p)
		}
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		pm.BroadcastLog(fmt.Sprintf("[Manager] Failed to attach stdout: %v", err))
		pm.mu.Lock()
		pm.status = StatusStopped
		pm.mu.Unlock()
		return
	}
	stderr, _ := cmd.StderrPipe()

	if err := cmd.Start(); err != nil {
		pm.BroadcastLog(fmt.Sprintf("[Manager] Failed to start server process: %v", err))
		pm.mu.Lock()
		pm.status = StatusStopped
		pm.mu.Unlock()
		return
	}

	pm.mu.Lock()
	pm.cmd = cmd
	pm.status = StatusRunning
	pm.startTime = time.Now()
	pm.mu.Unlock()

	pm.BroadcastLog(fmt.Sprintf("[Manager] Server process started (PID: %d)", cmd.Process.Pid))

	go pm.streamPipe(stdout, "[Server]")
	go pm.streamPipe(stderr, "[Server Err]")

	// Start GameID watcher goroutine for SDR mode
	go pm.watchGameID(cfg.DataDir, runDir)

	err = cmd.Wait()

	pm.mu.Lock()
	wasManual := pm.manualStop
	startTime := pm.startTime
	pm.status = StatusStopped
	pm.cmd = nil
	pm.onlineNotified = false
	pm.mu.Unlock()

	uptimeSec := int64(0)
	if !startTime.IsZero() {
		uptimeSec = int64(time.Since(startTime).Seconds())
	}
	uptimeStr := formatUptime(uptimeSec)

	if err != nil {
		pm.BroadcastLog(fmt.Sprintf("[Manager] Server process exited with code/error: %v", err))
		if !wasManual {
			exitCode := "unknown"
			if exitErr, ok := err.(*exec.ExitError); ok {
				exitCode = strconv.Itoa(exitErr.ExitCode())
			}
			logs := pm.GetLogs()
			recentLogs := ""
			startIdx := len(logs) - 15
			if startIdx < 0 {
				startIdx = 0
			}
			if len(logs) > 0 {
				recentLogs = strings.Join(logs[startIdx:], "\n")
			}
			NotifyDiscordEvent(cfg, "server_crashed", map[string]string{
				"server_name": cfg.WorldName,
				"exit_code":   exitCode,
				"error_log":   recentLogs,
			})
		} else {
			NotifyDiscordEvent(cfg, "server_offline", map[string]string{
				"server_name": cfg.WorldName,
				"uptime":      uptimeStr,
			})
		}
	} else {
		pm.BroadcastLog("[Manager] Server process exited cleanly.")
		NotifyDiscordEvent(cfg, "server_offline", map[string]string{
			"server_name": cfg.WorldName,
			"uptime":      uptimeStr,
		})
	}
}

func (pm *ProcessManager) notifyServerOnline(gameID string) {
	pm.mu.Lock()
	if pm.onlineNotified {
		pm.mu.Unlock()
		return
	}
	pm.onlineNotified = true
	pm.mu.Unlock()

	cfg := pm.configMgr.Get()
	if gameID == "" {
		gameID = pm.detectedGameID
	}
	if gameID == "" {
		gameID = cfg.GameID
	}
	if gameID == "" && cfg.NetworkMode == "direct" {
		gameID = fmt.Sprintf("%s:%d", cfg.IP, cfg.Port)
	}

	modeName := "Steam SDR"
	if cfg.NetworkMode == "direct" {
		modeName = fmt.Sprintf("Direct IP (%s:%d)", cfg.IP, cfg.Port)
	}

	vars := map[string]string{
		"server_name":  cfg.WorldName,
		"game_id":      gameID,
		"network_mode": modeName,
		"world_name":   cfg.WorldName,
		"world_index":  strconv.Itoa(cfg.WorldIndex),
		"max_players":  strconv.Itoa(cfg.MaxPlayers),
	}
	NotifyDiscordEvent(cfg, "server_online", vars)
}

func formatUptime(seconds int64) string {
	if seconds < 0 {
		seconds = 0
	}
	hours := seconds / 3600
	minutes := (seconds % 3600) / 60
	secs := seconds % 60
	if hours > 0 {
		return fmt.Sprintf("%dh %dm %ds", hours, minutes, secs)
	}
	if minutes > 0 {
		return fmt.Sprintf("%dm %ds", minutes, secs)
	}
	return fmt.Sprintf("%ds", secs)
}

func (pm *ProcessManager) streamPipe(r io.Reader, prefix string) {
	scanner := bufio.NewScanner(r)
	scanner.Split(scanLinesOrCR)
	for scanner.Scan() {
		text := strings.TrimSpace(scanner.Text())
		if text == "" {
			continue
		}
		pm.BroadcastLog(fmt.Sprintf("%s %s", prefix, text))

		// Check player connect / disconnect
		if matches := rePlayerConnect.FindStringSubmatch(text); len(matches) > 1 {
			pName := strings.TrimSpace(matches[1])
			if pName != "" && !strings.Contains(strings.ToLower(pName), "connected") {
				go func(name string) {
					c := pm.configMgr.Get()
					NotifyDiscordEvent(c, "player_join", map[string]string{
						"player_name": name,
						"server_name": c.WorldName,
					})
				}(pName)
			}
		} else if matches := rePlayerDisconnect.FindStringSubmatch(text); len(matches) > 1 {
			pName := strings.TrimSpace(matches[1])
			if pName != "" && !strings.Contains(strings.ToLower(pName), "disconnected") {
				go func(name string) {
					c := pm.configMgr.Get()
					NotifyDiscordEvent(c, "player_leave", map[string]string{
						"player_name": name,
						"server_name": c.WorldName,
					})
				}(pName)
			}
		}

		// Check if log contains Game ID output
		if strings.Contains(text, "Started session with info:") {
			parts := strings.Split(text, "Started session with info:")
			if len(parts) > 1 {
				info := strings.TrimSpace(parts[1])
				gid := info
				if strings.Contains(info, ";") {
					tokens := strings.Split(info, ";")
					// Format: <ip>;<port>;<gameId>;<password>
					if len(tokens) >= 3 && len(tokens[2]) >= 5 {
						gid = strings.TrimSpace(tokens[2])
					}
				}
				if len(gid) >= 5 && len(gid) <= 40 {
					pm.recordGameID(gid)
				}
			}
		} else if strings.Contains(text, "Steam GameID:") || strings.Contains(text, "Game ID:") || strings.Contains(text, "GameID:") {
			var rawID string
			if strings.Contains(text, "Steam GameID:") {
				rawID = strings.Split(text, "Steam GameID:")[1]
			} else if strings.Contains(text, "Game ID:") {
				rawID = strings.Split(text, "Game ID:")[1]
			} else {
				rawID = strings.Split(text, "GameID:")[1]
			}
			gid := strings.TrimSpace(rawID)
			if len(gid) >= 5 && len(gid) <= 40 {
				pm.recordGameID(gid)
			}
		}
	}
}

func (pm *ProcessManager) recordGameID(gid string) {
	pm.mu.Lock()
	pm.detectedGameID = gid
	pm.mu.Unlock()

	cfg := pm.configMgr.Get()
	if cfg.GameID != gid {
		cfg.GameID = gid
		_ = pm.configMgr.Update(cfg)
	}
	if cfg.DataDir != "" {
		_ = os.WriteFile(filepath.Join(cfg.DataDir, "GameID.txt"), []byte(gid+"\n"), 0644)
	}
	pm.notifyServerOnline(gid)
}

// scanLinesOrCR splits input by either newline (\n) or carriage return (\r)
// so SteamCMD interactive download progress lines are caught immediately.
func scanLinesOrCR(data []byte, atEOF bool) (advance int, token []byte, err error) {
	if atEOF && len(data) == 0 {
		return 0, nil, nil
	}
	for i := 0; i < len(data); i++ {
		if data[i] == '\n' {
			return i + 1, data[0:i], nil
		}
		if data[i] == '\r' {
			if i+1 < len(data) && data[i+1] == '\n' {
				return i + 2, data[0:i], nil
			}
			return i + 1, data[0:i], nil
		}
	}
	if atEOF {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func findSteamCmd() string {
	if _, err := exec.LookPath("steamcmd"); err == nil {
		return "steamcmd"
	}
	commonPaths := []string{
		"/usr/games/steamcmd",
		"/usr/bin/steamcmd",
		"/home/steam/.local/share/Steam/steamcmd/steamcmd.sh",
		"/home/steam/steamcmd/steamcmd.sh",
		"/steamcmd/steamcmd.sh",
	}
	for _, p := range commonPaths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "steamcmd"
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func (pm *ProcessManager) watchGameID(dataDir, runDir string) {
	for i := 0; i < 60; i++ {
		pm.mu.RLock()
		st := pm.status
		pm.mu.RUnlock()
		if st != StatusRunning {
			return
		}

		gid := pm.readGameIDFile(dataDir, runDir)
		if gid != "" {
			pm.recordGameID(gid)
			cfg := pm.configMgr.Get()
			if cfg.NetworkMode == "direct" {
				pm.BroadcastLog(fmt.Sprintf("[Manager] >> Detected Game ID: %s (Direct Mode) <<", gid))
			} else {
				pm.BroadcastLog(fmt.Sprintf("[Manager] >> Detected SDR Game ID: %s <<", gid))
			}
			return
		}

		if i == 8 {
			cfg := pm.configMgr.Get()
			pm.notifyServerOnline(cfg.GameID)
		}

		time.Sleep(2 * time.Second)
	}
}

func (pm *ProcessManager) readGameIDFile(dataDir, runDir string) string {
	paths := make([]string, 0, 4)
	if runDir != "" {
		paths = append(paths, filepath.Join(runDir, "GameInfo.txt"), filepath.Join(runDir, "GameID.txt"))
	}
	if dataDir != "" {
		paths = append(paths, filepath.Join(dataDir, "GameID.txt"), filepath.Join(dataDir, "GameInfo.txt"))
	}

	for _, p := range paths {
		// Strictly ignore symlinks so sandbox cannot link to base game or another instance
		if info, err := os.Lstat(p); err == nil && info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		if content, err := os.ReadFile(p); err == nil {
			str := strings.TrimSpace(string(content))
			if str == "" {
				continue
			}
			lines := strings.Split(str, "\n")
			for _, l := range lines {
				trimmed := strings.TrimSpace(l)
				if strings.HasPrefix(trimmed, "Steam GameID:") {
					gid := strings.TrimSpace(strings.TrimPrefix(trimmed, "Steam GameID:"))
					if len(gid) >= 5 && len(gid) <= 40 {
						return gid
					}
				}
				if strings.HasPrefix(trimmed, "Game ID:") {
					gid := strings.TrimSpace(strings.TrimPrefix(trimmed, "Game ID:"))
					if len(gid) >= 5 && len(gid) <= 40 {
						return gid
					}
				}
				if strings.HasPrefix(trimmed, "GameID:") {
					gid := strings.TrimSpace(strings.TrimPrefix(trimmed, "GameID:"))
					if len(gid) >= 5 && len(gid) <= 40 {
						return gid
					}
				}
			}
			// In GameID.txt, the first line is the raw Game ID if it's alphanumeric and 5-40 chars
			if len(lines) > 0 {
				firstLine := strings.TrimSpace(lines[0])
				if len(firstLine) >= 5 && len(firstLine) <= 40 && !strings.Contains(firstLine, " ") && !strings.Contains(firstLine, ";") && !strings.Contains(firstLine, ":") {
					return firstLine
				}
			}
		}
	}
	return ""
}

func (pm *ProcessManager) setupSteamLibs(serverDir string) {
	// Core Keeper Dedicated Server AppID file (1963720 is the dedicated server tool with anonymous login rights)
	_ = os.WriteFile(filepath.Join(serverDir, "steam_appid.txt"), []byte("1963720\n"), 0644)

	// Create symlinks for Steamworks SDK linux64 steamclient.so if needed
	home := os.Getenv("HOME")
	if home == "" || home == "/root" {
		home = "/home/steam"
	}
	sdk64Path := filepath.Join(home, ".steam", "sdk64")
	_ = os.MkdirAll(sdk64Path, 0755)

	srcLib := filepath.Join(serverDir, "linux64", "steamclient.so")
	dstLib := filepath.Join(sdk64Path, "steamclient.so")

	if _, err := os.Stat(srcLib); err == nil {
		if _, err := os.Stat(dstLib); os.IsNotExist(err) {
			_ = os.Symlink(srcLib, dstLib)
		}
	}
}
