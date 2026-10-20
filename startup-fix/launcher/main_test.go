package main

import (
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T) (*assetServer, string) {
	t.Helper()
	root := t.TempDir()
	for name := range assets {
		if err := os.WriteFile(filepath.Join(root, name), []byte("asset:"+name), 0600); err != nil {
			t.Fatal(err)
		}
	}
	s, err := newAssetServer(root)
	if err != nil {
		t.Fatal(err)
	}
	return s, root
}
func request(s *assetServer, method, path, host string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "http://localhost:18764"+path, nil)
	r.Host = host
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}
func TestWhitelistAndMIME(t *testing.T) {
	s, root := fixture(t)
	os.WriteFile(filepath.Join(root, "secret.txt"), []byte("private"), 0600)
	for name, mime := range assets {
		w := request(s, "GET", "/"+name, "localhost:18764")
		if w.Code != 200 || w.Header().Get("Content-Type") != mime || w.Body.String() != "asset:"+name {
			t.Fatalf("%s: %d %s", name, w.Code, w.Body.String())
		}
	}
	for _, path := range []string{"/secret.txt", "/go.mod", "/main.go", "/missing", "/sub/", "//index.html", "/./index.html", "/../index.html", "/%2e%2e/index.html", "/%2e/index.html", "/..%2findex.html", "/..%5cindex.html", "/index.html/", "/INDEX.HTML"} {
		if w := request(s, "GET", path, "localhost:18764"); w.Code != 404 {
			t.Errorf("path %q got %d", path, w.Code)
		}
	}
	for _, path := range []string{"/", "/index.html?cache=123", "/index.wasm?path=../secret.txt"} {
		if w := request(s, "GET", path, "localhost:18764"); w.Code != 200 {
			t.Errorf("query/root %q got %d", path, w.Code)
		}
	}
}
func TestMethodsHostsHeaders(t *testing.T) {
	s, _ := fixture(t)
	for _, method := range []string{"POST", "PUT", "DELETE", "OPTIONS", "PATCH", "CONNECT", "TRACE"} {
		w := request(s, method, "/", "localhost:18764")
		if w.Code != 405 || w.Header().Get("Allow") != "GET, HEAD" {
			t.Errorf("method %s: %d", method, w.Code)
		}
	}
	for _, host := range []string{"evil.example:18764", "localhost", "localhost:80", "127.0.0.1:80", "localhost:18764.evil", "[::1]:18764", ""} {
		if w := request(s, "GET", "/", host); w.Code != 403 {
			t.Errorf("host %q: %d", host, w.Code)
		}
	}
	for _, host := range []string{"localhost:18764", "127.0.0.1:18764"} {
		w := request(s, "HEAD", "/index.wasm", host)
		if w.Code != 200 || w.Body.Len() != 0 || w.Header().Get("Content-Length") == "" {
			t.Errorf("HEAD %s: %d", host, w.Code)
		}
		for h, v := range map[string]string{"X-Content-Type-Options": "nosniff", "Cache-Control": "no-store"} {
			if w.Header().Get(h) != v {
				t.Errorf("header %s", h)
			}
		}
	}
}
func TestNoLinksOrDirectories(t *testing.T) {
	s, root := fixture(t)
	target := filepath.Join(t.TempDir(), "private")
	os.WriteFile(target, []byte("private"), 0600)
	p := filepath.Join(root, "index.png")
	os.Remove(p)
	if err := os.Symlink(target, p); err != nil {
		t.Logf("symlink creation unavailable: %v", err)
	} else {
		if w := request(s, "GET", "/index.png", "localhost:18764"); w.Code != 404 {
			t.Fatalf("symlink exposed: %d", w.Code)
		}
		os.Remove(p)
	}
	if err := os.Mkdir(p, 0700); err != nil {
		t.Fatal(err)
	}
	if w := request(s, "GET", "/index.png", "localhost:18764"); w.Code != 404 {
		t.Fatalf("directory exposed: %d", w.Code)
	}
}
func TestRequiredValidation(t *testing.T) {
	_, root := fixture(t)
	os.Remove(filepath.Join(root, "index.wasm"))
	if _, err := newAssetServer(root); err == nil || !strings.Contains(err.Error(), "index.wasm") {
		t.Fatalf("expected missing wasm error: %v", err)
	}
}
func TestPortConflict(t *testing.T) {
	l, err := listen()
	if err != nil {
		t.Fatalf("test requires free %s: %v", address, err)
	}
	defer l.Close()
	if a, ok := l.Addr().(*net.TCPAddr); !ok || a.IP.String() != "127.0.0.1" || a.Port != 18764 {
		t.Fatalf("unexpected address: %s", l.Addr())
	}
	second, err := listen()
	if err == nil {
		second.Close()
		t.Fatal("second listener must fail; no fallback port allowed")
	}
}
func TestRange(t *testing.T) {
	s, _ := fixture(t)
	r := httptest.NewRequest(http.MethodGet, browserURL+"index.wasm", nil)
	r.Header.Set("Range", "bytes=0-4")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 206 || w.Body.String() != "asset" {
		t.Fatalf("range: %d %q", w.Code, w.Body.String())
	}
}
