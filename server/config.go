package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// ServerConfig represents the Core Keeper server configuration
type ServerConfig struct {
	NetworkMode  string `json:"networkMode"`  // "sdr" or "direct"
	Port         int    `json:"port"`         // Direct Connect port (default: 27015)
	IP           string `json:"ip"`           // Direct Connect bind IP (default: "0.0.0.0")
	Password     string `json:"password"`     // Server password (for direct connect)
	WorldIndex   int    `json:"worldIndex"`   // World slot index 0-29
	WorldName    string `json:"worldName"`    // Name of active world
	WorldSeed    int64  `json:"worldSeed"`    // World seed (0 for random)
	WorldMode    int    `json:"worldMode"`    // 0: Normal, 1: Hard, 2: Creative, 4: Casual
	MaxPlayers   int    `json:"maxPlayers"`   // Max players (1-100)
	GameID       string `json:"gameId"`       // Custom Game ID (optional for SDR)
	AutoStart    bool   `json:"autoStart"`    // Auto start server on boot
	AutoUpdate   bool   `json:"autoUpdate"`   // Auto update server via steamcmd on boot
	ServerDir    string `json:"serverDir"`    // Path to game server directory
	DataDir      string `json:"dataDir"`      // Path to server save/data directory
	WebPort       int    `json:"webPort"`       // Web manager port (default 8080)
	ProxyEnabled  bool   `json:"proxyEnabled"`  // Master switch
	ProxySDR      bool   `json:"proxySDR"`      // Enable proxy for Core Keeper server SDR
	ProxySteamCmd bool   `json:"proxySteamCmd"` // Enable proxy for SteamCMD server updates
	ProxyMods     bool   `json:"proxyMods"`     // Enable proxy for MOD downloads
	ProxyType     string `json:"proxyType"`     // "http", "socks5", "clash"
	ProxyAddress string `json:"proxyAddress"` // HTTP/SOCKS5 address (e.g. "http://127.0.0.1:7890" or "socks5://127.0.0.1:7890")
	ClashApiUrl  string `json:"clashApiUrl"`  // Clash API URL (e.g. "http://127.0.0.1:9090")
	ClashSecret  string `json:"clashSecret"`  // Clash API Bearer secret
	ClashNode    string `json:"clashNode"`    // Selected Clash proxy node
	ClashGroup   string `json:"clashGroup"`   // Selected Clash proxy group
	ModioApiKey  string `json:"modioApiKey"`  // Mod.io API Key (shared across instances)
}

// OfficialServerConfig represents the format in ServerConfig.json used by the game engine
type OfficialServerConfig struct {
	GameID           string `json:"gameId"`
	World            int    `json:"world"`
	WorldName        string `json:"worldName"`
	WorldSeed        int64  `json:"worldSeed"`
	MaxNumberPlayers int    `json:"maxNumberPlayers"`
	WorldMode        int    `json:"worldMode"`
}

type ConfigManager struct {
	config     ServerConfig
	configPath string
	mu         sync.RWMutex
}

func NewConfigManager(dataPath, serverPath string, webPort int) *ConfigManager {
	cfg := ServerConfig{
		NetworkMode: getEnv("NETWORK_MODE", "sdr"), // Default SDR as requested
		Port:        getEnvInt("PORT", 27015),
		IP:          getEnv("BIND_IP", "0.0.0.0"),
		Password:    getEnv("SERVER_PASSWORD", ""),
		WorldIndex:   getEnvInt("WORLD_INDEX", 0),
		WorldName:    getEnv("WORLD_NAME", "libzonda's Dedicated Server"),
		WorldSeed:    getEnvInt64("WORLD_SEED", 0),
		WorldMode:    getEnvInt("WORLD_MODE", 0),
		MaxPlayers:   getEnvInt("MAX_PLAYERS", 10),
		GameID:       getEnv("GAME_ID", ""),
		AutoStart:    getEnvBool("AUTO_START", true),
		AutoUpdate:   getEnvBool("AUTO_UPDATE", true),
		ServerDir:     serverPath,
		DataDir:       dataPath,
		WebPort:       webPort,
		ProxyEnabled:  getEnvBool("PROXY_ENABLED", false),
		ProxySDR:      getEnvBool("PROXY_SDR", true),
		ProxySteamCmd: getEnvBool("PROXY_STEAMCMD", true),
		ProxyMods:     getEnvBool("PROXY_MODS", true),
		ProxyType:     getEnv("PROXY_TYPE", "http"),
		ProxyAddress:  getEnv("PROXY_ADDRESS", ""),
		ClashApiUrl:   getEnv("CLASH_API_URL", "http://127.0.0.1:9090"),
		ClashSecret:   getEnv("CLASH_SECRET", ""),
		ClashNode:     getEnv("CLASH_NODE", ""),
		ClashGroup:    getEnv("CLASH_GROUP", ""),
		ModioApiKey:   getEnv("MODIO_API_KEY", ""),
	}

	cm := &ConfigManager{
		config:     cfg,
		configPath: filepath.Join(dataPath, "manager_config.json"),
	}

	// Try loading persistent manager config if it exists
	cm.load()
	// Persist to ensure all defaults and newly introduced fields are on disk
	_ = cm.saveUnlocked()
	// Sync with official ServerConfig.json
	cm.syncOfficialConfig()

	return cm
}

func (cm *ConfigManager) Get() ServerConfig {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.config
}

