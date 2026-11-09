package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type ServerInstance struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Port        int       `json:"port"`
	NetworkMode string    `json:"networkMode"` // "sdr" or "direct"
	Password    string    `json:"password"`
	WorldIndex  int       `json:"worldIndex"`
	WorldName   string    `json:"worldName"`
	WorldSeed   int64     `json:"worldSeed"`
	WorldMode   int       `json:"worldMode"`
	MaxPlayers  int       `json:"maxPlayers"`
	AutoStart   bool      `json:"autoStart"`
	EnabledMods []string  `json:"enabledMods"`
	CreatedAt   time.Time `json:"createdAt"`
}

type InstanceSummary struct {
	ServerInstance
	Status           ServerStatus `json:"status"`
	PID              int          `json:"pid"`
	UptimeSec        int64        `json:"uptimeSec"`
	GameID           string       `json:"gameId"`
	EnabledModsCount int          `json:"enabledModsCount"`
	TotalModsCount   int          `json:"totalModsCount"`
	IsActive         bool         `json:"isActive"`
	RestartRequired  bool         `json:"restartRequired"`
}

type InstancesRegistry struct {
	ActiveInstanceID string           `json:"activeInstanceId"`
	Instances        []ServerInstance `json:"instances"`
}

type InstanceRuntime struct {
	Instance  ServerInstance
	ConfigMgr *ConfigManager
	ProcMgr   *ProcessManager
	AdminMgr  *AdminManager
	WorldMgr  *WorldManager
	DataDir   string
}

func (r *InstanceRuntime) GetStatus() StatusResponse {
	st := r.ProcMgr.GetStatus()
	st.InstanceID = r.Instance.ID
	st.InstanceName = r.Instance.Name
	st.WorldName = r.Instance.WorldName
	st.ServerName = r.Instance.Name
	return st
}

type InstanceManager struct {
	baseDataDir     string
	baseServerDir   string
	webPort         int
	instancesDir    string
	sharedModsDir   string
	runSandboxesDir string

	mu              sync.RWMutex
	activeID        string
	instances       map[string]*InstanceRuntime
	modMgr          *ModManager
	globalConfigMgr *ConfigManager
}

func NewInstanceManager(baseDataDir, baseServerDir string, webPort int) *InstanceManager {
	instancesDir := filepath.Join(baseDataDir, "instances")
	sharedModsDir := filepath.Join(baseDataDir, "shared_mods")
	runSandboxesDir := "/server/instances_run"
	if _, err := os.Stat("/server"); os.IsNotExist(err) {
		runSandboxesDir = filepath.Join(baseDataDir, "instances_run")
	}

	_ = os.MkdirAll(instancesDir, 0755)
	_ = os.MkdirAll(sharedModsDir, 0755)
	_ = os.MkdirAll(runSandboxesDir, 0755)

	// Clean up any stale runtime identification files from base game server directory
	_ = os.Remove(filepath.Join(baseServerDir, "GameID.txt"))
	_ = os.Remove(filepath.Join(baseServerDir, "GameInfo.txt"))
	_ = os.Remove(filepath.Join(baseServerDir, "CoreKeeperServerLog.txt"))

	im := &InstanceManager{
		baseDataDir:     baseDataDir,
		baseServerDir:   baseServerDir,
		webPort:         webPort,
		instancesDir:    instancesDir,
		sharedModsDir:   sharedModsDir,
		runSandboxesDir: runSandboxesDir,
		instances:       make(map[string]*InstanceRuntime),
	}

	// Initialize shared mod manager
	im.modMgr = NewModManager(baseServerDir, baseDataDir, nil)
	im.modMgr.SetSharedModsDir(sharedModsDir)

	// Perform migration if needed
	im.ensureRegistryAndMigrate()

	return im
}

func (im *InstanceManager) SetGlobalConfigManager(cm *ConfigManager) {
	im.mu.Lock()
	defer im.mu.Unlock()
	im.globalConfigMgr = cm
	if im.modMgr != nil {
		im.modMgr.SetGlobalConfigManager(cm)
	}
}

func (im *InstanceManager) GetAllRuntimes() []*InstanceRuntime {
	im.mu.RLock()
	defer im.mu.RUnlock()
	res := make([]*InstanceRuntime, 0, len(im.instances))
	for _, r := range im.instances {
		res = append(res, r)
	}
	return res
}

