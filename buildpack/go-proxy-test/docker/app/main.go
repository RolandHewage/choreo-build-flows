package main

import (
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Go proxy E2E test — build succeeded!")
	})
	fmt.Println("Go proxy E2E test — build succeeded!")
	fmt.Println("  chi version: v5")
	http.ListenAndServe(":8080", r)
}
