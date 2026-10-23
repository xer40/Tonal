# Tonal

**Tonal is a weather-aware AI outfit picker for iOS.** Photograph the clothes you're deciding between, pick an occasion, and Tonal tells you exactly which combination to wear. It checks today's weather, what you've worn recently, and how the colors work together.

The app is native SwiftUI. The backend is Node.js/Express with MongoDB and calls Google's **Gemini 2.5 Flash Lite** vision model to analyze the photos.

---

## Features

| Tab | What it does |
|-----|--------------|
| **Today** | Shows live weather for your location. You pick an occasion (Casual, Work, Going Out, Formal, Gym, Date Night, Beach, Travel), add photos from the camera or library, and tap **Pick My Outfit**. |
| **Result** | Gives a 1–10 rating, a one-line verdict, the pieces to wear, and notes on color, weather and occasion fit, plus one tip to level up the outfit. Shows a rain alert when needed. From here you can **Save** the combo or **Log** it as worn. |
| **Saved** | Outfits you saved. Swipe to delete. |
| **History** | Outfits you logged. Gemini sees the last 7 days so it avoids repeating a look. |
| **Closet** | Optional text-only list of things you own. Gemini can mention one of them as a styling tip, but never puts them in the outfit itself. |

---

## How it works

```
┌────────────┐  GET /api/weather?lat&lon       ┌──────────────┐ ──▶ Open-Meteo (forecast)
│  iOS app   │ ──────────────────────────────▶ │   Express    │
│  SwiftUI   │  POST /api/analyze/:googleId    │   backend    │ ──▶ Gemini 2.5 Flash Lite
│            │  (base64 photos + occasion      │              │
│            │   + weather)                    │              │ ◀─▶ MongoDB (combos, logs,
└────────────┘ ◀── OutfitAnalysis JSON ─────── └──────────────┘      closet, users)
```

1. The app gets your location (the simulator is hardcoded to Los Angeles) and asks the backend for weather. The backend proxies [Open-Meteo](https://open-meteo.com/), which needs no API key.
2. You choose an occasion and add up to 6 library photos plus camera shots.
3. The app sends the photos as base64 JPEGs, along with the occasion and current conditions, to `POST /api/analyze/:googleId`.
4. The backend builds a prompt from the occasion's dress code, the weather rules, your recent outfit history and your closet hints, then sends the prompt and images to Gemini in JSON mode.
5. The backend cleans up the response (see the guardrails below) and returns an `OutfitAnalysis`. The app shows it in the Result sheet.

### Prompt guardrails

These are deliberate. Don't weaken them when you edit the prompt.

- **Literal only.** Gemini may only pick items that are actually visible in the photos. If there's no clothing, it returns `pieces: []` and the app shows "No Clothing Detected".
- **One top, one bottom**, plus at most one outer layer (jacket, coat, etc.), and only when the weather calls for it.
- **Weather rules:**
  - Above 85°F: prefer light colors.
  - Above 95°F: flag dark tops in `weatherCheck`.
  - Rain at or above 50%: recommend a layer or jacket.
  - Below 60°F: recommend layers.
- **Server-side dedup.** After parsing, the server keeps at most one outer layer, one top and one bottom. It matches whole words, so "sweatshirt" isn't read as "sweats" and "laptop" isn't read as "top".
- **One rain threshold (`RAIN_ALERT_THRESHOLD = 50`).** The weather card alert, the prompt and the result's `rainAlert` all use it.

---

## Project structure

```
Tonal/
├── Tonal/                      # iOS app (SwiftUI)
│   ├── TonalApp.swift          # App entry point
│   ├── ContentView.swift       # Tab bar; holds the googleId
│   ├── Models.swift            # WeatherData, OutfitAnalysis, SavedCombo, OutfitLog, ClosetItem, Occasion
│   ├── Services/
│   │   └── APIService.swift    # All backend calls; set baseURL here
│   └── Views/
│       ├── HomeView.swift      # Today tab: weather, occasion, photos, analyze; LocationManager
│       ├── CameraView.swift    # AVFoundation multi-shot camera
│       ├── ResultView.swift    # Outfit result, Save and Log
│       ├── CombosView.swift    # Saved tab
│       ├── LogView.swift       # History tab
│       └── ClosetView.swift    # Closet tab, plus the add-item sheet
├── Tonal.xcodeproj
├── TonalTests/, TonalUITests/  # Xcode template tests (still empty)
└── backend/
    ├── server.js               # Express API: routes, Mongo schemas, Gemini prompt
    ├── package.json
    └── .env.example            # Copy to .env
```

> **Xcode note.** The project uses Xcode 16's synchronized folders (`PBXFileSystemSynchronizedRootGroup`), so every `.swift` file under `Tonal/` compiles automatically. A stray duplicate folder, such as a second `Views/`, causes "duplicate type" or "does not conform to ObservableObject" errors. Check for duplicate folders before you blame the build cache.

---

## Running locally

### Prerequisites
- Xcode 16 or later
- Node.js 18 or later
- A MongoDB connection string (MongoDB Atlas free tier works)
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey)