func (im *InstanceManager) registryFilePath() string {
	return filepath.Join(im.baseDataDir, "instances.json")
}

func (im *InstanceManager) ensureRegistryAndMigrate() {
	regPath := im.registryFilePath()
	var reg InstancesRegistry

	data, err := os.ReadFile(regPath)
	if err == nil && len(data) > 0 {
		_ = json.Unmarshal(data, &reg)
	}

	// If registry is empty or missing on fresh run, initialize with empty instances
	if _, err := os.Stat(regPath); os.IsNotExist(err) {
		log.Println("[InstanceManager] No instances.json found. Initializing fresh empty instances registry...")
		reg.ActiveInstanceID = ""
		reg.Instances = []ServerInstance{}
		_ = im.saveRegistryLocked(reg)
	}

	// Clean up any empty strings and deduplicate EnabledMods
	registryDirty := false
	for i := range reg.Instances {
		inst := &reg.Instances[i]
		var cleanMods []string
		for _, m := range inst.EnabledMods {
			m = strings.TrimSpace(m)
			if m != "" && !contains(cleanMods, m) {
				cleanMods = append(cleanMods, m)
			}
		}
		if len(cleanMods) != len(inst.EnabledMods) {
			inst.EnabledMods = cleanMods
			registryDirty = true
		}
	}
	if registryDirty {
		_ = im.saveRegistryLocked(reg)
	}

	im.activeID = reg.ActiveInstanceID
	if im.activeID == "" && len(reg.Instances) > 0 {
		im.activeID = reg.Instances[0].ID
	}

	// Initialize runtime for each instance
	for _, inst := range reg.Instances {
		im.initInstanceRuntimeLocked(inst)
	}

	// Ensure legacy worlds and saves are synced into default instance if default instance exists
	if _, exists := im.instances["default"]; exists {
		im.syncLegacyWorldsToDefault()
	}

	// Sanity check: Ensure instances never share duplicate GameIDs
	seenGameIDs := make(map[string]string)
	for _, r := range im.instances {
		cfg := r.ConfigMgr.Get()
		if cfg.GameID != "" {
			if firstInstID, exists := seenGameIDs[cfg.GameID]; exists {
				log.Printf("[InstanceManager] Duplicate GameID '%s' detected between instance '%s' and '%s'. Resetting GameID for '%s'",
					cfg.GameID, firstInstID, r.Instance.ID, r.Instance.ID)
				cfg.GameID = ""
				_ = r.ConfigMgr.Update(cfg)
				_ = os.Remove(filepath.Join(r.DataDir, "GameID.txt"))
				_ = os.Remove(filepath.Join(r.DataDir, "GameInfo.txt"))
			} else {
				seenGameIDs[cfg.GameID] = r.Instance.ID
			}
		}
	}
}

func (im *InstanceManager) syncLegacyWorldsToDefault() {
	defaultDir := filepath.Join(im.instancesDir, "default")
	srcWorlds := filepath.Join(im.baseDataDir, "worlds")
	dstWorlds := filepath.Join(defaultDir, "worlds")
	if dirExists(srcWorlds) {
		_ = os.MkdirAll(dstWorlds, 0755)
		if entries, err := os.ReadDir(srcWorlds); err == nil {
			for _, entry := range entries {
				if entry.IsDir() {
					continue
				}
				sFile := filepath.Join(srcWorlds, entry.Name())
				dFile := filepath.Join(dstWorlds, entry.Name())
				sInfo, err1 := os.Stat(sFile)
				dInfo, err2 := os.Stat(dFile)
				if err1 == nil && (err2 != nil || sInfo.Size() > dInfo.Size()) {
					_ = copyFile(sFile, dFile)
				}
			}
		}
	}

	// Sync legacy backups
	srcBackups := filepath.Join(im.baseDataDir, "backups")
	dstBackups := filepath.Join(defaultDir, "backups")
	if dirExists(srcBackups) {
		_ = os.MkdirAll(dstBackups, 0755)
		if entries, err := os.ReadDir(srcBackups); err == nil {
			for _, entry := range entries {
				if entry.IsDir() {
					continue
				}
				sFile := filepath.Join(srcBackups, entry.Name())
				dFile := filepath.Join(dstBackups, entry.Name())
				if !fileExists(dFile) {
					_ = copyFile(sFile, dFile)
				}
			}
		}
	}
}

