package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

type AdminItem struct {
	Index      int    `json:"index"`
	Privileges int    `json:"privileges"` // 2: Full Admin, 1: Moderator
	Name       string `json:"name"`
	SteamID    int64  `json:"steamId"`
	SteamIDStr string `json:"steamIdStr,omitempty"`
}

type AdminsFile struct {
	AdminList []AdminItem `json:"adminList"`
}

type AdminManager struct {
	dataPath string
	mu       sync.RWMutex
}

func NewAdminManager(dataPath string) *AdminManager {
	return &AdminManager{dataPath: dataPath}
}

func (am *AdminManager) getFilePath() string {
	return filepath.Join(am.dataPath, "Admins.json")
}

func (am *AdminManager) GetAdmins() ([]AdminItem, error) {
	am.mu.RLock()
	defer am.mu.RUnlock()

	filePath := am.getFilePath()
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		return []AdminItem{}, nil
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		return []AdminItem{}, err
	}

	var file AdminsFile
	if err := json.Unmarshal(data, &file); err != nil {
		return []AdminItem{}, err
	}

	if file.AdminList == nil {
		file.AdminList = []AdminItem{}
	}
	for i := range file.AdminList {
		file.AdminList[i].SteamIDStr = fmt.Sprintf("%d", file.AdminList[i].SteamID)
	}

	return file.AdminList, nil
}

func (am *AdminManager) AddAdmin(name string, steamID int64, privileges int) error {
	am.mu.Lock()
	defer am.mu.Unlock()

	admins, err := am.readAdminsUnlocked()
	if err != nil {
		admins = []AdminItem{}
	}

	// Check if steamID already exists
	for _, a := range admins {
		if a.SteamID == steamID {
			return fmt.Errorf("Admin with SteamID %d already exists", steamID)
		}
	}

	maxIndex := 0
	for _, a := range admins {
		if a.Index > maxIndex {
			maxIndex = a.Index
		}
	}

	if privileges <= 0 {
		privileges = 2 // Default full admin
	}

	admins = append(admins, AdminItem{
		Index:      maxIndex + 1,
		Privileges: privileges,
		Name:       name,
		SteamID:    steamID,
	})

	return am.saveAdminsUnlocked(admins)
}

func (am *AdminManager) UpdateAdmin(steamID int64, name string, privileges int) error {
	am.mu.Lock()
	defer am.mu.Unlock()

	admins, err := am.readAdminsUnlocked()
	if err != nil {
		return err
	}

	found := false
	for i, a := range admins {
		if a.SteamID == steamID {
			admins[i].Name = name
			admins[i].Privileges = privileges
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("Admin with SteamID %d not found", steamID)
	}

	return am.saveAdminsUnlocked(admins)
}

func (am *AdminManager) DeleteAdmin(targetID string) error {
	am.mu.Lock()
	defer am.mu.Unlock()

	admins, err := am.readAdminsUnlocked()
	if err != nil {
		return err
	}

	var updated []AdminItem
	for _, a := range admins {
		idStr := fmt.Sprintf("%d", a.SteamID)
		if idStr != targetID {
			updated = append(updated, a)
		}
	}

	if updated == nil {
		updated = []AdminItem{}
	}

	return am.saveAdminsUnlocked(updated)
}

func (am *AdminManager) readAdminsUnlocked() ([]AdminItem, error) {
	filePath := am.getFilePath()
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		return []AdminItem{}, nil
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}

	var file AdminsFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, err
	}

	if file.AdminList == nil {
		file.AdminList = []AdminItem{}
	}

	return file.AdminList, nil
}

func (am *AdminManager) saveAdminsUnlocked(admins []AdminItem) error {
	filePath := am.getFilePath()
	_ = os.MkdirAll(filepath.Dir(filePath), 0755)

	if admins == nil {
		admins = []AdminItem{}
	}

	// Clean up for disk writing (keep only disk fields)
	cleanList := make([]AdminItem, len(admins))
	for i, a := range admins {
		cleanList[i] = AdminItem{
			Index:      a.Index,
			Privileges: a.Privileges,
			Name:       a.Name,
			SteamID:    a.SteamID,
		}
	}

	file := AdminsFile{AdminList: cleanList}
	data, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(filePath, data, 0644)
}

