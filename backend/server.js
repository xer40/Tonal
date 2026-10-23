import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import fetch from 'node-fetch';
import mongoose from 'mongoose';

const app = express();
const PORT = process.env.PORT || 3000;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const RAIN_ALERT_THRESHOLD = 50; // % chance — shared by /api/weather and the analyze prompt

app.use(cors());
app.use(express.json({ limit: '20mb' })); // larger limit for base64 images

// ─── Connect to MongoDB ───────────────────────────────────────────────────────
mongoose.connect(process.env.MONGODB_URI)
  .then(() => console.log('✅ Connected to MongoDB'))
  .catch(err => console.error('❌ MongoDB connection error:', err));

// ─── Schemas & Models ─────────────────────────────────────────────────────────
const userSchema = new mongoose.Schema({
  googleId: { type: String, required: true, unique: true },
  name: String, email: String, picture: String,
  createdAt: { type: Date, default: Date.now }
});

// Optional closet — text-only, no images, used as hints for Gemini
const closetItemSchema = new mongoose.Schema({
  googleId: { type: String, required: true },
  name: { type: String, required: true },
  type: String,
  color: String,
  description: String,
  addedAt: { type: Date, default: Date.now }
});

// Saved combos the user liked
const savedComboSchema = new mongoose.Schema({
  googleId: { type: String, required: true },
  date: { type: Date, default: Date.now },
  pieces: [String],       // text descriptions of each piece Gemini identified
  occasion: String,
  weather: Object,
  verdict: String,        // Gemini's one-line summary
  colorAnalysis: String,
  rating: Number,
  notes: String
});

// Outfit history for repetition awareness
const outfitLogSchema = new mongoose.Schema({
  googleId: { type: String, required: true },
  date: { type: Date, default: Date.now },
  pieces: [String],
  occasion: String,
  weather: Object,
  notes: String
});

const User = mongoose.model('User', userSchema);
const ClosetItem = mongoose.model('ClosetItem', closetItemSchema);
const SavedCombo = mongoose.model('SavedCombo', savedComboSchema);
const OutfitLog = mongoose.model('OutfitLog', outfitLogSchema);

// ─── Auth Routes ──────────────────────────────────────────────────────────────
app.post('/api/auth/google', async (req, res) => {
  const { googleId, name, email, picture } = req.body;
  if (!googleId) return res.status(400).json({ error: 'googleId is required' });
  try {
    let user = await User.findOne({ googleId });
    if (!user) {
      user = await User.create({ googleId, name, email, picture });
      console.log(`👤 New user: ${name}`);
    }
    res.json({ user });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Auth failed' });
  }
});

