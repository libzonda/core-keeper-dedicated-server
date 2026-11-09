package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var worldFileRe = regexp.MustCompile(`^(\d+)\.world(?:\.gzip)?$`)

type WorldMeta struct {
	Index     int       `json:"index"`
	Name      string    `json:"name"`
	Mode      int       `json:"mode"`
	Seed      int64     `json:"seed"`
	CreatedAt time.Time `json:"createdAt"`
}

type WorldInfo struct {
	Index      int       `json:"index"`
	Name       string    `json:"name"`
	Exists     bool      `json:"exists"`
	SizeBytes  int64     `json:"sizeBytes"`
	CreatedAt  time.Time `json:"createdAt"`
	ModifiedAt time.Time `json:"modifiedAt"`
	IsActive   bool      `json:"isActive"`
	Mode       int       `json:"mode"`
	Seed       int64     `json:"seed"`
}

type WorldManager struct {
	dataPath string
	mu       sync.RWMutex
}

func NewWorldManager(dataPath string) *WorldManager {
	wm := &WorldManager{dataPath: dataPath}
	wm.initRegistry()
	return wm
}

func (wm *WorldManager) registryFilePath() string {
	return filepath.Join(wm.dataPath, "worlds.json")
}

func (wm *WorldManager) getWorldFilePath(index int) string {
	candidates := []string{
		filepath.Join(wm.dataPath, "worlds", fmt.Sprintf("%d.world.gzip", index)),
		filepath.Join(wm.dataPath, "worlds", fmt.Sprintf("%d.world", index)),
		filepath.Join(wm.dataPath, fmt.Sprintf("%d.world.gzip", index)),
		filepath.Join(wm.dataPath, fmt.Sprintf("%d.world", index)),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return filepath.Join(wm.dataPath, "worlds", fmt.Sprintf("%d.world.gzip", index))
}

func (wm *WorldManager) initRegistry() {
	wm.mu.Lock()
	defer wm.mu.Unlock()

	regPath := wm.registryFilePath()
	metas := make(map[int]WorldMeta)

	if data, err := os.ReadFile(regPath); err == nil && len(data) > 0 {
		var list []WorldMeta
		if err := json.Unmarshal(data, &list); err == nil {
			for _, m := range list {
				metas[m.Index] = m
			}
		}
	}

	// Ensure metas is not completely empty if no worlds were loaded
	if len(metas) == 0 {
		metas[0] = WorldMeta{
			Index:     0,
			Name:      "默认世界",
			Mode:      0,
			Seed:      0,
			CreatedAt: time.Now(),
		}
	}

	worldsDir := filepath.Join(wm.dataPath, "worlds")
	backupsDir := filepath.Join(wm.dataPath, "backups")
	_ = os.MkdirAll(backupsDir, 0755)

	// Move any legacy .bak.* files to the isolated backups directory
	if entries, err := os.ReadDir(worldsDir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			fname := entry.Name()
			if strings.Contains(fname, ".world.gzip.bak.") || strings.Contains(fname, ".world.bak.") {
				_ = os.Rename(filepath.Join(worldsDir, fname), filepath.Join(backupsDir, fname))
			}
		}
	}

	// Scan for valid pre-existing world save files on disk without slot limit
	// Must strictly match ^(\d+)\.world(?:\.gzip)?$ and have size > 0
	if entries, err := os.ReadDir(worldsDir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			fname := entry.Name()
			matches := worldFileRe.FindStringSubmatch(fname)
			if len(matches) != 2 {
				continue
			}
			idx, err := strconv.Atoi(matches[1])
			if err != nil {
				continue
			}
			info, err := entry.Info()
			if err != nil || info.Size() <= 0 {
				continue
			}

			if _, exists := metas[idx]; !exists {
				metas[idx] = WorldMeta{
					Index:     idx,
					Name:      fmt.Sprintf("世界 %d", idx+1),
					Mode:      0,
					Seed:      0,
					CreatedAt: info.ModTime(),
				}
			}
		}
	}

	// Clean up phantom entries in metas with no corresponding world save file on disk
	// (e.g. auto-generated "世界 %d", or phantom "默认世界" when other real worlds exist)
	for idx, m := range metas {
		path := wm.getWorldFilePath(idx)
		info, err := os.Stat(path)
		hasFile := err == nil && !info.IsDir() && info.Size() > 0
		if !hasFile {
			if m.Name == fmt.Sprintf("世界 %d", idx+1) || (idx == 0 && m.Name == "默认世界" && len(metas) > 1) {
				delete(metas, idx)
			}
		}
	}

	_ = wm.saveMetaMapLocked(metas)
}

