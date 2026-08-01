#!/usr/bin/env python3
"""Drop a finished import draft into the simulator's app-group inbox.

Exercises the real post-import path (ImportInboxDrainer -> MediaClipEnqueue)
without driving the share sheet by hand. Dev tool; not shipped.

Usage: python3 scripts/seedSimImport.py <app-group-plist-path>
"""
import json
import plistlib
import sys
import uuid

plist_path = sys.argv[1]

with open(plist_path, "rb") as f:
    data = plistlib.load(f)
print("existing keys:", list(data.keys()))

draft = {
    "id": str(uuid.uuid4()).upper(),
    "title": "Gordon Ramsay's Perfect Steak",
    "summary": "Pan-seared steak basted with garlic, thyme and butter.",
    "creator": "Hodder Books",
    "sourceURL": "https://www.youtube.com/watch?v=AmC9SmCBUj4",
    "platform": "youtube",
    "servings": 2,
    "prepMinutes": 5,
    "cookMinutes": 10,
    "ingredientLines": [
        "2 sirloin steaks",
        "Sea salt",
        "Cracked black pepper",
        "2 tbsp olive oil",
        "3 cloves garlic",
        "4 sprigs thyme",
        "50g butter",
    ],
    "stepTexts": [
        "Season the steaks generously with sea salt and cracked black pepper on both sides.",
        "Heat olive oil in a heavy pan until smoking hot, then lay the steaks in away from you.",
        "Sear the steaks for two minutes on each side until a deep crust forms.",
        "Add garlic, thyme and butter, then baste the steaks continuously with the foaming butter.",
        "Rest the steaks for five minutes before slicing against the grain.",
    ],
    "tags": ["beef", "dinner"],
    "nutritionIsEstimated": True,
    "issues": [],
    "stepsAreAISuggested": False,
    "isAIGenerated": False,
    "usedSpeechTranscript": False,
}

data["importInboxItems"] = json.dumps([draft]).encode("utf-8")
with open(plist_path, "wb") as f:
    plistlib.dump(data, f)
print("wrote inbox item ->", draft["title"])