func (im *InstanceManager) migrateLegacyFiles() ServerInstance {
	defaultDir := filepath.Join(im.instancesDir, "default")
	_ = os.MkdirAll(defaultDir, 0755)

	// 1. Move/copy legacy files from baseDataDir into defaultDir
	legacyFiles := []string{
		"ServerConfig.json", "ServerConfig.json.pugbackup",
		"Admins.json", "Admins.json.pugbackup",
		"PlayerBans.json", "PlayerBans.json.pugbackup",
		"GameID.txt", "manager_config.json",
		"worlds.json",
	}

	for _, f := range legacyFiles {
		src := filepath.Join(im.baseDataDir, f)
		dst := filepath.Join(defaultDir, f)
		if fileExists(src) && !fileExists(dst) {
			_ = copyFile(src, dst)
		}
	}

	// Move worlds and backups
	im.syncLegacyWorldsToDefault()

	// 2. Migrate existing mods into shared_mods/
	enabledMods := make([]string, 0)
	modSources := []string{
		filepath.Join(im.baseServerDir, "CoreKeeperServer_Data", "StreamingAssets", "Mods"),
	}

	for _, mDir := range modSources {
		if entries, err := os.ReadDir(mDir); err == nil {
			for _, entry := range entries {
				if !entry.IsDir() {
					continue
				}
				name := entry.Name()
				if strings.HasPrefix(name, ".") {
					continue
				}
				cleanID := strings.TrimSuffix(name, ".disabled")
				cleanID = strings.TrimSpace(cleanID)
				if cleanID == "" {
					continue
				}
				srcPath := filepath.Join(mDir, name)
				if !isModDir(srcPath) {
					continue
				}
				dstPath := filepath.Join(im.sharedModsDir, cleanID)

				if !fileExists(dstPath) {
					_ = copyDir(srcPath, dstPath)
				}

				// If it wasn't disabled, mark as enabled for default instance
				if !strings.HasSuffix(name, ".disabled") {
					if !contains(enabledMods, cleanID) {
						enabledMods = append(enabledMods, cleanID)
					}
				}
			}
		}
	}

	// Read existing manager_config if available
	netMode := getEnv("NETWORK_MODE", "sdr")
	port := getEnvInt("PORT", 27015)
	maxPlayers := getEnvInt("MAX_PLAYERS", 10)
	serverName := getEnv("WORLD_NAME", "Core Keeper Server")
	worldIndex := getEnvInt("WORLD_INDEX", 0)
	worldMode := getEnvInt("WORLD_MODE", 0)
	worldSeed := int64(getEnvInt("WORLD_SEED", 0))
	autoStart := getEnv("AUTO_START", "true") == "true"

	if data, err := os.ReadFile(filepath.Join(defaultDir, "manager_config.json")); err == nil {
		var cfg ServerConfig
		if err := json.Unmarshal(data, &cfg); err == nil {
			if cfg.NetworkMode != "" {
				netMode = cfg.NetworkMode
			}
			if cfg.Port != 0 {
				port = cfg.Port
			}
			if cfg.MaxPlayers != 0 {
				maxPlayers = cfg.MaxPlayers
			}
			if cfg.WorldName != "" {
				serverName = cfg.WorldName
			}
			worldIndex = cfg.WorldIndex
			worldMode = cfg.WorldMode
			worldSeed = cfg.WorldSeed
			autoStart = cfg.AutoStart
		}
	}

	return ServerInstance{
		ID:          "default",
		Name:        "默认服务器",
		Port:        port,
		NetworkMode: netMode,
		Password:    "",
		WorldIndex:  worldIndex,
		WorldName:   serverName,
		WorldSeed:   worldSeed,
		WorldMode:   worldMode,
		MaxPlayers:  maxPlayers,
		AutoStart:   autoStart,
		EnabledMods: enabledMods,
		CreatedAt:   time.Now(),
	}
}

