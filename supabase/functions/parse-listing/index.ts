// ====================================================================
// DHWANI (ಧ್ವನಿ) - SUPABASE EDGE FUNCTION: parse-listing
// "Your voice. Your shop." - Karnataka Statewide Micro-Commerce
// ====================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface RequestPayload {
  transcript: string;
  language?: string;
  seller_name?: string;
  district?: string;
}

interface ParsedItem {
  title: string;
  price: number;
  unit: string;
  category: string;
  description_local: string;
  description_en: string;
}

interface ExtractionResult {
  shop_name: string;
  category: string;
  district: string;
  bio: string;
  items: ParsedItem[];
  theme_color?: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { transcript, language = "kn-IN", seller_name, district } = (await req.json()) as RequestPayload;

    if (!transcript || transcript.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Missing or empty transcript" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const apiKey =
      Deno.env.get("LLM_API_KEY") ||
      Deno.env.get("GEMINI_API_KEY") ||
      Deno.env.get("OPENAI_API_KEY");

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);

    const systemPrompt = `You are the AI extraction engine for "Dhwani" (ಧ್ವನಿ), a voice-first micro-commerce platform for women and micro-entrepreneurs across all districts of Karnataka, India.
The user is speaking or typing a description of their business, products, or services in Kannada, Kanglish, Hindi, or English.
Parse the transcript into a structured storefront and catalogue matching their exact spoken intent.

Schema:
{
  "shop_name": "Catchy shop title reflecting their actual business",
  "category": "One of: Sweets & Snacks | Masalas & Podis | Tiffin & Meals | Home Bakery | Handicrafts & Tailoring | Organic Produce | Dairy & Ghee | Tech & Digital Services | Custom Services",
  "district": "Karnataka District if mentioned (e.g., Bengaluru, Hubballi-Dharwad, Mysuru, Belagavi, Mangaluru, Kalaburagi, Shivamogga, Udupi, Bagalkote) or sensible default",
  "bio": "Warm 1-sentence bio describing their specialty",
  "theme_color": "Hex color matching category (e.g. #1F5E4B, #E8A317, #C8553D, #0284C7, #7E22CE)",
  "items": [
    {
      "title": "Clear item/service name",
      "price": 250,
      "unit": "e.g., kg, pack of 10, piece, hour, project, jar, month",
      "category": "Matching category",
      "description_local": "Short appealing 1-line description in local language",
      "description_en": "Short appealing 1-line description in English"
    }
  ]
}

CRITICAL:
1. Return ONLY pure valid JSON. No markdown fences.
2. If user describes a service (e.g. software, tailoring, catering), extract their actual service items.
3. Extract realistic prices or set a sensible default if unmentioned.`;

    const userPrompt = `Transcript: "${transcript}"\nLanguage: ${language}\nSeller Name: ${seller_name || "Self"}\nDistrict: ${district || "Karnataka"}`;

    let parsedResult: ExtractionResult;