func (wm *WorldManager) loadMetaMapLocked() map[int]WorldMeta {
	regPath := wm.registryFilePath()
	metas := make(map[int]WorldMeta)

	if data, err := os.ReadFile(regPath); err == nil && len(data) > 0 {
		var list []WorldMeta
		if err := json.Unmarshal(data, &list); err == nil {
			for _, m := range list {
				metas[m.Index] = m
			}
		}
	}

	if len(metas) == 0 {
		metas[0] = WorldMeta{
			Index:     0,
			Name:      "默认世界",
			Mode:      0,
			Seed:      0,
			CreatedAt: time.Now(),
		}
	}
	return metas
}

func (wm *WorldManager) saveMetaMapLocked(metas map[int]WorldMeta) error {
	list := make([]WorldMeta, 0, len(metas))
	for _, m := range metas {
		list = append(list, m)
	}
	sort.Slice(list, func(i, j int) bool {
		return list[i].Index < list[j].Index
	})

	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(wm.registryFilePath(), data, 0644)
}

func (wm *WorldManager) GetWorlds(activeWorldIndex int) []WorldInfo {
	wm.mu.Lock()
	metas := wm.loadMetaMapLocked()

	// Ensure active world is in the registry
	if _, ok := metas[activeWorldIndex]; !ok {
		metas[activeWorldIndex] = WorldMeta{
			Index:     activeWorldIndex,
			Name:      fmt.Sprintf("World Slot #%d", activeWorldIndex),
			Mode:      0,
			Seed:      0,
			CreatedAt: time.Now(),
		}
		_ = wm.saveMetaMapLocked(metas)
	}
	wm.mu.Unlock()

	wm.mu.RLock()
	defer wm.mu.RUnlock()

	result := make([]WorldInfo, 0, len(metas))
	for _, meta := range metas {
		path := wm.getWorldFilePath(meta.Index)
		info, err := os.Stat(path)
		exists := err == nil && !info.IsDir() && info.Size() > 0
		var size int64 = 0
		var modTime time.Time
		if exists {
			size = info.Size()
			modTime = info.ModTime()
		}

		name := meta.Name
		if name == "" {
			name = "世界"
		}

		createdAt := meta.CreatedAt
		if createdAt.IsZero() {
			if exists && !modTime.IsZero() {
				createdAt = modTime
			} else {
				createdAt = time.Now()
			}
		}

		result = append(result, WorldInfo{
			Index:      meta.Index,
			Name:       name,
			Exists:     exists,
			SizeBytes:  size,
			CreatedAt:  createdAt,
			ModifiedAt: modTime,
			IsActive:   meta.Index == activeWorldIndex,
			Mode:       meta.Mode,
			Seed:       meta.Seed,
		})
	}

	// Sort worlds by creation time (earliest to latest)
	sort.Slice(result, func(i, j int) bool {
		if result[i].CreatedAt.Equal(result[j].CreatedAt) {
			return result[i].Index < result[j].Index
		}
		return result[i].CreatedAt.Before(result[j].CreatedAt)
	})

	return result
}

func (wm *WorldManager) GetWorldMeta(index int) (*WorldMeta, error) {
	wm.mu.RLock()
	defer wm.mu.RUnlock()

	metas := wm.loadMetaMapLocked()
	if meta, ok := metas[index]; ok {
		return &meta, nil
	}
	return nil, fmt.Errorf("world not found in worlds list; please create it first")
}