### 1. Backend
```bash
cd backend
cp .env.example .env      # then fill in MONGODB_URI and GEMINI_API_KEY
npm install
npm run dev               # nodemon restarts on changes; `npm start` runs plain node
```
Check that it's up: `curl http://localhost:3000/api/health` should return `{"status":"ok","app":"Tonal"}`.

### 2. iOS app
1. Open `Tonal.xcodeproj` in Xcode.
2. Set `APIService.baseURL` in `Tonal/Services/APIService.swift`:
   - **Simulator:** `http://localhost:3000`
   - **Real iPhone:** your Mac's LAN IP, e.g. `http://192.168.1.170:3000`. The phone and the Mac must be on the same Wi-Fi network.
3. Build and run. Allow camera and location access when asked.

`Info.plist` sets `NSAllowsArbitraryLoads` so the app can reach a plain-HTTP local backend. Remove it once the backend is deployed behind HTTPS.

---

## API reference

All user data is keyed by `googleId` in the URL. Errors return `{ "error": "message" }` with a 4xx or 5xx status, and the app shows that message.

| Method | Route | Body / query | Returns |
|--------|-------|--------------|---------|
| GET | `/api/health` | — | `{ status, app }` |
| GET | `/api/weather` | `?lat=&lon=` | `WeatherData` (current conditions, next 24 hours, 5 days) |
| POST | `/api/analyze/:googleId` | `{ images: [{base64, mimeType}], occasion, temp, feelsLike, condition, precipChance, humidity, windSpeed }` | `{ analysis: OutfitAnalysis }` |
| GET | `/api/combos/:googleId` | — | `{ combos }` |
| POST | `/api/combos/:googleId` | `{ pieces, occasion, weather, verdict, colorAnalysis, rating, notes }` | `{ combo }` |
| DELETE | `/api/combos/:googleId/:comboId` | — | `{ success }` |
| GET | `/api/logs/:googleId` | — | `{ logs }` |
| POST | `/api/logs/:googleId` | `{ pieces, occasion, weather, notes }` | `{ log }` |
| GET | `/api/closet/:googleId` | — | `{ items }` |
| POST | `/api/closet/:googleId` | `{ name, type, color, description }` | `{ item }` |
| DELETE | `/api/closet/:googleId/:itemId` | — | `{ success }` |
| POST | `/api/auth/google` | `{ googleId, name, email, picture }` | `{ user }` (upserts the user; not called by the app yet) |
| GET | `/api/auth/user/:googleId` | — | `{ user }` |

`OutfitAnalysis` has this shape:
```json
{
  "pieces": ["white linen shirt", "navy chinos", "white sneakers"],
  "rating": 8,
  "verdict": "…",
  "colorAnalysis": "…",
  "weatherCheck": "…",
  "occasionFit": "…",
  "elevationTip": "…",
  "tips": ["…", "…"],
  "rainAlert": false
}
```

---

## Environment variables (`backend/.env`)

| Variable | Required | Purpose |
|----------|----------|---------|
| `MONGODB_URI` | yes | MongoDB connection string |
| `GEMINI_API_KEY` | yes | Google Gemini API key |
| `PORT` | no | Defaults to `3000` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | not yet | Reserved for Google Sign-In |

---

## Status and roadmap

**Done**
- Photo analysis with Gemini, with guardrails against made-up items and duplicate pieces and with weather rules
- Live weather (Open-Meteo) with rain alerts
- Saved combos, outfit history (fed back into the prompt) and the text closet
- Multi-shot camera and library picker
- Error states across the app: unreachable server, failed save, denied location

**Next**
1. **Google Sign-In.** Replace the hardcoded `googleId = "dev-user-001"` in `ContentView.swift`. The backend should then verify a Google ID token on each request instead of trusting the `googleId` in the URL. Right now anyone who knows an ID can read or write that user's data.
2. **Deploy the backend** (Railway is the plan) so the app works without a Mac running on the same network. Then point `baseURL` at the HTTPS URL and remove `NSAllowsArbitraryLoads`.
3. **Tests.** The Xcode test targets are still the empty templates.

---

## History

The backend started as the Express server of an earlier web project, **Bring An Umbrella** ([xer40/Bring-An-Umbrella](https://github.com/xer40/Bring-An-Umbrella)), and was reworked for Tonal. It now lives in this repo under `backend/`.
