# Dhwani (ಧ್ವನಿ) - "Your voice. Your shop."

> **Voice-first micro-commerce & lender-ready business passports for women and micro-entrepreneurs across Karnataka (Bengaluru, Hubballi-Dharwad, Mysuru, Belagavi, Mangaluru, Kalaburagi, Shivamogga, Udupi, and all districts).**

---

## 🌟 The Problem & Solution

Across **all 31 districts of Karnataka**, thousands of women and micro-entrepreneurs run home kitchens, craft workshops, tailoring boutiques, tech & digital consulting, and local services through WhatsApp and word of mouth. They encounter major systemic barriers:
- **No GST Registration** required to begin micro-selling.
- **No Product Photography** studio or cataloguing tools.
- **No Complex Returns Process** or high marketplace commissions.
- **No App Installation Friction** for either sellers or neighborhood buyers.
- **No Credit Access** because informal transactions leave no formal ledger.

**Dhwani (ಧ್ವನಿ = voice)** solves this in **under 60 seconds**:
1. **Interactive Voice Studio & Smart Item Extractor (`#/sell`):** Starts with a clean slate. The seller speaks or types in **Kannada (ಕನ್ನಡ), English, or Hindi (हिन्दी)**. The smart adaptive NLP engine extracts the exact business type (Food, Tech/Software, Tailoring, Crafts, Organic Produce) and products/services into an interactive visual customizer.
2. **Direct Bank UPI:** Customers pay directly to her personal Google Pay, PhonePe, or BHIM UPI ID with zero platform cuts.
3. **The Business Passport (Second Hook):** Every order writes to a verified transaction ledger, calculating a transparent **0-100 Consistency Score** (40% active-weeks ratio, 25% sales volume, 20% repeat buyers, 15% quarterly growth) with a printable, bank-ready PDF profile to unlock micro-credit.

---

## 🚀 Key Updates & Highlights

- **100% Consistent Trilingual Localization:** Strict language consistency across every single screen, navigation bar, filter chip, placeholder, status badge, modal, and receipt in **Kannada**, **English**, and **Hindi**.
- **Statewide Karnataka Scope:** Built-in district filtering and seed sellers covering Bengaluru Urban, Hubballi-Dharwad, Mysuru, Belagavi, Mangaluru, Kalaburagi, Shivamogga, Udupi, Bagalkote, and more.
- **Adaptive Multi-Domain Voice Parser:** Accurately parses food, bakery, organic farming, handicrafts, software & tech services, catering, and bespoke tailoring without forcing hardcoded snack fallbacks.
- **Single-File Front End (`index.html`):** 100% self-contained vanilla HTML/JS/CSS without any build step or bundler.
- **Dual Operating Modes:**
  - **Live Mode:** Powered by Supabase (Postgres, Realtime, Storage, Edge Functions).
  - **Demo Mode:** Zero-config fallback with seeded Karnataka sellers, 12 weeks of historical order ledgers, and cross-tab/cross-window event streaming via `BroadcastChannel` and `localStorage`.

---

## 🛠️ Step-by-Step Setup Guide

### 1. Run Locally in 5 Seconds (Demo Mode)
No build step or server is needed. Simply open `index.html` directly in Google Chrome or serve it via any static local server (e.g. XAMPP, Live Server, or Python HTTP server):

```bash
# Optional local test server
python -m http.server 8000
```
Open `http://localhost:8000` (or `http://localhost/dhwani/` in XAMPP) in your browser.

---

### 2. Configure Live Supabase Backend

#### Step A: Create a Supabase Project
1. Go to [supabase.com](https://supabase.com) and create a new project.
2. Copy your **Project URL** and **Anon Public Key** from `Project Settings > API`.

#### Step B: Execute Database Schema & Seed Data
1. Navigate to the **SQL Editor** in your Supabase dashboard.
2. Open [`supabase/schema.sql`](file:///c:/xampp/htdocs/dhwani/supabase/schema.sql) and paste its contents into the SQL Editor.
3. Click **Run**. This will create the `sellers`, `listings`, `orders` tables, enable Row Level Security, configure Realtime replication, and seed Karnataka sellers with 12 weeks of historical order history.

#### Step C: Deploy the Edge Function (`parse-listing`)
1. Install the Supabase CLI if you haven't already:
   ```bash
   npm install -g supabase
   ```
2. Login and link your project:
   ```bash
   supabase login
   supabase link --project-ref <your-project-id>
   ```
3. Set your LLM API Key secret:
   ```bash
   supabase secrets set LLM_API_KEY=your_gemini_or_openai_api_key
   ```
4. Deploy the function:
   ```bash
   supabase functions deploy parse-listing
   ```

#### Step D: Update `index.html` Configuration
Open `index.html` and update the top configuration block:
```html
<script>
  window.DHWANI_CONFIG = {
    SUPABASE_URL: "https://<your-project-id>.supabase.co",
    SUPABASE_ANON_KEY: "<your-anon-public-key>",
  };
</script>
```

---

## 🎬 3-Minute Live Presentation Demo Script

| Time | Screen | Action & Talk Track |
|---|---|---|
| **0:00 - 0:40** | `#/` Landing | Show the problem: Karnataka micro-entrepreneurs have no GST or app. Switch language between **English**, **ಕನ್ನಡ**, and **हिन्दी** to demonstrate 100% consistent localization. Tap **"Open Store with Voice"**. |
| **0:40 - 1:30** | `#/sell` Voice Studio | **The WOW Moment:** Start on a clean slate. Speak or type: *"Bengaluru Fresh Ragi Brownies 320 rupees box, and Filter Coffee Powder 220 rupees pack"* or *"Custom Web Development Service 2500 rupees"*. Watch the live NLP extractor parse the actual items into an editable customizer! Add custom items, set your UPI ID & district, and tap **"Publish Storefront"** to trigger confetti and generate the WhatsApp share link & QR code! |
| **1:30 - 2:15** | `#/demo` Dual Phone Live Sync | Open the **⚡ Live Demo** view. On the right (Buyer Phone), tap **"Order 1-Tap"**. Instantly watch the left (Seller Phone) **ding with an incoming order chime and live order card**! Progress the order status: `New` ➔ `Paid` ➔ `Ready` ➔ `Delivered`. |
| **2:15 - 3:00** | `#/passport/renuka-holige` Business Passport | Navigate to the **Business Passport**. Highlight the **94/100 Consistency Score**, the 12-week sales chart, and the mathematical formula breakdown. Tap **"Download PDF"** to demonstrate the clean print-ready financial certificate for bank loans. |