func (wm *WorldManager) RenameWorld(index int, newName string) error {
	wm.mu.Lock()
	defer wm.mu.Unlock()

	newName = strings.TrimSpace(newName)
	if newName == "" {
		return fmt.Errorf("world name cannot be empty")
	}

	metas := wm.loadMetaMapLocked()
	meta, exists := metas[index]
	if !exists {
		path := wm.getWorldFilePath(index)
		if _, err := os.Stat(path); err == nil {
			meta = WorldMeta{
				Index:     index,
				Name:      newName,
				Mode:      0,
				Seed:      0,
				CreatedAt: time.Now(),
			}
		} else {
			return fmt.Errorf("world slot #%d not found", index)
		}
	}

	meta.Name = newName
	metas[index] = meta
	return wm.saveMetaMapLocked(metas)
}

func (wm *WorldManager) AddWorld(index int, name string, mode int, seed int64) (int, error) {
	wm.mu.Lock()
	defer wm.mu.Unlock()

	metas := wm.loadMetaMapLocked()

	// If index is negative or already occupied, auto-assign lowest free index >= 0 (no slot limit)
	if index < 0 || (index >= 0 && metas[index].Name != "") {
		assigned := -1
		for i := 0; ; i++ {
			if _, exists := metas[i]; !exists {
				assigned = i
				break
			}
		}
		index = assigned
	}

	if name == "" {
		name = fmt.Sprintf("新世界 %d", index+1)
	}

	metas[index] = WorldMeta{
		Index:     index,
		Name:      name,
		Mode:      mode,
		Seed:      seed,
		CreatedAt: time.Now(),
	}

	return index, wm.saveMetaMapLocked(metas)
}

func (wm *WorldManager) ImportWorld(name string, mode int, seed int64, fileData []byte) (int, error) {
	wm.mu.Lock()
	defer wm.mu.Unlock()

	metas := wm.loadMetaMapLocked()

	// Check if fileData is a zip archive
	var saveBytes []byte
	if len(fileData) >= 4 && fileData[0] == 0x50 && fileData[1] == 0x4B {
		zr, err := zip.NewReader(bytes.NewReader(fileData), int64(len(fileData)))
		if err == nil {
			for _, f := range zr.File {
				lowerName := strings.ToLower(f.Name)
				if strings.HasSuffix(lowerName, ".world.gzip") || strings.HasSuffix(lowerName, ".world") {
					rc, err := f.Open()
					if err == nil {
						extracted, err := io.ReadAll(rc)
						_ = rc.Close()
						if err == nil && len(extracted) > 0 {
							saveBytes = extracted
							if name == "" {
								base := filepath.Base(f.Name)
								base = strings.TrimSuffix(base, ".world.gzip")
								base = strings.TrimSuffix(base, ".world")
								if base != "" {
									name = base
								}
							}
							break
						}
					}
				}
			}
			// Look for meta.json inside zip to read world metadata if available
			for _, f := range zr.File {
				if f.Name == "meta.json" {
					rc, err := f.Open()
					if err == nil {
						var parsedMeta WorldMeta
						if err := json.NewDecoder(rc).Decode(&parsedMeta); err == nil {
							if name == "" && parsedMeta.Name != "" {
								name = parsedMeta.Name
							}
							if mode == 0 && parsedMeta.Mode != 0 {
								mode = parsedMeta.Mode
							}
							if seed == 0 && parsedMeta.Seed != 0 {
								seed = parsedMeta.Seed
							}
						}
						_ = rc.Close()
					}
				}
			}
		}
	}

	if len(saveBytes) == 0 {
		// Raw .world.gzip or .world file
		saveBytes = fileData
	}

	// Auto-assign lowest free index >= 0 (no slot limit)
	index := 0
	for i := 0; ; i++ {
		if _, exists := metas[i]; !exists {
			index = i
			break
		}
	}

	if name == "" {
		name = fmt.Sprintf("导入世界 %d", index+1)
	}

	worldsDir := filepath.Join(wm.dataPath, "worlds")
	if err := os.MkdirAll(worldsDir, 0755); err != nil {
		return -1, fmt.Errorf("failed to create worlds directory: %w", err)
	}

	targetPath := filepath.Join(worldsDir, fmt.Sprintf("%d.world.gzip", index))
	if err := os.WriteFile(targetPath, saveBytes, 0644); err != nil {
		return -1, fmt.Errorf("failed to write imported save file: %w", err)
	}

	metas[index] = WorldMeta{
		Index:     index,
		Name:      name,
		Mode:      mode,
		Seed:      seed,
		CreatedAt: time.Now(),
	}

	if err := wm.saveMetaMapLocked(metas); err != nil {
		_ = os.Remove(targetPath)
		return -1, err
	}

	return index, nil
}