func (im *InstanceManager) initInstanceRuntimeLocked(inst ServerInstance) *InstanceRuntime {
	instDataDir := filepath.Join(im.instancesDir, inst.ID)
	_ = os.MkdirAll(instDataDir, 0755)

	configMgr := NewConfigManager(instDataDir, im.baseServerDir, im.webPort)
	// Apply instance-specific parameters to config
	cfg := configMgr.Get()
	cfg.NetworkMode = inst.NetworkMode
	cfg.Port = inst.Port
	cfg.Password = inst.Password
	cfg.WorldIndex = inst.WorldIndex
	cfg.WorldName = inst.WorldName
	cfg.WorldSeed = inst.WorldSeed
	cfg.WorldMode = inst.WorldMode
	cfg.MaxPlayers = inst.MaxPlayers
	cfg.AutoStart = inst.AutoStart
	cfg.DataDir = instDataDir
	if !fileExists(filepath.Join(instDataDir, "manager_config.json")) {
		cfg.GameID = ""
	}
	if im.globalConfigMgr != nil {
		gCfg := im.globalConfigMgr.Get()
		if cfg.ModioApiKey == "" && gCfg.ModioApiKey != "" {
			cfg.ModioApiKey = gCfg.ModioApiKey
		}
	}

	_ = configMgr.Update(cfg)

	adminMgr := NewAdminManager(instDataDir)
	worldMgr := NewWorldManager(instDataDir)
	if inst.WorldName != "" {
		if meta, err := worldMgr.GetWorldMeta(inst.WorldIndex); err == nil {
			if meta.Name != inst.WorldName {
				_ = worldMgr.RenameWorld(inst.WorldIndex, inst.WorldName)
			}
		}
	}
	procMgr := NewProcessManager(configMgr)

	instID := inst.ID
	procMgr.SetSandboxPreparer(func() (string, error) {
		return im.PrepareInstanceSandbox(instID)
	})

	runtime := &InstanceRuntime{
		Instance:  inst,
		ConfigMgr: configMgr,
		ProcMgr:   procMgr,
		AdminMgr:  adminMgr,
		WorldMgr:  worldMgr,
		DataDir:   instDataDir,
	}

	im.instances[inst.ID] = runtime
	return runtime
}

func (im *InstanceManager) PrepareInstanceSandbox(instID string) (string, error) {
	im.mu.RLock()
	runtime, ok := im.instances[instID]
	im.mu.RUnlock()
	if !ok {
		return "", fmt.Errorf("instance %s not found", instID)
	}

	sandboxDir := filepath.Join(im.runSandboxesDir, instID)
	_ = os.RemoveAll(sandboxDir)
	if err := os.MkdirAll(sandboxDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create sandbox dir: %w", err)
	}

	// 1. Symlink top-level files and folders from baseServerDir
	entries, err := os.ReadDir(im.baseServerDir)
	if err != nil {
		return "", fmt.Errorf("failed to read game server dir: %w", err)
	}

	for _, entry := range entries {
		name := entry.Name()
		if name == "CoreKeeperServer_Data" || name == "instances_run" ||
			name == "GameID.txt" || name == "GameInfo.txt" ||
			name == "CoreKeeperServerLog.txt" ||
			strings.HasSuffix(name, ".log") || strings.HasSuffix(name, ".pid") {
			continue
		}
		src := filepath.Join(im.baseServerDir, name)
		dst := filepath.Join(sandboxDir, name)
		if name == "CoreKeeperServer" {
			// Copy the small 15KB executable binary so Linux readlink(/proc/self/exe) resolves to this instance's sandbox!
			if err := copyFile(src, dst); err != nil {
				return "", fmt.Errorf("failed to copy executable binary: %w", err)
			}
			_ = os.Chmod(dst, 0755)
		} else {
			_ = os.Symlink(src, dst)
		}
	}

	// 2. Prepare CoreKeeperServer_Data
	gameDataDir := filepath.Join(im.baseServerDir, "CoreKeeperServer_Data")
	sandboxDataDir := filepath.Join(sandboxDir, "CoreKeeperServer_Data")
	if err := os.MkdirAll(sandboxDataDir, 0755); err != nil {
		return "", err
	}

	if dataEntries, err := os.ReadDir(gameDataDir); err == nil {
		for _, entry := range dataEntries {
			name := entry.Name()
			if name == "StreamingAssets" {
				continue
			}
			src := filepath.Join(gameDataDir, name)
			dst := filepath.Join(sandboxDataDir, name)
			_ = os.Symlink(src, dst)
		}
	}

	// 3. Prepare StreamingAssets
	gameStreamingDir := filepath.Join(gameDataDir, "StreamingAssets")
	sandboxStreamingDir := filepath.Join(sandboxDataDir, "StreamingAssets")
	if err := os.MkdirAll(sandboxStreamingDir, 0755); err != nil {
		return "", err
	}

	if saEntries, err := os.ReadDir(gameStreamingDir); err == nil {
		for _, entry := range saEntries {
			name := entry.Name()
			if name == "Mods" {
				continue
			}
			src := filepath.Join(gameStreamingDir, name)
			dst := filepath.Join(sandboxStreamingDir, name)
			_ = os.Symlink(src, dst)
		}
	}

	// 4. Prepare StreamingAssets/Mods with ONLY enabled mods for this instance
	sandboxModsDir := filepath.Join(sandboxStreamingDir, "Mods")
	if err := os.MkdirAll(sandboxModsDir, 0755); err != nil {
		return "", err
	}

	enabledSet := make(map[string]bool)
	for _, modName := range runtime.Instance.EnabledMods {
		enabledSet[modName] = true
	}

	if sharedEntries, err := os.ReadDir(im.sharedModsDir); err == nil {
		for _, entry := range sharedEntries {
			if !entry.IsDir() {
				continue
			}
			modName := entry.Name()
			if enabledSet[modName] {
				src := filepath.Join(im.sharedModsDir, modName)
				if isModDir(src) {
					dst := filepath.Join(sandboxModsDir, modName)
					_ = os.Symlink(src, dst)
				}
			}
		}
	}

	return sandboxDir, nil
}

