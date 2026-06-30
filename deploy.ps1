# ─────────────────────────────────────────────────────────────────────────────
# deploy.ps1 — byg web-release (med Supabase-nøgler) og deploy til Vercel (prod)
# Brug:  .\deploy.ps1
# Forudsætning: 'vercel login' + første 'vercel --prod' i build\web er kørt ÉN gang.
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
$flutter = 'C:\src\flutter\bin\flutter.bat'

Set-Location $PSScriptRoot
# --wasm: bygger med WebAssembly (skwasm) for hurtigste grafik-performance.
# Flutter laver automatisk et JS-fallback til browsere uden WasmGC (fx ældre
# iOS < 18.2), så det er sikkert at slå til. Ingen server-header-krav for
# single-threaded skwasm. (Vil du teste uden wasm: fjern --wasm igen.)
Write-Host '==> Bygger web-release (WebAssembly)...' -ForegroundColor Cyan
& $flutter build web --release --wasm --dart-define-from-file=dart_defines.json

# Sørg for at vercel.json (HTTP cache-headers) altid er med i build-output,
# så browseren tvinges til at gen-tjekke bootstrap-filerne ved hver udrulning.
Copy-Item (Join-Path $PSScriptRoot 'web\vercel.json') `
          (Join-Path $PSScriptRoot 'build\web\vercel.json') -Force

Set-Location (Join-Path $PSScriptRoot 'build\web')
Write-Host '==> Deployer til Vercel (production)...' -ForegroundColor Cyan
vercel --prod