    if (apiKey) {
      try {
        const isGemini = apiKey.startsWith("AIza") || !!Deno.env.get("GEMINI_API_KEY");
        const endpoint = isGemini
          ? `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`
          : "https://api.openai.com/v1/chat/completions";

        let responseText = "";
        if (isGemini) {
          const res = await fetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ role: "user", parts: [{ text: `${systemPrompt}\n\n${userPrompt}` }] }],
              generationConfig: { response_mime_type: "application/json", temperature: 0.2 },
            }),
            signal: controller.signal,
          });
          const json = await res.json();
          responseText = json.candidates?.[0]?.content?.parts?.[0]?.text || "{}";
        } else {
          const res = await fetch(endpoint, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
              model: "gpt-4o-mini",
              messages: [
                { role: "system", content: systemPrompt },
                { role: "user", content: userPrompt },
              ],
              response_format: { type: "json_object" },
              temperature: 0.2,
            }),
            signal: controller.signal,
          });
          const json = await res.json();
          responseText = json.choices?.[0]?.message?.content || "{}";
        }

        clearTimeout(timeoutId);
        const cleanJson = responseText.replace(/```json/gi, "").replace(/```/g, "").trim();
        parsedResult = JSON.parse(cleanJson);
      } catch (err) {
        clearTimeout(timeoutId);
        parsedResult = parseAdaptiveListing(transcript, seller_name, district);
      }
    } else {
      clearTimeout(timeoutId);
      parsedResult = parseAdaptiveListing(transcript, seller_name, district);
    }

    if (!parsedResult.items || !Array.isArray(parsedResult.items) || parsedResult.items.length === 0) {
      parsedResult = parseAdaptiveListing(transcript, seller_name, district);
    }

    return new Response(JSON.stringify({ success: true, data: parsedResult }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error: any) {
    return new Response(
      JSON.stringify({ success: false, error: error.message || "Failed to parse listing" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// Adaptive NLP Parser supporting arbitrary businesses (Food, Tech, Crafts, Services)
function parseAdaptiveListing(text: string, sellerName?: string, defaultDistrict?: string): ExtractionResult {
  const clean = text.toLowerCase().trim();
  const items: ParsedItem[] = [];

  // Detect domain
  let category = "Sweets & Snacks";
  let themeColor = "#1F5E4B";
  let shopTitle = sellerName ? `${sellerName}'s Enterprise` : "Dhwani Store";

  if (clean.includes("software") || clean.includes("developer") || clean.includes("tech") || clean.includes("app") || clean.includes("website") || clean.includes("it company")) {
    category = "Tech & Digital Services";
    themeColor = "#0284C7";
    shopTitle = sellerName ? `${sellerName} Digital & Tech Solutions` : "Tech & Digital Solutions";
  } else if (clean.includes("tailor") || clean.includes("blouse") || clean.includes("embroidery") || clean.includes("saree") || clean.includes("craft") || clean.includes("art")) {
    category = "Handicrafts & Tailoring";
    themeColor = "#7E22CE";
    shopTitle = sellerName ? `${sellerName} Artisanal Creations` : "Handicraft & Tailoring Studio";
  } else if (clean.includes("masala") || clean.includes("podi") || clean.includes("powder") || clean.includes("pickle") || clean.includes("chutney")) {
    category = "Masalas & Podis";
    themeColor = "#C8553D";
    shopTitle = sellerName ? `${sellerName} Spice & Podi Kitchen` : "Authentic Spices & Podis";
  } else if (clean.includes("cake") || clean.includes("brownie") || clean.includes("bake") || clean.includes("cookie") || clean.includes("bread")) {
    category = "Home Bakery";
    themeColor = "#D97706";
    shopTitle = sellerName ? `${sellerName} Home Bakery` : "Artisanal Home Bakery";
  } else if (clean.includes("rotti") || clean.includes("tiffin") || clean.includes("biryani") || clean.includes("meal") || clean.includes("curry") || clean.includes("catering")) {
    category = "Tiffin & Meals";
    themeColor = "#1F5E4B";
    shopTitle = sellerName ? `${sellerName} Traditional Kitchen` : "Traditional Home Kitchen";
  } else if (clean.includes("oil") || clean.includes("honey") || clean.includes("organic") || clean.includes("millet") || clean.includes("ghee")) {
    category = "Organic Produce";
    themeColor = "#15803D";
    shopTitle = sellerName ? `${sellerName} Organic Farm Products` : "Pure Organic Farm Products";
  }

  // Split clauses
  const clauses = clean.split(/[,;\.\n]+|\band\b|\bmattu\b|\baur\b/gi).map((s) => s.trim()).filter(Boolean);

  for (const clause of clauses) {
    const priceMatch = clause.match(/(?:rs\.?|inr|₹)?\s*(\d+)\s*(?:rupees?|rs\.?|rupayi|\/-)?/i);
    const price = priceMatch ? parseInt(priceMatch[1], 10) : 250;

    let unit = "unit";
    if (clause.includes("kg") || clause.includes("half kg")) unit = clause.includes("half") ? "half kg" : "1 kg";
    else if (clause.includes("pack") || clause.includes("packet")) unit = "packet";
    else if (clause.includes("month") || clause.includes("monthly")) unit = "per month";
    else if (clause.includes("hour") || clause.includes("hourly")) unit = "per hour";
    else if (clause.includes("project")) unit = "per project";
    else if (clause.includes("piece") || clause.includes("pc")) unit = "piece";
    else if (clause.includes("jar") || clause.includes("bottle")) unit = "jar";

    // Clean title from clause
    let itemTitle = clause
      .replace(/\d+/g, "")
      .replace(/(?:rupees?|rs\.?|kg|g|packet|pack|half|per|\/-|hello|this is|want to open|nanna hattira|mera|meri)/gi, "")
      .trim();

    if (itemTitle.length > 2) {
      itemTitle = itemTitle.charAt(0).toUpperCase() + itemTitle.slice(1);
    } else {
      itemTitle = category === "Tech & Digital Services" ? "Custom Software Development Consultation" : "Handcrafted Specialty Item";
    }

    if (!items.some((i) => i.title.toLowerCase() === itemTitle.toLowerCase())) {
      items.push({
        title: itemTitle,
        price,
        unit,
        category,
        description_local: `ವಿಶೇಷ ಸೇವೆ / ಉತ್ಪನ್ನ (${itemTitle})`,
        description_en: `High quality customized ${itemTitle} offered with dedicated support`,
      });
    }
  }

  if (items.length === 0) {
    items.push({
      title: category === "Tech & Digital Services" ? "Web & Mobile App Development Service" : "Specialty Handcrafted Product",
      price: category === "Tech & Digital Services" ? 1500 : 250,
      unit: category === "Tech & Digital Services" ? "per project" : "pack",
      category,
      description_local: "ತಾಜಾ ಮತ್ತು ವಿಶ್ವಾಸಾರ್ಹ ಸೇವೆ / ಉತ್ಪನ್ನ",
      description_en: "Reliable and high quality service crafted for your needs",
    });
  }

  return {
    shop_name: shopTitle,
    category,
    district: defaultDistrict || "Bengaluru",
    bio: `Dedicated to delivering authentic, top-quality offerings directly across Karnataka.`,
    theme_color: themeColor,
    items,
  };
}
