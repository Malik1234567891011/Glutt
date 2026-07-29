S = "/private/tmp/claude-501/-Users-omarlahmimi-Documents-Glutt/57997fee-0958-4e01-9d23-9987b0b21e83/scratchpad"

PANELS = {
    # 1 — what it is
    "p1": {
        "bg": "cream",
        "blob": ("peach", (1.06, 0.50), (0.50, 0.615), 0.0),
        "shot": f"{S}/shots/recipes.png",
        "phone_w": 0.61, "phone_y": 0.275, "crop_status": 0.062, "island": False,
        "scene": {"file": f"{S}/out/scene-band-1.png", "bottom": 0.975},
        "head_y": 0.042, "leading": 0.90,
        "head": [
            ("Glutt", 92, 800, 100, "green", 2),
            ("Cook what", 200, 800, 82, "ink", -3),
            ("you save", 200, 800, 82, "ink", -3),
        ],
        "props": [
            {"file": f"{S}/props/pasta.png", "w": 0.235, "x": 0.068, "y": 0.352,
             "label": "40 min", "label_size": 46, "label_x": 0.098, "label_y": 0.277},
            {"file": f"{S}/props/chicken.png", "w": 0.225, "x": 0.905, "y": 0.445,
             "label": "Ready now", "label_size": 46, "label_x": 0.878, "label_y": 0.368},
        ],
    },

    # 2 — the differentiator: hands-free voice cooking
    "p2": {
        "bg": "honey",
        "blob": ("peach", (1.04, 0.46), (0.50, 0.60), 1.3),
        "shot": f"{S}/refs/app-5586.png",
        "phone_w": 0.61, "phone_y": 0.275, "crop_status": 0.058, "island": False,
        "scene": {"file": f"{S}/out/scene-band-2.png", "bottom": 0.975},
        "head_y": 0.050, "leading": 0.90,
        "head": [
            ("Talk to Polly", 190, 800, 82, "ink", -3),
            ("while you cook", 190, 800, 82, "ink", -3),
        ],
        "props": [
            {"file": f"{S}/props/shrimp.png", "w": 0.245, "x": 0.075, "y": 0.395},
        ],
        "bubbles": [
            {"text": "Flip it now", "x": 0.845, "y": 0.325, "size": 52, "bg": "green", "fg": "white"},
            {"text": "How much salt?", "x": 0.815, "y": 0.435, "size": 48, "bg": "white", "fg": "ink"},
        ],
    },

    # 3 — the habit
    "p3": {
        "bg": "green",
        "blob": ("accentblob", (1.05, 0.48), (0.50, 0.60), 2.1),
        "shot": f"{S}/shots/discover.png",
        "phone_w": 0.61, "phone_y": 0.275, "crop_status": 0.062, "island": False,
        "scene": {"file": f"{S}/out/scene-band-3.png", "bottom": 0.985},
        "head_y": 0.050, "leading": 0.90,
        "head": [
            ("Swipe to find", 190, 800, 82, "cream", -3),
            ("tonight's dinner", 190, 800, 82, "cream", -3),
        ],
        "props": [
            {"file": f"{S}/props/salmon.png", "w": 0.245, "x": 0.078, "y": 0.400,
             "label": "45 min", "label_size": 46, "label_x": 0.105, "label_y": 0.322},
        ],
    },

    # 4 — the everyday problem
    "p4": {
        "bg": "cream",
        "blob": ("greentint", (1.05, 0.48), (0.50, 0.60), 3.4),
        "shot": f"{S}/shots/kitchen.png",
        "phone_w": 0.61, "phone_y": 0.275, "crop_status": 0.062, "island": False,
        "scene": {"file": f"{S}/out/scene-band-4.png", "bottom": 0.975},
        "head_y": 0.050, "leading": 0.90,
        "head": [
            ("Use what", 200, 800, 82, "ink", -3),
            ("you already have", 168, 800, 80, "ink", -3),
        ],
        "props": [
            {"file": f"{S}/props/onion.png", "w": 0.185, "x": 0.075, "y": 0.400,
             "label": "Add to list", "label_size": 44, "label_x": 0.115, "label_y": 0.330},
            {"file": f"{S}/props/garlic.png", "w": 0.215, "x": 0.912, "y": 0.470,
             "label": "In your kitchen", "label_size": 44, "label_x": 0.845, "label_y": 0.395},
        ],
    },

    # 5 — the payoff
    "p5": {
        "bg": "green",
        "blob": ("accentblob", (1.05, 0.48), (0.50, 0.60), 4.7),
        "shot": f"{S}/shots/detail.png",
        "phone_w": 0.61, "phone_y": 0.280, "crop_status": 0.062, "island": False,
        "scene": {"file": f"{S}/out/scene-band-5.png", "bottom": 0.985},
        "head_y": 0.058, "leading": 0.90,
        "head": [
            ("Macros, no math", 176, 800, 80, "cream", -3),
        ],
        "card": {"pairs": [("380", "CAL"), ("28g", "PROTEIN"), ("37g", "CARBS"), ("1g", "FAT")],
                 "x": 0.50, "y": 0.578, "w": 0.88, "tilt": 0.0},
        "props": [
            {"file": f"{S}/props/chicken.png", "w": 0.215, "x": 0.088, "y": 0.335},
        ],
    },
}