func (im *InstanceManager) saveRegistryLocked(reg InstancesRegistry) error {
	data, err := json.MarshalIndent(reg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(im.registryFilePath(), data, 0644)
}

func (im *InstanceManager) GetActiveInstanceID() string {
	im.mu.RLock()
	defer im.mu.RUnlock()
	return im.activeID
}

func (im *InstanceManager) SetActiveInstanceID(id string) error {
	im.mu.Lock()
	defer im.mu.Unlock()

	if _, ok := im.instances[id]; !ok {
		return fmt.Errorf("instance %s not found", id)
	}

	im.activeID = id
	return im.persistRegistryLocked()
}

func (im *InstanceManager) persistRegistryLocked() error {
	list := make([]ServerInstance, 0, len(im.instances))
	for _, r := range im.instances {
		list = append(list, r.Instance)
	}

	sort.Slice(list, func(i, j int) bool {
		return list[i].CreatedAt.Before(list[j].CreatedAt)
	})

	reg := InstancesRegistry{
		ActiveInstanceID: im.activeID,
		Instances:        list,
	}
	return im.saveRegistryLocked(reg)
}

func (im *InstanceManager) GetInstanceRuntime(id string) (*InstanceRuntime, error) {
	im.mu.RLock()
	defer im.mu.RUnlock()

	if id == "" {
		id = im.activeID
	}
	if runtime, ok := im.instances[id]; ok {
		return runtime, nil
	}
	return nil, fmt.Errorf("instance %s not found", id)
}

func (im *InstanceManager) ListInstances() []InstanceSummary {
	im.mu.RLock()
	defer im.mu.RUnlock()

	// Canonical list of all installed and valid mods
	availableMods, _ := im.modMgr.ListModsWithEnabled(nil)
	totalMods := len(availableMods)
	installedModMap := make(map[string]bool, totalMods)
	for _, m := range availableMods {
		installedModMap[m.ID] = true
	}

	result := make([]InstanceSummary, 0, len(im.instances))
	for id, r := range im.instances {
		st := r.ProcMgr.GetStatus()
		enabledCount := 0
		for _, mID := range r.Instance.EnabledMods {
			mID = strings.TrimSpace(mID)
			if mID != "" && installedModMap[mID] {
				enabledCount++
			}
		}

		summary := InstanceSummary{
			ServerInstance:   r.Instance,
			Status:           st.Status,
			PID:              st.PID,
			UptimeSec:        st.UptimeSec,
			GameID:           st.GameID,
			EnabledModsCount: enabledCount,
			TotalModsCount:   totalMods,
			IsActive:         id == im.activeID,
			RestartRequired:  st.RestartRequired,
		}
		result = append(result, summary)
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.Before(result[j].CreatedAt)
	})

	return result
}

