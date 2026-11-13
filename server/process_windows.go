//go:build windows

package main

import (
	"fmt"
	"os/exec"
)

func setProcessGroup(cmd *exec.Cmd) {
	// On Windows, child processes are managed by the Windows job or process object.
}

func interruptProcess(cmd *exec.Cmd) {
	if cmd == nil || cmd.Process == nil {
		return
	}
	// Try graceful termination or taskkill
	_ = cmd.Process.Kill()
}

func killProcess(cmd *exec.Cmd) {
	if cmd == nil || cmd.Process == nil {
		return
	}
	// Use taskkill /T /F to kill the entire process tree on Windows
	killCmd := exec.Command("taskkill", "/PID", fmt.Sprintf("%d", cmd.Process.Pid), "/T", "/F")
	_ = killCmd.Run()
}