func (cm *ConfigManager) Update(newCfg ServerConfig) error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	cm.config.NetworkMode = newCfg.NetworkMode
	cm.config.Port = newCfg.Port
	cm.config.IP = newCfg.IP
	cm.config.Password = newCfg.Password
	cm.config.WorldIndex = newCfg.WorldIndex
	cm.config.WorldName = newCfg.WorldName
	cm.config.WorldSeed = newCfg.WorldSeed
	cm.config.WorldMode = newCfg.WorldMode
	cm.config.MaxPlayers = newCfg.MaxPlayers
	cm.config.GameID = newCfg.GameID
	cm.config.AutoStart = newCfg.AutoStart
	cm.config.AutoUpdate = newCfg.AutoUpdate
	cm.config.ProxyEnabled = newCfg.ProxyEnabled
	cm.config.ProxySDR = newCfg.ProxySDR
	cm.config.ProxySteamCmd = newCfg.ProxySteamCmd
	cm.config.ProxyMods = newCfg.ProxyMods
	cm.config.ProxyType = newCfg.ProxyType
	cm.config.ProxyAddress = newCfg.ProxyAddress
	cm.config.ClashApiUrl = newCfg.ClashApiUrl
	cm.config.ClashSecret = newCfg.ClashSecret
	cm.config.ClashNode = newCfg.ClashNode
	cm.config.ClashGroup = newCfg.ClashGroup
	cm.config.ModioApiKey = newCfg.ModioApiKey

	if err := cm.saveUnlocked(); err != nil {
		return err
	}

	return cm.syncOfficialConfigUnlocked()
}

func (cm *ConfigManager) UpdateProxy(enabled, sdr, steamcmd, mods bool, pType, addr, clashUrl, clashSecret, clashNode, clashGroup string) error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	cm.config.ProxyEnabled = enabled
	cm.config.ProxySDR = sdr
	cm.config.ProxySteamCmd = steamcmd
	cm.config.ProxyMods = mods
	if pType != "" {
		cm.config.ProxyType = pType
	}
	cm.config.ProxyAddress = addr
	if clashUrl != "" {
		cm.config.ClashApiUrl = clashUrl
	}
	cm.config.ClashSecret = clashSecret
	if clashNode != "" {
		cm.config.ClashNode = clashNode
	}
	if clashGroup != "" {
		cm.config.ClashGroup = clashGroup
	}

	return cm.saveUnlocked()
}

func (cm *ConfigManager) SetWorldIndex(index int) error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	cm.config.WorldIndex = index
	if err := cm.saveUnlocked(); err != nil {
		return err
	}
	return cm.syncOfficialConfigUnlocked()
}

func (cm *ConfigManager) SetModioApiKey(key string) error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	cm.config.ModioApiKey = key
	return cm.saveUnlocked()
}

func (cm *ConfigManager) load() {
	data, err := os.ReadFile(cm.configPath)
	if err != nil {
		return
	}
	var loaded ServerConfig
	if err := json.Unmarshal(data, &loaded); err == nil {
		cm.config.NetworkMode = loaded.NetworkMode
		cm.config.Port = loaded.Port
		cm.config.IP = loaded.IP
		cm.config.Password = loaded.Password
		cm.config.WorldIndex = loaded.WorldIndex
		cm.config.WorldName = loaded.WorldName
		cm.config.WorldSeed = loaded.WorldSeed
		cm.config.WorldMode = loaded.WorldMode
		cm.config.MaxPlayers = loaded.MaxPlayers
		cm.config.GameID = loaded.GameID
		cm.config.AutoStart = loaded.AutoStart
		cm.config.AutoUpdate = loaded.AutoUpdate
		cm.config.ProxyEnabled = loaded.ProxyEnabled

		var rawMap map[string]interface{}
		_ = json.Unmarshal(data, &rawMap)
		if _, ok := rawMap["proxySDR"]; ok {
			cm.config.ProxySDR = loaded.ProxySDR
		} else {
			cm.config.ProxySDR = true
		}
		if _, ok := rawMap["proxySteamCmd"]; ok {
			cm.config.ProxySteamCmd = loaded.ProxySteamCmd
		} else {
			cm.config.ProxySteamCmd = true
		}
		if _, ok := rawMap["proxyMods"]; ok {
			cm.config.ProxyMods = loaded.ProxyMods
		} else {
			cm.config.ProxyMods = true
		}

		if loaded.ProxyType != "" {
			cm.config.ProxyType = loaded.ProxyType
		}
		cm.config.ProxyAddress = loaded.ProxyAddress
		if loaded.ClashApiUrl != "" {
			cm.config.ClashApiUrl = loaded.ClashApiUrl
		}
		cm.config.ClashSecret = loaded.ClashSecret
		cm.config.ClashNode = loaded.ClashNode
		cm.config.ClashGroup = loaded.ClashGroup
		cm.config.ModioApiKey = loaded.ModioApiKey
	}
}

func (cm *ConfigManager) saveUnlocked() error {
	_ = os.MkdirAll(filepath.Dir(cm.configPath), 0755)
	data, err := json.MarshalIndent(cm.config, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(cm.configPath, data, 0644)
}

func (cm *ConfigManager) syncOfficialConfig() error {
	cm.mu.Lock()
	defer cm.mu.Unlock()
	return cm.syncOfficialConfigUnlocked()
}

func (cm *ConfigManager) syncOfficialConfigUnlocked() error {
	officialPath := filepath.Join(cm.config.DataDir, "ServerConfig.json")
	_ = os.MkdirAll(filepath.Dir(officialPath), 0755)

	official := OfficialServerConfig{
		GameID:           cm.config.GameID,
		World:            cm.config.WorldIndex,
		WorldName:        cm.config.WorldName,
		WorldSeed:        cm.config.WorldSeed,
		MaxNumberPlayers: cm.config.MaxPlayers,
		WorldMode:        cm.config.WorldMode,
	}

	data, err := json.MarshalIndent(official, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(officialPath, data, 0644)
}