func (wm *WorldManager) ExportWorldZip(index int, w io.Writer) (string, error) {
	wm.mu.RLock()
	defer wm.mu.RUnlock()

	metas := wm.loadMetaMapLocked()
	meta, exists := metas[index]
	if !exists {
		return "", fmt.Errorf("world not found")
	}

	path := wm.getWorldFilePath(index)
	info, err := os.Stat(path)
	if err != nil || info.IsDir() || info.Size() == 0 {
		return "", fmt.Errorf("world file does not exist yet (server needs to run to generate map data)")
	}

	safeName := strings.ReplaceAll(meta.Name, "/", "_")
	safeName = strings.ReplaceAll(safeName, "\\", "_")
	safeName = strings.ReplaceAll(safeName, " ", "_")
	if safeName == "" {
		safeName = fmt.Sprintf("world_%d", index)
	}

	saveFile, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("failed to open save file: %w", err)
	}
	defer saveFile.Close()

	zw := zip.NewWriter(w)
	defer zw.Close()

	// 1. Write the .world.gzip inside zip
	internalFilename := fmt.Sprintf("%s.world.gzip", safeName)
	saveHeader := &zip.FileHeader{
		Name:     internalFilename,
		Method:   zip.Deflate,
		Modified: info.ModTime(),
	}
	entryWriter, err := zw.CreateHeader(saveHeader)
	if err != nil {
		return "", fmt.Errorf("failed to create zip entry: %w", err)
	}
	if _, err := io.Copy(entryWriter, saveFile); err != nil {
		return "", fmt.Errorf("failed to write zip save data: %w", err)
	}

	// 2. Write meta.json inside zip
	metaBytes, err := json.MarshalIndent(meta, "", "  ")
	if err == nil {
		metaHeader := &zip.FileHeader{
			Name:     "meta.json",
			Method:   zip.Deflate,
			Modified: time.Now(),
		}
		if metaWriter, err := zw.CreateHeader(metaHeader); err == nil {
			_, _ = metaWriter.Write(metaBytes)
		}
	}

	return fmt.Sprintf("%s.zip", safeName), nil
}

func (wm *WorldManager) DeleteWorld(index int, activeWorldIndex int) error {
	wm.mu.Lock()
	defer wm.mu.Unlock()

	if index == activeWorldIndex {
		return fmt.Errorf("cannot delete currently active world")
	}

	metas := wm.loadMetaMapLocked()
	if _, exists := metas[index]; !exists {
		return fmt.Errorf("world does not exist")
	}

	delete(metas, index)
	if err := wm.saveMetaMapLocked(metas); err != nil {
		return err
	}

	backupsDir := filepath.Join(wm.dataPath, "backups")
	_ = os.MkdirAll(backupsDir, 0755)

	// Backup and remove save file if present to isolated backups directory
	path := wm.getWorldFilePath(index)
	if info, err := os.Stat(path); err == nil && !info.IsDir() {
		bakFilename := fmt.Sprintf("%d_%d.world.gzip.bak", index, time.Now().Unix())
		bakPath := filepath.Join(backupsDir, bakFilename)
		_ = os.Rename(path, bakPath)
		_ = os.Remove(path)
	}

	// Clean up any related residual files for this index in worlds directory
	worldsDir := filepath.Join(wm.dataPath, "worlds")
	if entries, err := os.ReadDir(worldsDir); err == nil {
		prefix := fmt.Sprintf("%d.world", index)
		for _, entry := range entries {
			fname := entry.Name()
			if strings.HasPrefix(fname, prefix) {
				_ = os.Remove(filepath.Join(worldsDir, fname))
			}
		}
	}

	return nil
}