func (im *InstanceManager) CreateInstance(inst ServerInstance) (ServerInstance, error) {
	im.mu.Lock()
	defer im.mu.Unlock()

	if inst.ID == "" {
		inst.ID = fmt.Sprintf("inst_%d", time.Now().Unix())
	}
	if inst.Name == "" {
		inst.Name = fmt.Sprintf("服务器实例 %d", len(im.instances)+1)
	}
	if inst.WorldName == "" {
		inst.WorldName = "默认世界"
	}
	if inst.Port == 0 {
		inst.Port = im.nextAvailablePortLocked()
	}
	if inst.NetworkMode == "" {
		inst.NetworkMode = "sdr"
	}
	if inst.MaxPlayers <= 0 {
		inst.MaxPlayers = 10
	}
	if inst.EnabledMods == nil {
		inst.EnabledMods = []string{} // default none enabled as requested!
	}
	inst.CreatedAt = time.Now()

	if _, exists := im.instances[inst.ID]; exists {
		return ServerInstance{}, fmt.Errorf("instance ID %s already exists", inst.ID)
	}

	// Check port collision across all instances
	for _, r := range im.instances {
		if r.Instance.Port == inst.Port {
			return ServerInstance{}, fmt.Errorf("port %d is already in use by instance '%s'", inst.Port, r.Instance.Name)
		}
	}

	runtime := im.initInstanceRuntimeLocked(inst)
	if im.activeID == "" {
		im.activeID = inst.ID
	}
	_ = im.persistRegistryLocked()

	// If AutoStart is true, launch
	if inst.AutoStart {
		go func() {
			_ = runtime.ProcMgr.Start()
		}()
	}

	return inst, nil
}

func (im *InstanceManager) nextAvailablePortLocked() int {
	maxPort := 27005
	for _, r := range im.instances {
		if r.Instance.Port > maxPort {
			maxPort = r.Instance.Port
		}
	}
	return maxPort + 10
}

func (im *InstanceManager) UpdateInstance(id string, update ServerInstance) error {
	im.mu.Lock()
	defer im.mu.Unlock()

	runtime, ok := im.instances[id]
	if !ok {
		return fmt.Errorf("instance %s not found", id)
	}

	if update.Name != "" {
		runtime.Instance.Name = update.Name
	}
	if update.NetworkMode != "" {
		runtime.Instance.NetworkMode = update.NetworkMode
	}
	if update.Port != 0 && update.Port != runtime.Instance.Port {
		for _, r := range im.instances {
			if r.Instance.ID != id && r.Instance.Port == update.Port {
				return fmt.Errorf("port %d is already in use by instance '%s'", update.Port, r.Instance.Name)
			}
		}
		runtime.Instance.Port = update.Port
	}
	runtime.Instance.Password = update.Password
	if update.MaxPlayers > 0 {
		runtime.Instance.MaxPlayers = update.MaxPlayers
	}
	runtime.Instance.AutoStart = update.AutoStart
	runtime.Instance.WorldIndex = update.WorldIndex
	if update.WorldName != "" {
		runtime.Instance.WorldName = update.WorldName
	}
	runtime.Instance.WorldMode = update.WorldMode
	runtime.Instance.WorldSeed = update.WorldSeed

	// Sync configMgr
	cfg := runtime.ConfigMgr.Get()
	cfg.NetworkMode = runtime.Instance.NetworkMode
	cfg.Port = runtime.Instance.Port
	cfg.Password = runtime.Instance.Password
	cfg.MaxPlayers = runtime.Instance.MaxPlayers
	cfg.AutoStart = runtime.Instance.AutoStart
	cfg.WorldIndex = runtime.Instance.WorldIndex
	cfg.WorldName = runtime.Instance.WorldName
	cfg.WorldMode = runtime.Instance.WorldMode
	cfg.WorldSeed = runtime.Instance.WorldSeed
	_ = runtime.ConfigMgr.Update(cfg)

	// If running, mark restart required
	st := runtime.ProcMgr.GetStatus()
	if st.Status == StatusRunning || st.Status == StatusStarting {
		runtime.ProcMgr.SetRestartRequired(true)
	}

	return im.persistRegistryLocked()
}

