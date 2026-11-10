# AIGifMaker (Swift)

Turn text into animated GIFs with AI GIF Maker. Native GIF generation — no video conversion. Type what you want and download your GIF in about a minute.

This is the official Swift SDK for [AI GIF Maker](https://aigifmaker.ai/?utm_source=cocoapods&utm_medium=package), for iOS 15+ and macOS 12+ (Linux too). One call sends your prompt, waits for the GIF and returns its URL.

```swift
import AIGifMaker

let gif = AIGifMaker()   // reads AIGIFMAKER_API_KEY
let url = try await gif.generate("a corgi in sunglasses dancing on a beach, looping")
print(url)               // the finished GIF
```

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/hanshs474/aigifmaker-swift.git", from: "0.1.0")
```

CocoaPods:

```ruby
pod 'AIGifMaker', '~> 0.1'
```

No dependencies beyond Foundation.

## API key

Create a key at https://aigifmaker.ai/settings/apikeys, then pass it as `AIGifMaker(apiKey: "sk-...")` or set `AIGIFMAKER_API_KEY`. In an app, keep the key on your server and call it from there rather than shipping it in the binary.

Each GIF costs 1 credit on your AI GIF Maker account, the same as on the website. New accounts get one free GIF (it carries a small aigifmaker.ai badge). A GIF that fails to generate gives its credit back. Credit packs are on the [pricing](https://aigifmaker.ai/pricing?utm_source=cocoapods&utm_medium=package) page.

```swift
let left = try await gif.credits()   // free to call
```

## Submit now, collect later

```swift
let id = try await gif.submit("happy birthday text bouncing in rainbow letters")
let st = try await gif.status(id)    // st.status: pending | processing | success | failed; st.url when done
let url = try await gif.wait(id)     // polls every 3 seconds
```

A run from an account that has not bought credits yet may wait in a short queue first (`st.queued` is true while `status` stays `processing`). That is normal; `generate` and `wait` keep polling, for up to 15 minutes by default (`gif.timeout`).

## Errors worth catching

Failures throw `AIGifMaker.AIGifMakerError`:

- `.auth`: no key, or the key is wrong or deleted
- `.quota`: the account is out of credits
- `.rejected`: the content filter refused the prompt, or a cooldown is active; reword it
- `.failed`: the run was accepted but failed; the message says why
- `.timeout`: the wait ran out; the GIF may still finish in your history

Anything else is `.api` with the server's message.

## Tests

```bash
swift test                       # mocked, offline
AIGIFMAKER_SMOKE=1 swift test    # plus two free live checks, no generation
```

MIT licensed. Questions: support@aigifmaker.ai