app.get('/api/auth/user/:googleId', async (req, res) => {
  try {
    const user = await User.findOne({ googleId: req.params.googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ user });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// ─── Weather Routes ───────────────────────────────────────────────────────────
app.get('/api/weather', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon are required' });
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,precipitation_probability,weathercode,windspeed_10m,relative_humidity_2m&hourly=temperature_2m,precipitation_probability,weathercode&daily=temperature_2m_max,temperature_2m_min,weathercode,precipitation_probability_max&temperature_unit=fahrenheit&windspeed_unit=mph&precipitation_unit=inch&forecast_days=5&timezone=auto`;
    const response = await fetch(url);
    const data = await response.json();
    const current = data.current;
    const condition = interpretWeatherCode(current.weathercode);

    const now = new Date();
    const hourly = data.hourly.time
      .map((time, i) => ({
        time,
        hour: new Date(time).getHours(),
        temperature: Math.round(data.hourly.temperature_2m[i]),
        precipitationChance: data.hourly.precipitation_probability[i],
        condition: interpretWeatherCode(data.hourly.weathercode[i]),
      }))
      .filter(h => new Date(h.time) >= now)
      .slice(0, 24);

    const daily = data.daily.time.map((date, i) => ({
      date,
      high: Math.round(data.daily.temperature_2m_max[i]),
      low: Math.round(data.daily.temperature_2m_min[i]),
      condition: interpretWeatherCode(data.daily.weathercode[i]),
      precipitationChance: data.daily.precipitation_probability_max[i],
    }));

    res.json({
      temperature: Math.round(current.temperature_2m),
      feelsLike: Math.round(current.apparent_temperature),
      precipitationChance: current.precipitation_probability,
      windSpeed: Math.round(current.windspeed_10m),
      humidity: current.relative_humidity_2m,
      condition,
      rainAlert: current.precipitation_probability >= RAIN_ALERT_THRESHOLD,
      unit: 'F',
      hourly,
      daily,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch weather data' });
  }
});

function interpretWeatherCode(code) {
  if (code === null || code === undefined) return 'Partly Cloudy';
  if (code === 0) return 'Clear';
  if (code <= 3) return 'Partly Cloudy';
  if (code <= 39) return 'Partly Cloudy';
  if (code <= 49) return 'Foggy';
  if (code <= 59) return 'Drizzle';
  if (code <= 69) return 'Rainy';
  if (code <= 79) return 'Snowy';
  if (code <= 84) return 'Showers';
  if (code <= 99) return 'Stormy';
  return 'Partly Cloudy';
}

// ─── Core Tonal Route — Analyze Outfit from Camera Photos ────────────────────
// POST /api/analyze/:googleId
// Body: { images: [{base64, mimeType}], occasion, temp, feelsLike,
//         condition, precipChance, humidity, windSpeed }
// Returns: style verdict, color analysis, weather check, rating, tips
app.post('/api/analyze/:googleId', async (req, res) => {
  const { googleId } = req.params;
  const {
    images, occasion,
    temp, feelsLike, condition, precipChance, humidity, windSpeed
  } = req.body;

  if (!images || images.length === 0) {
    return res.status(400).json({ error: 'At least one image is required' });
  }

  try {
    const hour = new Date().getHours();
    const timeOfDay = hour < 12 ? 'morning' : hour < 17 ? 'afternoon' : 'evening';

    // Recent outfit history so Gemini avoids flagging the same look twice
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const recentLogs = await OutfitLog.find({
      googleId,
      date: { $gte: sevenDaysAgo }
    }).sort({ date: -1 }).limit(5);

    const recentHistory = recentLogs.length > 0
      ? recentLogs.map(log => {
          const daysAgo = Math.floor((Date.now() - new Date(log.date)) / (1000 * 60 * 60 * 24));
          const label = daysAgo === 0 ? 'today' : daysAgo === 1 ? 'yesterday' : `${daysAgo} days ago`;
          return `- ${label}: ${log.pieces.join(', ')}${log.occasion ? ` (${log.occasion})` : ''}`;
        }).join('\n')
      : null;

    // Optional closet items as enhancement hints
    const closetItems = await ClosetItem.find({ googleId });
    const closetHints = closetItems.length > 0
      ? `\nCLOSET HINTS — the user owns these items but did NOT photograph them. Never put them in "pieces"; you may only mention one in "elevationTip":\n${closetItems.map(i => `- ${i.name}${i.color ? ` (${i.color})` : ''}${i.description ? `: ${i.description}` : ''}`).join('\n')}`
      : '';

    const prompt = `You are Tonal — a sharp, fashion-forward AI style consultant. The user has photographed items they are considering wearing today. Your job is to ONLY work with what is literally visible in the photos — do NOT invent, assume, or suggest any items that are not actually shown. If the photos do not contain clothing, say so honestly. If you can see clothing, pick the best outfit from exactly those visible pieces.

OCCASION: ${occasion || 'Casual'}
Dress code for this occasion:
- Casual: effortless, relaxed everyday wear
- Work: polished and professional — no athletic wear
- Going Out: stylish, trendy, evening-appropriate
- Formal: elegant and elevated — no sneakers or overly casual pieces
- Gym: functional and athletic — performance first
- Date Night: attractive, intentional, put-together
- Beach: light, breezy, summer-appropriate
- Travel: comfortable, practical, easy to move in

WEATHER RULES (follow strictly):
- Above 85°F: strongly prefer light colors (white, grey, pastels) — avoid black or dark tops that absorb heat
- Above 95°F: dark tops are a bad choice regardless of style — flag this in weatherCheck
- Rain chance ${RAIN_ALERT_THRESHOLD}% or higher: recommend layers or a jacket
- Below 60°F: recommend layers

WEATHER RIGHT NOW:
- Temperature: ${temp}°F (feels like ${feelsLike || temp}°F)
- Condition: ${condition}
- Rain chance: ${precipChance}%
- Humidity: ${humidity}%
- Wind: ${windSpeed} mph
- Time of day: ${timeOfDay}
${recentHistory ? `\nRECENT OUTFIT HISTORY (avoid recommending a very similar look to these):\n${recentHistory}` : ''}
${closetHints}

YOUR TASK:
1. IDENTIFY ALL PIECES — Mentally note every clothing item you see, but do NOT list them all in your response.
2. PICK THE BEST OUTFIT — Choose ONLY from clothing items literally visible in the photos. Pick exactly ONE top and ONE bottom — never two bottoms, never two tops. If you see multiple shorts or multiple shirts, pick the single best one and ignore the rest. You may add at most ONE outer layer (jacket, coat, etc.) only if one is visible in the photos and the weather calls for it. If no clothing is visible, set "pieces" to [] and explain in "verdict".
3. EXPLAIN THE COLORS — How do the chosen pieces work together? What makes this palette work?
4. WEATHER CHECK — Why is this combination right for the current conditions?
5. OCCASION FIT — Why does this combination nail the ${occasion || 'casual'} vibe?
6. LEVEL IT UP — One specific accessory or styling tweak to make this outfit even better.
7. RATE IT — Give an honest 1–10 for the chosen combination.

Be direct and confident. Don't hedge — tell them exactly what to wear.

Respond ONLY with valid JSON, no markdown fences:
{
  "pieces": ["chosen top", "chosen bottom", "shoes if visible", "accessories if visible — only items you are recommending, never rejected pieces"],
  "rating": 8,
  "verdict": "One punchy sentence — what you picked and why it works",
  "colorAnalysis": "How the colors of the chosen pieces work together",
  "weatherCheck": "Why this combination suits the current weather",
  "occasionFit": "Why this nails the occasion",
  "elevationTip": "One specific styling tweak to make it even better",
  "tips": ["specific tip 1", "specific tip 2"],
  "rainAlert": ${parseInt(precipChance) >= RAIN_ALERT_THRESHOLD ? 'true' : 'false'}
}`;

    // Build multimodal parts — prompt first, then all images
    const parts = [{ text: prompt }];
    for (const img of images) {
      parts.push({
        inline_data: {
          mime_type: img.mimeType || 'image/jpeg',
          data: img.base64
        }
      });
    }

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts }],
          generationConfig: { temperature: 0.7, maxOutputTokens: 800, responseMimeType: 'application/json' }
        })
      }
    );

    const geminiData = await geminiRes.json();
    const rawText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text || '';
    console.log('🎨 Tonal analysis:', rawText.slice(0, 200));

    if (!rawText) {
      console.error('❌ Gemini empty response:', JSON.stringify(geminiData, null, 2));
      throw new Error('Empty response from Gemini');
    }

    const cleaned = rawText.replace(/```json|```/g, '').trim();
    const analysis = JSON.parse(cleaned);

    // Guard: keep at most one outer layer, one top, and one bottom if Gemini picks more.
    // Whole-word matching so e.g. "sweatshirt" isn't read as "sweats" or "laptop" as "top".
    const categories = [
      { name: 'outer', words: ['jacket', 'coat', 'blazer', 'cardigan', 'windbreaker', 'parka', 'raincoat', 'overshirt'] },
      { name: 'bottom', words: ['shorts', 'pants', 'jeans', 'chinos', 'trousers', 'skirt', 'leggings', 'sweats', 'sweatpants', 'joggers'] },
      { name: 'top', words: ['shirt', 't-shirt', 'tee', 'top', 'blouse', 'hoodie', 'sweater', 'sweatshirt', 'polo', 'tank', 'henley'] }
    ];
    const hasWord = (text, word) => new RegExp(`\\b${word}s?\\b`).test(text);
    const counts = {};
    if (Array.isArray(analysis.pieces)) {
      analysis.pieces = analysis.pieces.filter(piece => {
        const p = String(piece).toLowerCase();
        const category = categories.find(c => c.words.some(w => hasWord(p, w)));
        if (!category) return true;
        counts[category.name] = (counts[category.name] || 0) + 1;
        return counts[category.name] <= 1;
      });
    } else {
      analysis.pieces = [];
    }

    res.json({ analysis });
  } catch (err) {
    console.error('Analysis error:', err);
    res.status(500).json({ error: 'Failed to analyze outfit. Gemini may be busy — try again in a moment.' });
  }
});

// ─── Saved Combos ─────────────────────────────────────────────────────────────
app.get('/api/combos/:googleId', async (req, res) => {
  try {
    const combos = await SavedCombo.find({ googleId: req.params.googleId }).sort({ date: -1 });
    res.json({ combos });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch saved combos' });
  }
});

app.post('/api/combos/:googleId', async (req, res) => {
  const { googleId } = req.params;
  const { pieces, occasion, weather, verdict, colorAnalysis, rating, notes } = req.body;
  try {
    const combo = await SavedCombo.create({
      googleId,
      pieces: pieces || [],
      occasion: occasion || '',
      weather: weather || {},
      verdict: verdict || '',
      colorAnalysis: colorAnalysis || '',
      rating: rating || null,
      notes: notes || ''
    });
    res.status(201).json({ combo });
  } catch (err) {
    res.status(500).json({ error: 'Failed to save combo' });
  }
});

app.delete('/api/combos/:googleId/:comboId', async (req, res) => {
  const { googleId, comboId } = req.params;
  try {
    await SavedCombo.findOneAndDelete({ _id: comboId, googleId });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete combo' });
  }
});

// ─── Outfit Log Routes ────────────────────────────────────────────────────────
app.get('/api/logs/:googleId', async (req, res) => {
  try {
    const logs = await OutfitLog.find({ googleId: req.params.googleId }).sort({ date: -1 });
    res.json({ logs });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch logs' });
  }
});

app.post('/api/logs/:googleId', async (req, res) => {
  const { googleId } = req.params;
  const { pieces, weather, notes, occasion } = req.body;
  try {
    const log = await OutfitLog.create({
      googleId,
      pieces: pieces || [],
      occasion: occasion || '',
      weather: weather || {},
      notes: notes || ''
    });
    res.status(201).json({ log });
  } catch (err) {
    res.status(500).json({ error: 'Failed to save log' });
  }
});

// ─── Optional Closet (text-only, no images) ───────────────────────────────────
app.get('/api/closet/:googleId', async (req, res) => {
  try {
    const items = await ClosetItem.find({ googleId: req.params.googleId });
    res.json({ items });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch closet' });
  }
});

app.post('/api/closet/:googleId', async (req, res) => {
  const { googleId } = req.params;
  const { name, type, color, description } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  try {
    const item = await ClosetItem.create({ googleId, name, type, color, description });
    res.status(201).json({ item });
  } catch (err) {
    res.status(500).json({ error: 'Failed to add item' });
  }
});

app.delete('/api/closet/:googleId/:itemId', async (req, res) => {
  const { googleId, itemId } = req.params;
  try {
    await ClosetItem.findOneAndDelete({ _id: itemId, googleId });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete item' });
  }
});

// ─── Health Check ─────────────────────────────────────────────────────────────
app.get('/api/health', (req, res) => res.json({ status: 'ok', app: 'Tonal' }));

app.listen(PORT, () => {
  console.log(`🎨 Tonal backend running on http://localhost:${PORT}`);
});