func (im *InstanceManager) DeleteInstance(id string) error {
	im.mu.Lock()
	defer im.mu.Unlock()

	runtime, ok := im.instances[id]
	if !ok {
		return fmt.Errorf("instance %s not found", id)
	}

	st := runtime.ProcMgr.GetStatus()
	if st.Status == StatusRunning || st.Status == StatusStarting {
		return fmt.Errorf("cannot delete a running instance; please stop it first")
	}

	// Remove from map
	delete(im.instances, id)

	// If active instance is deleted, pick first remaining instance or empty
	if len(im.instances) == 0 {
		im.activeID = ""
	} else if im.activeID == id {
		ordered := make([]ServerInstance, 0, len(im.instances))
		for _, r := range im.instances {
			ordered = append(ordered, r.Instance)
		}
		sort.Slice(ordered, func(i, j int) bool {
			return ordered[i].CreatedAt.Before(ordered[j].CreatedAt)
		})
		im.activeID = ordered[0].ID
	}

	_ = im.persistRegistryLocked()

	// Clean up instance data and runtime sandbox
	_ = os.RemoveAll(runtime.DataDir)
	_ = os.RemoveAll(filepath.Join(im.runSandboxesDir, id))

	return nil
}

func (im *InstanceManager) ToggleModForInstance(instID, modID string, enable bool) error {
	modID = strings.TrimSpace(modID)
	if modID == "" {
		return fmt.Errorf("mod ID cannot be empty")
	}

	im.mu.Lock()
	defer im.mu.Unlock()

	runtime, ok := im.instances[instID]
	if !ok {
		return fmt.Errorf("instance %s not found", instID)
	}

	currentMods := runtime.Instance.EnabledMods
	newMods := make([]string, 0, len(currentMods)+1)
	found := false

	for _, m := range currentMods {
		m = strings.TrimSpace(m)
		if m == "" {
			continue
		}
		if m == modID {
			found = true
			if enable {
				newMods = append(newMods, m)
			}
		} else {
			newMods = append(newMods, m)
		}
	}

	if enable && !found {
		newMods = append(newMods, modID)
	}

	runtime.Instance.EnabledMods = newMods
	runtime.ProcMgr.SetRestartRequired(true)

	return im.persistRegistryLocked()
}

func (im *InstanceManager) AddModToInstance(instID, modID string) {
	modID = strings.TrimSpace(modID)
	if modID == "" {
		return
	}

	im.mu.Lock()
	defer im.mu.Unlock()

	runtime, ok := im.instances[instID]
	if !ok {
		return
	}

	if !contains(runtime.Instance.EnabledMods, modID) {
		runtime.Instance.EnabledMods = append(runtime.Instance.EnabledMods, modID)
		runtime.ProcMgr.SetRestartRequired(true)
		_ = im.persistRegistryLocked()
	}
}

func (im *InstanceManager) StartAllAutoStart() {
	im.mu.RLock()
	defer im.mu.RUnlock()

	for id, r := range im.instances {
		if r.Instance.AutoStart {
			log.Printf("[InstanceManager] Auto-starting instance '%s' (ID: %s)...", r.Instance.Name, id)
			go func(instRuntime *InstanceRuntime) {
				_ = instRuntime.ProcMgr.Start()
			}(r)
		}
	}
}

func (im *InstanceManager) StopAll() {
	im.mu.RLock()
	defer im.mu.RUnlock()

	var wg sync.WaitGroup
	for id, r := range im.instances {
		wg.Add(1)
		go func(instID string, instRuntime *InstanceRuntime) {
			defer wg.Done()
			log.Printf("[InstanceManager] Stopping instance '%s' (ID: %s)...", instRuntime.Instance.Name, instID)
			_ = instRuntime.ProcMgr.Stop()
		}(id, r)
	}
	wg.Wait()
}

func contains(slice []string, val string) bool {
	for _, s := range slice {
		if s == val {
			return true
		}
	}
	return false
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
