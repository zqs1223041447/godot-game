// Local web launcher. Standard library only; no external network services.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const address = "127.0.0.1:18764"
const browserURL = "http://localhost:18764/"

var assets = map[string]string{
	"index.html":                      "text/html; charset=utf-8",
	"index.js":                        "text/javascript; charset=utf-8",
	"index.wasm":                      "application/wasm",
	"index.pck":                       "application/octet-stream",
	"single_instance_gate.js":         "text/javascript; charset=utf-8",
	"index.audio.worklet.js":          "text/javascript; charset=utf-8",
	"index.audio.position.worklet.js": "text/javascript; charset=utf-8",
	"index.icon.png":                  "image/png",
	"index.apple-touch-icon.png":      "image/png",
	"index.png":                       "image/png",
}
var required = []string{"index.html", "index.js", "index.wasm", "index.pck", "single_instance_gate.js", "index.audio.worklet.js", "index.audio.position.worklet.js", "index.icon.png", "index.apple-touch-icon.png", "index.png"}

type assetServer struct{ root string }

func newAssetServer(root string) (*assetServer, error) {
	resolved, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, err
	}
	resolved, err = filepath.Abs(resolved)
	if err != nil {
		return nil, err
	}
	s := &assetServer{root: resolved}
	for _, name := range required {
		f, err := s.openAsset(name)
		if err != nil {
			return nil, fmt.Errorf("required asset %s: %w", name, err)
		}
		f.Close()
	}
	return s, nil
}
func (s *assetServer) openAsset(name string) (*os.File, error) {
	if _, ok := assets[name]; !ok {
		return nil, fmt.Errorf("unlisted asset")
	}
	p := filepath.Join(s.root, name)
	before, err := os.Lstat(p)
	if err != nil {
		return nil, err
	}
	if !before.Mode().IsRegular() {
		return nil, fmt.Errorf("asset must be a regular file, not a link or directory")
	}
	f, err := os.Open(p)
	if err != nil {
		return nil, err
	}
	after, err := f.Stat()
	if err != nil || !after.Mode().IsRegular() || !os.SameFile(before, after) {
		f.Close()
		return nil, fmt.Errorf("asset changed while opening")
	}
	return f, nil
}
func (s *assetServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	if r.Host != "localhost:18764" && r.Host != "127.0.0.1:18764" {
		http.Error(w, "Invalid Host", http.StatusForbidden)
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "Only GET and HEAD are supported", http.StatusMethodNotAllowed)
		return
	}
	// Compare exact decoded paths. Never clean or redirect traversal paths.
	name := strings.TrimPrefix(r.URL.Path, "/")
	if r.URL.Path == "/" {
		name = "index.html"
	}
	if r.URL.Path != "/" && r.URL.Path != "/"+name {
		http.NotFound(w, r)
		return
	}
	mime, ok := assets[name]
	if !ok || strings.ContainsAny(name, "/\\") {
		http.NotFound(w, r)
		return
	}
	f, err := s.openAsset(name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		http.Error(w, "Read failed", 500)
		return
	}
	w.Header().Set("Content-Type", mime)
	http.ServeContent(w, r, name, info.ModTime(), f)
}
func listen() (net.Listener, error) { return net.Listen("tcp4", address) }
func openBrowser() error {
	// Fixed literal URL and direct argv, no user-controlled shell interpolation.
	switch runtime.GOOS {
	case "windows":
		return exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", browserURL).Run()
	case "darwin":
		return exec.Command("open", browserURL).Run()
	default:
		return exec.Command("xdg-open", browserURL).Run()
	}
}
func run(out io.Writer, noBrowser bool) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	exe, err = filepath.EvalSymlinks(exe)
	if err != nil {
		return err
	}
	handler, err := newAssetServer(filepath.Dir(exe))
	if err != nil {
		return fmt.Errorf("game files missing or unsafe: %w; place the launcher beside the extracted index.html", err)
	}
	listener, err := listen()
	if err != nil {
		return fmt.Errorf("cannot listen on %s: %w. Close the previous launcher yourself, or resolve the port conflict. No process was stopped; the port will not change", address, err)
	}
	defer listener.Close()
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second}
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	fmt.Fprintln(out, "Game URL:", browserURL, "\nKeep this console open. Press Ctrl+C to stop.\nUse this same localhost URL and browser profile for existing saves.")
	if !noBrowser {
		if err := openBrowser(); err != nil {
			fmt.Fprintln(out, "Browser could not be opened automatically. Open the URL above manually:", err)
		}
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	select {
	case err := <-done:
		if err != http.ErrServerClosed {
			return err
		}
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return server.Shutdown(shutdown)
	}
	return nil
}
func main() {
	noBrowser := flag.Bool("no-browser", false, "serve without opening a browser (for automated checks)")
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "Unexpected arguments")
		os.Exit(2)
	}
	if err := run(os.Stdout, *noBrowser); err != nil {
		fmt.Fprintln(os.Stderr, "Launcher error:", err)
		// Keep a double-clicked Windows console visible on failure.
		if runtime.GOOS == "windows" && !*noBrowser {
			fmt.Fprintln(os.Stderr, "Press Enter to exit.")
			fmt.Scanln()
		}
		os.Exit(1)
	}
}
