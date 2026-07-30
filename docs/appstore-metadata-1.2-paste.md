# Paste sheet, Glutt 1.2

Mechanical instructions for filling in App Store Connect. Every value here is final: no
alternatives, no decisions left open. The reasoning behind each one lives in
`appstore-metadata-1.2.md`, which is a briefing document and must **not** be pasted into
any field.

## Rules

1. Paste each block **exactly** as it appears, including line breaks. Do not add a heading,
   a character count, a bullet, or a closing line.
2. Only touch the fields named below. Leave everything else in the listing alone.
3. If a field rejects a value, or the character counter goes red, **stop and report it**. Do
   not shorten, reword, or improvise a replacement.
4. If a field already contains different text, replace it entirely rather than appending.
5. English (U.S.) is the only locale. Do not add another.

## Do not attempt these

They cannot be done in a browser, and they are being handled separately:

- Archiving or uploading the build (Xcode or Transporter)
- Publishing Superwall paywall 243875
- Setting `ELEVENLABS_API_KEY` on Vercel
- Any code change
- The age rating questionnaire, which is waiting on one product decision

---

## 1. App-level fields

App Store Connect moves these between the App Information page and the version page
depending on the layout you get. Match on the field label, not the page.

**Name**

```
Glutt: Recipes & AI Chef
```

This is a change from the current `Glutt - Cooking`. Expected.

**Subtitle**

```
Your cookbook, smart pantry
```

**Privacy Policy URL**

```
https://glutt.org/privacy
```

**Category:** Primary `Food & Drink`. Leave Secondary as it is.

**Copyright**

```
2026 CielPM, Inc.
```

---

## 2. Version 1.2 fields

**Promotional Text**

```
Glutt has been rebuilt. Every screen is redesigned, and Polly now wakes up when you say her name, so your hands never have to leave the pan.
```

**Keywords**

```
cooking,meal,dinner,fridge,grocery,leftovers,voice,hands free,macro,calorie,kitchen,organizer
```

**Description**

```
Glutt is your kitchen, finally figured out.

Save any recipe, cook it hands-free with your own live AI chef, and use what is already in your fridge.

SAVE RECIPES FROM ANYWHERE
Found something on Instagram, TikTok, Reddit or any recipe site? Share it to Glutt and it becomes a clean, cookable recipe with ingredients, steps and timings in one place. If the method is only spoken out loud in the video, Glutt listens and writes it down for you. Screenshots work too. No more saved links you never open again.

MEET POLLY, YOUR LIVE AI CHEF
Talk to Polly out loud while you cook. Say her name, then ask what to use instead of buttermilk or whether the chicken is done, and the answer comes back straight away with no greasy taps on your phone. Polly walks you through every step, runs your timers, and can look through the camera at what is happening in the pan.

A KITCHEN THAT KNOWS WHAT YOU HAVE
Tell Glutt what is in your fridge and pantry by voice, by camera or by typing, then tick off the equipment you own. Recipes show what you are missing before you start, offer a substitute for what you do not have, and send the rest straight to your grocery list.

FIND TONIGHT'S DINNER
Swipe a feed of real dishes and cooking videos picked for your taste. Save the ones you want to cook, skip the rest, and Glutt gets better at reading you as you go.

COOK IT PROPERLY
Step by step cook mode with type big enough for greasy hands, timers that run themselves, serving scaling that does the arithmetic, and short lessons on the basics nobody ever taught you.

MACROS WITHOUT THE MATH
Every recipe carries calories and protein per serving, scaled to the number of servings you actually cook. No food diary, no daily goals, no guilt.

GLUTT PREMIUM
Glutt needs an active subscription. Yearly is $49.99 and monthly is $7.99, or start with a 3-day free trial that turns into the yearly plan unless you cancel first. Prices are in US dollars and may vary by country.

Payment is charged to your Apple Account at confirmation of purchase. Your subscription renews automatically unless auto renew is turned off at least 24 hours before the end of the current period. Manage or cancel it any time in your Apple Account settings.

Terms of Use (EULA): https://glutt.org/terms
Privacy Policy: https://glutt.org/privacy
```

**What's New in This Version**

```
Glutt has been rebuilt.

A NEW LOOK
Every screen redesigned, with new type, new icons and a new app icon to match. Recipe cards now open by zooming into the dish.

POLLY LISTENS FOR HER NAME
Just say "Polly" while your hands are covered in flour. No tap, no wake button. Her voice runs on a new engine, so she answers faster, lets you interrupt her, and stops talking over you. Ask her anything mid-cook, and she can look through the camera at what is in the pan.

RECIPES FROM VIDEOS THAT NEVER WROTE ANYTHING DOWN
Share a cooking video and Glutt listens to what the cook actually says, then writes the ingredients and steps out properly.

BEFORE AND AFTER THE COOK
A short briefing before you start, so you know what is coming. A recap at the end, where you keep a photo of what you made.

YOUR KITCHEN, BY VOICE
Say what is in your fridge instead of typing it in, and every recipe now carries its calories and protein per serving.

YOUR OWN ACCOUNT
Sign in with Apple or Google after you subscribe, so your subscription follows you to a new phone.

Plus better AirPods and Bluetooth headset support during a live cook, fixes to logging in and restoring purchases, and a lot of polish underneath.

Happy cooking.
```

