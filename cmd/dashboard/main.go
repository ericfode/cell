package main

import (
	"context"
	"database/sql"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

//go:embed templates/*
var templateFS embed.FS

var tmpl *template.Template

func main() {
	dsn := envOr("RETORT_DSN", "root:@tcp(127.0.0.1:3308)/")
	database := envOr("RETORT_DB", "retort")
	addr := envOr("DASHBOARD_ADDR", ":8070")

	db, err := sql.Open("mysql", dsn+database+"?parseTime=true")
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.PingContext(context.Background()); err != nil {
		log.Fatalf("ping: %v", err)
	}

	funcMap := template.FuncMap{
		"json": func(v interface{}) template.JS {
			b, _ := json.Marshal(v)
			return template.JS(b)
		},
		"stateClass": func(s string) string {
			switch s {
			case "frozen":
				return "state-frozen"
			case "computing":
				return "state-computing"
			case "tentative":
				return "state-tentative"
			case "bottom":
				return "state-bottom"
			case "skipped":
				return "state-skipped"
			default:
				return "state-declared"
			}
		},
		"statusClass": func(s string) string {
			switch s {
			case "ready":
				return "status-ready"
			case "running":
				return "status-running"
			case "quiescent":
				return "status-quiescent"
			case "error":
				return "status-error"
			default:
				return "status-loading"
			}
		},
		"truncate": func(n int, s string) string {
			if len(s) <= n {
				return s
			}
			return s[:n] + "..."
		},
	}

	tmpl = template.Must(template.New("").Funcs(funcMap).ParseFS(templateFS, "templates/*.html"))

	hub := &SSEHub{clients: make(map[chan string]struct{})}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", indexHandler(db))
	mux.HandleFunc("GET /api/programs", programsHandler(db))
	mux.HandleFunc("GET /api/cells", cellsHandler(db))
	mux.HandleFunc("GET /api/deps", depsHandler(db))
	mux.HandleFunc("GET /api/trace", traceHandler(db))
	mux.HandleFunc("GET /api/oracles", oraclesHandler(db))
	mux.HandleFunc("GET /api/ready", readyHandler(db))
	mux.HandleFunc("GET /api/evolution", evolutionHandler(db))
	mux.HandleFunc("GET /api/history", historyHandler(db))
	mux.HandleFunc("GET /api/overview", overviewHandler(db))
	mux.HandleFunc("GET /events", sseHandler(hub))

	// Background poller pushes SSE updates
	go poller(db, hub)

	log.Printf("Retort Dashboard listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

// --- SSE Hub ---

type SSEHub struct {
	mu      sync.RWMutex
	clients map[chan string]struct{}
}

func (h *SSEHub) Subscribe() chan string {
	ch := make(chan string, 16)
	h.mu.Lock()
	h.clients[ch] = struct{}{}
	h.mu.Unlock()
	return ch
}

func (h *SSEHub) Unsubscribe(ch chan string) {
	h.mu.Lock()
	delete(h.clients, ch)
	close(ch)
	h.mu.Unlock()
}

func (h *SSEHub) Broadcast(data string) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for ch := range h.clients {
		select {
		case ch <- data:
		default:
		}
	}
}

func sseHandler(hub *SSEHub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming not supported", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")

		ch := hub.Subscribe()
		defer hub.Unsubscribe(ch)

		for {
			select {
			case <-r.Context().Done():
				return
			case msg := <-ch:
				fmt.Fprintf(w, "data: %s\n\n", msg)
				flusher.Flush()
			}
		}
	}
}

func poller(db *sql.DB, hub *SSEHub) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		data, err := buildOverview(db)
		if err != nil {
			continue
		}
		b, _ := json.Marshal(data)
		hub.Broadcast(string(b))
	}
}

// --- Handlers ---

func indexHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		tmpl.ExecuteTemplate(w, "index.html", nil)
	}
}

func overviewHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		data, err := buildOverview(db)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "overview.html", data)
	}
}

func programsHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(),
			`SELECT id, name, COALESCE(source_file,''), status,
			        COALESCE(created_at,''), COALESCE(updated_at,'')
			 FROM programs ORDER BY created_at DESC`)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Program struct {
			ID, Name, SourceFile, Status, CreatedAt, UpdatedAt string
		}
		var programs []Program
		for rows.Next() {
			var p Program
			rows.Scan(&p.ID, &p.Name, &p.SourceFile, &p.Status, &p.CreatedAt, &p.UpdatedAt)
			programs = append(programs, p)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "programs.html", programs)
	}
}

func cellsHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		programID := r.URL.Query().Get("program")
		query := `SELECT c.id, c.name, c.body_type, c.state, c.retry_count, c.max_retries,
		                  COUNT(y.field_name) as yield_count,
		                  COALESCE(SUM(y.is_frozen),0) as frozen_count
		           FROM cells c LEFT JOIN yields y ON c.id = y.cell_id`
		var args []interface{}
		if programID != "" {
			query += ` WHERE c.program_id = ?`
			args = append(args, programID)
		}
		query += ` GROUP BY c.id ORDER BY c.name`

		rows, err := db.QueryContext(r.Context(), query, args...)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Cell struct {
			ID, Name, BodyType, State    string
			RetryCount, MaxRetries       int
			YieldCount, FrozenCount      int
		}
		var cells []Cell
		for rows.Next() {
			var c Cell
			rows.Scan(&c.ID, &c.Name, &c.BodyType, &c.State, &c.RetryCount, &c.MaxRetries,
				&c.YieldCount, &c.FrozenCount)
			cells = append(cells, c)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "cells.html", cells)
	}
}

func depsHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		programID := r.URL.Query().Get("program")
		query := `SELECT g.cell_id, c1.name as consumer, g.param_name,
		                  COALESCE(g.source_cell,'') as source_cell,
		                  COALESCE(c2.name,'') as producer,
		                  COALESCE(g.source_field,'') as source_field,
		                  g.resolved
		           FROM givens g
		           JOIN cells c1 ON g.cell_id = c1.id
		           LEFT JOIN cells c2 ON c2.program_id = c1.program_id AND c2.name = g.source_cell`
		var args []interface{}
		if programID != "" {
			query += ` WHERE c1.program_id = ?`
			args = append(args, programID)
		}
		query += ` ORDER BY c1.name, g.param_name`

		rows, err := db.QueryContext(r.Context(), query, args...)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Dep struct {
			CellID, Consumer, ParamName       string
			SourceCell, Producer, SourceField  string
			Resolved                           bool
		}
		var deps []Dep
		for rows.Next() {
			var d Dep
			rows.Scan(&d.CellID, &d.Consumer, &d.ParamName,
				&d.SourceCell, &d.Producer, &d.SourceField, &d.Resolved)
			deps = append(deps, d)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "deps.html", deps)
	}
}

func traceHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(),
			`SELECT t.step, COALESCE(c.name,'?') as cell_name, t.action,
			        COALESCE(t.duration_ms,0), COALESCE(t.detail,''),
			        COALESCE(t.created_at,'')
			 FROM trace t LEFT JOIN cells c ON t.cell_id = c.id
			 ORDER BY t.step DESC LIMIT 50`)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Trace struct {
			Step                   int
			CellName, Action       string
			DurationMs             int
			Detail, CreatedAt      string
		}
		var traces []Trace
		for rows.Next() {
			var t Trace
			rows.Scan(&t.Step, &t.CellName, &t.Action, &t.DurationMs, &t.Detail, &t.CreatedAt)
			traces = append(traces, t)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "trace.html", traces)
	}
}

func oraclesHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(),
			`SELECT c.name, o.oracle_type, o.assertion, c.state
			 FROM oracles o JOIN cells c ON o.cell_id = c.id
			 ORDER BY c.name, o.ordinal`)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Oracle struct {
			CellName, OracleType, Assertion, CellState string
		}
		var oracles []Oracle
		for rows.Next() {
			var o Oracle
			rows.Scan(&o.CellName, &o.OracleType, &o.Assertion, &o.CellState)
			oracles = append(oracles, o)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "oracles.html", oracles)
	}
}

func readyHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(),
			`SELECT id, name, body_type, state FROM ready_cells ORDER BY name`)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Ready struct {
			ID, Name, BodyType, State string
		}
		var ready []Ready
		for rows.Next() {
			var rc Ready
			rows.Scan(&rc.ID, &rc.Name, &rc.BodyType, &rc.State)
			ready = append(ready, rc)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "ready.html", ready)
	}
}

func evolutionHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(),
			`SELECT e.id, COALESCE(c.name,'?'), e.current_iteration,
			        e.max_iterations, e.status, COALESCE(e.until_expr,'')
			 FROM evolution_loops e
			 LEFT JOIN cells c ON e.target_cell_id = c.id
			 ORDER BY e.status, c.name`)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Evo struct {
			ID, CellName                     string
			CurrentIteration, MaxIterations  int
			Status, UntilExpr                string
		}
		var evos []Evo
		for rows.Next() {
			var e Evo
			rows.Scan(&e.ID, &e.CellName, &e.CurrentIteration, &e.MaxIterations,
				&e.Status, &e.UntilExpr)
			evos = append(evos, e)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "evolution.html", evos)
	}
}

func historyHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(),
			`SELECT message, date FROM dolt_log ORDER BY date DESC LIMIT 20`)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		type Entry struct {
			Message, Date string
		}
		var entries []Entry
		for rows.Next() {
			var e Entry
			rows.Scan(&e.Message, &e.Date)
			entries = append(entries, e)
		}
		w.Header().Set("Content-Type", "text/html")
		tmpl.ExecuteTemplate(w, "history.html", entries)
	}
}

// --- Overview data ---

type Overview struct {
	Programs       int
	TotalCells     int
	FrozenCells    int
	ComputingCells int
	BottomCells    int
	ReadyCells     int
	DeclaredCells  int
	TraceSteps     int
	OracleCount    int
}

func buildOverview(db *sql.DB) (*Overview, error) {
	ctx := context.Background()
	o := &Overview{}

	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM programs`).Scan(&o.Programs)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM cells`).Scan(&o.TotalCells)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM cells WHERE state='frozen'`).Scan(&o.FrozenCells)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM cells WHERE state='computing'`).Scan(&o.ComputingCells)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM cells WHERE state='bottom'`).Scan(&o.BottomCells)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM cells WHERE state='declared'`).Scan(&o.DeclaredCells)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM trace`).Scan(&o.TraceSteps)
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM oracles`).Scan(&o.OracleCount)

	// ready_cells is a view, may fail if no programs loaded
	db.QueryRowContext(ctx, `SELECT COUNT(*) FROM ready_cells`).Scan(&o.ReadyCells)

	return o, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
