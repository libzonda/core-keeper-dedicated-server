package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

type ModInfo struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Version     string    `json:"version,omitempty"`
	Author      string    `json:"author,omitempty"`
	Description string    `json:"description,omitempty"`
	Enabled     bool      `json:"enabled"`
	SizeBytes   int64     `json:"sizeBytes"`
	ModifiedAt  time.Time `json:"modifiedAt"`
	IsWorkshop  bool      `json:"isWorkshop"`
	WorkshopID  string    `json:"workshopId,omitempty"`
	Source      string    `json:"source"`
	SourceID    string    `json:"sourceId,omitempty"`
	SourceURL   string    `json:"sourceUrl,omitempty"`
	CanUpdate   bool      `json:"canUpdate"`
}

type ModMeta struct {
	Source      string    `json:"source"`              // "workshop" | "modio" | "url" | "upload"
	SourceID    string    `json:"sourceId,omitempty"`
	SourceURL   string    `json:"sourceUrl,omitempty"`
	InstalledAt time.Time `json:"installedAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

type ModManifest struct {
	Name        string `json:"name"`
	DisplayName string `json:"displayName,omitempty"`
	Version     string `json:"version,omitempty"`
	Author      string `json:"author,omitempty"`
	Description string `json:"description,omitempty"`
}

type ModManager struct {
	serverDir       string
	dataDir         string
	configMgr       *ConfigManager
	globalConfigMgr *ConfigManager
	sharedModsDir   string
}

func NewModManager(serverDir, dataDir string, cfgMgr *ConfigManager) *ModManager {
	return &ModManager{
		serverDir: serverDir,
		dataDir:   dataDir,
		configMgr: cfgMgr,
	}
}

func (mm *ModManager) SetSharedModsDir(dir string) {
	mm.sharedModsDir = dir
}

func (mm *ModManager) SetConfigManager(cm *ConfigManager) {
	mm.configMgr = cm
}

func (mm *ModManager) SetGlobalConfigManager(cm *ConfigManager) {
	mm.globalConfigMgr = cm
}

func (mm *ModManager) GetModioApiKey() string {
	if mm.configMgr != nil {
		k := strings.TrimSpace(mm.configMgr.Get().ModioApiKey)
		if k != "" {
			return k
		}
	}
	if mm.globalConfigMgr != nil {
		k := strings.TrimSpace(mm.globalConfigMgr.Get().ModioApiKey)
		if k != "" {
			return k
		}
	}
	return strings.TrimSpace(os.Getenv("MODIO_API_KEY"))
}

func (mm *ModManager) GetModsDir() string {
	if mm.sharedModsDir != "" {
		_ = os.MkdirAll(mm.sharedModsDir, 0755)
		return mm.sharedModsDir
	}
	pShared := filepath.Join(mm.dataDir, "shared_mods")
	if _, err := os.Stat(pShared); err == nil {
		return pShared
	}

	// Standard path for Core Keeper dedicated server mods
	p := filepath.Join(mm.serverDir, "CoreKeeperServer_Data", "StreamingAssets", "Mods")
	if _, err := os.Stat(p); err == nil {
		return p
	}
	// Also check game folder in serverDir/game
	pGame := filepath.Join(mm.serverDir, "game", "CoreKeeperServer_Data", "StreamingAssets", "Mods")
	if _, err := os.Stat(pGame); err == nil {
		return pGame
	}
	// Fallback to dataDir/Mods
	fallback := filepath.Join(mm.dataDir, "Mods")
	_ = os.MkdirAll(fallback, 0755)
	return fallback
}

func (mm *ModManager) getModMeta(dirPath string) (*ModMeta, error) {
	metaFile := filepath.Join(dirPath, ".manager_meta.json")
	data, err := os.ReadFile(metaFile)
	if err != nil {
		return nil, err
	}
	var meta ModMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, err
	}
	return &meta, nil
}

func (mm *ModManager) saveModMeta(modFolderName string, meta ModMeta) {
	modsDir := mm.GetModsDir()
	p := filepath.Join(modsDir, modFolderName)
	if _, err := os.Stat(p); os.IsNotExist(err) {
		p = filepath.Join(modsDir, modFolderName+".disabled")
	}
	if _, err := os.Stat(p); os.IsNotExist(err) {
		return
	}
	metaFile := filepath.Join(p, ".manager_meta.json")
	if meta.InstalledAt.IsZero() {
		meta.InstalledAt = time.Now()
	}
	if meta.UpdatedAt.IsZero() {
		meta.UpdatedAt = time.Now()
	}
	data, err := json.MarshalIndent(meta, "", "  ")
	if err == nil {
		_ = os.WriteFile(metaFile, data, 0644)
	}
}

func isModDir(dirPath string) bool {
	if fi, err := os.Stat(dirPath); err != nil || !fi.IsDir() {
		return false
	}
	// 1. Has ModManifest.json
	if fileExists(filepath.Join(dirPath, "ModManifest.json")) {
		return true
	}
	// 2. Has .manager_meta.json
	if fileExists(filepath.Join(dirPath, ".manager_meta.json")) {
		return true
	}
	// 3. Has Scripts directory
	scriptsDir := filepath.Join(dirPath, "Scripts")
	if fi, err := os.Stat(scriptsDir); err == nil && fi.IsDir() {
		return true
	}
	// 4. Has Bundles directory (common in Core Keeper asset mods)
	bundlesDir := filepath.Join(dirPath, "Bundles")
	if fi, err := os.Stat(bundlesDir); err == nil && fi.IsDir() {
		return true
	}
	// 5. Check for any .dll, .cs, or .assetbundle file directly or in subdirectories
	var hasModFile bool
	_ = filepath.Walk(dirPath, func(p string, info os.FileInfo, err error) error {
		if err != nil || hasModFile {
			return nil
		}
		if !info.IsDir() {
			ext := strings.ToLower(filepath.Ext(info.Name()))
			if ext == ".dll" || ext == ".assetbundle" || ext == ".cs" {
				hasModFile = true
				return filepath.SkipAll
			}
		}
		return nil
	})
	return hasModFile
}

func (mm *ModManager) ListMods() ([]ModInfo, error) {
	return mm.ListModsWithEnabled(nil)
}

func (mm *ModManager) ListModsWithEnabled(enabledList []string) ([]ModInfo, error) {
	modsDir := mm.GetModsDir()
	_ = os.MkdirAll(modsDir, 0755)

	entries, err := os.ReadDir(modsDir)
	if err != nil {
		return []ModInfo{}, err
	}

	enabledSet := make(map[string]bool)
	filterByList := enabledList != nil
	if filterByList {
		for _, id := range enabledList {
			id = strings.TrimSpace(id)
			if id != "" {
				enabledSet[id] = true
			}
		}
	}

	mods := make([]ModInfo, 0)
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		dirName := entry.Name()
		if strings.HasPrefix(dirName, ".") {
			continue
		}

		fullDir := filepath.Join(modsDir, dirName)
		if !isModDir(fullDir) {
			continue
		}

		cleanID := strings.TrimSuffix(dirName, ".disabled")
		cleanID = strings.TrimSpace(cleanID)
		if cleanID == "" {
			continue
		}
		var enabled bool
		if filterByList {
			enabled = enabledSet[cleanID]
		} else {
			enabled = !strings.HasSuffix(dirName, ".disabled")
		}

		info, err := entry.Info()
		var size int64 = 0
		var modTime time.Time
		if err == nil {
			modTime = info.ModTime()
			size = dirSize(filepath.Join(modsDir, dirName))
		}

		// Read ModManifest.json if available
		displayName := cleanID
		version := ""
		author := ""
		description := ""

		manifestPath := filepath.Join(modsDir, dirName, "ModManifest.json")
		if data, err := os.ReadFile(manifestPath); err == nil {
			var m ModManifest
			if err := json.Unmarshal(data, &m); err == nil {
				if strings.TrimSpace(m.DisplayName) != "" {
					displayName = strings.TrimSpace(m.DisplayName)
				} else if strings.TrimSpace(m.Name) != "" {
					displayName = strings.TrimSpace(m.Name)
				}
				version = strings.TrimSpace(m.Version)
				author = strings.TrimSpace(m.Author)
				description = strings.TrimSpace(m.Description)
			}
		}

		isWorkshop := false
		workshopID := ""
		source := "upload"
		sourceID := ""
		sourceURL := ""
		canUpdate := false

		// 1. Check .manager_meta.json
		if meta, err := mm.getModMeta(filepath.Join(modsDir, dirName)); err == nil && meta != nil {
			source = meta.Source
			sourceID = meta.SourceID
			sourceURL = meta.SourceURL
			if source == "workshop" {
				isWorkshop = true
				workshopID = sourceID
				if workshopID != "" {
					canUpdate = true
				}
			} else if (source == "modio" || source == "url") && sourceURL != "" {
				canUpdate = true
			}
		} else {
			// 2. Fallback heuristics for pre-existing mods
			if isNumeric(cleanID) {
				source = "workshop"
				sourceID = cleanID
				isWorkshop = true
				workshopID = cleanID
				canUpdate = true
			} else if strings.EqualFold(author, "Steam Workshop") || strings.Contains(strings.ToLower(description), "workshop") {
				source = "workshop"
				isWorkshop = true
				re := regexp.MustCompile(`\b(\d{7,12})\b`)
				if match := re.FindStringSubmatch(description); len(match) > 1 {
					sourceID = match[1]
					workshopID = match[1]
					canUpdate = true
				}
			}
		}

		mods = append(mods, ModInfo{
			ID:          cleanID,
			Name:        displayName,
			Version:     version,
			Author:      author,
			Description: description,
			Enabled:     enabled,
			SizeBytes:   size,
			ModifiedAt:  modTime,
			IsWorkshop:  isWorkshop,
			WorkshopID:  workshopID,
			Source:      source,
			SourceID:    sourceID,
			SourceURL:   sourceURL,
			CanUpdate:   canUpdate,
		})
	}

	return mods, nil
}

func (mm *ModManager) ToggleMod(modID string, enable bool) error {
	modsDir := mm.GetModsDir()

	activePath := filepath.Join(modsDir, modID)
	disabledPath := filepath.Join(modsDir, modID+".disabled")

	if enable {
		if _, err := os.Stat(disabledPath); err == nil {
			return os.Rename(disabledPath, activePath)
		}
	} else {
		if _, err := os.Stat(activePath); err == nil {
			return os.Rename(activePath, disabledPath)
		}
	}

	return nil
}

func (mm *ModManager) DeleteMod(modID string) error {
	modsDir := mm.GetModsDir()

	activePath := filepath.Join(modsDir, modID)
	disabledPath := filepath.Join(modsDir, modID+".disabled")

	_ = os.RemoveAll(activePath)
	_ = os.RemoveAll(disabledPath)
	return nil
}

// Mod.io API structs
type ModioErrorResponse struct {
	Error struct {
		Code     int    `json:"code"`
		ErrorRef int    `json:"error_ref"`
		Message  string `json:"message"`
	} `json:"error"`
}

type ModioGame struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	NameID string `json:"name_id"`
}

type ModioGamesResponse struct {
	Data        []ModioGame `json:"data"`
	ResultCount int         `json:"result_count"`
	ResultTotal int         `json:"result_total"`
}

type ModioFile struct {
	ID        int64  `json:"id"`
	ModID     int64  `json:"mod_id"`
	Version   string `json:"version"`
	Filename  string `json:"filename"`
	Filesize  int64  `json:"filesize"`
	DateAdded int64  `json:"date_added"`
	Download  struct {
		BinaryURL   string `json:"binary_url"`
		DateExpires int64  `json:"date_expires"`
	} `json:"download"`
}

type ModioUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

type ModioMod struct {
	ID          int64     `json:"id"`
	GameID      int64     `json:"game_id"`
	Name        string    `json:"name"`
	NameID      string    `json:"name_id"`
	Summary     string    `json:"summary"`
	Description string    `json:"description_plaintext"`
	ProfileURL  string    `json:"profile_url"`
	SubmittedBy ModioUser `json:"submitted_by"`
	Modfile     ModioFile `json:"modfile"`
}

type ModioModsResponse struct {
	Data        []ModioMod `json:"data"`
	ResultCount int        `json:"result_count"`
	ResultTotal int        `json:"result_total"`
}

func TestModioApiKey(client *http.Client, apiKey string) (*ModioGame, error) {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return nil, fmt.Errorf("Mod.io API Key 不能为空")
	}
	req, err := http.NewRequest("GET", "https://api.mod.io/v1/games?name_id=corekeeper", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "CoreKeeper-Server-Manager/1.0")
	req.Header.Set("X-Modio-API-Key", apiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("网络请求失败: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("读取响应失败: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		var errResp ModioErrorResponse
		if jsonErr := json.Unmarshal(body, &errResp); jsonErr == nil && errResp.Error.Message != "" {
			return nil, fmt.Errorf("%s (错误码: %d)", errResp.Error.Message, errResp.Error.Code)
		}
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var gResp ModioGamesResponse
	if err := json.Unmarshal(body, &gResp); err != nil {
		return nil, fmt.Errorf("解析游戏数据失败: %v", err)
	}
	if len(gResp.Data) == 0 {
		return nil, fmt.Errorf("未在 Mod.io 匹配到 Core Keeper 游戏")
	}

	return &gResp.Data[0], nil
}

func parseModioTarget(target string) (slugOrID string, isModio bool, isZipUrl bool) {
	target = strings.TrimSpace(target)
	if target == "" {
		return "", false, false
	}
	lower := strings.ToLower(target)
	if strings.HasPrefix(lower, "modio:") {
		return strings.TrimSpace(target[6:]), true, false
	}

	if strings.Contains(lower, "mod.io") {
		u, err := url.Parse(target)
		if err == nil {
			if strings.HasSuffix(strings.ToLower(u.Path), ".zip") {
				return target, true, true
			}
			parts := strings.Split(strings.Trim(u.Path, "/"), "/")
			for i, p := range parts {
				if p == "m" && i+1 < len(parts) {
					return parts[i+1], true, false
				}
			}
			if len(parts) > 0 && parts[len(parts)-1] != "" {
				return parts[len(parts)-1], true, false
			}
		}
		return target, true, false
	}

	return target, false, false
}

func (mm *ModManager) FetchModioGameID(client *http.Client, apiKey string) (int64, error) {
	game, err := TestModioApiKey(client, apiKey)
	if err == nil && game != nil && game.ID > 0 {
		return game.ID, nil
	}
	return 5576, nil
}

func (mm *ModManager) ResolveModioMod(target string, logFn func(string)) (*ModioMod, error) {
	if logFn == nil {
		logFn = func(string) {}
	}
	apiKey := mm.GetModioApiKey()
	if apiKey == "" {
		return nil, fmt.Errorf("未配置 Mod.io API Key，请在模组管理页面配置 API Key 后再安装 Mod.io 模组")
	}

	slugOrID, _, _ := parseModioTarget(target)
	if slugOrID == "" {
		slugOrID = target
	}

	client := mm.getHTTPClient()
	gameID, _ := mm.FetchModioGameID(client, apiKey)

	// If numeric, query by mod ID directly
	if isNumeric(slugOrID) {
		reqURL := fmt.Sprintf("https://api.mod.io/v1/games/%d/mods/%s", gameID, slugOrID)
		req, err := http.NewRequest("GET", reqURL, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", "CoreKeeper-Server-Manager/1.0")
		req.Header.Set("X-Modio-API-Key", apiKey)
		req.Header.Set("Accept", "application/json")

		resp, err := client.Do(req)
		if err != nil {
			return nil, fmt.Errorf("网络请求失败: %v", err)
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
		if err != nil {
			return nil, err
		}
		if resp.StatusCode != http.StatusOK {
			var errResp ModioErrorResponse
			if jErr := json.Unmarshal(body, &errResp); jErr == nil && errResp.Error.Message != "" {
				return nil, fmt.Errorf("%s (错误码: %d)", errResp.Error.Message, errResp.Error.Code)
			}
			return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
		}

		var m ModioMod
		if err := json.Unmarshal(body, &m); err != nil {
			return nil, fmt.Errorf("解析模组数据失败: %v", err)
		}
		return &m, nil
	}

	// Query by slug (name_id)
	reqURL := fmt.Sprintf("https://api.mod.io/v1/games/%d/mods?name_id=%s", gameID, url.QueryEscape(slugOrID))
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "CoreKeeper-Server-Manager/1.0")
	req.Header.Set("X-Modio-API-Key", apiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("网络请求失败: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		var errResp ModioErrorResponse
		if jErr := json.Unmarshal(body, &errResp); jErr == nil && errResp.Error.Message != "" {
			return nil, fmt.Errorf("%s (错误码: %d)", errResp.Error.Message, errResp.Error.Code)
		}
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var mResp ModioModsResponse
	if err := json.Unmarshal(body, &mResp); err != nil {
		return nil, fmt.Errorf("解析模组列表失败: %v", err)
	}

	if len(mResp.Data) > 0 {
		return &mResp.Data[0], nil
	}

	// Try fuzzy search query with _q
	qURL := fmt.Sprintf("https://api.mod.io/v1/games/%d/mods?_q=%s", gameID, url.QueryEscape(slugOrID))
	reqQ, _ := http.NewRequest("GET", qURL, nil)
	reqQ.Header.Set("User-Agent", "CoreKeeper-Server-Manager/1.0")
	reqQ.Header.Set("X-Modio-API-Key", apiKey)
	reqQ.Header.Set("Accept", "application/json")

	if respQ, err := client.Do(reqQ); err == nil {
		defer respQ.Body.Close()
		bodyQ, _ := io.ReadAll(io.LimitReader(respQ.Body, 2<<20))
		var mRespQ ModioModsResponse
		if json.Unmarshal(bodyQ, &mRespQ) == nil && len(mRespQ.Data) > 0 {
			return &mRespQ.Data[0], nil
		}
	}

	return nil, fmt.Errorf("未在 Mod.io Core Keeper 专区中找到模组 '%s'", slugOrID)
}

func (mm *ModManager) InstallModioMod(target string, logFn func(string)) (*ModInfo, error) {
	if logFn == nil {
		logFn = func(string) {}
	}
	apiKey := mm.GetModioApiKey()
	if apiKey == "" {
		return nil, fmt.Errorf("未配置 Mod.io API Key，请在模组管理页面配置 API Key 后再安装 Mod.io 模组")
	}

	slugOrID, _, isZipUrl := parseModioTarget(target)
	if isZipUrl {
		return mm.downloadAndInstallZipWithHeaders(target, map[string]string{
			"X-Modio-API-Key": apiKey,
		}, logFn)
	}

	logFn(fmt.Sprintf("[Mod.io] Querying mod metadata for '%s'...", slugOrID))
	mod, err := mm.ResolveModioMod(target, logFn)
	if err != nil {
		return nil, err
	}

	if mod.Modfile.Download.BinaryURL == "" {
		return nil, fmt.Errorf("模组 '%s' 在 Mod.io 上暂无可用下载文件", mod.Name)
	}

	logFn(fmt.Sprintf("[Mod.io] Found '%s' (v%s, file: %s, %d bytes). Downloading...", mod.Name, mod.Modfile.Version, mod.Modfile.Filename, mod.Modfile.Filesize))

	client := mm.getHTTPClient()
	req, err := http.NewRequest("GET", mod.Modfile.Download.BinaryURL, nil)
	if err != nil {
		return nil, fmt.Errorf("invalid download URL: %v", err)
	}
	req.Header.Set("User-Agent", "CoreKeeper-Server-Manager/1.0")
	req.Header.Set("X-Modio-API-Key", apiKey)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed downloading mod from Mod.io: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("Mod.io download server returned HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	buf, err := io.ReadAll(io.LimitReader(resp.Body, 200<<20))
	if err != nil {
		return nil, fmt.Errorf("failed reading downloaded content: %v", err)
	}

	if len(buf) < 4 {
		return nil, fmt.Errorf("downloaded file is empty or too short")
	}

	if !bytes.HasPrefix(buf, []byte{0x50, 0x4B, 0x03, 0x04}) && !bytes.HasPrefix(buf, []byte{0x50, 0x4B, 0x05, 0x06}) {
		preview := string(buf)
		if len(preview) > 120 {
			preview = preview[:120]
		}
		return nil, fmt.Errorf("downloaded resource is not a valid .zip archive (got: %s)", strings.TrimSpace(preview))
	}

	defaultName := mod.NameID
	if defaultName == "" {
		defaultName = strings.TrimSuffix(mod.Modfile.Filename, filepath.Ext(mod.Modfile.Filename))
	}
	if defaultName == "" {
		defaultName = fmt.Sprintf("modio_%d", mod.ID)
	}

	modInfo, err := mm.InstallZipBytes(buf, defaultName, logFn)
	if err != nil {
		return nil, err
	}

	// Update or complement ModManifest.json if necessary
	targetDir := filepath.Join(mm.GetModsDir(), modInfo.ID)
	if _, err := os.Stat(targetDir); os.IsNotExist(err) {
		targetDir = filepath.Join(mm.GetModsDir(), modInfo.ID+".disabled")
	}
	manifestPath := filepath.Join(targetDir, "ModManifest.json")
	var mf ModManifest
	if data, err := os.ReadFile(manifestPath); err == nil {
		_ = json.Unmarshal(data, &mf)
	}
	if mf.Name == "" {
		mf.Name = modInfo.ID
	}
	if mf.DisplayName == "" {
		mf.DisplayName = mod.Name
	}
	if mf.Version == "" && mod.Modfile.Version != "" {
		mf.Version = mod.Modfile.Version
	}
	if mf.Author == "" && mod.SubmittedBy.Username != "" {
		mf.Author = mod.SubmittedBy.Username
	}
	if mf.Description == "" {
		if mod.Summary != "" {
			mf.Description = mod.Summary
		} else if mod.Description != "" {
			mf.Description = mod.Description
		}
	}
	if mfData, err := json.MarshalIndent(mf, "", "  "); err == nil {
		_ = os.WriteFile(manifestPath, mfData, 0644)
	}

	mm.saveModMeta(modInfo.ID, ModMeta{
		Source:      "modio",
		SourceID:    fmt.Sprintf("%d", mod.ID),
		SourceURL:   mod.ProfileURL,
		InstalledAt: time.Now(),
		UpdatedAt:   time.Now(),
	})

	logFn(fmt.Sprintf("[Mod.io] Mod '%s' (v%s, ID %d) installed successfully!", mod.Name, mod.Modfile.Version, mod.ID))
	return mm.getModInfoByID(modInfo.ID)
}

func (mm *ModManager) getHTTPClient() *http.Client {
	transport := &http.Transport{}
	var cfg ServerConfig
	if mm.configMgr != nil {
		cfg = mm.configMgr.Get()
	} else if mm.globalConfigMgr != nil {
		cfg = mm.globalConfigMgr.Get()
	}
	if cfg.ProxyEnabled && cfg.ProxyMods {
		if p, err := GetEffectiveProxyURL(cfg); err == nil && p != "" {
			if proxyURL, err := url.Parse(p); err == nil {
				transport.Proxy = http.ProxyURL(proxyURL)
			}
		}
	}
	return &http.Client{
		Transport: transport,
		Timeout:   180 * time.Second,
	}
}

// InstallMod handles any input: URL (ZIP, mod.io, Steam Workshop), or numeric Steam Workshop ID
func (mm *ModManager) InstallMod(target string, logFn func(string)) (*ModInfo, error) {
	if logFn == nil {
		logFn = func(string) {}
	}
	target = strings.TrimSpace(target)
	if target == "" {
		return nil, fmt.Errorf("Mod URL or Workshop ID cannot be empty")
	}

	// Check if target is a Steam Workshop link: e.g. ?id=12345678
	if strings.Contains(target, "steamcommunity.com") || strings.Contains(target, "sharedfiles") {
		re := regexp.MustCompile(`[?&]id=(\d+)`)
		match := re.FindStringSubmatch(target)
		if len(match) > 1 {
			target = match[1]
		}
	}

	// If numeric, it's a Steam Workshop item
	if isNumeric(target) {
		logFn(fmt.Sprintf("[ModManager] Installing Steam Workshop mod %s...", target))
		return mm.InstallSteamWorkshopMod(target, logFn)
	}

	// Mod.io URL or modio: prefix
	if strings.HasPrefix(strings.ToLower(target), "modio:") || strings.Contains(strings.ToLower(target), "mod.io") {
		return mm.InstallModioMod(target, logFn)
	}

	// Otherwise, treat as HTTP/HTTPS URL
	if strings.HasPrefix(target, "http://") || strings.HasPrefix(target, "https://") {
		modInfo, err := mm.downloadAndInstallZip(target, logFn)
		if err != nil {
			return nil, err
		}
		mm.saveModMeta(modInfo.ID, ModMeta{
			Source:      "url",
			SourceURL:   target,
			InstalledAt: time.Now(),
			UpdatedAt:   time.Now(),
		})
		return mm.getModInfoByID(modInfo.ID)
	}

	// If not URL and not numeric, check if user provided a Mod.io slug
	if mm.GetModioApiKey() != "" && !strings.ContainsAny(target, "/\\: \t\r\n") {
		logFn(fmt.Sprintf("[ModManager] Target '%s' is not a URL, attempting resolution via Mod.io slug...", target))
		modInfo, err := mm.InstallModioMod(target, logFn)
		if err == nil {
			return modInfo, nil
		}
		return nil, fmt.Errorf("未能通过 Mod.io 解析 slug '%s': %v (若为其他来源请提供完整 URL 或 Steam 创意工坊 ID)", target, err)
	}

	return nil, fmt.Errorf("unsupported mod target '%s': please provide a valid download URL (.zip), Mod.io link/slug, or Steam Workshop ID", target)
}

func (mm *ModManager) downloadAndInstallZipWithHeaders(rawURL string, headers map[string]string, logFn func(string)) (*ModInfo, error) {
	logFn(fmt.Sprintf("[ModManager] Downloading mod package from: %s", rawURL))

	client := mm.getHTTPClient()
	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %v", err)
	}
	req.Header.Set("User-Agent", "CoreKeeper-Server-Manager/1.0")
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to download mod: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("download server returned HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	// Read up to 200MB
	limitReader := io.LimitReader(resp.Body, 200<<20)
	buf, err := io.ReadAll(limitReader)
	if err != nil {
		return nil, fmt.Errorf("failed reading downloaded content: %v", err)
	}

	if len(buf) < 4 {
		return nil, fmt.Errorf("downloaded file is empty or too short")
	}

	// Check ZIP magic header (PK\x03\x04 or PK\x05\x06)
	if !bytes.HasPrefix(buf, []byte{0x50, 0x4B, 0x03, 0x04}) && !bytes.HasPrefix(buf, []byte{0x50, 0x4B, 0x05, 0x06}) {
		// Could be an HTML error page or unsupported page
		preview := string(buf)
		if len(preview) > 120 {
			preview = preview[:120]
		}
		return nil, fmt.Errorf("downloaded resource is not a valid .zip archive (got: %s)", strings.TrimSpace(preview))
	}

	// Fallback name from URL
	parsedURL, _ := url.Parse(rawURL)
	fallbackName := filepath.Base(parsedURL.Path)
	fallbackName = strings.TrimSuffix(fallbackName, filepath.Ext(fallbackName))
	if fallbackName == "" || fallbackName == "/" || fallbackName == "." {
		fallbackName = fmt.Sprintf("mod_%d", time.Now().Unix())
	}

	return mm.InstallZipBytes(buf, fallbackName, logFn)
}

func (mm *ModManager) downloadAndInstallZip(rawURL string, logFn func(string)) (*ModInfo, error) {
	return mm.downloadAndInstallZipWithHeaders(rawURL, nil, logFn)
}

func (mm *ModManager) InstallUploadedZip(filename string, r io.Reader, size int64, logFn func(string)) (*ModInfo, error) {
	if logFn == nil {
		logFn = func(string) {}
	}
	logFn(fmt.Sprintf("[ModManager] Processing uploaded mod archive: %s (%d bytes)...", filename, size))

	buf, err := io.ReadAll(io.LimitReader(r, 200<<20))
	if err != nil {
		return nil, fmt.Errorf("failed to read uploaded file: %v", err)
	}

	fallbackName := strings.TrimSuffix(filename, filepath.Ext(filename))
	modInfo, err := mm.InstallZipBytes(buf, fallbackName, logFn)
	if err != nil {
		return nil, err
	}
	mm.saveModMeta(modInfo.ID, ModMeta{
		Source:      "upload",
		SourceURL:   filename,
		InstalledAt: time.Now(),
		UpdatedAt:   time.Now(),
	})
	return mm.getModInfoByID(modInfo.ID)
}

func (mm *ModManager) InstallZipBytes(data []byte, defaultName string, logFn func(string)) (*ModInfo, error) {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, fmt.Errorf("failed to parse ZIP archive: %v", err)
	}

	// 1. Search for ModManifest.json inside the zip
	var manifestEntry *zip.File
	var detectedManifest ModManifest

	for _, f := range zr.File {
		base := filepath.Base(f.Name)
		if strings.EqualFold(base, "ModManifest.json") {
			rc, err := f.Open()
			if err == nil {
				mBytes, _ := io.ReadAll(rc)
				rc.Close()
				var m ModManifest
				if err := json.Unmarshal(mBytes, &m); err == nil {
					manifestEntry = f
					detectedManifest = m
					break
				}
			}
		}
	}

	// Determine prefix and folder name
	var prefix string
	var modFolderName string

	if manifestEntry != nil {
		manifestDir := filepath.Dir(manifestEntry.Name)
		if manifestDir == "." || manifestDir == "" {
			prefix = ""
		} else {
			prefix = strings.TrimPrefix(filepath.Clean(manifestDir), "/") + "/"
		}

		if strings.TrimSpace(detectedManifest.DisplayName) != "" {
			modFolderName = sanitizeFolderName(detectedManifest.DisplayName)
		} else if strings.TrimSpace(detectedManifest.Name) != "" {
			modFolderName = sanitizeFolderName(detectedManifest.Name)
		} else if manifestDir != "." && manifestDir != "" {
			modFolderName = sanitizeFolderName(filepath.Base(manifestDir))
		}
	}

	if modFolderName == "" {
		// Look for any .dll
		for _, f := range zr.File {
			if strings.EqualFold(filepath.Ext(f.Name), ".dll") {
				dllName := strings.TrimSuffix(filepath.Base(f.Name), filepath.Ext(f.Name))
				modFolderName = sanitizeFolderName(dllName)
				break
			}
		}
	}

	if modFolderName == "" {
		modFolderName = sanitizeFolderName(defaultName)
	}
	if modFolderName == "" {
		modFolderName = fmt.Sprintf("mod_%d", time.Now().Unix())
	}

	modsDir := mm.GetModsDir()
	targetDir := filepath.Join(modsDir, modFolderName)
	_ = os.RemoveAll(targetDir)
	_ = os.RemoveAll(targetDir + ".disabled")
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create mod directory %s: %v", targetDir, err)
	}

	logFn(fmt.Sprintf("[ModManager] Extracting mod files to %s...", targetDir))

	extractedCount := 0
	for _, f := range zr.File {
		fName := f.Name
		if strings.HasPrefix(fName, "__MACOSX/") || filepath.Base(fName) == ".DS_Store" {
			continue
		}

		if prefix != "" && !strings.HasPrefix(fName, prefix) {
			continue
		}

		relPath := strings.TrimPrefix(fName, prefix)
		relPath = strings.TrimPrefix(relPath, "/")
		if relPath == "" || relPath == "." {
			continue
		}

		destPath := filepath.Join(targetDir, relPath)
		// ZipSlip directory traversal guard
		if !strings.HasPrefix(filepath.Clean(destPath), filepath.Clean(targetDir)) {
			continue
		}

		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(destPath, 0755)
			continue
		}

		_ = os.MkdirAll(filepath.Dir(destPath), 0755)
		outFile, err := os.OpenFile(destPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
		if err != nil {
			continue
		}

		rc, err := f.Open()
		if err == nil {
			_, _ = io.Copy(outFile, rc)
			rc.Close()
			extractedCount++
		}
		outFile.Close()
	}

	if extractedCount == 0 {
		_ = os.RemoveAll(targetDir)
		return nil, fmt.Errorf("no usable files found in the archive for mod %s", modFolderName)
	}

	// Ensure ModManifest.json exists
	targetManifest := filepath.Join(targetDir, "ModManifest.json")
	if _, err := os.Stat(targetManifest); err != nil {
		fallbackManifest := ModManifest{
			Name:        modFolderName,
			Version:     "1.0.0",
			Description: "Installed via Core Keeper Manager",
			Author:      "Community",
		}
		b, _ := json.MarshalIndent(fallbackManifest, "", "  ")
		_ = os.WriteFile(targetManifest, b, 0644)
	}

	logFn(fmt.Sprintf("[ModManager] Mod '%s' installed successfully (%d files)!", modFolderName, extractedCount))
	return mm.getModInfoByID(modFolderName)
}

func (mm *ModManager) getModInfoByID(modID string) (*ModInfo, error) {
	mods, err := mm.ListMods()
	if err != nil {
		return nil, err
	}
	for _, m := range mods {
		if m.ID == modID {
			return &m, nil
		}
	}
	// Fallback
	return &ModInfo{
		ID:      modID,
		Name:    modID,
		Enabled: true,
	}, nil
}

var steamcmdLock sync.Mutex

func (mm *ModManager) InstallSteamWorkshopMod(workshopID string, logFn func(string)) (*ModInfo, error) {
	workshopID = strings.TrimSpace(workshopID)
	if workshopID == "" {
		return nil, fmt.Errorf("Workshop ID is required")
	}

	steamcmdLock.Lock()
	defer steamcmdLock.Unlock()

	logFn(fmt.Sprintf("[Steamworks] Downloading Workshop Mod: ID %s for Core Keeper (AppID 1621690)...", workshopID))

	// Find steamcmd binary
	steamcmdPath := "steamcmd"
	if p, err := exec.LookPath("steamcmd"); err == nil {
		steamcmdPath = p
	} else {
		commonPaths := []string{
			"/usr/games/steamcmd",
			"/usr/bin/steamcmd",
			"/home/steam/.local/share/Steam/steamcmd/steamcmd.sh",
			"/home/steam/steamcmd/steamcmd.sh",
			"/steamcmd/steamcmd.sh",
		}
		for _, cp := range commonPaths {
			if _, err := os.Stat(cp); err == nil {
				steamcmdPath = cp
				break
			}
		}
	}

	homeDir := os.Getenv("HOME")
	if homeDir == "" {
		homeDir = "/home/steam"
	}

	var proxyURL string
	if mm.configMgr != nil {
		cfg := mm.configMgr.Get()
		if cfg.ProxyEnabled && cfg.ProxyMods {
			if p, err := GetEffectiveProxyURL(cfg); err == nil && p != "" {
				proxyURL = p
			}
		}
	}

	runOnce := func(useProxy bool) (string, error) {
		args := []string{
			"+login", "anonymous",
			"+workshop_download_item", "1621690", workshopID,
			"+quit",
		}

		cmd := exec.Command(steamcmdPath, args...)
		cmd.Dir = homeDir
		if useProxy && proxyURL != "" {
			logFn(fmt.Sprintf("[SteamCMD] Connecting via configured proxy: %s", proxyURL))
			ApplyProxyEnv(cmd, proxyURL)
		} else {
			// Ensure clean baseline environment with HOME and PATH
			cmd.Env = os.Environ()
			hasHome := false
			for _, e := range cmd.Env {
				if strings.HasPrefix(e, "HOME=") {
					hasHome = true
					break
				}
			}
			if !hasHome {
				cmd.Env = append(cmd.Env, "HOME="+homeDir)
			}
		}

		var outBuf bytes.Buffer
		cmd.Stdout = io.MultiWriter(&outBuf, &logWriter{logFn: logFn})
		cmd.Stderr = io.MultiWriter(&outBuf, &logWriter{logFn: logFn})

		err := cmd.Run()
		return outBuf.String(), err
	}

	var output string
	var err error

	if proxyURL != "" {
		logFn(fmt.Sprintf("[SteamCMD] Downloading Workshop item via configured proxy: %s", proxyURL))
		output, err = runOnce(true)
		if err != nil {
			logFn(fmt.Sprintf("[SteamCMD] Proxy download encountered an issue (%v), retrying via direct connection...", err))
			output, err = runOnce(false)
		}
	} else {
		output, err = runOnce(false)
	}

	if err != nil {
		return nil, fmt.Errorf("SteamCMD failed to download Workshop item: %v (output: %s)", err, output)
	}

	// Locate downloaded workshop files
	possibleWorkshopPaths := []string{
		filepath.Join(homeDir, "Steam", "steamapps", "workshop", "content", "1621690", workshopID),
		filepath.Join(homeDir, ".local", "share", "Steam", "steamapps", "workshop", "content", "1621690", workshopID),
		filepath.Join(homeDir, ".steam", "steamapps", "workshop", "content", "1621690", workshopID),
		filepath.Join("/home/steam/Steam/steamapps/workshop/content/1621690", workshopID),
		filepath.Join("/home/steam/.local/share/Steam/steamapps/workshop/content/1621690", workshopID),
		filepath.Join("/root/Steam/steamapps/workshop/content/1621690", workshopID),
		filepath.Join("/root/.local/share/Steam/steamapps/workshop/content/1621690", workshopID),
		filepath.Join("/steamcmd/steamapps/workshop/content/1621690", workshopID),
		filepath.Join(mm.serverDir, "steamapps", "workshop", "content", "1621690", workshopID),
	}

	var foundSrc string
	for _, p := range possibleWorkshopPaths {
		if stat, err := os.Stat(p); err == nil && stat.IsDir() {
			foundSrc = p
			break
		}
	}

	if foundSrc == "" {
		matches, _ := filepath.Glob(fmt.Sprintf("**/content/1621690/%s", workshopID))
		if len(matches) > 0 {
			foundSrc = matches[0]
		}
	}

	if foundSrc == "" {
		return nil, fmt.Errorf("could not locate downloaded workshop files for ID %s. SteamCMD output: %s", workshopID, output)
	}

	// Read ModManifest.json if present to determine best target folder name
	targetFolderName := workshopID
	manifestPath := filepath.Join(foundSrc, "ModManifest.json")
	if data, err := os.ReadFile(manifestPath); err == nil {
		var m ModManifest
		if err := json.Unmarshal(data, &m); err == nil {
			if strings.TrimSpace(m.DisplayName) != "" {
				targetFolderName = sanitizeFolderName(m.DisplayName)
			} else if strings.TrimSpace(m.Name) != "" {
				targetFolderName = sanitizeFolderName(m.Name)
			}
		}
	}

	targetDir := filepath.Join(mm.GetModsDir(), targetFolderName)
	_ = os.RemoveAll(targetDir)
	_ = os.RemoveAll(targetDir + ".disabled")
	if targetFolderName != workshopID {
		_ = os.RemoveAll(filepath.Join(mm.GetModsDir(), workshopID))
		_ = os.RemoveAll(filepath.Join(mm.GetModsDir(), workshopID+".disabled"))
	}
	_ = os.MkdirAll(targetDir, 0755)

	logFn(fmt.Sprintf("[Steamworks] Copying mod files from %s to %s...", foundSrc, targetDir))
	if err := copyDir(foundSrc, targetDir); err != nil {
		return nil, fmt.Errorf("failed copying mod files: %v", err)
	}

	// Ensure ModManifest.json exists
	targetManifest := filepath.Join(targetDir, "ModManifest.json")
	if _, err := os.Stat(targetManifest); err != nil {
		fallbackManifest := ModManifest{
			Name:        targetFolderName,
			Version:     "1.0.0",
			Description: fmt.Sprintf("Steam Workshop Item %s", workshopID),
			Author:      "Steam Workshop",
		}
		b, _ := json.MarshalIndent(fallbackManifest, "", "  ")
		_ = os.WriteFile(targetManifest, b, 0644)
	}

	mm.saveModMeta(targetFolderName, ModMeta{
		Source:      "workshop",
		SourceID:    workshopID,
		SourceURL:   fmt.Sprintf("https://steamcommunity.com/sharedfiles/filedetails/?id=%s", workshopID),
		InstalledAt: time.Now(),
		UpdatedAt:   time.Now(),
	})

	logFn(fmt.Sprintf("[Steamworks] Mod '%s' (Workshop ID %s) installed successfully!", targetFolderName, workshopID))
	return mm.getModInfoByID(targetFolderName)
}

func (mm *ModManager) UpdateMod(modID string, logFn func(string)) (*ModInfo, error) {
	if logFn == nil {
		logFn = func(string) {}
	}
	modsDir := mm.GetModsDir()
	targetDir := filepath.Join(modsDir, modID)
	disabledDir := filepath.Join(modsDir, modID+".disabled")

	dirToUse := targetDir
	wasDisabled := false
	if _, err := os.Stat(targetDir); os.IsNotExist(err) {
		if _, err2 := os.Stat(disabledDir); err2 == nil {
			dirToUse = disabledDir
			wasDisabled = true
		} else {
			return nil, fmt.Errorf("mod '%s' not found", modID)
		}
	}

	meta, _ := mm.getModMeta(dirToUse)
	source := "upload"
	sourceID := ""
	sourceURL := ""

	if meta != nil {
		source = meta.Source
		sourceID = meta.SourceID
		sourceURL = meta.SourceURL
	} else {
		// Heuristics for existing mods without metadata
		if isNumeric(modID) {
			source = "workshop"
			sourceID = modID
		} else {
			manifestPath := filepath.Join(dirToUse, "ModManifest.json")
			if data, err := os.ReadFile(manifestPath); err == nil {
				var m ModManifest
				if err := json.Unmarshal(data, &m); err == nil {
					if strings.EqualFold(m.Author, "Steam Workshop") || strings.Contains(strings.ToLower(m.Description), "workshop") {
						re := regexp.MustCompile(`\b(\d{7,12})\b`)
						if match := re.FindStringSubmatch(m.Description); len(match) > 1 {
							source = "workshop"
							sourceID = match[1]
						}
					}
				}
			}
		}
	}

	logFn(fmt.Sprintf("[ModManager] Updating mod '%s' (Source: %s)...", modID, source))

	switch source {
	case "workshop":
		wsID := sourceID
		if wsID == "" && isNumeric(modID) {
			wsID = modID
		}
		if wsID == "" {
			return nil, fmt.Errorf("mod '%s' is missing Workshop ID, cannot update", modID)
		}
		info, err := mm.InstallSteamWorkshopMod(wsID, logFn)
		if err != nil {
			return nil, fmt.Errorf("failed updating workshop mod: %v", err)
		}
		if wasDisabled {
			_ = mm.ToggleMod(info.ID, false)
		}
		return mm.getModInfoByID(info.ID)

	case "modio":
		apiKey := mm.GetModioApiKey()
		if apiKey == "" {
			return nil, fmt.Errorf("未配置 Mod.io API Key，无法从 Mod.io 检查并更新模组")
		}
		target := sourceID
		if target == "" {
			target = sourceURL
		}
		if target == "" {
			target = modID
		}
		logFn(fmt.Sprintf("[Mod.io] Querying latest version for mod '%s' (SourceID: %s)...", modID, sourceID))
		modioMod, err := mm.ResolveModioMod(target, logFn)
		if err != nil {
			return nil, fmt.Errorf("failed resolving mod from Mod.io: %v", err)
		}
		if modioMod.Modfile.Download.BinaryURL == "" {
			return nil, fmt.Errorf("mod '%s' does not have a downloadable file on Mod.io", modioMod.Name)
		}
		logFn(fmt.Sprintf("[Mod.io] Downloading latest release '%s' (v%s, file: %s)...", modioMod.Name, modioMod.Modfile.Version, modioMod.Modfile.Filename))
		info, err := mm.InstallModioMod(fmt.Sprintf("modio:%d", modioMod.ID), logFn)
		if err != nil {
			return nil, fmt.Errorf("failed updating mod from Mod.io: %v", err)
		}
		if wasDisabled {
			_ = mm.ToggleMod(info.ID, false)
		}
		return mm.getModInfoByID(info.ID)

	case "url":
		if sourceURL == "" {
			return nil, fmt.Errorf("mod '%s' does not have a download URL recorded", modID)
		}
		info, err := mm.downloadAndInstallZip(sourceURL, logFn)
		if err != nil {
			return nil, fmt.Errorf("failed updating mod from URL: %v", err)
		}
		mm.saveModMeta(info.ID, ModMeta{
			Source:      source,
			SourceURL:   sourceURL,
			InstalledAt: time.Now(),
			UpdatedAt:   time.Now(),
		})
		if wasDisabled {
			_ = mm.ToggleMod(info.ID, false)
		}
		return mm.getModInfoByID(info.ID)

	case "upload":
		return nil, fmt.Errorf("本地上传的模组不支持在线更新，请直接上传新版本 .zip 文件覆盖")

	default:
		return nil, fmt.Errorf("unsupported update source: %s", source)
	}
}

type logWriter struct {
	logFn func(string)
}

func (w *logWriter) Write(p []byte) (n int, err error) {
	lines := strings.Split(string(p), "\n")
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l != "" {
			w.logFn(l)
		}
	}
	return len(p), nil
}

func dirSize(path string) int64 {
	var size int64
	_ = filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			size += info.Size()
		}
		return nil
	})
	return size
}

func isNumeric(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func sanitizeFolderName(s string) string {
	s = strings.TrimSpace(s)
	// Replace non-safe filename characters with _
	re := regexp.MustCompile(`[^a-zA-Z0-9_\-\.]`)
	clean := re.ReplaceAllString(s, "_")
	clean = strings.Trim(clean, "._- ")
	return clean
}

func copyDir(src string, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}
		return copyFile(path, target)
	})
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}