**Support URL**

```
https://glutt.org/support
```

**Marketing URL**

```
https://glutt.org
```

---

## 3. Screenshots

iPhone 6.9 inch display, portrait, in this exact order. Delete the existing 1.1 screenshots
first, then upload these five:

1. `/Users/omarlahmimi/Desktop/glutt-appstore/panels/01-cook-what-you-save.png`
2. `/Users/omarlahmimi/Desktop/glutt-appstore/panels/02-talk-to-polly.png`
3. `/Users/omarlahmimi/Desktop/glutt-appstore/panels/03-swipe-to-find-dinner.png`
4. `/Users/omarlahmimi/Desktop/glutt-appstore/panels/04-use-what-you-have.png`
5. `/Users/omarlahmimi/Desktop/glutt-appstore/panels/05-macros-no-math.png`

Each is 1320 x 2868. No other display size is required, since the app is iPhone only.

---

## 4. App Review Information

Tick **Sign-in required**.

App Store Connect will not save the page with these empty once the box is ticked. It
rejects with "User name, This field is required" and the same for Password. Confirmed
2026-07-30. Put this in **both** fields, exactly:

```
Sign in with Apple only. See Notes.
```

Never invent credentials. Glutt has no password-based login, so anything that looks like a
working account sends a reviewer into a loop and reads as bad faith. The string above is a
pointer to the Notes block below, which is where the real instruction lives.

Leave the contact name, phone and email as they are.

**Notes**

```
Glutt requires an active subscription to use. There is no free tier. How to get in:

1. Complete the short onboarding on first launch.
2. The paywall appears. Either tap Continue to take the yearly plan, or turn on the "Not sure yet? Enable free trial." switch and tap "Start my 3-day free trial". If the switch is not shown, Continue takes the yearly plan.
3. Complete the purchase with your sandbox Apple Account. Sandbox purchases are free.
4. The app unlocks, then asks you to sign in. Tap "Sign in with Apple" and use your own Apple Account — Glutt creates the account for you on the spot. There is no password-based demo login to hand over, because Glutt only supports Sign in with Apple and Google. Signing in is what carries a subscription to a new phone; Glutt stores nothing but your name and email.

Three in-app purchases are submitted with this build: com.omarlahmimi.glutt.premium.yearly, com.omarlahmimi.glutt.premium.monthly, and com.omarlahmimi.glutt.premium.yearly.trial.

Other things worth knowing:

Restore Purchases is on the paywall and in Settings.
Sign-in is asked for after the purchase, never before, and only via Sign in with Apple or Google. Account deletion is in Settings, Account, Delete account.
The microphone and speech recognition are used by Polly, the in-app voice cooking assistant. Wake word detection runs on device. Camera access is optional and only used inside a Polly session or when scanning a pantry.
To try Polly: open any recipe, tap Cook with Polly, then say "Polly" or tap the mic. It needs a network connection.
The app is iPhone only and portrait only by design.
```

---

## 5. In-app purchase metadata

Under Monetization, Subscriptions. Edit the localization for each of the three products.
Do not change any price, duration, or the introductory offer.

| Product ID | Display Name | Description |
|---|---|---|
| `com.omarlahmimi.glutt.premium.yearly` | `Glutt Premium, Yearly` | `Everything in Glutt. Billed once a year.` |
| `com.omarlahmimi.glutt.premium.monthly` | `Glutt Premium, Monthly` | `Everything in Glutt. Billed every month.` |
| `com.omarlahmimi.glutt.premium.yearly.trial` | `Glutt Premium, Yearly Trial` | `3 days free, then the yearly plan.` |

All three must reach **Ready to Submit**, which needs a review screenshot on each. Any
capture of the paywall works.

---

## 6. App Privacy

The listing currently says **Data Not Collected**. That is wrong and has to be replaced.

Open App Privacy, edit the data types, and declare exactly these seven. For every one:

- **Used for tracking: No.** This applies to all seven, without exception.
- Set the purposes and the linked answer from the table.

| Category | Data type | Purposes | Linked to the user's identity |
|---|---|---|---|
| Contact Info | Email Address | App Functionality, Analytics | Yes |
| Identifiers | User ID | App Functionality, Analytics | Yes |
| Usage Data | Product Interaction | Analytics | Yes |
| Purchases | Purchase History | App Functionality, Analytics | Yes |
| User Content | Photos or Videos | App Functionality | No |
| User Content | Audio Data | App Functionality | No |
| User Content | Other User Content | App Functionality | No |

Declare nothing else. In particular: no Location, no Contacts, no Health, no Financial Info,
no Browsing History, no Diagnostics, and no Advertising Data. None of those are collected.

If the questionnaire asks whether data is collected from this app for third-party
advertising or your own advertising, the answer is **No** in both cases.

---

## 7. Report back

When finished, report which of these were completed, and quote anything App Store Connect
refused to accept:

- [ ] Name and Subtitle
- [ ] Promotional Text, Keywords, Description, What's New
- [ ] Support URL, Marketing URL, Privacy Policy URL, Copyright
- [ ] Five screenshots uploaded in order, 1.1 set removed
- [ ] Sign-in required ticked, review notes pasted
- [ ] Three IAP localizations updated
- [ ] Seven privacy data types declared, tracking answered No

Do not submit for review. That is a human decision.
